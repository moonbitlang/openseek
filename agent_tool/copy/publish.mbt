///|
priv struct CopyDestination {
  resolved_path : String
  existed : Bool
  staging_parent : String
}

///|
fn is_mbt_source(path : String) -> Bool {
  path.has_suffix(".mbt") || path.has_suffix(".mbt.md")
}

///|
fn requires_text(path : String) -> Bool {
  is_mbt_source(path) ||
  path.has_suffix(".mbtx") ||
  path.has_suffix(".mbti") ||
  @manifest_path.is_moon_mod_path(path) ||
  @manifest_path.is_moon_mod_json_path(path) ||
  @manifest_path.is_moon_pkg_path(path)
}

///|
async fn inspect_destination(path : String) -> CopyDestination {
  let exists = @fs.exists(path)
  let target = if exists { @fs.realpath(path) } else { path }
  guard !(exists && (is_mbt_source(path) || is_mbt_source(target))) else {
    fail("cannot overwrite an existing source file; use edit or multi_edit")
  }
  if exists {
    guard @fs.kind(target) is Regular && @fs.can_write(target) else {
      fail("copy can only replace writable regular files")
    }
  } else if (@fs.kind(path, follow_symlink=false) catch { _ => Unknown })
    is SymLink {
    fail("copy cannot write through a dangling symbolic link")
  }
  let basename = @path.Path(target).basename()
  guard !basename.is_empty() && target.has_suffix(basename) else {
    fail("copy requires a file destination")
  }
  let mut parent = @path.Path(target).dirname().to_string()
  let mut relative = @path.Path(basename.to_owned())
  while !@fs.exists(parent) {
    let directory = @path.Path(parent)
    let next = directory.dirname().to_string()
    guard next != parent else {
      fail("cannot resolve copy destination directory")
    }
    relative = @path.Path(directory.basename().to_owned()).join(relative)
    parent = next
  }
  let staging_parent = @fs.realpath(parent)
  guard @fs.kind(staging_parent) is Directory else {
    fail("copy destination parent must be a directory")
  }
  {
    resolved_path: @path.Path(staging_parent)
    .join(relative)
    .normalize()
    .to_string(),
    existed: exists,
    staging_parent,
  }
}

///|
async fn recheck_destination(path : String, expected : CopyDestination) -> Unit {
  let current = inspect_destination(path)
  // Another operation may have created a parent we would have made anyway.
  guard current.resolved_path == expected.resolved_path &&
    current.existed == expected.existed else {
    fail("file target changed before copying; re-read and retry")
  }
}
