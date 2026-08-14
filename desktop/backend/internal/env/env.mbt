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
