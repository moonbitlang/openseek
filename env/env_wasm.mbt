///|
#unsafe_skip_stub_check
fn current_exe_ffi() -> UInt64 = "moonbitlang/core" "env/current_exe"

///|
#unsafe_skip_stub_check
fn current_exe_dir_ffi() -> UInt64 = "moonbitlang/core" "env/current_exe_dir"

///|
#unsafe_skip_stub_check
fn os_string_decode_len(buffer : UInt64, offset : Int, len : Int) -> Int = "moonbitlang/async" "os_string/decode_len"

///|
#unsafe_skip_stub_check
#borrow(path)
fn os_string_decode(
  buffer : UInt64,
  offset : Int,
  len : Int,
  path : String,
  path_len : Int,
) -> Unit = "moonbitlang/async" "os_string/decode"

///|
#unsafe_skip_stub_check
fn free_buffer(buffer : UInt64) -> Unit = "moonbitlang/async" "c_buffer/free"

///|
fn executable_path_from_buffer(
  buffer : UInt64,
  context : String,
) -> String raise @os_error.OSError {
  let errno = @os_error.get_errno()
  if buffer == 0 {
    raise OSError(errno, context~)
  }
  // Each successful import transfers one NUL-terminated native path buffer.
  defer free_buffer(buffer)
  let len = os_string_decode_len(buffer, 0, -1)
  let path = String::make(len, '\u{0}')
  os_string_decode(buffer, 0, -1, path, len)
  path
}

///|
fn current_exe_internal() -> String raise @os_error.OSError {
  executable_path_from_buffer(current_exe_ffi(), "@env.current_exe()")
}

///|
fn current_exe_dir_internal() -> String raise @os_error.OSError {
  executable_path_from_buffer(current_exe_dir_ffi(), "@env.current_exe_dir()")
}

///|
let _unused_native_imports : Unit = ignore(
  (@utf8.decode_lossy(b""), @path.Path::dirname),
)
