///|
test "normalizes accepted root relative paths" {
  let simple = expect_path("foo.mbt")
  assert_eq(simple.to_string(), "foo.mbt")
  assert_eq(simple.display_name(), "foo.mbt")
  let nested = expect_path("nested/file.txt")
  assert_eq(nested.to_string(), "nested/file.txt")

  let backslash = expect_path("nested\\file.txt")
  assert_eq(backslash.to_string(), "nested/file.txt")
}

///|
test "rejects invalid root relative paths" {
  expect_path_error("", MissingPath)
  expect_path_error("/absolute.mbt", InvalidPath)
  expect_path_error("//host/file.mbt", InvalidPath)
  expect_path_error("../outside.mbt", InvalidPath)
  expect_path_error("a/../outside.mbt", InvalidPath)
  expect_path_error("C:\\outside.mbt", InvalidPath)
  expect_path_error("bad\u{0}path.mbt", InvalidPath)
}

///|
test "parses document uris" {
  let memory = expect_uri("memory://main.mbt")
  assert_eq(memory.scheme, "memory")
  assert_eq(memory.to_string(), "memory://main.mbt")

  let file = expect_uri("file://server/nested/file.mbt")
  assert_eq(file.scheme, "file")
  assert_eq(file.path, "/nested/file.mbt")
  assert_eq(@base_common.basename_or_authority(file), "file.mbt")
  assert_eq(file.to_string(), "file://server/nested/file.mbt")

  // Non-strict parse falls back to the file scheme (Monaco `_schemeFix`);
  // only strict mode rejects a missing scheme.
  assert_eq(@base_common.Uri::parse("missing-scheme").scheme, "file")
  try @base_common.Uri::parse("missing-scheme", strict=true) |> ignore catch {
    UriError(_) => ()
  } noraise {
    _ => fail("expected UriError for missing scheme in strict mode")
  }
}

///|
async test "filesystem provider reads document snapshots by uri" {
  let uri = expect_uri("file://local/main.mbt")
  let provider = TestFileSystemProvider::{ }

  match @workspace.read_document(provider, uri) {
    DocumentLoaded(document) => {
      assert_eq(document.uri.to_string(), "file://local/main.mbt")
      assert_eq(document.display_name, "main.mbt")
      assert_eq(document.language_id, "moonbit")
      assert_eq(document.revision, "rev-1")
      assert_eq(document.text, "pub fn main {}\n")
    }
    DocumentReadFailed(error) =>
      fail("unexpected provider error \{error.message}")
    DocumentNotFound(uri) => fail("unexpected not found \{uri.to_string()}")
  }
}

///|
async test "filesystem provider rejects mismatched schemes" {
  let uri = expect_uri("memory://main.mbt")
  let provider = TestFileSystemProvider::{ }

  match @workspace.read_document(provider, uri) {
    DocumentReadFailed(error) => assert_true(error.code == InvalidUri)
    DocumentLoaded(document) =>
      fail("unexpected document \{document.uri.to_string()}")
    DocumentNotFound(uri) => fail("unexpected not found \{uri.to_string()}")
  }
}

///|
test "infers language ids from source names" {
  assert_eq(@workspace.infer_language_id("moon.pkg"), "moonbit-config")
  assert_eq(@workspace.infer_language_id("moon.mod"), "moonbit-config")
  assert_eq(@workspace.infer_language_id("src/moon.pkg"), "moonbit-config")
  assert_eq(@workspace.infer_language_id("src\\moon.mod"), "moonbit-config")
  assert_eq(@workspace.infer_language_id("main.mbt"), "moonbit")
  assert_eq(@workspace.infer_language_id("README.mbt.md"), "moonbit")
  assert_eq(@workspace.infer_language_id("run.mbtx"), "moonbit")
  assert_eq(@workspace.infer_language_id("main.js"), "javascript")
  assert_eq(@workspace.infer_language_id("main.mjs"), "javascript")
  assert_eq(@workspace.infer_language_id("main.ts"), "typescript")
  assert_eq(@workspace.infer_language_id("config.json"), "json")
  assert_eq(@workspace.infer_language_id("README.md"), "markdown")
  assert_eq(@workspace.infer_language_id("style.css"), "css")
  assert_eq(@workspace.infer_language_id("index.html"), "html")
  assert_eq(@workspace.infer_language_id("notes.txt"), "plaintext")
  assert_eq(@workspace.infer_language_id("moon.mod.json"), "json")
  assert_eq(@workspace.infer_language_id("notmoon.pkg"), "moonbit")
  assert_eq(@workspace.infer_language_id("unknown.source"), "moonbit")
}

///|
test "document snapshot owns identity and text helpers" {
  let document = @workspace.DocumentSnapshot(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/main.mbt",
    ),
    "main.mbt",
    "",
    "rev-3",
    "pub fn main {}\r\nlet x = 1",
  )
  assert_eq(document.revision, "rev-3")
  assert_eq(document.text, "pub fn main {}\r\nlet x = 1")
  assert_eq(document.language_id, "moonbit")
  assert_eq(document.line_count(), 2)
  assert_eq(document.line_text(0), "pub fn main {}")
  assert_eq(document.line_start_offset(1), 16)
  assert_eq(document.offset_at_position(Position(2, 4)), 19)
  let position = document.position_at_offset(19)
  assert_eq(position.line_number, 2)
  assert_eq(position.column, 4)
}

///|
fn expect_path(raw_path : String) -> @workspace.SourcePath raise {
  match @workspace.SourcePath::normalize_root_relative_path(raw_path) {
    ParsedSourcePath(path) => path
    SourcePathError(error) => fail("unexpected path error \{error.to_string()}")
  }
}

///|
fn expect_path_error(
  raw_path : String,
  expected : @workspace.SourceError,
) -> Unit raise {
  match @workspace.SourcePath::normalize_root_relative_path(raw_path) {
    SourcePathError(error) => assert_true(error == expected)
    ParsedSourcePath(path) => fail("unexpected path \{path.to_string()}")
  }
}

///|
fn expect_uri(raw_uri : String) -> @base_common.Uri raise {
  @base_common.Uri::parse(raw_uri)
}

///|
struct TestFileSystemProvider {}

///|
impl @workspace.FileSystemProvider for TestFileSystemProvider with fn scheme(
  _self,
) {
  "file"
}

///|
impl @workspace.FileSystemProvider for TestFileSystemProvider with fn read_file(
  _self,
  _uri,
) {
  FileReadOk(
    DocumentContent(
      "pub fn main {}\n",
      display_name="main.mbt",
      revision="rev-1",
    ),
  )
}

///|
impl @workspace.FileSystemProvider for TestFileSystemProvider with fn watch(
  _self,
  _uri,
  _options,
  _listener,
) {
  { dispose: () => (), }
}
