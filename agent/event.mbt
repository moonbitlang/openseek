///|
/// Tool call metadata emitted by the event-driven agent runner before local
/// execution starts.
pub struct ToolCallEvent {
  id : String
  name : String
  arguments : String
}

///|
/// Tool result metadata emitted after a local tool returns a normal response.
pub struct ToolResultEvent {
  id : String
  name : String
  content : String
  is_error : Bool
}

///|
/// Structured progress events produced by `run` and passed to its `on_event`
/// handler.
pub(all) enum AgentEvent {
  StepStarted(Int)
  AssistantMessage(String)
  ReasoningMessage(String)
  Usage(@deepseek.Usage)
  ToolCallStarted(ToolCallEvent)
  ToolCallFinished(ToolResultEvent)
  Finished(String)
  Aborted(String)
  MaxStepsExhausted
  AgentError(String)
}
