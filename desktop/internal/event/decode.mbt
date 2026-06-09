// Local copy of the OpenSeek event decoder used by the desktop app.

///|
/// Map one decoded JSONL value from the engine into an `AgentEvent`.
///
/// Unknown or malformed events return `None`, keeping the desktop UI tolerant
/// of newer engine versions.
pub fn decode_event(object : Json) -> AgentEvent? {
  match string_field(object, "event") {
    "agent_step" => Some(AgentStep)
    "assistant_message" =>
      Some(AssistantMessage(string_field(object, "content")))
    "runtime_update" => Some(RuntimeUpdate(string_field(object, "content")))
    "usage" => {
      let prompt = int_field(object, "prompt_tokens")
      let completion = int_field(object, "completion_tokens")
      Some(Usage({ total_tokens: prompt + completion }))
    }
    "tool_result" =>
      Some(
        ToolResult({
          name: string_field(object, "tool_name"),
          content: string_field(object, "content"),
          is_error: bool_field(object, "is_error"),
        }),
      )
    "tool_call_decode_error" =>
      Some(
        ToolResult({
          name: string_field(object, "tool_name"),
          content: "error: \{string_field(object, "error")}",
          is_error: true,
        }),
      )
    "agent_finished" => Some(AgentFinished(string_field(object, "answer")))
    "agent_aborted" => Some(AgentAborted(string_field(object, "reason")))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" =>
      Some(AgentError("agent setup failed: " + string_field(object, "error")))
    _ => None
  }
}

///|
fn string_field(object : Json, name : String) -> String {
  match object {
    Object(fields) =>
      match fields.get(name) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
fn int_field(object : Json, name : String) -> Int {
  match object {
    Object(fields) =>
      match fields.get(name) {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
    _ => 0
  }
}

///|
fn bool_field(object : Json, name : String) -> Bool {
  match object {
    Object(fields) =>
      match fields.get(name) {
        Some(True) => true
        Some(False) => false
        _ => false
      }
    _ => false
  }
}
