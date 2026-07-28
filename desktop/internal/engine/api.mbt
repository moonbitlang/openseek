///|
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
/// The engine-host input `settings_wsl_request` builds from the stored
/// settings; requests no longer carry it.
priv struct WslRequest {
  distro : String?
  engine : String?
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
/// The endpoint (provider, credentials) and the WSL preference are the
/// host-owned settings' business — a start names only the work and where it
/// runs.
pub(all) struct StartRequest {
  task : String
  // Optional client-minted lifecycle identity echoed with `agent.started`.
  // The host ignores blank ids and ids longer than 128 UTF-8 bytes; accepted
  // values are opaque and echoed unchanged.
  submission_id : String?
  model : String?
  max_steps : Int?
  session : String?
  // A registered workspace directory to run in: the engine works in the
  // project itself and the session's durable record lands in its in-project
  // store. Overrides the derived scratch cwd and store lookup.
  workspace : String?
}

///|
pub(all) struct CancelRequest {
  run_id : String?
}

///|
pub(all) struct SteerRequest {
  text : String
  run_id : String?
  // Optional client-minted lifecycle identity echoed on the matching steer
  // receipt. The same 128-byte, non-blank boundary as StartRequest applies.
  submission_id : String?
}

///|
pub(all) struct CompactRequest {
  // The conversation to compact, addressed by its durable session id. Unlike
  // cancel/steer there is no open run to key on: compaction is normally asked
  // for once a turn has finished and the engine is idle.
  session : String
  // The same engine settings a start carries (minus the task): a conversation
  // resumed after a restart has no live serve process, and compacting it
  // spawns one on the durable session with exactly these settings.
  model : String?
  max_steps : Int?
  workspace : String?
}

///|
pub(all) struct LoadSessionRequest {
  session : String
  // The workspace whose store holds the session, when the client knows it;
  // otherwise the host probes the registered workspaces and the global root.
  workspace : String?
}

///|
struct StartReply {
  run_id : String
  status : String
  exit_code : Int
} derive(ToJson)

///|
struct CancelReply {
  cancelled : Bool
  run_id : String?
} derive(ToJson)

///|
struct SteerReply {
  steered : Bool
  run_id : String?
} derive(ToJson)

///|
struct CompactReply {
  // Whether the compaction command reached a live engine for this
  // conversation; the engine reports the actual progress through events.
  compacting : Bool
} derive(ToJson)

///|
/// One sidebar group of `list_sessions`: the conversations stored under one
/// session root. `workspace` is the project directory ("" for the default
/// group of scratch conversations) and `name` its display label (the folder's
/// basename). A group whose listing failed carries the engine's message in
/// `error` and an empty `sessions` — one broken workspace must not take the
/// whole sidebar down.
struct SessionGroup {
  workspace : String
  name : String
  session_root : String
  sessions : Json
  error : String
} derive(ToJson)

///|
struct SessionsReply {
  groups : Array[SessionGroup]
} derive(ToJson)

///|
struct WorkspacesReply {
  workspaces : Array[String]
} derive(ToJson)

///|
struct LoadSessionReply {
  session : Json
  // The highest event sequence contained in `session` — the client's
  // starting watermark: `session.event` commits at or below it are already
  // in the snapshot, and the first fresh commit is watermark + 1.
  watermark : Int
} derive(ToJson)

///|
struct ConnectedPayload {
  ready : Bool
} derive(ToJson)

///|
struct StartedPayload {
  run_id : String
  task : String
  submission_id : String?
  engine : String
  model : String
  max_steps : Int
  cwd : String?
  session : String?
  session_root : String?
} derive(ToJson)

///|
struct EventPayload {
  // The run this event belongs to — absent for events the engine emits
  // before any run of this process's lifetime (a spawn for compaction).
  run_id : String?
  // The conversation the event belongs to (the engine's session key, "" for
  // a session-less engine). Idle events — the compaction lifecycle and
  // background notices — are routed by it: run-id routing needs a `Started`
  // event this app-lifetime, which a conversation resumed and compacted
  // before its first prompt never had.
  session : String
  event : Json
} derive(ToJson)

///|
pub struct FinishedPayload {
  run_id : String
  status : String
  answer : String?
  exit_code : Int?
  // Present only after the host's follower completed its final durable scan.
  // An abnormal process exit may have no Terminal item; this sequence is the
  // exact chronology boundary clients can safely attach local notices to.
  durable_sequence : Int?
} derive(ToJson)

///|
struct ErrorPayload {
  run_id : String?
  message : String
  exit_code : Int?
  diagnostics : String?
} derive(ToJson)

///|
/// One durably committed session event, broadcast as `session.event`. The
/// canonical transcript channel: a commit exists if and only if its item is
/// in the session's store file, and `sequence` is the item's one-based
/// position there — contiguous per session, so a client can apply commits
/// with a plain watermark (drop ≤ W, apply W+1, anything later is a gap and
/// means reload). `event` is the store's event JSON verbatim
/// (`{"sequence", "ts", "item"}`), exactly what a `session.load` snapshot
/// carries in its `events` array.
struct SessionCommitPayload {
  session : String
  sequence : Int
  event : Json
} derive(ToJson)

///|
/// A lifecycle finish emitted before a stubborn child could be reaped is
/// later strengthened by this non-lifecycle boundary notification. Keeping it
/// distinct avoids a second Finished (and duplicate system/client terminal
/// side effects) for the same run.
struct DurableBoundaryPayload {
  run_id : String
  session : String
  sequence : Int
} derive(ToJson)

///|
pub(all) enum EngineEvent {
  Connected(ConnectedPayload)
  Started(StartedPayload)
  StreamEvent(EventPayload)
  Error(ErrorPayload)
  Finished(FinishedPayload)
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
  emit(sink, Error({ run_id, message, exit_code, diagnostics }))
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
