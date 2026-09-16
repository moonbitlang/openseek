///|
#cfg(platform="windows")
extern "c" fn current_exe_ffi() -> String = "moonbit_rt_get_current_exe"

///|
#cfg(not(platform="windows"))
extern "c" fn current_exe_ffi() -> Bytes = "moonbit_rt_get_current_exe"

///|
#cfg(not(platform="windows"))
fn current_exe_internal() -> String raise @os_error.OSError {
  let path = current_exe_ffi()
  // The runtime ABI signals failure with an empty native string. Capture its
  // OS error before decoding can allocate or otherwise disturb errno.
  let errno = @os_error.get_errno()
  if path.length() == 0 {
    raise OSError(errno, context="@env.current_exe()")
  }
  @utf8.decode_lossy(path)
}

///|
#cfg(platform="windows")
fn current_exe_internal() -> String raise @os_error.OSError {
  let path = current_exe_ffi()
  let errno = @os_error.get_errno()
  if path.length() == 0 {
    raise OSError(errno, context="@env.current_exe()")
  }
  path
}

///|
fn current_exe_dir_internal() -> String raise @os_error.OSError {
  @path.Path(current_exe_internal()).dirname().to_string()
}

///|
#cfg(platform="windows")
let _unused_unix_import : Unit = ignore(@utf8.decode_lossy(b""))
