///|
/// Whether `workspace_root` selects the default (pre-workspace) behavior: both
/// an empty root and "." mean "leave paths as-is".
fn is_default_root(workspace_root : String) -> Bool {
  workspace_root == "" || workspace_root == "."
}

///|
/// Remove trailing `/` separators without collapsing a filesystem root.
pub fn strip_trailing_slash(path : String) -> String {
  for view = path[:] {
    match view {
      [.. rest, '/'] if rest.length() > 0 => continue rest
      _ =>
        break if view.length() == path.length() {
          path
        } else {
          view.to_owned()
        }
    }
  }
}

///|
/// Return the final lexical component of `path`.
///
/// Backslashes are treated as separators and trailing slashes are removed
/// without collapsing a filesystem root. The path is not resolved against the
/// filesystem and `.` or `..` components are not normalized.
pub fn path_basename(path : String) -> String {
  let normalized = workspace_compare_path(path)
  match normalized.rev_after("/") {
    Some(base) => base.to_owned()
    None => normalized
  }
}

///|
/// Return whether `path` is `root` itself or lexically below it.
///
/// Comparison is case-sensitive. Backslashes are treated as separators and
/// trailing slashes are ignored, but `.` and `..` components and symlinks are
/// not resolved. Callers comparing user input should normalize or resolve it
/// first.
pub fn is_under_workspace_root(root : String, path : String) -> Bool {
  let root = workspace_compare_path(root)
  let path = workspace_compare_path(path)
  if path == root {
    true
  } else if root == "/" {
    path.has_prefix("/")
  } else {
    path.has_prefix("\{root}/")
  }
}

///|
fn workspace_compare_path(path : String) -> String {
  strip_trailing_slash(path.replace_all(old="\\", new="/"))
}

///|
/// Return the lexical parent of a POSIX or Windows-style path.
pub fn parent_dir(path : String) -> String? {
  let normalized = workspace_compare_path(path)
  if normalized == "" ||
    normalized == "." ||
    normalized == "/" ||
    (normalized.length() == 2 && normalized[1] == ':') {
    return None
  }
  // An empty part before the last slash means the slash was the leading one,
  // so the parent is the root itself rather than "".
  match normalized.rev_split_once("/") {
    Some(([], _)) => Some("/")
    Some((dir, _)) => Some(dir.to_owned())
    None => Some(".")
  }
}

///|
/// Append one basename to a lexical directory path.
pub fn join_child(dir : String, base : String) -> String {
  if dir == "" || dir == "." {
    base
  } else if dir.has_suffix("/") {
    "\{dir}\{base}"
  } else {
    "\{dir}/\{base}"
  }
}

///|
/// Resolve a tool path against the agent workspace root. Absolute paths are
/// already explicit, and the default root "." intentionally preserves the
/// pre-workspace behavior and output text.
pub fn resolve(workspace_root : String, path : String) -> String {
  if path == "" ||
    is_default_root(workspace_root) ||
    @path.Path(path).is_absolute() {
    path
  } else {
    @path.Path(workspace_root).join(Path(path)).normalize().to_string()
  }
}

///|
/// Resolve an optional cwd. A missing or empty cwd means the workspace root;
/// with the default root "." this remains the old current-directory behavior.
pub fn resolve_cwd(workspace_root : String, cwd : String?) -> String? {
  match cwd {
    Some(cwd) if cwd != "" => Some(resolve(workspace_root, cwd))
    _ if is_default_root(workspace_root) => None
    _ => Some(workspace_root)
  }
}
