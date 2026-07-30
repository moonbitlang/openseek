// End-to-end tests against a local stand-in for mooncakes.io: a real HTTP
// server serving the catalog, the per-skill API, and SKILL.md bodies, with a
// temporary directory as the skills library.

///|
/// The SKILL.md every fake asset serves.
let skill_body : Bytes = b"---\nname: widget\ndescription: Build widgets fast.\n---\n\nUse moon runwasm acme/widget.\n"

///|
/// A distinct upgrade body lets the concurrent-install test verify that the
/// installed instructions and provenance came from the same request.
let skill_body_v2 : Bytes = b"---\nname: widget\ndescription: Build widgets better.\n---\n\nUse moon run acme/widget.\n"

///|
/// Test-only request concurrency observed by one fake registry.
struct RegistryProbe {
  lock : @async.Mutex
  mut active : Int
  mut max_active : Int
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
fn catalog_body() -> String {
  let json : Json = [
    {
      "module": "acme/widget",
      "version": "1.0.0",
      "name": "acme/widget",
      "package": "",
      "author": "acme",
      "repository": "https://example.com/acme/widget",
      "metadata": { "description": "Build widgets fast." },
    },
    {
      "module": "acme/bare-wasm",
      "version": "1.0.0",
      "name": "acme/bare-wasm",
      "package": "",
      "author": "acme",
      "metadata": { "description": "" },
    },
  ]
  json.stringify()
}

///|
const SkillsPrefix = "/api/v0/skills/"

///|
const AssetsPrefix = "/assets/"

///|
const SkillMdSuffix = "/SKILL.md"

///|
/// A local mooncakes.io stand-in. Returns its base URL, or None when the
/// sandbox forbids binding a local TCP port. `acme/widget@1.0.0` is a skill
/// with a SKILL.md; `acme/nomd@1.0.0` is a skill whose SKILL.md asset is
/// missing; everything else is not a skill.
async fn fake_registry(
  group : @async.TaskGroup[Unit],
  probe? : RegistryProbe,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println("local TCP bind unavailable; skipping test: \{message}")
        return None
      }
      raise error
    }
  }
  let base = "http://127.0.0.1:\{server.addr.port()}"
  // entry -> whether its SKILL.md asset exists.
  let skills : Map[String, Bool] = {
    "acme/widget@1.0.0": true,
    "acme/widget@2.0.0": true,
    "acme/nomd@1.0.0": false,
  }
  group.spawn_bg(no_wait=true) <| () => {
    let json_headers = { "Content-Type": "application/json" }
    server.run_forever(
      (request, body, conn) => {
        let _ = body.read_all()
        if probe is Some(probe) {
          probe.enter()
          @async.sleep(20)
          probe.leave()
        }
        let path = request.path
        if path == "/api/v0/skills" {
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string(catalog_body())
        } else if path.strip_prefix(SkillsPrefix) is Some(skill) &&
          skills.contains(skill.to_owned()) {
          // The per-skill API only confirms the entry is a skill; the install
          // ignores the body.
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string("{}")
        } else if path.strip_prefix(AssetsPrefix) is Some(asset) &&
          asset.strip_suffix(SkillMdSuffix) is Some(skill) &&
          skills.get(skill.to_owned()) is Some(true) {
          conn.send_response(200, "OK")
          if skill == "acme/widget@2.0.0" {
            conn.write(skill_body_v2)
          } else {
            conn.write(skill_body)
          }
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
  lib : @path.Path,
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
async fn uninstall_failure(lib : @path.Path, id : String) -> String {
  try {
    @skillmarket.uninstall_skill(id, library_dir=lib)
    fail("uninstall of \{id} should have failed")
  } catch {
    @skillmarket.SkillMarketError(message) => message
    error => raise error
  }
}

///|
async test "the catalog lists installable skills only" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let skills = @skillmarket.fetch_catalog(registry=base)
    guard skills is [skill] else { fail("expected one installable skill") }
    assert_eq(skill.name, "acme/widget")
    assert_eq(skill.version, "1.0.0")
    assert_eq(skill.description, "Build widgets fast.")
  }
}

///|
async test "install downloads the SKILL.md, writes the library and lists the skill" {
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
    // The exact wire bytes landed on disk where the engine discovers them.
    assert_eq(@fs.read_file("\{lib}/acme-widget/SKILL.md").binary(), skill_body)
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
async test "concurrent upgrades of one slug are serialized" {
  @async.with_task_group() <| group => {
    let probe : RegistryProbe = { lock: Mutex(), active: 0, max_active: 0 }
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
    // Each install makes two registry requests. Holding the library mutation
    // lock for the complete install keeps the other upgrade out until both
    // requests and both file writes finish.
    assert_eq(probe.max_active, 1)
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
    let _ = @skillmarket.install_skill(
      module_name="acme/widget",
      version="1.0.0",
      package_path="",
      registry=base,
      library_dir=lib,
    )
    @skillmarket.uninstall_skill("acme-widget", library_dir=lib)
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
async test "a non-skill module is refused" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let message = install_failure(
      base,
      @fs.tmpdir(prefix="skillmarket-"),
      "acme/nothing",
    )
    assert_true(message.contains("is not a published skill"))
  }
}

///|
async test "a skill whose SKILL.md is missing reports it plainly" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let message = install_failure(base, lib, "acme/nomd")
    assert_true(message.contains("does not publish a SKILL.md"))
    assert_false(@fs.exists("\{lib}/acme-nomd"))
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
