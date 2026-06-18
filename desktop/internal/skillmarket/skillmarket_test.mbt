// End-to-end tests against a local stand-in for mooncakes.io: a real HTTP
// server serving the catalog, discovery indexes, and SKILL.md bodies, with
// a temporary directory as the skills library.

///|
/// The SKILL.md every fake asset serves. Bytes, not String — the digest is
/// over the exact wire bytes, and MoonBit strings are UTF-16.
let skill_body : Bytes = b"---\nname: widget\ndescription: Build widgets fast.\n---\n\nUse moon runwasm acme/widget.\n"

///|
fn skill_digest() -> String {
  "sha256:" + @crypto.bytes_to_hex_string(@crypto.sha256(skill_body))
}

///|
fn discovery_index(name : String, url : String, digest : String) -> String {
  let json : Json = {
    "skills": [
      {
        "name": name,
        "type": "skill-md",
        "description": "Build widgets fast.",
        "url": url,
        "digest": digest,
      },
    ],
  }
  json.stringify()
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
const IndexPathPrefix = "/api/v0/skill-sources/"

///|
const IndexPathSuffix = "/.well-known/agent-skills/index.json"

///|
fn index_path(entry : String) -> String {
  IndexPathPrefix + entry + IndexPathSuffix
}

///|
/// A local mooncakes.io stand-in. Returns its base URL, or None when the
/// sandbox forbids binding a local TCP port.
async fn fake_registry(group : @async.TaskGroup[Unit]) -> String? {
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
  let text_routes : Map[String, String] = { "/api/v0/skills": catalog_body() }
  text_routes[index_path("acme/widget@1.0.0")] = discovery_index(
    "acme-widget",
    "\{base}/assets/acme/widget@1.0.0/SKILL.md",
    skill_digest(),
  )
  text_routes[index_path("acme/baddigest@1.0.0")] = discovery_index(
    "acme-baddigest",
    "\{base}/assets/acme/baddigest@1.0.0/SKILL.md",
    "sha256:deadbeef",
  )
  text_routes[index_path("acme/evil@1.0.0")] = discovery_index(
    "acme-evil",
    "http://evil.invalid/assets/acme/evil@1.0.0/SKILL.md",
    skill_digest(),
  )
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        let _ = body.read_all()
        if request.path == "/assets/acme/widget@1.0.0/SKILL.md" ||
          request.path == "/assets/acme/baddigest@1.0.0/SKILL.md" {
          conn.send_response(200, "OK")
          conn.write(skill_body)
        } else if text_routes.get(request.path) is Some(reply) {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write_string(reply)
        } else {
          conn.send_response(404, "Not Found", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write_string("{\"detail\":\"Skill source not found\"}")
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
async test "install verifies the digest, writes the library and lists the skill" {
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
async test "a digest mismatch refuses the install" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let message = install_failure(base, lib, "acme/baddigest")
    assert_true(message.contains("digest mismatch"))
    assert_false(@fs.exists("\{lib}/acme-baddigest"))
  }
}

///|
async test "an index pointing outside the registry is refused" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let lib = @fs.tmpdir(prefix="skillmarket-")
    let message = install_failure(base, lib, "acme/evil")
    assert_true(message.contains("outside the registry"))
  }
}

///|
async test "a module without a SKILL.md reports it plainly" {
  @async.with_task_group() <| group => {
    guard fake_registry(group) is Some(base) else { return }
    let message = install_failure(
      base,
      @fs.tmpdir(prefix="skillmarket-"),
      "acme/nothing",
    )
    assert_true(message.contains("does not publish a SKILL.md"))
  }
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
