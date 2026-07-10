// Local copy of the OpenSeek event decoder used by the desktop app.

///|
/// Map one decoded JSONL value from the engine into an `AgentEvent`.
///
/// Unknown or malformed events return `None`, keeping the desktop UI tolerant
/// of newer engine versions. Malformed means missing a field the engine
/// emits unconditionally — the host forwards such an event raw rather than
/// act on a fabricated placeholder.
pub fn decode_event(object : Json) -> AgentEvent? {
  guard object is Object(fields) else { return None }
  guard @jsonx.json_text(fields, "event") is Some(event) else { return None }
  let content = @jsonx.json_text(fields, "content")
  match event {
    "agent_step" => Some(AgentStep)
    "assistant_message" => content.map(content => AssistantMessage(content))
    "runtime_update" => content.map(content => RuntimeUpdate(content))
    "steer_applied" => content.map(content => SteerApplied(content))
    "steer_dropped" => content.map(content => SteerDropped(content))
    "usage" => {
      // The engine nests the counters under a `usage` object (`print_usage`
      // serializes the DeepSeek `Usage` struct verbatim, whose counters are
      // plain always-present ints).
      guard fields.get("usage") is Some(Object(usage)) &&
        @jsonx.json_int(usage, "prompt_tokens") is Some(prompt) &&
        @jsonx.json_int(usage, "completion_tokens") is Some(completion) else {
        return None
      }
      Some(Usage({ total_tokens: prompt + completion }))
    }
    "tool_result" => {
      guard @jsonx.json_text(fields, "tool_name") is Some(name) &&
        @jsonx.json_text(fields, "content") is Some(content) &&
        @jsonx.json_bool(fields, "is_error") is Some(is_error) else {
        return None
      }
      Some(ToolResult({ name, content, is_error }))
    }
    "tool_call_decode_error" => {
      guard @jsonx.json_text(fields, "tool_name") is Some(name) &&
        @jsonx.json_text(fields, "error") is Some(error) else {
        return None
      }
      Some(ToolResult({ name, content: "error: \{error}", is_error: true }))
    }
    "agent_finished" =>
      @jsonx.json_text(fields, "answer").map(answer => AgentFinished(answer))
    "context_yield" =>
      @jsonx.json_text(fields, "answer").map(answer => ContextYield(answer))
    "agent_aborted" =>
      @jsonx.json_text(fields, "reason").map(reason => AgentAborted(reason))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" =>
      @jsonx.json_text(fields, "error").map(error => {
        AgentError("agent setup failed: " + error)
      })
    // A serve-mode turn that died with a non-cancellation error. Terminal for
    // the run even though the engine process lives on.
    "turn_failed" =>
      @jsonx.json_text(fields, "error").map(error => {
        AgentError("turn failed: " + error)
      })
    "compaction_started" => Some(CompactionStarted)
    "compaction_finished" => Some(CompactionFinished)
    "compaction_failed" => Some(CompactionFailed)
    _ => None
  }
}
