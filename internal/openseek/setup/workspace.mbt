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
  match probe_dir(dir) {
    Exists(root) => root
    Absent(..) => {
      @fs.mkdir(dir)
      let root = @fs.realpath(dir)
      if log_created {
        @emit.emit(WorkspaceCreated(dir=root))
      }
      root
    }
  }
}

///|
/// How a `--dir` argument resolves: `Exists(root)` for a directory that is
/// already there (path resolved), or `Absent(parent~, base~)` for one that is
/// not but whose parent is an existing directory (`parent` resolved, `base` the
/// final component). Fails when the path is a file, when the parent is missing,
/// or when the parent is not a directory — the one contract every `--dir`
/// consumer shares, so a single run and a fleet accept the same inputs.
pub(all) enum DirProbe {
  Exists(String)
  Absent(parent~ : String, base~ : String)
}

///|
/// Classify a `--dir` argument as a `DirProbe`, raising the shared
/// validation failures on the way.
pub async fn probe_dir(dir : String) -> DirProbe {
  if dir.is_empty() {
    fail("--dir must not be empty")
  }
  if @fs.exists(dir) {
    if @fs.kind(dir) != Directory {
      fail("--dir is not a directory: \{dir}")
    }
    return Exists(@fs.realpath(dir))
  }
  let parent = @path.Path(dir).dirname().to_string()
  let parent = if parent == "" { "." } else { parent }
  if !@fs.exists(parent) {
    fail("parent directory for --dir does not exist: \{parent}")
  }
  if @fs.kind(parent) != Directory {
    fail("parent path for --dir is not a directory: \{parent}")
  }
  Absent(
    parent=@fs.realpath(parent),
    base=@path.Path(dir).basename().to_owned(),
  )
}

///|
/// Remove trailing path separators while preserving filesystem roots.
pub fn trim_trailing_path_separators(path : String) -> String {
  let mut result = path
  while !is_path_root(result) && result[:] is [.. rest, '/' | '\\'] {
    result = rest.to_owned()
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
