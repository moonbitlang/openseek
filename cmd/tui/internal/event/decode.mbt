// Mapping from the engine's decoded JSONL values to typed `AgentEvent`s. Reading
// lines, skipping blanks, and parsing each as JSON is `bobzhang/jsonl`'s job
// (`@jsonl.each` in `cmd/tui`); this module only maps an already-parsed value,
// keyed by its `"event"` discriminator.

///|
/// Map one decoded JSONL value from the engine into an `AgentEvent`.
///
/// Returns `None` for a non-object value or an unrecognized `"event"` string so
/// a noisy or newer engine never crashes the UI; the caller simply drops it.
pub fn decode_event(object : Json) -> AgentEvent? {
  match @jsonx.string(object, "event") {
    "agent_step" => Some(AgentStep)
    "assistant_delta" => Some(AssistantDelta(@jsonx.string(object, "content")))
    "reasoning_delta" => Some(ReasoningDelta(@jsonx.string(object, "content")))
    "reasoning_message" =>
      Some(ReasoningMessage(@jsonx.string(object, "content")))
    "assistant_message" =>
      Some(AssistantMessage(@jsonx.string(object, "content")))
    "runtime_update" => Some(RuntimeUpdate(@jsonx.string(object, "content")))
    "usage" => {
      let prompt = @jsonx.int(object, "prompt_tokens")
      let completion = @jsonx.int(object, "completion_tokens")
      Some(Usage({ total_tokens: prompt + completion }))
    }
    "tool_result" =>
      Some(
        ToolResult({
          name: @jsonx.string(object, "tool_name"),
          content: @jsonx.string(object, "content"),
          is_error: @jsonx.bool(object, "is_error"),
        }),
      )
    "tool_call_decode_error" =>
      Some(
        ToolResult({
          name: @jsonx.string(object, "tool_name"),
          content: "error: \{@jsonx.string(object, "error")}",
          is_error: true,
        }),
      )
    "agent_finished" => Some(AgentFinished(@jsonx.string(object, "answer")))
    "agent_aborted" => Some(AgentAborted(@jsonx.string(object, "reason")))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" =>
      Some(AgentError("agent setup failed: " + @jsonx.string(object, "error")))
    // A serve-mode turn that died with a non-cancellation error. Terminal for
    // the run even though the engine process lives on.
    "turn_failed" =>
      Some(AgentError("turn failed: " + @jsonx.string(object, "error")))
    _ => None
  }
}
