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
pub(all) struct WslRequest {
  distro : String?
  engine : String?
}

///|
pub(all) struct StartRequest {
  task : String
  api_key : String?
  api_url : String?
  model : String?
  max_steps : Int?
  session : String?
  session_root : String?
  // A registered workspace directory to run in: the engine works in the
  // project itself and the session's durable record lands in its in-project
  // store. Overrides the derived scratch cwd and `session_root`.
  workspace : String?
  wsl : WslRequest?
}

///|
pub(all) struct CancelRequest {
  run_id : Int?
}

///|
pub(all) struct SteerRequest {
  text : String
  run_id : Int?
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
  api_key : String?
  api_url : String?
  model : String?
  max_steps : Int?
  session_root : String?
  workspace : String?
  wsl : WslRequest?
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
  run_id : Int
  status : String
  exit_code : Int
} derive(ToJson)

///|
struct CancelReply {
  cancelled : Bool
  run_id : Int?
} derive(ToJson)

///|
struct SteerReply {
  steered : Bool
  run_id : Int?
} derive(ToJson)

///|
struct CompactReply {
  // Whether the compaction command reached a live engine for this
  // conversation; the engine reports the actual progress through events.
  compacting : Bool
} derive(ToJson)

///|
struct PumpReply {
  disconnected : Bool
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
} derive(ToJson)

///|
struct ConnectedPayload {
  ready : Bool
} derive(ToJson)

///|
struct StartedPayload {
  run_id : Int
  task : String
  engine : String
  model : String
  max_steps : Int
  cwd : String?
  session : String?
  session_root : String?
} derive(ToJson)

///|
struct EventPayload {
  run_id : Int
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
  run_id : Int
  status : String
  answer : String?
  exit_code : Int?
} derive(ToJson)

///|
struct ErrorPayload {
  run_id : Int?
  message : String
  exit_code : Int?
  diagnostics : String?
} derive(ToJson)

///|
pub(all) enum EngineEvent {
  Connected(ConnectedPayload)
  Started(StartedPayload)
  StreamEvent(EventPayload)
  Error(ErrorPayload)
  Finished(FinishedPayload)
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
  run_id? : Int,
  exit_code? : Int,
  diagnostics? : String,
) -> Unit {
  emit(sink, Error({ run_id, message, exit_code, diagnostics }))
}

///|
async fn emit_finished(
  sink : EventSink,
  run_id : Int,
  status : RunStatus,
  answer? : String,
  exit_code? : Int,
) -> Unit {
  emit(sink, Finished({ run_id, status: status.wire(), answer, exit_code }))
}
