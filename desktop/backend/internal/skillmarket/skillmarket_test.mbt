// End-to-end tests against a local stand-in for mooncakes.io: a real HTTP
// server serving the catalog, the per-skill API, and skill archives, with a
// temporary directory as the skills library.

///|
/// The SKILL.md inside every v1 fake archive.
let skill_body : Bytes = b"---\nname: widget\ndescription: Build widgets fast.\n---\n\nUse moon runwasm acme/widget.\n"

///|
/// A distinct upgrade body lets the concurrent-install test verify that the
/// installed instructions and provenance came from the same request.
let skill_body_v2 : Bytes = b"---\nname: widget\ndescription: Build widgets better.\n---\n\nUse moon run acme/widget.\n"

///|
/// A supporting file installed beside the SKILL.md.
let reference_body : Bytes = b"Extra reference notes.\n"

///|
/// Test-only request concurrency observed by one fake registry.
struct RegistryProbe {
  lock : @async.Mutex
  mut active : Int32
  mut max_active : Int32
}

///|
struct ArchiveGate {
  arrived : @async.Queue[Unit]
  release : @async.Queue[Unit]
}

///|
async fn RegistryProbe::enter(self : RegistryProbe) -> Unit {
  self.lock.acquire()
  self.active += 1
  if self.active > self.max_active {
    self.max_active = self.active
  }
  self.lock.release()
}

///|
async fn RegistryProbe::leave(self : RegistryProbe) -> Unit {
  self.lock.acquire()
  self.active -= 1
  self.lock.release()
}

///|
/// Wire bytes of a zip archive holding `files`.
fn zip_of(files : Array[(String, Bytes)]) -> Bytes raise {
  let archive = @zip.Archive::Archive()
  for file in files {
    archive.add(file.0, file.1)
  }
  @zip.write(archive)
}

