// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Return when the event was appended, as unix milliseconds.
///
/// A value of `0` means the event was created without a clock, which is the
/// default for pure in-memory `Session::append` and `append_event` calls. The
/// filesystem store always passes a real wall-clock timestamp.
pub fn SessionEvent::unix_ms(self : SessionEvent) -> Int64 {
  self.ts
}

///|
/// Build a summary for an inclusive event sequence range.
///
/// This constructor stores the values exactly as supplied and does not validate
/// that the range is non-empty, positive, or present in a session. Prefer
/// `Session::compact` when creating a summary event for a real session because
/// it validates content and range before appending.
pub fn SessionSummary::SessionSummary(
  content~ : String,
  from_sequence~ : Int,
  to_sequence~ : Int,
) -> SessionSummary {
  { content, from_sequence, to_sequence, }
}

///|
/// Return the optional one-line human summary of the call, or `None` for results
/// recorded before briefs existed (or by tools that supply none). Display only —
/// never part of what the model is replayed.
pub fn ToolResult::brief(self : ToolResult) -> String? {
  self.brief
}

///|
/// Return the id of the assistant tool call this result answers. Protocol
/// matching uses this to pair a result with its call; consumers (e.g. a
/// visualizer) can use it to correlate a projected tool message back to its
/// durable result.
pub fn ToolResult::tool_call_id(self : ToolResult) -> String {
  self.tool_call_id
}
