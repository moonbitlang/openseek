///|
fn restore_env(name : String, previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var(name, value)
  } else {
    @sys.unset_env_var(name)
  }
}

///|
/// A lock for the two tests below that redirect platform env vars. Only one
/// test at a time may redirect process-wide state, even on different platforms.
let runtime_env_test_lock : @async.Mutex = Mutex()

///|
async test "platform_app_data_dir uses %LOCALAPPDATA% on Windows, falls back to USERPROFILE" {
  if !(@sysplatform.win32 || @sysplatform.win64) {
    return
  }
  runtime_env_test_lock.acquire()
  defer runtime_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-runtime-test-")
  defer @fs.rmdir(dir, recursive=true)
  let previous_local = @sys.get_env_var("LOCALAPPDATA")
  @sys.set_env_var("LOCALAPPDATA", dir + "\\AppData\\Local")
  defer restore_env("LOCALAPPDATA", previous_local)
  let previous_userprofile = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", dir)
  defer restore_env("USERPROFILE", previous_userprofile)
  guard platform_app_data_dir() is Some(app_data) else {
    fail("platform_app_data_dir returned None")
  }
  assert_eq(app_data.to_string(), dir + "\\AppData\\Local")
  @sys.unset_env_var("LOCALAPPDATA")
  guard platform_app_data_dir() is Some(app_data) else {
    fail("platform_app_data_dir returned None after unsetting LOCALAPPDATA")
  }
  assert_eq(app_data.to_string(), dir + "\\AppData\\Local")
}

///|
async test "platform_app_data_dir uses XDG_DATA_HOME on Linux, falls back to ~/.local/share" {
  if @sysplatform.win32 || @sysplatform.win64 {
    return
  }
  if @platform.is_darwin() {
    return
  }
  runtime_env_test_lock.acquire()
  defer runtime_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-runtime-test-")
  defer @fs.rmdir(dir, recursive=true)
  let previous_xdg = @sys.get_env_var("XDG_DATA_HOME")
  @sys.set_env_var("XDG_DATA_HOME", dir + "/xdg-data")
  defer restore_env("XDG_DATA_HOME", previous_xdg)
  let previous_home = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", dir)
  defer restore_env("HOME", previous_home)
  guard platform_app_data_dir() is Some(app_data) else {
    fail("platform_app_data_dir returned None with XDG_DATA_HOME set")
  }
  assert_eq(app_data.to_string(), dir + "/xdg-data")
  @sys.unset_env_var("XDG_DATA_HOME")
  guard platform_app_data_dir() is Some(app_data) else {
    fail("platform_app_data_dir returned None after unsetting XDG_DATA_HOME")
  }
  assert_eq(app_data.to_string(), dir + "/.local/share")
}
