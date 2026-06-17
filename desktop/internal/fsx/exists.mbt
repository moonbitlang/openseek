///|
pub async fn exists(path : @path.Path) -> Bool {
  @fs.exists(path.to_string())
}

///|
pub async fn try_read_text(path : @path.Path) -> String? {
  Some(@fs.read_file(path.to_string()).text()) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => return None
    error => raise error
  }
}

///|
pub async fn read_text(path : @path.Path) -> String {
  @fs.read_file(path.to_string()).text()
}

///|
pub async fn write_text(path : @path.Path, content : String) -> Unit {
  @fs.write_file(path.to_string(), content, create_mode=CreateOrTruncate)
}

///|
pub async fn is_dir(path : @path.Path) -> Bool {
  try @fs.kind(path.to_string()) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => return false
    error => raise error
  } noraise {
    kind => kind is Directory
  }
}

///|
/// Copy a file, replacing the destination if it already exists.
pub async fn copy_file(source : @path.Path, destination : @path.Path) -> Unit {
  @fs.write_file(
    destination.to_string(),
    @fs.read_file(source.to_string()),
    create_mode=CreateOrTruncate,
  )
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
