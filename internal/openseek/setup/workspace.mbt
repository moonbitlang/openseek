///|
/// Resolve the workspace and create a missing final directory when its parent exists.
pub async fn prepare_workspace_root(
  matches : @argparse.Matches,
  log_created? : Bool = true,
) -> String {
  let dir_input = match matches {
    { values: { "dir": [dir, ..], .. }, .. } => dir
    _ => fail("missing parsed argument: dir")
  }
  let dir = trim_trailing_path_separators("\{dir_input.trim()}")
  if dir.is_empty() {
    fail("--dir must not be empty")
  }
  if @fs.exists(dir) {
    if @fs.kind(dir) != Directory {
      fail("--dir is not a directory: \{dir}")
    }
    return @fs.realpath(dir)
  }
  let parent = @path.Path(dir).dirname().to_string()
  let parent = if parent == "" { "." } else { parent }
  if !@fs.exists(parent) {
    fail("parent directory for --dir does not exist: \{parent}")
  }
  if @fs.kind(parent) != Directory {
    fail("parent path for --dir is not a directory: \{parent}")
  }
  @fs.mkdir(dir)
  let root = @fs.realpath(dir)
  if log_created {
    @emit.emit(WorkspaceCreated(dir=root))
  }
  root
}

///|
/// Remove trailing path separators while preserving filesystem roots.
pub fn trim_trailing_path_separators(path : String) -> String {
  let mut result = path
  while !is_path_root(result) {
    if result.strip_suffix("/") is Some(rest) {
      result = rest.to_owned()
    } else if result.strip_suffix("\\") is Some(rest) {
      result = rest.to_owned()
    } else {
      break
    }
  }
  result
}

///|
fn is_path_root(path : String) -> Bool {
  path == "/" ||
  path == "\\" ||
  path == "//" ||
  path == "\\\\" ||
  is_windows_drive_root(path)
}

///|
fn is_windows_drive_root(path : String) -> Bool {
  path.length() == 3 &&
  path[1] == ':' &&
  (path.has_suffix("/") || path.has_suffix("\\"))
}
