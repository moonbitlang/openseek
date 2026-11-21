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
/// `~/.local/share/SeekMoon`) elsewhere. A bundle whose name marks it as a
/// development build (`SeekMoon-dev.app`, `SeekMoon Dev.app`) keeps
/// `SeekMoon-dev` instead, so a locally packaged app can run beside an
/// installed release without the two sharing one settings file.
/// `SEEKMOON_STATE_DIR` overrides the whole decision with an absolute
/// directory. An unbundled Moon host instead keeps state under the detected
/// checkout's `desktop/target/dev-state`.
fn app_runtime_dir(executable : String) -> @pathx.Path? {
  if @development.Layout::detect(executable) is Some(layout) {
    let state : @pathx.Path = layout.state_dir()
    return Some(state)
  }
  if @env.get("SEEKMOON_STATE_DIR") is Some(dir) {
    guard !dir.is_blank() else { return None }
    let path : @pathx.Path = Path(dir)
    return Some(path.normalize())
  }
  guard platform_app_data_dir() is Some(app_data) else { return None }
  Some(app_data.join(state_dir_name(executable)).normalize())
}

///|
/// The state directory one bundle owns. The bundle's own name is the only
/// difference the runtime can see between a release and a locally packaged
/// build of the same app, and those two must not share an
/// `engine-settings.json`: a newer schema written by one makes the other
/// refuse to save.
fn state_dir_name(executable : String) -> String {
  // The debug package the build makes is `SeekMoonDev.app`; a release bundle
  // copied aside for local verification is usually `SeekMoon-dev.app`.
  if executable.contains("SeekMoonDev.app") ||
    executable.contains("SeekMoon-dev.app") ||
    executable.contains("SeekMoon Dev.app") {
    "SeekMoon-dev"
  } else {
    "SeekMoon"
  }
}

///|
/// The current platform's per-user application-data directory, the parent
/// this app's own `SeekMoon` state directory lives under.
fn platform_app_data_dir() -> @pathx.Path? {
  if @async.platform is MacOS {
    guard @home.dir() is Some(home) else { return None }
    return Some(home.join("Library").join("Application Support"))
  }
  if @async.platform is Windows {
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
    @os_error.OsError(NotFound, ..) => false
    error => raise error
  }
  if !exists {
    @fs.mkdir(dir.to_string(), recursive=true) catch {
      _ => return None
    }
  }
  Some(dir)
}
