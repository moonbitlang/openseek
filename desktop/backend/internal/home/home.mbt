// The user's home directory, and paths expressed relative to it.

///|
/// The user's home directory: `USERPROFILE` on Windows, otherwise `HOME`.
#cfg(platform="windows")
pub fn dir() -> @pathx.Path? {
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
pub fn dir() -> @pathx.Path? {
  if @env.get("HOME") is Some(home) {
    Some(Path(home))
  } else {
    None
  }
}

///|
/// Expand a leading `~` (the agent often writes paths home-relative) to the
/// user's home directory; other paths pass through unchanged.
pub fn expand(path : @pathx.Path) -> @pathx.Path {
  if path.0 == "~" && dir() is Some(home) {
    home
  } else if path.0.strip_prefix("~/") is Some(rest) && dir() is Some(home) {
    home.join(Relative(rest.to_owned()))
  } else {
    path
  }
}