///|
/// The plain hexadecimal SHA-256 the standalone registry declares.
fn digest_of(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
/// One fake registry entry: the archive its download URL serves (`None`
/// 404s the download) and the digest its API declares.
struct FakeSkill {
  archive : Bytes?
  digest : String
}

///|
fn skill_record(base : String, entry : String, digest : String) -> Json raise {
  guard entry.split_once("/") is Some((owner, rest)) &&
    rest.split_once("@") is Some((name, version)) else {
    fail("invalid fixture reference: \{entry}")
  }
  {
    "owner": owner.to_owned(),
    "name": name.to_owned(),
    "version": version.to_owned(),
    "author_avatar": "",
    "description": "Build widgets fast.",
    "detail_url": "/skills/\{entry}",
    "archive_url": "\{base}/download/\{entry}/skills.zip",
    "archive_digest": digest,
    "created_at": "2026-10-30T00:00:00Z",
  }
}

///|
fn skill_entry_body(
  base : String,
  entry : String,
  digest : String,
  readme : String,
) -> String raise {
  guard skill_record(base, entry, digest) is Object(fields) else {
    fail("expected a skill record")
  }
  fields["readme"] = Json::string(readme)
  fields["versions"] = ["1.0.0", "2.0.0", "3.0.0"]
  Json::object(fields).stringify()
}

///|
const SkillsPrefix = "/api/v0/skills/"

///|
const DownloadPrefix = "/download/"

///|
const BlobPrefix = "/blob/"

///|
const ZipSuffix = "/skills.zip"

///|
/// The one fake entry whose download redirects to itself forever.
const LoopEntry = "acme/loop@1.0.0"

///|
/// A local mooncakes.io stand-in. Returns its base URL, or None when the
/// sandbox forbids binding a local TCP port. `acme/widget` publishes real
/// archives; the other entries cover each way an install must fail;
/// everything else is not a skill.
async fn fake_registry(
  group : @async.TaskGroup[Unit],
  probe? : RegistryProbe,
  archive_gate? : ArchiveGate,
  gate_entry~ : String = "acme/widget@2.0.0",
  catalog_version~ : String = "1.0.0",
  requests? : Array[String],
  catalog_response? : Json,
  preview? : String,
  include_builtins~ : Bool = false,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println("local TCP bind unavailable; skipping test: \{error}")
      return None
    }
    error => raise error
  }
  let base = "http://127.0.0.1:\{server.addr.port()}"
  let widget_v1 = zip_of([
    ("SKILL.md", skill_body),
    ("reference/usage.md", reference_body),
  ])
  let widget_v2 = zip_of([("SKILL.md", skill_body_v2)])
  let wrapped = zip_of([("widget/SKILL.md", skill_body)])
  let no_md = zip_of([("README.md", b"no instructions here\n")])
  let slip = zip_of([("SKILL.md", skill_body), ("../evil.md", b"escape\n")])
  let not_text = zip_of([("SKILL.md", b"\xff\xfe\xfd")])
  let skills : Map[String, FakeSkill] = {
    "acme/widget@1.0.0": {
      archive: Some(widget_v1),
      digest: digest_of(widget_v1),
    },
    "acme/widget@2.0.0": {
      archive: Some(widget_v2),
      digest: digest_of(widget_v2),
    },
    "acme/widget@3.0.0": {
      archive: Some(widget_v2),
      digest: digest_of(widget_v2),
    },
    "acme/noarchive@1.0.0": { archive: None, digest: digest_of(b""), },
    "acme/badsum@1.0.0": { archive: Some(widget_v1), digest: "deadbeef", },
    "acme/nomd@1.0.0": { archive: Some(no_md), digest: digest_of(no_md), },
    "acme/wrapped@1.0.0": {
      archive: Some(wrapped),
      digest: digest_of(wrapped),
    },
    "acme/slip@1.0.0": { archive: Some(slip), digest: digest_of(slip), },
    "acme/binary@1.0.0": {
      archive: Some(not_text),
      digest: digest_of(not_text),
    },
    "acme/mismatch@1.0.0": {
      archive: Some(widget_v1),
      digest: digest_of(widget_v1),
    },
    "acme/loop@1.0.0": {
      archive: Some(widget_v1),
      digest: digest_of(widget_v1),
    },
  }
  for name in ["typst", "office-cli", "office"] {
    let bytes = zip_of([
      (
        "SKILL.md",
        @utf8.encode(
          "---\nname: \{name}\ndescription: Built-in skill\n---\nInstructions",
        ),
      ),
    ])
    skills["moonbitlang/\{name}@1.0.0"] = {
      archive: Some(bytes),
      digest: digest_of(bytes),
    }
  }
  let catalog : Array[Json] = [
    skill_record(base, "acme/widget@\{catalog_version}", digest_of(widget_v1)),
  ]
  if include_builtins {
    for name in ["typst", "office-cli"] {
      let entry = "moonbitlang/\{name}@1.0.0"
      guard skills.get(entry) is Some(skill) else {
        fail("missing built-in fixture")
      }
      catalog.push(skill_record(base, entry, skill.digest))
    }
  }
  group.spawn_bg(no_wait=true) <| () => {
    let json_headers : @http.Headers = { "Content-Type": "application/json" }
    server.run_forever(
      (request, body, conn) => {
        let _ = body.read_all()
        if probe is Some(probe) {
          probe.enter()
          @async.sleep(20)
          probe.leave()
        }
        if requests is Some(requests) {
          requests.push(request.path)
        }
        let path = request.path.replace_all(old="%40", new="@")
        if path == "/api/v0/skills" {
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string(
            catalog_response.unwrap_or(Json::array(catalog)).stringify(),
          )
        } else if path == "/api/v0/skills/acme/bare@1.0.0" {
          // Missing required release coordinates are a malformed response.
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string("{\"module\":\"acme/bare\"}")
        } else if path == "/api/v0/skills/acme/malformed@1.0.0" {
          // Empty-string coordinates: registry corruption, not absence.
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string("{\"archive_url\":\"\",\"archive_digest\":\"\"}")
        } else if path.strip_prefix(SkillsPrefix) is Some(entry) &&
          skills.get(entry.to_owned()) is Some(skill) {
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string(
            skill_entry_body(
              base,
              entry.to_owned(),
              skill.digest,
              preview.unwrap_or(
                @utf8.decode(
                  if entry == "acme/widget@2.0.0" {
                    skill_body_v2
                  } else {
                    skill_body
                  },
                ),
              ),
            ),
          )
        } else if path.strip_prefix(DownloadPrefix) is Some(download) &&
          download.strip_suffix(ZipSuffix) is Some(entry) &&
          skills.get(entry.to_owned()) is Some(skill) &&
          skill.archive is Some(_) {
          // The real registry's download host hands the archive to its
          // object store through a redirect; mirror that, including one
          // entry that loops forever.
          let location = if entry == LoopEntry {
            path
          } else {
            "\{BlobPrefix}\{entry}\{ZipSuffix}"
          }
          let redirect_headers : @http.Headers = { "Location": location }
          conn.send_response(302, "Found", extra_headers=redirect_headers)
        } else if path.strip_prefix(BlobPrefix) is Some(blob) &&
          blob.strip_suffix(ZipSuffix) is Some(entry) &&
          skills.get(entry.to_owned()) is Some(skill) &&
          skill.archive is Some(archive) {
          if entry == gate_entry && archive_gate is Some(gate) {
            gate.arrived.put(())
            gate.release.get()
          }
          conn.send_response(200, "OK")
          conn.write(archive)
        } else {
          conn.send_response(404, "Not Found", extra_headers=json_headers)
          conn.write_string("{\"detail\":\"Skill not found\"}")
        }
      },
      max_connections=16,
    )
  }
  Some(base)
}

