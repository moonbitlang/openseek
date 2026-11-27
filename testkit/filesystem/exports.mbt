// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Every file as a `FileEntry`, sorted by path for deterministic iteration.
/// Raises when the JSON violates the filesystem convention.
pub fn FileSystem::entries(self : FileSystem) -> Array[FileEntry] raise {
  let fields = self.object_fields()
  let paths = [..fields.keys()]
  paths.sort()
  [
    for path in paths => {
      validate_relative_path(path)
      match fields[path] {
        String(content) => { path, content, }
        _ => fail("file content for `\{path}` must be a string")
      }
    }
  ]
}

///|
/// Wrap an already-encoded JSON filesystem, validating the convention up
/// front (object shape, relative string paths, string contents) so later
/// reads cannot fail on malformed fixture data.
pub fn FileSystem::from_json(json : Json) -> FileSystem raise {
  let filesystem = FileSystem(json)
  filesystem.validate()
  filesystem
}

///|
/// Every file path, sorted — the entries without their contents.
///
/// Deliberate export: the package README lists `paths()` in its `API Shape`
/// section and uses it in its checked example
/// (`testkit/filesystem/README.mbt.md`), so it stays the documented surface
/// that outside users of the published `moonbitlang/openseek` module read.
pub fn FileSystem::paths(self : FileSystem) -> Array[String] raise {
  [
    for entry in self.entries() => entry.path
  ]
}

///|
/// Build a filesystem from `(path, content)` pairs — the convenient form for
/// literal fixtures in test code. Rejects invalid paths and duplicates.
///
/// Test seam: tests of other packages build fixtures with it —
/// `agent_tool/edit/edit_guard_test.mbt`,
/// `agent_tool/edit/guard_consistency_test.mbt`,
/// `agent_tool/mbtx/examples_test.mbt`,
/// `agent_tool/mbtx/fix_deprecations_test.mbt`,
/// `agent_tool/multi_edit/multi_edit_guard_test.mbt`,
/// `agent_tool/multi_edit/multi_edit_reach_test.mbt`, and
/// `internal/openseek/setup/session_test.mbt`.
pub fn FileSystem::from_pairs(
  files : Array[(String, String)],
) -> FileSystem raise {
  let object : Map[String, Json] = Map([])
  for (path, content) in files {
    validate_relative_path(path)
    if object.contains(path) {
      fail("duplicate file path: \{path}")
    }
    object[path] = Json(content)
  }
  FileSystem(Json(object))
}

///|
/// Write one text file at `root`/`path` (relative, validated), creating
/// parent directories and truncating any existing file.
///
/// Test seam: tests of other packages overwrite a single fixture file with
/// it — `agent_subtask/lifecycle_test.mbt`,
/// `agent_tool/internal/sandbox/worker_profile_test.mbt`,
/// `agent_tool/write_scope/write_scope_test.mbt`, and
/// `agent_worker/tool_test.mbt`.
pub async fn write_text(root : String, path : String, content : String) -> Unit {
  validate_relative_path(path)
  ensure_parent_dir(root, path)
  @fs.write_text("\{root}/\{path}", content, create_mode=CreateOrTruncate)
}
