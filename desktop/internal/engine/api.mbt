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
  guard submission_id is Some(submission_id) && !submission_id.is_blank() else {
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
    byte_length += width
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
type ApprovalReply = @protocol.ApprovalReply

///|
type CompactReply = @protocol.CompactReply

///|
type GoalReply = @protocol.GoalReply

///|
/// One sidebar group of `list_sessions`: the conversations stored under one
/// session root. `workspace` is the project directory and `name` its display
/// label (the folder's basename). A group whose listing failed carries the
/// engine's message in `error` and an empty `sessions` — one broken workspace
/// must not take the whole sidebar down.
type SessionGroup = @protocol.SessionGroup

///|
type SessionsReply = @protocol.SessionsReply

///|
type WorktreeInfo = @protocol.WorktreeInfo

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
pub(all) enum EngineEvent {
  Connected(ConnectedPayload)
  Started(StartedPayload)
  StreamEvent(EventPayload)
  Error(ErrorPayload)
  Finished(@protocol.FinishedPayload)
  SessionCommit(SessionCommitPayload)
  /// A running sub-run advanced. Not a lifecycle event and not durable: the
  /// brackets on the raw stream own the sub-run's start and end, and this
  /// only refreshes what it is doing in between.
  SubrunProgress(@protocol.SubrunProgressPayload)
  /// One resolved call of a workflow a snippet is running, read from the
  /// run's journal. Not lifecycle and not durable here: the journal is the
  /// record, and the `workflow_started`/`workflow_finished` brackets on the
  /// raw stream own the run's start and end.
  WorkflowEntry(@protocol.WorkflowEntryPayload)
}

///|
/// Where this package publishes everything a client can observe.
///
/// Deliberately not `async`: an event handed to the sink is public the moment
/// the call returns, so a suspension inside it would let a cancellation land
/// between "the observer saw Started" and "the caller believes nothing
/// happened". Delivery is a synchronous handoff to whatever fan-out the host
/// installed — the real one buffers per subscriber and evicts a wedged reader
/// rather than backpressuring lifecycle code — which is what lets the engine's
/// lifecycle transitions and their announcements be one uninterruptible step.
pub(all) struct EventSink((EngineEvent) -> Unit)

///|
priv enum RunStatus {
  Finished
  ContextYield
  Aborted
  Failed
  MaxStepsExhausted
}

///|
fn RunStatus::wire(self : RunStatus) -> String {
  match self {
    Finished => "finished"
    ContextYield => "context_yield"
    Aborted => "aborted"
    Failed => "failed"
    MaxStepsExhausted => "max_steps_exhausted"
  }
}

///|
fn emit(sink : EventSink, event : EngineEvent) -> Unit {
  sink(event)
}

///|
fn emit_error(
  sink : EventSink,
  message : String,
  run_id? : String,
  exit_code? : Int,
  diagnostics? : String,
) -> Unit {
  emit(sink, Error({ run_id, message: Some(message), exit_code, diagnostics, }))
}

///|
fn emit_finished(
  sink : EventSink,
  run_id : String,
  status : RunStatus,
  answer? : String,
  exit_code? : Int,
) -> Unit {
  emit(sink, Finished({ run_id, status: status.wire(), answer, exit_code, }))
}

///|
pub extend EngineError with Debug::{to_repr}
