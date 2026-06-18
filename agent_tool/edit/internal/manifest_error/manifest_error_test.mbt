///|
async test "manifest error allows ordinary files" {
  assert_true(@manifest_error.write_error("notes.json", "{}") is None)
}

///|
async test "manifest error accepts valid current manifests" {
  let moon_mod =
    #|name = "user/demo"
    #|version = "0.1.0"
    #|
  assert_true(@manifest_error.write_error("moon.mod", moon_mod) is None)
  let moon_pkg =
    #|import {
    #|  "moonbitlang/core/json",
    #|}
    #|
    #|warnings = "+unnecessary_annotation"
    #|
  assert_true(@manifest_error.write_error("moon.pkg", moon_pkg) is None)
  let moon_work =
    #|members = [
    #|  ".",
    #|]
    #|
  assert_true(@manifest_error.write_error("moon.work", moon_work) is None)
}

///|
async test "manifest error rejects new moon.mod.json" {
  let dir = @fs.tmpdir(prefix="openseek-edit-manifest-error-")
  let path = "\{dir}/moon.mod.json"
  let error = @manifest_error.write_error(path, "{}")
  @fs.rmdir(dir, recursive=true)
  guard error is Some(message) else { fail("expected manifest error") }
  assert_true(message.contains("moon.mod.json is legacy"))
}

///|
async test "manifest error allows existing moon.mod.json" {
  let dir = @fs.tmpdir(prefix="openseek-edit-manifest-error-")
  let path = "\{dir}/moon.mod.json"
  @fs.write_file(path, "{}", create_mode=CreateOrTruncate)
  let error = @manifest_error.write_error(path, "{}")
  @fs.rmdir(dir, recursive=true)
  assert_true(error is None)
}

///|
async test "manifest error rejects invalid moon.mod content" {
  guard @manifest_error.write_error("moon.mod", "") is Some(empty) else {
    fail("expected empty moon.mod error")
  }
  assert_eq(empty, "moon.mod must not be empty")
  guard @manifest_error.write_error("moon.mod", "{\"name\":\"demo\"}")
    is Some(json) else {
    fail("expected JSON moon.mod error")
  }
  assert_eq(json, "moon.mod uses current text syntax, not JSON")
  guard @manifest_error.write_error("moon.mod", "version = \"0.1.0\"")
    is Some(missing_name) else {
    fail("expected missing name moon.mod error")
  }
  assert_eq(missing_name, "moon.mod should include a module `name = ...` entry")
}

///|
async test "manifest error rejects parser-reported invalid moon.mod content" {
  let unexpected_key_content =
    #|name = "user/demo"
    #|deps = []
    #|
  guard @manifest_error.write_error("moon.mod", unexpected_key_content)
    is Some(unexpected_key) else {
    fail("expected unexpected key moon.mod error")
  }
  assert_true(unexpected_key.contains("moon.mod is invalid"))
  assert_true(unexpected_key.contains("unexpected key `deps`"))
  guard @manifest_error.write_error("moon.mod", "name =") is Some(syntax) else {
    fail("expected syntax moon.mod error")
  }
  assert_true(syntax.contains("moon.mod is invalid"))
}

///|
async test "manifest error rejects invalid moon.pkg content" {
  guard @manifest_error.write_error("moon.pkg", "x") is Some(tiny) else {
    fail("expected tiny moon.pkg error")
  }
  assert_eq(tiny, "moon.pkg content is suspiciously small")
  guard @manifest_error.write_error("moon.pkg", "{\"import\":[]}") is Some(json) else {
    fail("expected JSON moon.pkg error")
  }
  assert_eq(json, "moon.pkg uses current text syntax, not JSON")
}

///|
async test "manifest error rejects parser-reported invalid moon.pkg content" {
  guard @manifest_error.write_error("moon.pkg", "name = \"demo\"")
    is Some(unexpected_key) else {
    fail("expected unexpected key moon.pkg error")
  }
  assert_true(unexpected_key.contains("moon.pkg is invalid"))
  assert_true(unexpected_key.contains("unexpected key `name`"))
  guard @manifest_error.write_error("moon.pkg", "import {") is Some(syntax) else {
    fail("expected syntax moon.pkg error")
  }
  assert_true(syntax.contains("moon.pkg is invalid"))
}

///|
async test "manifest error rejects invalid moon.work content" {
  guard @manifest_error.write_error("moon.work", "{\"members\":[]}")
    is Some(json) else {
    fail("expected JSON moon.work error")
  }
  assert_eq(json, "moon.work uses current text syntax, not JSON")
  guard @manifest_error.write_error("moon.work", "workspace = []")
    is Some(unexpected_key) else {
    fail("expected unexpected key moon.work error")
  }
  assert_true(unexpected_key.contains("moon.work is invalid"))
  assert_true(unexpected_key.contains("unexpected key `workspace`"))
  guard @manifest_error.write_error("moon.work", "members = [") is Some(syntax) else {
    fail("expected syntax moon.work error")
  }
  assert_true(syntax.contains("moon.work is invalid"))
}

///|
async test "manifest error accepts Windows path separators" {
  guard @manifest_error.write_error(
      "C:\\workspace\\moon.mod", "{\"name\":\"bad\"}",
    )
    is Some(moon_mod) else {
    fail("expected moon.mod error")
  }
  assert_eq(moon_mod, "moon.mod uses current text syntax, not JSON")
  guard @manifest_error.write_error("C:\\workspace\\moon.pkg", "x")
    is Some(moon_pkg) else {
    fail("expected moon.pkg error")
  }
  assert_eq(moon_pkg, "moon.pkg content is suspiciously small")
  guard @manifest_error.write_error("C:\\workspace\\moon.mod.json", "{}")
    is Some(moon_mod_json) else {
    fail("expected moon.mod.json error")
  }
  assert_eq(
    moon_mod_json, "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
  )
  guard @manifest_error.write_error(
      "C:\\workspace\\moon.work", "{\"members\":[]}",
    )
    is Some(moon_work) else {
    fail("expected moon.work error")
  }
  assert_eq(moon_work, "moon.work uses current text syntax, not JSON")
}