///|
/// Run an install that must fail and return its user-facing message.
async fn install_failure(
  base : String,
  lib : @pathx.Path,
  module_name : String,
) -> String {
  try {
    let _ = @skillmarket.install_skill(
      module_name~,
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    fail("install of \{module_name} should have failed")
  } catch {
    @skillmarket.SkillMarketError(message) => message
    error => raise error
  }
}

///|
/// Run an uninstall that must fail and return its user-facing message.
async fn uninstall_failure(lib : @pathx.Path, id : String) -> String {
  try {
    @skillmarket.uninstall_skill(id, library_dir=lib)
    fail("uninstall of \{id} should have failed")
  } catch {
    @skillmarket.SkillMarketError(message) => message
    error => raise error
  }
}

///|
async test "the catalog projects standalone skill records into the host payload" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let skills = @skillmarket.fetch_catalog(registry=base)
    guard skills is [skill] else { fail("expected one installable skill") }
    assert_eq(skill.module_name, "acme/widget")
    assert_eq(skill.package_path, "")
    assert_eq(skill.author, "acme")
    assert_eq(skill.repository, "")
    assert_eq(skill.name, "widget")
    assert_eq(skill.version, "1.0.0")
    assert_eq(skill.description, "Build widgets fast.")
  }
}

///|
async test "install verifies the archive and writes every file it holds" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let installed = @skillmarket.install_skill(
      module_name="acme/widget",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    assert_eq(installed.id, "acme-widget")
    assert_eq(installed.name, "widget")
    assert_eq(installed.description, "Build widgets fast.")
    assert_eq(installed.source, "acme/widget@1.0.0")
    // The exact archive bytes landed on disk where the engine discovers them,
    // supporting files included.
    assert_eq(@fs.read_file("\{lib}/acme-widget/SKILL.md").binary(), skill_body)
    assert_eq(
      @fs.read_file("\{lib}/acme-widget/reference/usage.md").binary(),
      reference_body,
    )
    guard @skillmarket.installed_skills(library_dir=lib) is [listed] else {
      fail("expected one installed skill")
    }
    assert_eq(listed.id, "acme-widget")
    assert_eq(listed.source, "acme/widget@1.0.0")
    // Reinstalling over our own entry is an upgrade, not a conflict.
    let again = @skillmarket.install_skill(
      module_name="acme/widget",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    assert_eq(again.id, "acme-widget")
  }
}

///|
async test "an archive that wraps its files in a directory is refused" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let message = install_failure(base, lib, "acme/wrapped")
    assert_true(message.contains("Archive must contain SKILL.md at its root"))
    assert_false(@fs.exists("\{lib}/acme-wrapped"))
  }
}

