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
  { ..self.clear_streams(), heartbeat: None, retrying: None, }
}

///|
pub fn Conversation::run_heartbeat(
  self : Conversation,
) -> @composer.RunHeartbeat? {
  let stopping = self.control.map_or(false, control => {
      control.status == Stopping
    }) ||
    self.control_inputs.any(input => {
      input.operation is Stop && Some(input.task_id) == self.task
    })
  if stopping {
    Some({ stage: @composer.Stopping, started_ms: None, tokens: 0, })
  } else {
    self.heartbeat.map(heartbeat => {
      ..heartbeat,
      stage: self.retrying.unwrap_or(heartbeat.stage),
    })
  }
}

///|
fn Conversation::live_progress(
  self : Conversation,
  wire : @wire.Event,
) -> Conversation {
  let progress = @transcript.decode_engine_event(wire)
  let self = if progress.map_or(false, event => event.ends_retry()) ||
    wire is (@wire.AssistantMessage(..) | @wire.ToolResult(..)) {
    { ..self, retrying: None, }
  } else {
    self
  }
  if wire is @wire.AssistantMessage(..) {
    // As in Local, semantic events settle transient text; history supplies
    // the canonical assistant, including reasoning and structured tool calls.
    return self.clear_streams()
  }
  if wire is @wire.ToolResult(..) {
    return { ..self, streaming_response: None, }
  }
  match wire {
    CompactionStarted(..) =>
      return {
        ..self,
        compact_queued: false,
        compact_request: None,
        compacting: true,
      }
    AutoCompactionStarted(..) => return { ..self, compacting: true, }
    CompactionFinished(..) | CompactionFailed(..) =>
      return {
        ..self,
        compact_queued: false,
        compact_request: None,
        compacting: false,
      }
    AutoCompactionFinished(..) => return { ..self, compacting: false, }
    AutoCompactionFailed(..) => return { ..self, compacting: false, }
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
