///|
pub async fn exists(path : @path.Path) -> Bool {
  @fs.exists(path.to_string())
}

///|
pub async fn try_read_text(path : @path.Path) -> String? {
  Some(@fs.read_file(path.to_string()).text()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
pub async fn read_text(path : @path.Path) -> String {
  @fs.read_file(path.to_string()).text()
}

///|
pub async fn read_text_if_exists(path : @path.Path) -> String? {
  Some(@fs.read_file(path.to_string()).text()) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => None
    error => raise error
  }
}

///|
pub async fn write_text(path : @path.Path, content : String) -> Unit {
  @fs.write_file(path.to_string(), content, create_mode=CreateOrTruncate)
}

///|
pub async fn write_bytes(path : @path.Path, content : Bytes) -> Unit {
  @fs.write_file(path.to_string(), content, create_mode=CreateOrTruncate)
}

///|
pub async fn is_dir(path : @path.Path) -> Bool {
  try @fs.kind(path.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  } noraise {
    kind => kind is Directory
  }
}

///|
/// Copy a file, replacing the destination if it already exists.
pub async fn copy_file(source : @path.Path, destination : @path.Path) -> Unit {
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
#cfg(not(platform="windows"))
async fn chmod(path : StringView, permission : Int) -> Unit {
  @fs.chmod(path, permission)
}

///|
#cfg(platform="windows")
async fn chmod(_ : StringView, _ : Int) -> Unit {
  ()
}

///|
pub async fn ensure_dir(path : @path.Path) -> Unit {
  @fs.mkdir(path.to_string(), recursive=true) catch {
    @os_error.OSError(_) as os_error if os_error.is_EEXIST() => ()
    error => raise error
  }
}

///|
pub async fn remove_if_exists(path : @path.Path) -> Unit {
  let path = path.to_string()
  try @fs.kind(path) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => ()
    error => raise error
  } noraise {
    Directory => @fs.rmdir(path, recursive=true)
    _ => @fs.remove(path)
  }
}