///|
async test "a redirect loop on the archive download is refused" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let message = install_failure(base, lib, "acme/loop")
    assert_true(message.contains("Too many HTTP redirects"))
    assert_false(@fs.exists("\{lib}/acme-loop"))
  }
}

///|
async test "preview reads the versioned detail API without downloading archives" {
  @async.with_task_group() <| group => {
    let requests : Array[String] = []
    guard fake_registry(group, requests~) is Some(base) else { return }
    let content = @skillmarket.fetch_skill_content(
      module_name="acme/widget",
      version="2.0.0",
      package_path="",
      registry=base,
    )
    assert_eq(content, @utf8.decode(skill_body_v2))
    assert_eq(requests, ["/api/v0/skills/acme/widget%402.0.0"])
  }
}

///|
async test "catalog errors preserve registry context and the client diagnosis" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    try @skillmarket.fetch_catalog(registry="\{base}/missing") catch {
      @skillmarket.SkillMarketError(message) => {
        assert_true(message.contains(base))
        assert_true(message.contains("HTTP 404: Skill not found"))
      }
      error => raise error
    } noraise {
      _ => fail("expected a catalog HTTP error")
    }
    for response in [Json::null(), { "all": [] }, [{ "owner": "acme" }]] {
      guard fake_registry(group, catalog_response=response) is Some(malformed) else {
        fail("expected local registry")
      }
      try @skillmarket.fetch_catalog(registry=malformed) catch {
        @skillmarket.SkillMarketError(message) =>
          assert_true(message.contains("skill catalog from"))
        error => raise error
      } noraise {
        _ => fail("malformed catalog must not become an empty success")
      }
    }
    guard fake_registry(group, catalog_response=[]) is Some(empty) else {
      fail("expected local registry")
    }
    assert_eq(@skillmarket.fetch_catalog(registry=empty).length(), 0)
  }
}

///|
async test "preview reports missing skills and bounds readme bytes" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    try
      @skillmarket.fetch_skill_content(
        module_name="acme/missing",
        version="1.0.0",
        package_path="",
        registry=base,
      )
    catch {
      @skillmarket.SkillMarketError(message) =>
        assert_true(message.contains("HTTP 404"))
      error => raise error
    } noraise {
      _ => fail("missing skill must fail")
    }
    guard fake_registry(group, preview="界".repeat(180000)) is Some(large) else {
      fail("expected local registry")
    }
    try
      @skillmarket.fetch_skill_content(
        module_name="acme/widget",
        version="1.0.0",
        package_path="",
        registry=large,
      )
    catch {
      @skillmarket.SkillMarketError(message) =>
        assert_eq(message, "SKILL.md is too large to preview")
      error => raise error
    } noraise {
      _ => fail("oversized preview must fail")
    }
  }
}

///|
async test "legacy subpackages cannot accidentally install a standalone skill" {
  @async.with_task_group() <| group => {
    let requests : Array[String] = []
    guard fake_registry(group, requests~) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    defer @fs.rmdir(lib, recursive=true)
    try
      @skillmarket.install_skill(
        module_name="acme/widget",
        version="1.0.0",
        package_path="cmd/run",
        registry=base,
        library_dir=lib,
      )
    catch {
      @skillmarket.SkillMarketError(message) =>
        assert_true(message.contains("package path"))
      error => raise error
    } noraise {
      _ => fail("subpackage install must fail")
    }
    assert_eq(requests, [])
    assert_eq(@skillmarket.installed_skills(library_dir=lib).length(), 0)
  }
}

