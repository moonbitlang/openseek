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
  SteerApplied(String)
  SteerDropped(String)
  Usage(UsageInfo)
  ToolResult(ToolResultEvent)
  AgentFinished(String)
  // The turn stopped at the model's context ceiling after attempting an
  // automatic checkpoint. Terminal for the run, but not task success.
  ContextYield(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentError(String)
  // Compaction lifecycle: `started` is informational; finished/failed mean
  // the engine is done touching the durable record (the host gates archiving
  // on that). Not terminal for any run — compaction happens between turns.
  CompactionStarted
  CompactionFinished
  CompactionFailed
}
