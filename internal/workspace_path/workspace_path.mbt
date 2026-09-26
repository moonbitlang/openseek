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
/// Return the lexical parent without changing the path's separator spelling.
/// This is for filesystem operations whose provenance keys must match the
/// caller's original path string.
pub fn parent_dir_preserving_separators(path : String) -> String? {
  let mut end = path.length()
  while end > 1 &&
        is_separator(path[end - 1]) &&
        !(end == 3 && path[1] == ':' && is_separator(path[2])) {
    end -= 1
  }
  let path = path[:end].to_owned()
  if path == "" ||
    path == "." ||
    path == "/" ||
    path == "\\" ||
    (path.length() == 2 && path[1] == ':') ||
    (path.length() == 3 && path[1] == ':' && is_separator(path[2])) {
    return None
  }
  let separator_index = match (path.rev_find("/"), path.rev_find("\\")) {
    (Some(slash), Some(backslash)) =>
      Some(if slash > backslash { slash } else { backslash })
    (Some(slash), None) => Some(slash)
    (None, Some(backslash)) => Some(backslash)
    (None, None) => None
  }
  match separator_index {
    None => Some(".")
    Some(0) => Some(path[:1].to_owned())
    Some(2) if path[1] == ':' => Some(path[:3].to_owned())
    Some(index) => Some(path[:index].to_owned())
  }
}

///|
fn is_separator(unit : UInt16) -> Bool {
  unit == '/'.to_int().to_uint16() || unit == '\\'.to_int().to_uint16()
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
/// Append one basename while keeping the separator style already used by the
/// directory path.
pub fn join_child_preserving_separator(dir : String, base : String) -> String {
  if dir == "" || dir == "." {
    base
  } else if dir.has_suffix("/") || dir.has_suffix("\\") {
    "\{dir}\{base}"
  } else {
    let separator = match (dir.rev_find("/"), dir.rev_find("\\")) {
      (Some(slash), Some(backslash)) if slash > backslash => "/"
      (Some(_), None) => "/"
      (None, Some(_)) => "\\"
      _ => "/"
    }
    "\{dir}\{separator}\{base}"
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
