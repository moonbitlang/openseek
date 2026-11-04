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
  self.ts.to_int64()
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
  from_sequence~ : Int32,
  to_sequence~ : Int32,
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
/// Re-export the protocol image type that durable user and tool content carries
/// in `Image(image)` parts. Production callers name `Content` instead (see
/// `content.mbt`); tests of other packages reach the protocol image
/// constructors as `@agent_session.Image::from_bytes` / `from_base64`:
/// `agent` (`read_image_test.mbt`, `images_test.mbt`, `ptc_test.mbt`), `viz`
/// (`viz_test.mbt`), `inspect` (`main_wbtest.mbt`),
/// `internal/openseek/serve` (`state_wbtest.mbt`), and
/// `agent_session/store` (`images_test.mbt`, `images_realworld_test.mbt`,
/// `store_test.mbt`).
pub using @protocol {type Image}

///|
/// Return the optional machine-readable metadata recorded with a tool result;
/// never included in model messages.
///
/// The field is durable — it round-trips through the session JSON — and this
/// accessor is how its tests read it back: this package's own
/// `program_data_test.mbt`, and `agent/ptc_test.mbt`, which checks that a
/// program's nested trace is persisted but stays out of model context.
pub fn ToolResult::data(self : ToolResult) -> Json? {
  self.data
}

///|
/// Return the submitting controller's tag, exactly as stored; None for
/// untagged input.
///
/// The tag is durable — it is part of the stored user payload — and this
/// accessor is how tests read it back: `agent/steer_test.mbt` (a steer echoes
/// its tag) and `agent_session/store/store_test.mbt` (a legacy line that
/// carries a tag decodes to it).
pub fn UserMessage::submission_id(self : UserMessage) -> String? {
  self.submission_id
}

///|
/// Return the id of the assistant tool call this result answers. Protocol
/// matching uses this to pair a result with its call; consumers (e.g. a
/// visualizer) can use it to correlate a projected tool message back to its
/// durable result.
pub fn ToolResult::tool_call_id(self : ToolResult) -> String {
  self.tool_call_id
}
