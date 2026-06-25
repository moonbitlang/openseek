// End-to-end tests against a local stand-in for mooncakes.io: a real HTTP
// server serving the catalog, the per-skill API, and SKILL.md bodies, with a
// temporary directory as the skills library.

///|
/// The SKILL.md every fake asset serves.
let skill_body : Bytes = b"---\nname: widget\ndescription: Build widgets fast.\n---\n\nUse moon runwasm acme/widget.\n"

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
  // entry -> whether its SKILL.md asset exists.
  let skills : Map[String, Bool] = {
    "acme/widget@1.0.0": true,
    "acme/nomd@1.0.0": false,
  }
  group.spawn_bg(no_wait=true) <| () => {
    let json_headers = { "Content-Type": "application/json" }
    server.run_forever(
      (request, body, conn) => {
        let _ = body.read_all()
        let path = request.path
        if path == "/api/v0/skills" {
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string(catalog_body())
        } else if path.has_prefix(SkillsPrefix) &&
          skills.contains(path[SkillsPrefix.length():].to_owned()) {
          // The per-skill API only confirms the entry is a skill; the install
          // ignores the body.
          conn.send_response(200, "OK", extra_headers=json_headers)
          conn.write_string("{}")
        } else if path.has_prefix(AssetsPrefix) &&
          path.has_suffix(SkillMdSuffix) &&
          skills.get(
            path[AssetsPrefix.length():path.length() - SkillMdSuffix.length()].to_owned(),
          )
          is Some(true) {
          conn.send_response(200, "OK")
          conn.write(skill_body)
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