///|
async test "concurrent upgrades of one slug are serialized" {
  @async.with_task_group() <| group => {
    let probe : RegistryProbe = { lock: Mutex(), active: 0, max_active: 0, }
    guard fake_registry(group, probe~) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let completed : @async.Queue[Unit] = Queue(kind=Blocking(2))
    for version in ["1.0.0", "2.0.0"] {
      group.spawn_bg() <| () => {
        ignore(
          @skillmarket.install_skill(
            module_name="acme/widget",
            version~,
            package_path="",
            registry=base,
            library_dir=lib,
          ),
        )
        completed.put(())
      }
    }
    completed.get()
    completed.get()
    // Registry work is deliberately outside the library lock, so the two
    // downloads may overlap. Only recovery, staging, and the live-directory
    // switch are serialized.
    assert_eq(probe.max_active, 2)
    let content = @fs.read_file("\{lib}/acme-widget/SKILL.md").binary()
    let sidecar = @fs.read_file("\{lib}/acme-widget/.mooncakes.json").text()
    guard @json.parse(sidecar) is { "version": String(version), .. } else {
      fail("installed provenance is malformed")
    }
    if version == "1.0.0" {
      assert_eq(content, skill_body)
    } else if version == "2.0.0" {
      assert_eq(content, skill_body_v2)
    } else {
      fail("unexpected installed version \{version}")
    }
  }
}

///|
async test "install never overwrites a hand-written skill" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    @fs.mkdir("\{lib}/acme-widget", recursive=true)
    @fs.write_file(
      "\{lib}/acme-widget/SKILL.md",
      "my own playbook",
      create_mode=CreateOrTruncate,
    )
    let message = install_failure(base, lib, "acme/widget")
    assert_true(message.contains("already exists"))
    assert_eq(
      @fs.read_file("\{lib}/acme-widget/SKILL.md").text(),
      "my own playbook",
    )
    let flat_lib = @fs.tmpdir(prefix="skillmarket-")
    @fs.write_file(
      "\{flat_lib}/acme-widget.md",
      "my flat skill",
      create_mode=CreateOrTruncate,
    )
    let message = install_failure(base, flat_lib, "acme/widget")
    assert_true(message.contains("already exists"))
    assert_eq(
      @fs.read_file("\{flat_lib}/acme-widget.md").text(),
      "my flat skill",
    )
    assert_false(@fs.exists("\{flat_lib}/acme-widget"))
  }
}

///|
async test "uninstall removes registry installs and nothing else" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let mut changes = 0
    let _ = @skillmarket.install_skill(
      module_name="acme/widget",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
      on_committed=() => changes += 1,
    )
    @skillmarket.uninstall_skill("acme-widget", library_dir=lib, on_committed=() => {
      changes += 1
    })
    assert_eq(changes, 2)
    assert_false(@fs.exists("\{lib}/acme-widget"))
    let message = uninstall_failure(lib, "acme-widget")
    assert_true(message.contains("no skill named"))
    // A hand-written skill (no sidecar) is the user's file, not ours.
    @fs.mkdir("\{lib}/handmade", recursive=true)
    @fs.write_file(
      "\{lib}/handmade/SKILL.md",
      "mine",
      create_mode=CreateOrTruncate,
    )
    let message = uninstall_failure(lib, "handmade")
    assert_true(message.contains("remove it by hand"))
    assert_true(@fs.exists("\{lib}/handmade/SKILL.md"))
  }
}

