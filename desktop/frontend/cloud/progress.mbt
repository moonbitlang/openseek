///|
fn Conversation::clear_streams(self : Conversation) -> Conversation {
  { ..self, live: @engine_session.Stream::empty(), }
}

///|
/// The highest native sequence this conversation has read.
fn Conversation::durable_frontier(self : Conversation) -> Int32 {
  self.document.events
  .unwrap_or([])
  .fold(init=0, (frontier, event) => {
    if event.sequence > frontier {
      event.sequence
    } else {
      frontier
    }
  })
}

///|
/// The provisional reasoning to render beside `items`, the transcript built
/// by `Conversation::items`. Hides only a sealed preview whose durable record
/// this step already read, as Local does.
pub fn Conversation::visible_reasoning(
  self : Conversation,
  items : Array[@transcript.TranscriptItem],
) -> (String?, Bool) {
  self.live.visible_reasoning(items, frontier=self.reasoning_frontier)
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
  history_request : Int32?,
) -> Conversation {
  let progress = @transcript.decode_engine_event(wire)
  let self = if progress.map_or(false, event => event.ends_retry()) ||
    wire is (@wire.AssistantMessage(..) | @wire.ToolResult(..)) {
    { ..self, retrying: None, }
  } else {
    self
  }
  if wire is @wire.AssistantMessage(content~) {
    let prose = if content.is_blank() { None } else { Some(content) }
    let reasoning = self.live.reasoning.map(reasoning => reasoning.content)
    let pending_assistants = if self.task is Some(task) &&
      (prose is Some(_) || reasoning is Some(_)) {
      [
        ..self.pending_assistants,
        {
          task,
          history_request,
          item: {
            kind: @transcript.Assistant(
              prose~,
              reasoning~,
              calls=[],
              replay=false,
              finished=false,
              end_sequence=None,
            ),
            ts: None,
            sequence: None,
          },
        },
      ]
    } else {
      self.pending_assistants
    }
    let next = {
      ..self.clear_streams(),
      notification_answer: Some(content),
      pending_assistants,
    }
    // A read can land before the notification it covers. Hand the preview
    // off at once when its record is already here.
    return if history_request is None {
      next.acknowledge_assistants(0, next.document, next.records)
    } else {
      next
    }
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
        reasoning_frontier: self.durable_frontier(),
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
