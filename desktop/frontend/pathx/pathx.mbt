// Frontend paths are URI paths, so they always use POSIX separators regardless
// of the operating system running the browser. Keeping this type separate from
// `internal/pathx` prevents host-filesystem detection from entering the JS
// bundle.

///|
/// A workspace-relative URI path with forward-slash separators.
pub(all) struct Relative(String) derive(Debug, Eq, Hash)

///|
/// Render the relative spelling at protocol and URI boundaries.
pub impl Show for Relative with fn output(self, logger) {
  logger.write_string(self.0)
}

///|
/// The zero-segment relative path naming the workspace root itself.
pub fn Relative::root() -> Relative {
  Relative("")
}

///|
/// Whether this is the workspace root.
pub fn Relative::is_root(self : Relative) -> Bool {
  self.0.is_empty()
}

///|
/// Normalize dot segments and redundant separators with URI/POSIX rules.
/// A backslash remains an ordinary path character.
pub fn Relative::normalize(self : Relative) -> Relative {
  let normalized = @posix.Path(self.0).normalize().0
  if normalized == "." {
    Relative::root()
  } else {
    Relative(normalized)
  }
}

///|
/// Whether `path` is this relative URI path or one of its descendants.
pub fn Relative::contains(self : Relative, path : Relative) -> Bool {
  let path = path.normalize().0
  let root = self.normalize().0
  if path == root {
    return true
  }
  let prefix = if root.has_suffix("/") { root } else { "\{root}/" }
  path.strip_prefix(prefix) is Some(_)
}

///|
#deprecated
pub extend Relative with Debug::{to_repr}

///|
pub extend Relative with Eq::{equal, not_equal}

///|
pub extend Relative with Hash::{hash, hash_combine}

///|
pub extend Relative with Show::{output, to_string}
