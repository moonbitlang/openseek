///|
pub async fn exists(path : @pathx.Path) -> Bool {
  @fs.exists(path.to_string())
}

///|
/// True when `path` names a regular executable file — the right probe for
/// "can I spawn this binary". `can_execute` alone is not enough: X_OK on a
/// directory means searchable, so a directory shadowing a binary's name
/// would pass it. Sequenced as two statements — async calls joined with
/// `&&` are evaluated eagerly, and `kind` raises on a missing path. Probe
/// errors (an ENOTDIR from a file-shaped ancestor, a race with deletion)
/// mean "not a usable executable" — a probe answers a question, it does not
/// propagate the filesystem's mood.
pub async fn is_executable_file(path : @pathx.Path) -> Bool {
  try {
    if !@fs.can_execute(path.to_string()) {
      return false
    }
    @fs.kind(path.to_string()) is Regular
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
}

///|
pub async fn try_read_text(path : @pathx.Path) -> String? {
  Some(@fs.read_file(path.to_string()).text()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
pub async fn read_text(path : @pathx.Path) -> String {
  @fs.read_file(path.to_string()).text()
}

///|
pub async fn read_text_if_exists(path : @pathx.Path) -> String? {
  Some(@fs.read_file(path.to_string()).text()) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => None
    error => raise error
  }
}

///|
pub async fn write_text(path : @pathx.Path, content : String) -> Unit {
  @fs.write_file(path.to_string(), content, create_mode=CreateOrTruncate)
}

///|
pub async fn write_bytes(path : @pathx.Path, content : Bytes) -> Unit {
  @fs.write_file(path.to_string(), content, create_mode=CreateOrTruncate)
}

///|
pub async fn is_dir(path : @pathx.Path) -> Bool {
  try @fs.kind(path.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  } noraise {
    kind => kind is Directory
  }
}

///|
/// Copy a file, replacing the destination if it already exists.
pub async fn copy_file(source : @pathx.Path, destination : @pathx.Path) -> Unit {
  let source = source.to_string()
  let destination = destination.to_string()
  let permission = if @fs.can_execute(source) { 0o755 } else { 0o644 }
  @fs.write_file(
    destination,
    @fs.read_file(source),
    create_mode=CreateOrTruncate,
    permission~,
  )
  chmod(destination, permission)
}

///|
/// Copy a directory tree, creating `destination` and every directory beneath
/// it. Files already at the destination are replaced, files only there are
/// left alone. A symlink is copied as the bytes it points at rather than as a
/// link. Raises when the source cannot be read, leaving whatever was copied
/// so far in place — the caller decides whether a partial tree is worth
/// keeping.
pub async fn copy_dir(source : @pathx.Path, destination : @pathx.Path) -> Unit {
  ensure_dir(destination)
  // `collect` closes the handle before we descend, so copying a deep tree
  // does not hold one directory descriptor open per level.
  let entries = Directory(@fs.opendir(source.to_string())).collect()
  for entry in entries {
    let child = source.join(entry.name())
    let target = destination.join(entry.name())
    if entry.is_dir() {
      copy_dir(child, target)
    } else {
      copy_file(child, target)
    }
  }
}

///|
async fn chmod(path : StringView, permission : Int) -> Unit {
  // Windows has no Unix execute bit and async/fs deliberately reports chmod
  // as unsupported there. Keep the operation in this shared implementation so
  // every platform type-checks the real copy path without issuing an async
  // warning for a platform-only no-op.
  if !(@platform.win32 || @platform.win64) {
    @fs.chmod(path, permission)
  }
}

///|
pub async fn ensure_dir(path : @pathx.Path) -> Unit {
  @fs.mkdir(path.to_string(), recursive=true) catch {
    @os_error.OSError(_) as os_error if os_error.is_EEXIST() => ()
    error => raise error
  }
}

///|
pub async fn remove_if_exists(path : @pathx.Path) -> Unit {
  let path = path.to_string()
  try @fs.kind(path) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => ()
    error => raise error
  } noraise {
    Directory => @fs.rmdir(path, recursive=true)
    _ => @fs.remove(path)
  }
}
