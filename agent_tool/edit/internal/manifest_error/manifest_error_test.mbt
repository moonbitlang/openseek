///|
async test "manifest error allows ordinary files" {
  assert_true(@manifest_error.write_error("notes.json", "{}") is None)
  assert_true(@manifest_error.write_error("not-moon.mod", "{}") is None)
  assert_true(@manifest_error.write_error("not-moon.pkg", "x") is None)
}

///|
async test "manifest error rejects generated mbti files" {
  let message = "*.generated.mbti files are generated; run moon info instead of editing them"
  guard @manifest_error.write_error("lib/pkg.generated.mbti", "package x")
    is Some(unix) else {
    fail("expected generated mbti error")
  }
  assert_eq(unix, message)
  guard @manifest_error.write_error("C:\\workspace\\pkg.generated.mbti", "")
    is Some(windows) else {
    fail("expected generated mbti error")
  }
  assert_eq(windows, message)
}

///|
async test "manifest error rejects new moon.mod.json" {
  @vfs.with_tmpdir(prefix="openseek-edit-manifest-error-", dir => {
    let path = "\{dir}/moon.mod.json"
    let error = @manifest_error.write_error(path, "{}")
    guard error is Some(message) else { fail("expected manifest error") }
    assert_true(message.contains("moon.mod.json is legacy"))
  })
}

///|
async test "manifest error allows existing moon.mod.json" {
  @vfs.with_tmpdir(prefix="openseek-edit-manifest-error-", dir => {
    let path = "\{dir}/moon.mod.json"
    @fs.write_file(path, "{}", create_mode=CreateOrTruncate)
    let error = @manifest_error.write_error(path, "{}")
    assert_true(error is None)
  })
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
async test "manifest error checks invalid moon.pkg content" {
  assert_true(@manifest_error.write_error("moon.pkg", "x") is None)
  guard @manifest_error.write_error("moon.pkg", "# comment") is Some(comment) else {
    fail("expected moon.pkg comment syntax error")
  }
  assert_eq(comment, "moon.pkg use // for comment syntax, not #")
  guard @manifest_error.write_error("moon.pkg", "{\"import\":[]}") is Some(json) else {
    fail("expected JSON moon.pkg error")
  }
  assert_eq(json, "moon.pkg uses current text syntax, not JSON")
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
  assert_true(
    @manifest_error.write_error("C:\\workspace\\moon.pkg", "x") is None,
  )
  guard @manifest_error.write_error("C:\\workspace\\moon.pkg", "# comment")
    is Some(moon_pkg) else {
    fail("expected moon.pkg comment syntax error")
  }
  assert_eq(moon_pkg, "moon.pkg use // for comment syntax, not #")
  guard @manifest_error.write_error("C:\\workspace\\moon.mod.json", "{}")
    is Some(moon_mod_json) else {
    fail("expected moon.mod.json error")
  }
  assert_eq(
    moon_mod_json, "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
  )
}

///|
async test "manifest error rejects generated interfaces" {
  let message = "*.generated.mbti files are generated; run moon info instead of editing them"
  guard @manifest_error.write_error("pkg.generated.mbti", "...")
    is Some(root_error) else {
    fail("expected generated interface error")
  }
  assert_eq(root_error, message)
  guard @manifest_error.write_error("lib\\pkg.generated.mbti", "...")
    is Some(windows_error) else {
    fail("expected generated interface error")
  }
  assert_eq(windows_error, message)
}
