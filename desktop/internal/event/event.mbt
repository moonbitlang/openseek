// Decoded form of the OpenSeek engine JSONL event stream.

///|
/// Token accounting decoded from a `usage` event.
pub(all) struct UsageInfo {
  total_tokens : Int
}

///|
/// The result of one tool call after the engine ran it.
pub(all) struct ToolResultEvent {
  name : String
  content : String
  is_error : Bool
}

///|
/// Decoded agent progress events, one per JSONL object from the engine.
pub(all) enum AgentEvent {
  AgentStep
  AssistantMessage(String)
  RuntimeUpdate(String)
  SteerApplied(String)
  SteerDropped(String)
  Usage(UsageInfo)
  ToolResult(ToolResultEvent)
  AgentFinished(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentError(String)
}
