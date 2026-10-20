///|
/// Decode the engine's existing payload rather than inventing Cloud counters
/// or interpreting missing metadata as a reported value.
fn Event::engine_event(self : Event) -> @wire.Event? {
  guard self.data is Object(fields) else { return None }
  let fields = fields.copy()
  fields["event"] = Json(
    if self.kind == "step" {
      "agent_step"
    } else {
      self.kind
    },
  )
  @wire.parse(Json(fields))
}

///|
fn Event::is_live_progress(self : Event) -> Bool {
  match self.kind {
    "task_started"
    | "assistant_delta"
    | "reasoning_delta"
    | "reasoning_message"
    | "stream_retry"
    | "step"
    | "usage"
    | "compaction_started"
    | "compaction_finished"
    | "auto_compaction_started"
    | "auto_compaction_finished" => true
    _ => false
  }
}

///|
fn Conversation::clear_streams(self : Conversation) -> Conversation {
  {
    ..self,
    streaming_response: None,
    streaming_reasoning: None,
    reasoning_complete: false,
  }
}

///|
fn Conversation::clear_progress(self : Conversation) -> Conversation {
  {
    ..self.clear_streams(),
    heartbeat: None,
    retrying: None,
    compacting: false,
  }
}

///|
pub fn Conversation::run_heartbeat(
  self : Conversation,
) -> @composer.RunHeartbeat? {
  self.heartbeat.map(heartbeat => {
    ..heartbeat,
    stage: self.retrying.unwrap_or(heartbeat.stage),
  })
}

///|
fn Conversation::live_progress(
  self : Conversation,
  event : Event,
) -> Conversation {
  let progress = event.engine_event().bind(@transcript.decode_engine_event)
  let self = if progress.map_or(false, event => event.ends_retry()) ||
    event.kind
    is ("assistant_message" | "tool_call" | "tool_result" | "task_finished") {
    { ..self, retrying: None, }
  } else {
    self
  }
  if event.kind == "task_started" {
    return {
      ..self.clear_streams(),
      heartbeat: Some({
        stage: @composer.Thinking,
        started_ms: None,
        tokens: 0,
      }),
      compacting: false,
      retrying: None,
    }
  }
  if event.kind == "task_finished" {
    return self.clear_progress()
  }
  if event.kind == "assistant_message" {
    // This event is the canonical assistant, including reasoning-only replies.
    return self.clear_streams()
  }
  if event.kind is ("tool_call" | "tool_result") {
    return { ..self, streaming_response: None, }
  }
  guard event.engine_event() is Some(wire) else { return self }
  match wire {
    CompactionStarted(..) | AutoCompactionStarted(..) =>
      return { ..self, compacting: true, }
    CompactionFinished(..) | AutoCompactionFinished(..) =>
      return { ..self, compacting: false, }
    CompactionFailed(..) | AutoCompactionFailed(..) =>
      return { ..self, compacting: false, }
    _ => ()
  }
  guard progress is Some(progress) else { return self }
  match progress {
    AssistantDelta(content) =>
      if content.is_empty() {
        self
      } else {
        {
          ..self,
          streaming_response: Some(
            self.streaming_response.unwrap_or("") + content,
          ),
          reasoning_complete: self.streaming_reasoning is Some(_),
        }
      }
    ReasoningDelta(content) =>
      if content.is_empty() || self.reasoning_complete {
        self
      } else {
        {
          ..self,
          streaming_reasoning: Some(
            self.streaming_reasoning.unwrap_or("") + content,
          ),
        }
      }
    ReasoningMessage(content) =>
      {
        ..self,
        streaming_reasoning: if content.trim().is_empty() {
          None
        } else {
          Some(content)
        },
        reasoning_complete: !content.trim().is_empty(),
      }
    AgentStep(step) =>
      {
        ..self.clear_streams(),
        heartbeat: self.heartbeat.map(heartbeat => {
          ..heartbeat,
          stage: match step {
            Some(step) => @composer.AtStep(step)
            None => @composer.Working
          },
        }),
      }
    StreamRetry(attempt~, max_attempts~, reason~) =>
      {
        ..self.clear_streams(),
        retrying: Some(@composer.Retrying(attempt~, max_attempts~, reason~)),
      }
    Usage(prompt_tokens~, completion_tokens~) =>
      {
        ..self,
        heartbeat: self.heartbeat.map(heartbeat => {
          ..heartbeat,
          tokens: prompt_tokens + completion_tokens,
        }),
      }
    _ => self
  }
}
