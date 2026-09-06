///|
/// Asserts that writing `content` to `path` is refused with exactly `expected`.
async fn assert_write_error(
  path : String,
  content : String,
  expected : String,
) -> Unit {
  guard @manifest_error.write_error(path, content) is Some(message) else {
    fail("expected a manifest error for \{path}")
  }
  assert_eq(message, expected)
}

///|
async test "manifest error allows ordinary files" {
  assert_true(@manifest_error.write_error("notes.json", "{}") is None)
  assert_true(@manifest_error.write_error("not-moon.mod", "{}") is None)
  assert_true(@manifest_error.write_error("not-moon.pkg", "x") is None)
}

///|
async test "manifest error rejects generated mbti files" {
  let message = "*.generated.mbti files are generated; run moon info instead of editing them"
  assert_write_error("lib/pkg.generated.mbti", "package x", message)
  assert_write_error("C:\\workspace\\pkg.generated.mbti", "", message)
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
    @vfs.FileSystem({ "moon.mod.json": "{}" }).write_to(dir)
    let error = @manifest_error.write_error(path, "{}")
    assert_true(error is None)
  })
}

///|
async test "manifest error rejects invalid moon.mod content" {
  assert_write_error("moon.mod", "", "moon.mod must not be empty")
  assert_write_error(
    "moon.mod", "{\"name\":\"demo\"}", "moon.mod uses current text syntax, not JSON",
  )
  assert_write_error(
    "moon.mod", "version = \"0.1.0\"", "moon.mod should include a module `name = ...` entry",
  )
}

///|
async test "manifest error checks invalid moon.pkg content" {
  assert_true(@manifest_error.write_error("moon.pkg", "x") is None)
  assert_write_error(
    "moon.pkg", "# comment", "moon.pkg use // for comment syntax, not #",
  )
  assert_write_error(
    "moon.pkg", "{\"import\":[]}", "moon.pkg uses current text syntax, not JSON",
  )
}

///|
async test "manifest error accepts Windows path separators" {
  assert_write_error(
    "C:\\workspace\\moon.mod", "{\"name\":\"bad\"}", "moon.mod uses current text syntax, not JSON",
  )
  assert_true(
    @manifest_error.write_error("C:\\workspace\\moon.pkg", "x") is None,
  )
  assert_write_error(
    "C:\\workspace\\moon.pkg", "# comment", "moon.pkg use // for comment syntax, not #",
  )
  assert_write_error(
    "C:\\workspace\\moon.mod.json", "{}", "moon.mod.json is legacy; create moon.mod for new MoonBit projects",
  )
}

///|
async test "manifest error rejects generated interfaces" {
  let message = "*.generated.mbti files are generated; run moon info instead of editing them"
  assert_write_error("pkg.generated.mbti", "...", message)
  assert_write_error("lib\\pkg.generated.mbti", "...", message)
}
