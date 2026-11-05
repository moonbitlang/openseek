///|
/// The Cloud envelope carries routing and order only. Decode native payloads
/// through Local's wire parser and presentation decoder, without rebuilding
/// engine JSON from Cloud-specific event names.
fn State::engine_event(
  self : State,
  session : String,
  frame : EngineFrame,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd, String?) {
  let conversation = self.conversations[session]
  guard frame.session_id == session &&
    conversation.last_seq is Some(seq) &&
    frame.seq > seq else {
    return (self, @cmd.none, None)
  }
  let conversation = { ..conversation, last_seq: Some(frame.seq), }
  let next = self.replace(session, conversation)
  guard @wire.parse(frame.data) is Some(event) else {
    // Local also ignores unrecognized native events.
    return (next, @cmd.none, None)
  }
  if event is @wire.PredictionResult(source_sequence~, outcome~) {
    // Prediction ownership is the native log frontier, including results that
    // arrive after their task ends or ahead of a pending history response.
    return (
      next.replace(
        session,
        conversation.with_prediction(Some({ source_sequence, outcome, })),
      ),
      @cmd.none,
      None,
    )
  }
  let conversation = match event {
    @wire.SteerApplied(submission_id~, ..) if frame.task_id is Some(task) =>
      conversation.steer_receipt(task, submission_id, false)
    @wire.SteerDropped(submission_id~, ..) if frame.task_id is Some(task) =>
      conversation.steer_receipt(task, submission_id, true)
    _ => conversation
  }
  let next = next.replace(session, conversation)
  guard frame.task_id is None || frame.task_id == conversation.task else {
    // Receipts can settle their own input after a new task starts, but must
    // not replace the new task's run state or provisional text.
    return (next, @cmd.none, None)
  }
  guard @engine_session.is_idle_event(event) ||
    (frame.task_id is Some(_) && conversation.generating) else {
    return (next, @cmd.none, None)
  }
  let conversation = conversation.command_event(event)
  let conversation = if frame.task_id is Some(_) ||
    event
    is (@wire.CompactionStarted(..)
    | @wire.CompactionFinished(..)
    | @wire.AutoCompactionFinished(..)
    | @wire.CompactionFailed(..)) {
    conversation.live_progress(event)
  } else {
    conversation
  }
  let next = next.replace(session, conversation)
  if frame.task_id is None && @engine_session.refreshes_history(event) {
    // Idle commands can update the session outside a chat task.
    let (next, command) = next.load(session, token, emit)
    (next, command, None)
  } else {
    (next, @cmd.none, None)
  }
}

///|
fn State::session_record(
  self : State,
  session : String,
  task : String?,
  seq : Int32,
  record : @protocol.SessionEvent,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd, String?) {
  let conversation = self.conversations[session]
  let conversation = { ..conversation, last_seq: Some(seq), }
  guard (task is None || task == conversation.task) &&
    record.sequence > conversation.last_record_sequence else {
    return (self.replace(session, conversation), @cmd.none, None)
  }
  let events = conversation.document.events.unwrap_or([])
  let frontier = events.last().map_or(0, event => event.sequence)
  let missing = record.sequence > frontier + 1
  let duplicate = events.any(event => event.sequence == record.sequence)
  let conversation = { ..conversation, last_record_sequence: record.sequence, }
  let conversation = if duplicate {
    conversation
  } else {
    let events = [..events, record]
    if record.sequence < frontier {
      events.sort_by_key(event => event.sequence)
    }
    {
      ..conversation,
      document: { ..conversation.document, events: Some(events), },
      pushed_records: [..conversation.pushed_records, record],
    }
  }
  let conversation = match record.item {
    @protocol.User(user) => {
      let next = { ..conversation, history_required: false, }
      if conversation.pending is Some(pending) &&
        user.submission_id == Some(pending.id) {
        let consume_draft = pending.result_id is None
        {
          ..next,
          sending: false,
          pending: None,
          notice: None,
          uploads: [],
          submission_sequence: next.submission_sequence +
          (if consume_draft { 1 } else { 0 }),
          initial_submission: if consume_draft {
            None
          } else {
            next.initial_submission
          },
          initial_attachments: if consume_draft {
            []
          } else {
            next.initial_attachments
          },
        }
      } else {
        next
      }
    }
    @protocol.Assistant(reply) if task == conversation.task &&
      task is Some(_) &&
      reply.is_replay != Some(true) =>
      {
        ..conversation.clear_streams(),
        retrying: None,
        notification_answer: if reply.content.is_blank() {
          conversation.notification_answer
        } else {
          Some(reply.content)
        },
      }
    @protocol.Terminal(_) | @protocol.UnknownTerminal(_) if task is Some(id) =>
      {
        ..conversation,
        terminal_record: Some((id, record.sequence)),
        notification_answer: match record.item {
          @protocol.Terminal(@protocol.Finished(answer)) if !answer.is_blank() =>
            Some(answer)
          _ => conversation.notification_answer
        },
      }
    _ => conversation
  }
  let next = self.replace(session, conversation)
  if missing {
    let (next, command) = next.load(session, token, emit)
    (next, command, None)
  } else {
    (next, @cmd.none, None)
  }
}
