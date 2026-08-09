///|
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
pub(all) suberror EngineError {
  EngineError(String)
} derive(Debug)

///|
impl Show for EngineError with fn output(self, logger) {
  match self {
    EngineError(message) => logger.write_string(message)
  }
}

///|
const SubmissionIdMaxBytes = 128

///|
/// Keep client correlation bounded before it enters live-run state or an
/// outbound notification. Valid ids remain opaque — whitespace around a
/// non-blank id is significant and therefore echoed unchanged.
fn normalize_submission_id(submission_id : String?) -> String? {
  guard submission_id is Some(submission_id) && !submission_id.trim().is_empty() else {
    return None
  }
  let mut byte_length = 0
  for char in submission_id {
    let codepoint = char.to_int()
    let width = if codepoint <= 127 {
      1
    } else if codepoint <= 2047 {
      2
    } else if codepoint <= 65535 {
      3
    } else {
      4
    }
    byte_length = byte_length + width
    if byte_length > SubmissionIdMaxBytes {
      return None
    }
  }
  Some(submission_id)
}

///|
type StartReply = @protocol.StartReply

///|
type CancelReply = @protocol.CancelReply

///|
type SteerReply = @protocol.SteerReply

///|
type CompactReply = @protocol.CompactReply

///|
/// One sidebar group of `list_sessions`: the conversations stored under one
/// session root. `workspace` is the project directory ("" for the default
/// group of scratch conversations) and `name` its display label (the folder's
/// basename). A group whose listing failed carries the engine's message in
/// `error` and an empty `sessions` — one broken workspace must not take the
/// whole sidebar down.
type SessionGroup = @protocol.SessionGroup

///|
type SessionsReply = @protocol.SessionsReply

///|
type ArchiveReply = @protocol.ArchiveReply

///|
type ArchiveNeedsForceReply = @protocol.ArchiveNeedsForceReply

///|
type WorkspacesReply = @protocol.WorkspacesReply

///|
type LoadSessionReply = @protocol.LoadSessionReply

///|
type ConnectedPayload = @protocol.ConnectedPayload

///|
type StartedPayload = @protocol.StartedPayload

///|
type EventPayload = @protocol.AgentEventPayload

///|
type ErrorPayload = @protocol.AgentErrorPayload

///|
/// One durably committed session event, broadcast as `session.event`. The
/// canonical transcript channel: a commit exists if and only if its item is
/// in the session's store file, and `sequence` is the item's one-based
/// position there — contiguous per session, so a client can apply commits
/// with a plain watermark (drop ≤ W, apply W+1, anything later is a gap and
/// means reload). `event` is the typed store event, exactly the value a
/// `session.load` snapshot carries in its `events` array.
type SessionCommitPayload = @protocol.SessionCommitPayload

///|
/// A lifecycle finish emitted before a stubborn child could be reaped is
/// later strengthened by this non-lifecycle boundary notification. Keeping it
/// distinct avoids a second Finished (and duplicate system/client terminal
/// side effects) for the same run.
type DurableBoundaryPayload = @protocol.DurableBoundaryPayload

///|
pub(all) enum EngineEvent {
  Connected(ConnectedPayload)
  Started(StartedPayload)
  StreamEvent(EventPayload)
  Error(ErrorPayload)
  Finished(@protocol.FinishedPayload)
  SessionCommit(SessionCommitPayload)
  DurableBoundary(DurableBoundaryPayload)
}

///|
pub(all) struct EventSink(async (EngineEvent) -> Unit)

///|
priv enum RunStatus {
  Finished
  ContextYield
  Aborted
  Failed
  Cancelled
  MaxStepsExhausted
}

///|
fn RunStatus::wire(self : RunStatus) -> String {
  match self {
    Finished => "finished"
    ContextYield => "context_yield"
    Aborted => "aborted"
    Failed => "failed"
    Cancelled => "cancelled"
    MaxStepsExhausted => "max_steps_exhausted"
  }
}

///|
async fn emit(sink : EventSink, event : EngineEvent) -> Unit {
  sink(event)
}

///|
async fn emit_error(
  sink : EventSink,
  message : String,
  run_id? : String,
  exit_code? : Int,
  diagnostics? : String,
) -> Unit {
  emit(sink, Error({ run_id, message: Some(message), exit_code, diagnostics }))
}

///|
async fn emit_finished(
  sink : EventSink,
  run_id : String,
  status : RunStatus,
  answer? : String,
  exit_code? : Int,
  durable_sequence? : Int,
) -> Unit {
  emit(
    sink,
    Finished({
      run_id,
      status: status.wire(),
      answer,
      exit_code,
      durable_sequence,
    }),
  )
}

///|
async fn emit_durable_boundary(
  sink : EventSink,
  run_id : String,
  session : String,
  sequence : Int,
) -> Unit {
  emit(sink, DurableBoundary({ run_id, session, sequence }))
}