///|
async test "listing recovers interrupted local skill changes" {
  let lib = @fs.tmpdir(prefix="skillmarket-")
  // An interrupted upgrade parked the previous complete entry but never made
  // its staged replacement live. Listing must restore the backup before it
  // takes a directory snapshot.
  @fs.mkdir("\{lib}/.backup/acme-widget", recursive=true)
  @fs.write_file(
    "\{lib}/.backup/acme-widget/SKILL.md",
    "---\nname: widget\ndescription: recovered\n---\nold",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{lib}/.backup/acme-widget/.mooncakes.json",
    (
      {
        "module": "acme/widget",
        "version": "1.0.0",
        "package": "",
        "digest": "sha256:old",
      } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{lib}/.staging/acme-widget", recursive=true)
  @fs.write_file(
    "\{lib}/.staging/acme-widget/SKILL.md",
    "incomplete replacement",
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{lib}/.trash/removed-skill", recursive=true)
  @fs.write_file(
    "\{lib}/.trash/removed-skill/SKILL.md",
    "already uninstalled",
    create_mode=CreateOrTruncate,
  )
  guard @skillmarket.installed_skills(library_dir=lib) is [recovered] else {
    fail("the parked skill was not restored")
  }
  assert_eq(recovered.id, "acme-widget")
  assert_eq(recovered.description, "recovered")
  assert_eq(recovered.source, "acme/widget@1.0.0")
  assert_true(@fs.exists("\{lib}/acme-widget/SKILL.md"))
  assert_false(@fs.exists("\{lib}/.backup/acme-widget"))
  assert_false(@fs.exists("\{lib}/.staging/acme-widget"))
  assert_false(@fs.exists("\{lib}/.trash/removed-skill"))

  // If both target and backup exist, the new target was already activated;
  // recovery keeps it and only removes the obsolete backup.
  @fs.mkdir("\{lib}/.backup/acme-widget", recursive=true)
  @fs.write_file(
    "\{lib}/.backup/acme-widget/SKILL.md",
    "obsolete backup",
    create_mode=CreateOrTruncate,
  )
  ignore(@skillmarket.installed_skills(library_dir=lib))
  assert_true(@fs.exists("\{lib}/acme-widget/SKILL.md"))
  assert_false(@fs.exists("\{lib}/.backup/acme-widget"))
}

///|
async test "a non-skill module is refused" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let message = install_failure(
      base,
      @fs.tmpdir(prefix="skillmarket-"),
      "acme/nothing",
    )
    assert_true(message.contains("HTTP 404: Skill not found"))
  }
}

///|
/// Every bad registry fixture is refused with the phrase its own message
/// carries, and a refusal leaves no directory behind in the library. Each row
/// still names the scenario it stands for — that label rides the assertion, so
/// a failure says which refusal broke rather than only which line.
async test "install refuses every bad fixture and leaves no library directory" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    for
      row in [
        (
          "archive metadata must match the release", "acme/mismatch", "Archive name does not match",
          "acme-mismatch",
        ),
        (
          "legacy module records cannot install standalone skills", "acme/bare",
          "Invalid skill response", "acme-bare",
        ),
        (
          "an incomplete detail response is a registry error", "acme/malformed",
          "Invalid skill response", "acme-malformed",
        ),
        (
          "a skill whose archive is missing reports it plainly", "acme/noarchive",
          "HTTP 404", "acme-noarchive",
        ),
        (
          "an archive that fails its digest check is refused", "acme/badsum", "Archive SHA-256 mismatch",
          "acme-badsum",
        ),
        (
          "an archive without a SKILL.md is refused at install", "acme/nomd", "Archive must contain SKILL.md at its root",
          "acme-nomd",
        ),
        (
          "an archive whose SKILL.md is not text is refused", "acme/binary", "SKILL.md must be valid UTF-8",
          "acme-binary",
        ),
        (
          "a path-escaping archive is refused", "acme/slip", "Invalid archive path",
          "acme-slip",
        ),
      ] {
      let (scenario, module_name, reason, directory) = row
      let lib = @fs.tmpdir(prefix="skillmarket-")
      let message = install_failure(base, lib, module_name)
      assert_true(message.contains(reason), msg="case: \{scenario}: \{message}")
      assert_false(@fs.exists("\{lib}/\{directory}"), msg="case: \{scenario}")
    }
  }
}

///|
/// Regression test: the listing used to surface raw readdir order, which is
/// platform-defined (insertion order on some filesystems, name hash on
/// others) — the suite passed on macOS and failed on Linux ext4. The listing
/// must be name-sorted like the engine's own discovery.
async test "listing is name-sorted regardless of creation order" {
  let lib = @fs.tmpdir(prefix="skillmarket-")
  for name in ["ddd", "aaa", "eee", "ccc"] {
    @fs.mkdir("\{lib}/\{name}", recursive=true)
    @fs.write_file(
      "\{lib}/\{name}/SKILL.md",
      "---\nname: \{name}\ndescription: d\n---\nbody",
      create_mode=CreateOrTruncate,
    )
  }
  @fs.write_file(
    "\{lib}/bbb.md",
    "---\nname: bbb\ndescription: d\n---\nbody",
    create_mode=CreateOrTruncate,
  )
  let ids = @skillmarket.installed_skills(library_dir=lib).map(skill => skill.id)
  assert_eq(ids, ["aaa", "bbb", "ccc", "ddd", "eee"])
}

