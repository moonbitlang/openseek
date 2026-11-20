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
  if !(@async.platform is Windows) {
    return
  }
  runtime_env_test_lock.acquire()
  defer runtime_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-runtime-test-")
  defer @fs.remove(dir, recursive=true)
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
  if @async.platform is Windows {
    return
  }
  if @async.platform is MacOS {
    return
  }
  runtime_env_test_lock.acquire()
  defer runtime_env_test_lock.release()
  let dir = @fs.tmpdir(prefix="openseek-runtime-test-")
  defer @fs.remove(dir, recursive=true)
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

///|
test "a development bundle keeps its own state directory" {
  // The name a bundle is installed under is the only difference the runtime can
  // see between a release and a local package of the same app, and the two must
  // not share one `engine-settings.json`: a newer schema written by one makes
  // the other refuse to save.
  assert_eq(
    state_dir_name("/Applications/SeekMoon-dev.app/Contents/MacOS/seekmoon"),
    "SeekMoon-dev",
  )
  // The debug package the build produces is named without a separator.
  assert_eq(
    state_dir_name("/Users/x/dist/SeekMoonDev.app/Contents/MacOS/seekmoon"),
    "SeekMoon-dev",
  )
  assert_eq(
    state_dir_name("/Users/x/SeekMoon Dev.app/Contents/MacOS/seekmoon"),
    "SeekMoon-dev",
  )
  // A mounted image of the release is the same app, not a second profile.
  assert_eq(
    state_dir_name("/Applications/SeekMoon.app/Contents/MacOS/seekmoon"),
    "SeekMoon",
  )
  assert_eq(
    state_dir_name("/Volumes/SeekMoon/SeekMoon.app/Contents/MacOS/seekmoon"),
    "SeekMoon",
  )
}

///|
async test "an explicit state directory wins over the bundle's name" {
  runtime_env_test_lock.acquire()
  defer runtime_env_test_lock.release()
  let previous = @sys.get_env_var("SEEKMOON_STATE_DIR")
  @sys.set_env_var("SEEKMOON_STATE_DIR", "/tmp/seekmoon-profile")
  defer restore_env("SEEKMOON_STATE_DIR", previous)
  let executable = "/Applications/SeekMoon.app/Contents/MacOS/seekmoon"
  guard app_runtime_dir(executable) is Some(dir) else {
    fail("an explicit state directory must be honoured")
  }
  assert_eq(dir.to_string(), "/tmp/seekmoon-profile")
  // A blank value is not a directory: the bundle's own profile still applies.
  @sys.set_env_var("SEEKMOON_STATE_DIR", "   ")
  guard app_runtime_dir(executable) is Some(dir) else {
    fail("the bundle profile must still resolve")
  }
  assert_true(dir.to_string().has_suffix("SeekMoon"))
}
