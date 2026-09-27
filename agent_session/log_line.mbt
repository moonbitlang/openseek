///|
/// Encode the event as one session-log line (without the newline), as
/// session.schema.json describes it.
pub fn SessionEvent::to_json_line(self : SessionEvent) -> String {
  // Encoding a session event cannot fail: it has no flattened fields.
  self.to_json_string() catch {
    error => abort("session event encoding failed: \{error}")
  }
}

///|
/// Decode one session-log line. Errors carry serde's message for the first
/// problem in the line (for example ``missing field `item` ``).
pub fn SessionEvent::from_json_line(
  line : StringView,
) -> SessionEvent raise @typify_rt.DeError {
  SessionEvent::from_json_str(line)
}
