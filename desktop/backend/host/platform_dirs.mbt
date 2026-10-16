///|
/// The current platform's per-user application-data directory, the parent
/// this app's own `SeekMoon` state directory lives under.
pub fn platform_app_data_dir() -> @pathx.Path? {
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
