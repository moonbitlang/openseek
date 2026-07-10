///|
/// A normalized engine event. The bridge's `openseek.event` payload is
/// tagged by a `String`; this enum is the form `update()` matches on, so
/// each case carries only the fields that event actually uses and the match
/// is exhaustive.
pub(all) enum EngineEvent {
  // The 1-based step counter (`step`); `None` for an engine build that does
  // not number its steps.
  AgentStep(Int?)
  AssistantDelta(String)
  ReasoningDelta(String)
  ReasoningMessage(String)
  AssistantMessage(String)
  RuntimeUpdate(String)
  Usage(prompt_tokens~ : Int, completion_tokens~ : Int)
  ToolResult(
    tool_name~ : String,
    is_error~ : Bool,
    content~ : String,
    brief~ : String?
  )
  ToolCallDecodeError(tool_name~ : String, reason~ : String)
  AgentFinished(String)
  // The current turn stopped at the model's context ceiling after attempting
  // an automatic checkpoint. It is run-terminal, but not task success.
  ContextYield(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentSetupFailed(String)
  // Steering input settled by the engine: applied at a step boundary, or
  // dropped because it raced the turn's end. Both echo the original text.
  SteerApplied(String)
  SteerDropped(String)
  // An automatic checkpoint completed inside the open turn. Unlike the
  // manual lifecycle below, this does not put the conversation into an idle
  // compaction phase.
  AutoCompactionFinished(String)
  // Conversation compaction lifecycle: the engine started summarizing the
  // history, finished (carrying the checkpoint summary text), or failed
  // (carrying the reason). Requested while the engine is idle, so these arrive
  // outside any open turn.
  CompactionStarted
  CompactionFinished(String)
  CompactionFailed(String)
}

///|
/// Normalize the raw engine-event JSON into a typed event. Unknown event
/// names — and events missing a field the engine emits unconditionally —
/// decode to `None` and are dropped at the bridge, so neither the
/// stringly-typed tag nor a fabricated placeholder ever escapes into the
/// update logic.
pub fn decode_engine_event(raw : Map[String, Json]) -> EngineEvent? {
  // Older engine builds wrote `error` where current ones write `reason`
  // (the host's synthesized `compaction_failed` also says `reason`); the
  // current name wins when both are present.
  let content = @jsonx.json_text(raw, "content")
  let reason = @jsonx.json_first_text(raw, "reason", "error")
  guard @jsonx.json_text(raw, "event") is Some(event) else { return None }
  match event {
    "agent_step" => Some(AgentStep(@jsonx.json_int(raw, "step")))
    "assistant_delta" => content.map(content => AssistantDelta(content))
    "reasoning_delta" => content.map(content => ReasoningDelta(content))
    "reasoning_message" => content.map(content => ReasoningMessage(content))
    "assistant_message" => content.map(content => AssistantMessage(content))
    // A background job's completion notice (the `moon_check --watch` stream),
    // emitted while the engine is idle. `runtime_update` is the event's
    // legacy name. The engine's `plan_reminder` is deliberately not decoded:
    // it is model-directed text, not a notice for the user (the TUI drops it
    // too).
    "background_notice" => content.map(content => RuntimeUpdate(content))
    "runtime_update" => content.map(content => RuntimeUpdate(content))
    "usage" => {
      // The engine nests the counters under a `usage` object
      // (`print_usage` serializes the DeepSeek `Usage` struct verbatim,
      // whose counters are plain always-present ints).
      guard raw.get("usage") is Some(Object(usage)) &&
        @jsonx.json_int(usage, "prompt_tokens") is Some(prompt_tokens) &&
        @jsonx.json_int(usage, "completion_tokens") is Some(completion_tokens) else {
        return None
      }
      Some(Usage(prompt_tokens~, completion_tokens~))
    }
    "tool_result" => {
      guard @jsonx.json_text(raw, "tool_name") is Some(tool_name) &&
        @jsonx.json_bool(raw, "is_error") is Some(is_error) &&
        @jsonx.json_text(raw, "content") is Some(content) else {
        return None
      }
      Some(
        ToolResult(
          tool_name~,
          is_error~,
          content~,
          brief=@jsonx.json_text(raw, "brief"),
        ),
      )
    }
    "tool_call_decode_error" => {
      guard @jsonx.json_text(raw, "tool_name") is Some(tool_name) &&
        reason is Some(reason) else {
        return None
      }
      Some(ToolCallDecodeError(tool_name~, reason~))
    }
    "agent_finished" =>
      @jsonx.json_text(raw, "answer").map(answer => AgentFinished(answer))
    "context_yield" =>
      @jsonx.json_text(raw, "answer").map(answer => ContextYield(answer))
    "agent_aborted" => reason.map(reason => AgentAborted(reason))
    "max_steps_exhausted" => Some(MaxStepsExhausted)
    "agent_setup_failed" => reason.map(reason => AgentSetupFailed(reason))
    "steer_applied" => content.map(content => SteerApplied(content))
    "steer_dropped" => content.map(content => SteerDropped(content))
    "auto_compaction_finished" =>
      @jsonx.json_text(raw, "summary").map(summary => {
        AutoCompactionFinished(summary)
      })
    "compaction_started" => Some(CompactionStarted)
    "compaction_finished" =>
      @jsonx.json_text(raw, "summary").map(summary => {
        CompactionFinished(summary)
      })
    "compaction_failed" => reason.map(reason => CompactionFailed(reason))
    _ => None
  }
}
