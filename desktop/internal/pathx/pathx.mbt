// Cross-platform path-string comparison. `@path.Path` renders with the
// host separator (backslashes on Windows) while URIs, manifests, and the
// frontend speak forward slashes, so any prefix test between the two worlds
// must normalize first. These helpers own that dance; callers never
// hand-roll `replace_all` + `has_prefix` again.

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