///|
async test "listing mirrors the engine's discovery for hand-written skills" {
  let lib = @fs.tmpdir(prefix="skillmarket-")
  @fs.write_file(
    "\{lib}/notes.md",
    "---\nname: notes\ndescription: My notes.\n---\nbody",
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{lib}/local", recursive=true)
  @fs.write_file(
    "\{lib}/local/SKILL.md",
    "no frontmatter",
    create_mode=CreateOrTruncate,
  )
  let skills = @skillmarket.installed_skills(library_dir=lib)
  guard skills is [dir_skill, flat_skill] else {
    fail("expected two library entries, got \{skills.length()}")
  }
  assert_eq(flat_skill.id, "notes")
  assert_eq(flat_skill.name, "notes")
  assert_eq(flat_skill.description, "My notes.")
  assert_eq(flat_skill.source, "")
  assert_eq(dir_skill.id, "local")
  assert_eq(dir_skill.name, "local")
  assert_eq(dir_skill.source, "")
  // A missing library is an empty one.
  assert_eq(
    @skillmarket.installed_skills(library_dir="\{lib}/does-not-exist").length(),
    0,
  )
}

///|
async test "disabled registry skills retain their content, update state and uninstall support" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-disabled-")
    let first = @skillmarket.install_skill(
      module_name="acme/widget",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    assert_true(first.enabled)
    let mut changes = 0
    @skillmarket.set_skill_enabled(
      "acme-widget",
      enabled=false,
      library_dir=lib,
      on_committed=() => changes += 1,
    )
    // Repeating the desired state is harmless and makes no second move.
    @skillmarket.set_skill_enabled(
      "acme-widget",
      enabled=false,
      library_dir=lib,
      on_committed=() => changes += 1,
    )
    assert_eq(changes, 1)
    assert_false(@fs.exists("\{lib}/acme-widget"))
    assert_eq(
      @fs.read_file("\{lib}/.disabled/acme-widget/reference/usage.md").binary(),
      reference_body,
    )
    guard @skillmarket.installed_skills(library_dir=lib) is [disabled] else {
      fail("disabled skill must remain in the installed library")
    }
    assert_false(disabled.enabled)
    assert_eq(disabled.source, first.source)
    assert_eq(
      @skillmarket.read_skill_content("acme-widget", library_dir=lib),
      @utf8.decode(skill_body),
    )
    let updated = @skillmarket.install_skill(
      module_name="acme/widget",
      version="2.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    assert_false(updated.enabled)
    assert_false(@fs.exists("\{lib}/acme-widget"))
    assert_eq(
      @fs.read_file("\{lib}/.disabled/acme-widget/SKILL.md").binary(),
      skill_body_v2,
    )
    assert_false(@fs.exists("\{lib}/.disabled/acme-widget/reference/usage.md"))
    @skillmarket.set_skill_enabled("acme-widget", enabled=true, library_dir=lib)
    assert_eq(
      @fs.read_file("\{lib}/acme-widget/SKILL.md").binary(),
      skill_body_v2,
    )
    assert_false(@fs.exists("\{lib}/.disabled/acme-widget"))
    @skillmarket.set_skill_enabled(
      "acme-widget",
      enabled=false,
      library_dir=lib,
    )
    @skillmarket.uninstall_skill("acme-widget", library_dir=lib)
    assert_true(@skillmarket.installed_skills(library_dir=lib).is_empty())
    assert_false(@fs.exists("\{lib}/.disabled/acme-widget"))
  }
}

///|
async test "hand-written directory and flat skills can move without rewriting their files" {
  let lib = @fs.tmpdir(prefix="skillmarket-handwritten-")
  @fs.mkdir("\{lib}/node.js/reference", recursive=true)
  @fs.write_file(
    "\{lib}/node.js/SKILL.md",
    "Directory skill",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{lib}/node.js/reference/notes.txt",
    "Companion",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    "\{lib}/My notes.md",
    "Flat skill",
    create_mode=CreateOrTruncate,
  )
  for (id, text) in [("node.js", "Directory skill"), ("My notes", "Flat skill")] {
    @skillmarket.set_skill_enabled(id, enabled=false, library_dir=lib)
    assert_eq(@skillmarket.read_skill_content(id, library_dir=lib), text)
  }
  let disabled = @skillmarket.installed_skills(library_dir=lib)
  assert_eq(disabled.length(), 2)
  assert_true(
    disabled.iter().all(skill => !skill.enabled && skill.registry is None),
  )
  assert_eq(
    @fs.read_file("\{lib}/.disabled/node.js/reference/notes.txt").text(),
    "Companion",
  )
  for id in ["node.js", "My notes"] {
    @skillmarket.set_skill_enabled(id, enabled=true, library_dir=lib)
  }
  assert_eq(@fs.read_file("\{lib}/My notes.md").text(), "Flat skill")
  assert_eq(@fs.read_file("\{lib}/node.js/SKILL.md").text(), "Directory skill")
}

///|
async test "an interrupted disabled update recovers inside the disabled library" {
  let lib = @fs.tmpdir(prefix="skillmarket-recover-disabled-")
  @fs.mkdir("\{lib}/.disabled/.backup/widget", recursive=true)
  @fs.write_file(
    "\{lib}/.disabled/.backup/widget/SKILL.md",
    "Previous version",
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{lib}/.disabled/.staging/widget", recursive=true)
  @fs.write_file(
    "\{lib}/.disabled/.staging/widget/SKILL.md",
    "Incomplete",
    create_mode=CreateOrTruncate,
  )
  guard @skillmarket.installed_skills(library_dir=lib) is [skill] else {
    fail("the disabled backup must be restored")
  }
  assert_false(skill.enabled)
  assert_false(@fs.exists("\{lib}/widget"))
  assert_eq(
    @fs.read_file("\{lib}/.disabled/widget/SKILL.md").text(),
    "Previous version",
  )
  assert_false(@fs.exists("\{lib}/.disabled/.backup/widget"))
  assert_false(@fs.exists("\{lib}/.disabled/.staging/widget"))
}

///|
async test "an update commits to the current location after an in-flight enablement change" {
  @async.with_task_group() <| group => {
    for initially_enabled in [true, false] {
      let gate : ArchiveGate = {
        arrived: Queue(kind=Blocking(1)),
        release: Queue(kind=Blocking(1)),
      }
      guard fake_registry(group, archive_gate=gate) is Some(base) else {
        return
      }
      let lib = @fs.tmpdir(prefix="skillmarket-update-switch-")
      ignore(
        @skillmarket.install_skill(
          module_name="acme/widget",
          version="1.0.0",
          package_path="",
          registry=base,
          library_dir=lib,
        ),
      )
      @skillmarket.set_skill_enabled(
        "acme-widget",
        enabled=initially_enabled,
        library_dir=lib,
      )
      let finished : @async.Queue[@skillmarket.InstalledSkill] = Queue(
        kind=Blocking(1),
      )
      group.spawn_bg() <| () => {
        finished.put(
          @skillmarket.install_skill(
            module_name="acme/widget",
            version="2.0.0",
            package_path="",
            registry=base,
            library_dir=lib,
          ),
        )
      }
      gate.arrived.get()
      let expected_enabled = !initially_enabled
      @skillmarket.set_skill_enabled(
        "acme-widget",
        enabled=expected_enabled,
        library_dir=lib,
      )
      gate.release.put(())
      let updated = finished.get()
      assert_eq(updated.enabled, expected_enabled)
      let active = "\{lib}/acme-widget"
      let disabled = "\{lib}/.disabled/acme-widget"
      let (current, other) = {
        guard expected_enabled else { (disabled, active) }
        (active, disabled)
      }
      assert_eq(@fs.read_file("\{current}/SKILL.md").binary(), skill_body_v2)
      assert_false(@fs.exists(other))
      assert_eq(@skillmarket.installed_skills(library_dir=lib).length(), 1)
    }
  }
}
