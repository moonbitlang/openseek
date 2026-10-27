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
  if @engine_session.refreshes_history(event) {
    // Live semantic events are not a second durable transcript. Refresh the
    // unchanged history source, as Local renders canonical session records.
    let (next, command) = next.load(session, token, emit)
    (next, command, None)
  } else {
    (next, @cmd.none, None)
  }
}
