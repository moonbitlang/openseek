///|
/// A normalized engine event. The raw bridge callback is positional and tagged
/// by a `String`; this enum is the form `update()` matches on, so each case
/// carries only the fields that event actually uses and the match is exhaustive.
priv enum EngineEvent {
  AgentStep(String)
  AssistantDelta(String)
  ReasoningDelta(String)
  ReasoningMessage(String)
  AssistantMessage(String)
  RuntimeUpdate(String)
  Usage(prompt_tokens~ : Int, completion_tokens~ : Int)
  ToolResult(tool_name~ : String, is_error~ : Bool, content~ : String)
  ToolCallDecodeError(tool_name~ : String, reason~ : String)
  AgentFinished(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentSetupFailed(String)
  // Steering input settled by the engine: applied at a step boundary, or
  // dropped because it raced the turn's end. Both echo the original text.
  SteerApplied(String)
  SteerDropped(String)
}

///|
/// Normalize the positional bridge payload into a typed event. Unknown event
/// names decode to `None` and are dropped at the bridge, so the stringly-typed
/// tag never escapes into the update logic.
fn decode_engine_event(
  event_name : String,
  content : String,
  tool_name : String,
  is_error : Bool,
  prompt_tokens : Int,
  completion_tokens : Int,
  answer : String,
  reason : String,
) -> EngineEvent? {
  match event_name {
    "agent_step" => Some(AgentStep(content))
    "assistant_delta" => Some(AssistantDelta(content))
    "reasoning_delta" => Some(ReasoningDelta(content))
    "reasoning_message" => Some(ReasoningMessage(content))
    "assistant_message" => Some(AssistantMessage(content))
    "runtime_update" => Some(RuntimeUpdate(content))
    "usage" => Some(Usage(prompt_tokens~, completion_tokens~))
    "tool_result" => Some(ToolResult(tool_name~, is_error~, content~))
    "tool_call_decode_error" => Some(ToolCallDecodeError(tool_name~, reason~))
    "agent_finished" => Some(AgentFinished(answer))
    "agent_aborted" => Some(AgentAborted(reason))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" => Some(AgentSetupFailed(reason))
    "steer_applied" => Some(SteerApplied(content))
    "steer_dropped" => Some(SteerDropped(content))
    _ => None
  }
}
