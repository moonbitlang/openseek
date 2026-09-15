///|
/// The lowest child ordinal no session `<parent>-sr-N` in the store has
/// used yet: the floor a resumed parent hands the runner so a restarted
/// engine process never reuses a persisted child session id.
pub async fn first_free_child_ordinal(
  store : @store.SessionStore,
  parent : String,
) -> Int {
  let highest = store
    .list()
    .iter()
    .filter_map(id => child_session_ordinal(id.value(), parent))
    .maximum()
    .unwrap_or(0)
  highest + 1
}

///|
/// The N of a `<parent>-sr-N` child session id, or `None` for any other id
/// (bounded to 9 digits so a pathological name cannot overflow).
fn child_session_ordinal(id : String, parent : String) -> Int? {
  guard id.strip_prefix("\{parent}-sr-") is Some(digits) else { return None }
  guard !digits.is_empty() &&
    digits.length() <= 9 &&
    digits.all(c => c.is_ascii_digit()) else {
    return None
  }
  let value = for c in digits; value = 0 {
    continue value * 10 + (c.to_int() - '0'.to_int())
  } nobreak {
    value
  }
  Some(value)
}

///|
/// The executable to spawn for a child sub-run: this process's own binary,
/// resolved from argv[0]. A path with a separator is made absolute (the
/// child runs with a different cwd, so a relative path would break); a bare
/// name stays PATH-resolved, matching however this process was launched.
/// Never hardcode a name: parent and child must be the SAME binary, or the
/// typed report channel's same-codec guarantee is gone.
pub async fn self_executable() -> String {
  let argv0 = match @env.args() {
    [first, ..] => first
    _ => "openseek"
  }
  if argv0.contains("/") || argv0.contains("\\") {
    @fs.realpath(argv0) catch {
      _ => argv0
    }
  } else {
    argv0
  }
}
