///|
/// A normalized engine event. The bridge's `openseek.event` payload is
/// tagged by a `String`; this enum is the form `update()` matches on, so
/// each case carries only the fields that event actually uses and the match
/// is exhaustive.
pub(all) enum EngineEvent {
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
/// Normalize the raw engine-event JSON into a typed event. Unknown event
/// names decode to `None` and are dropped at the bridge, so the
/// stringly-typed tag never escapes into the update logic.
pub fn decode_engine_event(raw : Map[String, Json]) -> EngineEvent? {
  // Older engine builds wrote `step` and `error` where current ones write
  // `content` and `reason`; the current name wins when both are present.
  let content = json_first_text(raw, "content", "step")
  let reason = json_first_text(raw, "reason", "error")
  let tool_name = json_text(raw, "tool_name")
  match json_text(raw, "event") {
    "agent_step" => Some(AgentStep(content))
    "assistant_delta" => Some(AssistantDelta(content))
    "reasoning_delta" => Some(ReasoningDelta(content))
    "reasoning_message" => Some(ReasoningMessage(content))
    "assistant_message" => Some(AssistantMessage(content))
    "runtime_update" => Some(RuntimeUpdate(content))
    "usage" =>
      Some(
        Usage(
          prompt_tokens=json_int(raw, "prompt_tokens", 0),
          completion_tokens=json_int(raw, "completion_tokens", 0),
        ),
      )
    "tool_result" =>
      Some(
        ToolResult(
          tool_name~,
          is_error=raw.get("is_error") is Some(True),
          content~,
        ),
      )
    "tool_call_decode_error" => Some(ToolCallDecodeError(tool_name~, reason~))
    "agent_finished" => Some(AgentFinished(json_text(raw, "answer")))
    "agent_aborted" => Some(AgentAborted(reason))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" => Some(AgentSetupFailed(reason))
    "steer_applied" => Some(SteerApplied(content))
    "steer_dropped" => Some(SteerDropped(content))
    _ => None
  }
}
