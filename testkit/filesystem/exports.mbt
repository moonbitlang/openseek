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
