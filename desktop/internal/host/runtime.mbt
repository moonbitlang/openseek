///|
/// Per-user runtime directory for the host's own state (launch logs, the LSP
/// traffic log, sessions). It lives here instead of inside the .app bundle: a
/// signed bundle is read-only by convention (and may be mounted read-only under
/// app translocation), and writing next to the binary also breaks when a
/// repackage replaces the bundle under a running instance. Picked by compile-
/// time platform, not by probing which directories happen to exist: a stray
/// `~/Library/Application Support` (left by some unrelated app, or by an
/// earlier build of this very check) must never steer Windows or Linux onto
/// the macOS path. Uses each platform's own per-user app-data convention:
/// `~/Library/Application Support/SeekMoon` on macOS, `%LOCALAPPDATA%\SeekMoon`
/// on Windows, and `$XDG_DATA_HOME/SeekMoon` (falling back to
/// `~/.local/share/SeekMoon`) elsewhere. An unbundled Moon host instead keeps
/// state under the detected checkout's `desktop/target/dev-state`.
fn app_runtime_dir(executable : String) -> @pathx.Path? {
  if @development.Layout::detect(executable) is Some(layout) {
    let state : @pathx.Path = layout.state_dir()
    return Some(state)
  }
  guard platform_app_data_dir() is Some(app_data) else { return None }
  Some(app_data.join("SeekMoon").normalize())
}

///|
/// The current platform's per-user application-data directory, the parent
/// this app's own `SeekMoon` state directory lives under.
fn platform_app_data_dir() -> @pathx.Path? {
  if @platform.is_darwin() {
    guard @home.dir() is Some(home) else { return None }
    return Some(home.join("Library").join("Application Support"))
  }
  if @sysplatform.win32 || @sysplatform.win64 {
    if @env.get("LOCALAPPDATA") is Some(local_app_data) {
      return Some(local_app_data)
    }
    guard @home.dir() is Some(home) else { return None }
    return Some(home.join("AppData").join("Local"))
  }
  if @env.get("XDG_DATA_HOME") is Some(xdg_data_home) {
    return Some(xdg_data_home)
  }
  guard @home.dir() is Some(home) else { return None }
  Some(home.join(".local").join("share"))
}

///|
/// The runtime directory, created on demand. `None` when it cannot be
/// determined or created; callers then fall back to runtime defaults.
pub async fn prepared_runtime_dir(executable : String) -> @pathx.Path? {
  guard app_runtime_dir(executable) is Some(dir) else { return None }
  let exists = (@fs.kind(dir.to_string()) is Directory) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => false
    error => raise error
  }
  if !exists {
    @fs.mkdir(dir.to_string(), recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return None
    }
  }
  Some(dir)
}

///|
/// A lock for the two tests below that redirect platform env vars. Only one
/// test at a time may redirect process-wide state, even on different platforms.
let runtime_env_test_lock : @async.Mutex = Mutex()

///|
fn restore_env(name : String, previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var(name, value)
  } else {
    @sys.unset_env_var(name)
  }
}

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

///|
async test "development state stays inside the detected checkout" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-state-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let command_dir = root.join("_build/native/debug/build/openseek_desktop")
  @fs.mkdir(command_dir.to_string(), recursive=true)
  let executable = command_dir.join("openseek_desktop.exe").to_string()
  let expected = root.join("desktop/target/dev-state").to_string()
  guard prepared_runtime_dir(executable) is Some(actual) else {
    fail("detected development state directory was not created")
  }
  assert_eq(actual.to_string(), expected)
  assert_true(@fs.kind(expected) is Directory)
}
