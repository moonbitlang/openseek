///|
/// Extracts the user-facing message from MoonBit's default `fail(...)` error
/// rendering. This keeps tool argument errors stable when validation lives in
/// an internal package and the raw error string includes source locations.
pub fn failure_message(error_text : String) -> String {
  lexmatch error_text {
    // Greedy across lines to the LAST ` FAILED: ` marker — the same piece
    // rev_find chose.
    (re"^(.|\n)* FAILED: ", after=message) =>
      message.strip_suffix(")").unwrap_or(message).to_owned()
    _ => error_text
  }
}
