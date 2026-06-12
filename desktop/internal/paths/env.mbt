///|
/// `value` trimmed, or `None` when it is absent or blank.
pub fn non_empty(value : String?) -> String? {
  guard value is Some(value) else { return None }
  let value = value.trim().to_owned()
  if value.is_empty() {
    None
  } else {
    Some(value)
  }
}

///|
/// The first non-blank of: the explicit `value`, the `env_name` environment
/// variable, the `fallback`.
pub fn option_or_env(
  value : String?,
  env_name : String,
  fallback : String,
) -> String {
  if non_empty(value) is Some(value) {
    return value
  }
  if non_empty(@env.get_env_var(env_name)) is Some(value) {
    return value
  }
  fallback
}

///|
/// The user's home directory: `HOME`, or `USERPROFILE` on Windows.
pub fn home_dir() -> String? {
  if non_empty(@env.get_env_var("HOME")) is Some(home) {
    return Some(home)
  }
  non_empty(@env.get_env_var("USERPROFILE"))
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
