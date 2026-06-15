// The user's home directory, and paths expressed relative to it.

///|
/// The user's home directory: `USERPROFILE` on Windows, otherwise `HOME`.
pub fn dir() -> String? {
  home_dir_from_env(@env.get("OS"), @env.get("HOME"), @env.get("USERPROFILE"))
}

///|
fn home_dir_from_env(
  os : String?,
  home : String?,
  userprofile : String?,
) -> String? {
  if os is Some("Windows_NT") {
    if userprofile is Some(userprofile) {
      return Some(userprofile)
    }
    return home
  }
  if home is Some(home) {
    return Some(home)
  }
  userprofile
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
