///|
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
#derive(Debug)
pub(all) suberror EngineError {
  EngineError(String)
}

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
pub(all) enum EngineEvent {
  Connected(@protocol.ConnectedPayload)
  Started(@protocol.StartedPayload)
  StreamEvent(@protocol.AgentEventPayload)
  Error(@protocol.AgentErrorPayload)
  Finished(@protocol.FinishedPayload)
  SessionCommit(@protocol.SessionCommitPayload)
  PredictionReady(@protocol.PredictionReadyPayload)
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
  exit_code? : Int32,
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
  exit_code? : Int32,
) -> Unit {
  emit(sink, Finished({ run_id, status: status.wire(), answer, exit_code, }))
}

///|
pub extend EngineError with Debug::{to_repr}
