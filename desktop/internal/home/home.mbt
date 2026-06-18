// The user's home directory, and paths expressed relative to it.

///|
/// The user's home directory: `USERPROFILE` on Windows, otherwise `HOME`.
#cfg(platform="windows")
pub fn dir() -> @path.Path? {
  if @env.get("USERPROFILE") is Some(userprofile) {
    return Some(userprofile)
  }
  if @env.get("HOME") is Some(home) {
    return Some(home)
  }
  None
}

///|
#cfg(not(platform="windows"))
pub fn dir() -> @path.Path? {
  if @env.get("HOME") is Some(home) {
    Some(Path(home))
  } else {
    None
  }
}
