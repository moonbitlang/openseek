// Cross-platform path-string comparison. `@path.Path` renders with the
// host separator (backslashes on Windows) while URIs, manifests, and the
// frontend speak forward slashes, so any prefix test between the two worlds
// must normalize first. These helpers own that dance; callers never
// hand-roll `replace_all` + `has_prefix` again.

///|
/// An absolute filesystem path, as resolved by the host. The newtype keeps
/// workspace-relative strings from flowing into APIs that mean an absolute
/// path; it asserts provenance, not validity — construct it where the path
/// is known absolute.
pub(all) struct Absolute(String) derive(Eq)

///|
/// A workspace-relative path with forward-slash separators — the form
/// conversations, mention chips, and the file panel name files by. Like
/// `Absolute`, it asserts provenance, not validity: construct it where the
/// path is known relative (a host reply, a tree join), or through
/// `Absolute::relative_to`, the one blessed absolute→relative conversion.
pub(all) struct Relative(String) derive(Eq, Hash)

///|
/// The zero-segment relative path: the workspace root itself. Not a sentinel
/// — `""` is the value `relative_to` yields for the root and the parent
/// `child_path`-style joins build from, so it is the root's canonical name.
pub fn Relative::root() -> Relative {
  Relative("")
}

///|
/// Whether this is the workspace root (the zero-segment path).
pub fn Relative::is_root(self : Relative) -> Bool {
  self.0.is_empty()
}

///|
/// This path relative to the absolute directory `root`: `Some(Relative(""))`
/// when they are the same directory, `Some(Relative("a/b"))` for a
/// descendant, `None` for anything outside. Purely lexical — `..` segments
/// are not resolved. The `None` forces callers to decide what a path outside
/// the workspace means instead of letting an absolute string flow on as if
/// it were relative.
pub fn Absolute::relative_to(self : Absolute, root~ : Absolute) -> Relative? {
  match relative_to(self.0, root=root.0) {
    Some(rest) => Some(Relative(rest))
    None => None
  }
}

///|
/// The path with every backslash turned into a forward slash. Purely
/// lexical: no resolution, no deduplication of separators.
pub fn normalize(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
/// Whether `path` is `root` or lives under it, comparing with normalized
/// separators. Purely lexical — `..` segments are not resolved.
pub fn contains(root : String, path : String) -> Bool {
  relative_to(path, root~) is Some(_)
}

///|
/// `path` relative to `root`, with separators normalized: `Some("")` when
/// they are the same directory, `Some("a/b")` for a descendant, `None` for
/// anything outside. Purely lexical — `..` segments are not resolved.
pub fn relative_to(path : String, root~ : String) -> String? {
  let path = normalize(path)
  let root = normalize(root)
  if path == root {
    return Some("")
  }
  let prefix = if root.has_suffix("/") { root } else { root + "/" }
  match path.strip_prefix(prefix) {
    Some(rest) => Some(rest.to_owned())
    None => None
  }
}
