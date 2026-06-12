// The user's home directory, and paths expressed relative to it.

///|
/// The user's home directory: `HOME`, or `USERPROFILE` on Windows.
pub fn dir() -> String? {
  if @env.get("HOME") is Some(home) {
    return Some(home)
  }
  @env.get("USERPROFILE")
}

///|
/// Expand a leading `~` to the home directory; anything else passes through.
pub fn expand(cwd : String) -> String {
  guard dir() is Some(home) else { return cwd }
  if cwd == "~" {
    home
  } else if cwd.has_prefix("~/") {
    home + cwd[1:].to_owned()
  } else {
    cwd
  }
}
