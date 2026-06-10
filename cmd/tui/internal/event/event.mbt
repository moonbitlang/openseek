// The decoded, in-memory form of the engine's JSONL event stream. The `openseek`
// engine writes one JSON object per line to stdout; `decode_event` (see
// `decode.mbt`) maps each into an `AgentEvent`. The `cmd/tui` rendering loop
// pattern-matches on these types and never touches the wire format.

///|
/// Token accounting decoded from a `usage` event.
///
/// The engine reports prompt/completion/cache counts; only the derived total
/// (`prompt + completion`) is shown in the status line, so that is all we keep.
pub(all) struct UsageInfo {
  total_tokens : Int
}

///|
/// The result of a tool call after the engine ran it.
pub(all) struct ToolResultEvent {
  name : String
  content : String
  is_error : Bool
}

///|
/// Decoded agent progress events, one per JSONL line from the engine.
///
/// Variant names mirror the engine's wire `event` strings (`agent_step` →
/// `AgentStep`, `tool_result` → `ToolResult`, …) so decoding is a near-identity
/// map. `AgentError` is the exception: it carries both the engine's
/// `agent_setup_failed` and the TUI-synthesized "engine exited without a result"
/// error, so it stays a general category rather than a single wire event.
///
/// Terminal events (`AgentFinished`, `AgentAborted`, `MaxStepsExhausted`,
/// `AgentError`) leave the agent idle so the message loop can drain the next
/// queued input.
pub(all) enum AgentEvent {
  AgentStep
  AssistantDelta(String)
  ReasoningDelta(String)
  AssistantMessage(String)
  RuntimeUpdate(String)
  Usage(UsageInfo)
  ToolResult(ToolResultEvent)
  AgentFinished(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentError(String)
}
