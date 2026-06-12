// Process-environment reads, under the usual convention that a blank
// variable means "unset" and values are used trimmed.

///|
/// The `name` environment variable, trimmed; `None` when unset or blank.
pub fn get(name : String) -> String? {
  guard @sys.get_env_var(name) is Some(value) else { return None }
  let value = value.trim().to_owned()
  if value.is_empty() {
    None
  } else {
    Some(value)
  }
}

///|
/// The user's home directory: `HOME`, or `USERPROFILE` on Windows.
pub fn home_dir() -> String? {
  if get("HOME") is Some(home) {
    return Some(home)
  }
  get("USERPROFILE")
}

///|
/// Expand a leading `~` to the home directory; anything else passes through.
pub fn expand_home(cwd : String) -> String {
  guard home_dir() is Some(home) else { return cwd }
  if cwd == "~" {
    home
  } else if cwd.has_prefix("~/") {
    home + cwd[1:].to_owned()
  } else {
    cwd
  }
}
