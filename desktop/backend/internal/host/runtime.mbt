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
      _ => return None
    }
  }
  Some(dir)
}
