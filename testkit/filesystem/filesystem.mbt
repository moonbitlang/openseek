///|
/// One file of a `FileSystem`: its slash-separated relative `path` and full
/// text `content`.
pub struct FileEntry {
  path : String
  content : String
}

///|
/// A small JSON-backed virtual filesystem for tests and eval fixtures.
///
/// The convention is a flat JSON object where each key is a slash-separated
/// relative file path and each value is that file's text content.
pub(all) struct FileSystem(Json)

///|
/// Build a filesystem from `(path, content)` pairs — the convenient form for
/// literal fixtures in test code. Rejects invalid paths and duplicates.
pub fn FileSystem::from_pairs(
  files : Array[(String, String)],
) -> FileSystem raise {
  let object : Map[String, Json] = Map([])
  for file in files {
    let (path, content) = file
    validate_relative_path(path)
    if object.contains(path) {
      fail("duplicate file path: \{path}")
    }
    object[path] = Json::string(content)
  }
  FileSystem(Json::object(object))
}

///|
/// The underlying JSON object's fields, raising when the top-level JSON is not
/// an object as the convention requires.
fn FileSystem::object_fields(self : FileSystem) -> Map[String, Json] raise {
  let FileSystem(json) = self
  guard json is Object(fields) else {
    fail("file system must be a JSON object")
  }
  fields
}

///|
/// Check the whole filesystem against the convention, raising on the first
/// violation. Equivalent to `entries()` with the result discarded.
pub fn FileSystem::validate(self : FileSystem) -> Unit raise {
  let _ = self.entries()
}

///|
/// Every file path, sorted — the entries without their contents.
pub fn FileSystem::paths(self : FileSystem) -> Array[String] raise {
  [
    for entry in self.entries() => entry.path
  ]
}

///|
/// Content of the file at `path`, or `None` when absent. Raises on an
/// invalid `path` or malformed stored content rather than hiding either as
/// "absent".
pub fn FileSystem::get(self : FileSystem, path : String) -> String? raise {
  validate_relative_path(path)
  let fields = self.object_fields()
  match fields.get(path) {
    Some(String(content)) => Some(content)
    Some(_) => fail("file content for `\{path}` must be a string")
    None => None
  }
}

///|
/// Materialize every file under the `root` directory, creating parent
/// directories as needed — how an eval trial stages its starting workspace.
pub async fn FileSystem::write_to(self : FileSystem, root : String) -> Unit {
  for entry in self.entries() {
    write_text(root, entry.path, entry.content)
  }
}

///|
/// Compare this filesystem against the files under `root` and describe the
/// first difference — a missing file or a content mismatch — or return `""`
/// when everything matches. A description rather than a `Bool` so an eval
/// report can say what went wrong, not just that something did.
pub async fn FileSystem::mismatch_on_disk(
  self : FileSystem,
  root : String,
) -> String {
  let entries = self.entries() catch {
    error => return "invalid file system: \{error}"
  }
  for entry in entries {
    let path = "\{root}/\{entry.path}"
    let content = @fs.read_file(path).text() catch {
      error => return "missing expected file \{entry.path}: \{error}"
    }
    if content != entry.content {
      return "content mismatch in \{entry.path}"
    }
  }
  ""
}

///|
/// Write one text file at `root`/`path` (relative, validated), creating
/// parent directories and truncating any existing file.
pub async fn write_text(root : String, path : String, content : String) -> Unit {
  validate_relative_path(path)
  ensure_parent_dir(root, path)
  @fs.write_file("\{root}/\{path}", content, create_mode=CreateOrTruncate)
}

///|
/// Run `body` with a freshly created temporary directory, then remove that
/// directory (and everything under it) once `body` returns or raises.
///
/// The path handed to `body` is an existing directory, so callers can write
/// files directly beneath it without an `@fs.mkdir` first. Prefer this over a
/// hardcoded `/tmp/...` path: it keeps tests portable (Windows has no `/tmp`),
/// avoids collisions between concurrent runs, and cleans up after itself even
/// when `body` fails an assertion.
pub async fn[T] with_tmpdir(
  body : async (String) -> T,
  prefix? : String = "openseek-test-",
) -> T {
  let dir = @fs.tmpdir(prefix~)
  async fn rmdir() {
    @fs.rmdir(dir, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      // We sallow other errors here to perform best-effort clean up.
      _ => ()
    }
  }
  defer rmdir()
  body(dir)
}

///|
fn validate_relative_path(path : String) -> Unit raise {
  if path == "" {
    fail("file path must not be empty")
  }
  if path.has_prefix("/") {
    fail("file path must be relative: \{path}")
  }
  if path.contains("\\") {
    fail("file path must use `/` separators: \{path}")
  }
  for part in path.split("/") {
    if part == "" {
      fail("file path must not contain empty components: \{path}")
    }
    if part == "." || part == ".." {
      fail("file path must not contain `.` or `..`: \{path}")
    }
  }
}

///|
async fn ensure_parent_dir(root : String, path : String) -> Unit {
  guard path.rev_split_once("/") is Some((dirs, _)) else { return }
  @fs.mkdir("\{root}/\{dirs}", recursive=true) catch {
    _ => ()
  }
}
