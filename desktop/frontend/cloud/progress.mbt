///|
fn Conversation::clear_streams(self : Conversation) -> Conversation {
  { ..self, live: @engine_session.Stream::empty(), }
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
  if wire is @wire.AssistantMessage(content~) {
    // As in Local, semantic events settle transient text; history supplies
    // the canonical assistant, including reasoning and structured tool calls.
    return { ..self.clear_streams(), notification_answer: Some(content), }
  }
  if wire is @wire.ToolResult(..) {
    return { ..self, live: { ..self.live, response: None, }, }
  }
  guard progress is Some(progress) else { return self }
  let self = { ..self, live: self.live.event(progress), }
  match progress {
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
