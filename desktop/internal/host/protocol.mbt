// The wire types of the `openseek` IPC namespace: payloads the webview sends
// with each op, the replies it gets back, and the events the host pushes.

///|
/// Optional fields are normalized by the frontend bridge — values arrive
/// trimmed, and blank fields are omitted entirely — so `Some` here always
/// carries a non-blank string and the host does not re-normalize.
priv struct StartPayload {
  task : String
  api_key : String?
  api_url : String?
  model : String?
  max_steps : Int?
  session : String?
  session_root : String?
  // Present = run the engine inside WSL (Windows only); absent = native.
  wsl : WslPayload?
} derive(FromJson)

///|
/// The WSL half of a start payload: which distro hosts the engine (absent =
/// the user's default distro) and the engine command inside it (absent =
/// `openseek` on the distro's PATH).
priv struct WslPayload {
  distro : String?
  engine : String?
} derive(FromJson)

///|
priv struct CancelPayload {
  run_id : Int?
} derive(FromJson)

///|
priv struct StartedPayload {
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
priv struct EventPayload {
  run_id : Int
  event : Json
} derive(ToJson)

///|
priv struct FinishedPayload {
  run_id : Int
  status : String
  answer : String?
  exit_code : Int?
} derive(ToJson)

///|
priv struct ErrorPayload {
  run_id : Int?
  message : String
  exit_code : Int?
  diagnostics : String?
} derive(ToJson)

///|
priv struct ConnectedPayload {
  ready : Bool
} derive(ToJson)

///|
/// Terminal state of a run. `wire()` is the string sent to the frontend; the
/// values are part of the IPC contract and must not change casually.
priv enum RunStatus {
  Finished
  Aborted
  Failed
  Cancelled
  MaxStepsExhausted
}

///|
fn RunStatus::wire(self : RunStatus) -> String {
  match self {
    Finished => "finished"
    Aborted => "aborted"
    Failed => "failed"
    Cancelled => "cancelled"
    MaxStepsExhausted => "max_steps_exhausted"
  }
}

///|
priv struct StartReply {
  run_id : Int
  status : String
  exit_code : Int
} derive(ToJson)

///|
priv struct LoadSessionPayload {
  session : String
} derive(FromJson)

///|
/// Reply to `list_sessions`: the engine's `--session-list --format=json`
/// output (an array of `{id, title, updated_at_ms}`, newest first), passed
/// through verbatim.
priv struct SessionsReply {
  sessions : Json
  session_root : String
} derive(ToJson)

///|
/// Reply to `load_session`: the engine's `--session-show` output (the durable
/// session JSON with its full event log), passed through verbatim.
priv struct LoadSessionReply {
  session : Json
} derive(ToJson)

///|
priv struct CancelReply {
  cancelled : Bool
  run_id : Int?
} derive(ToJson)

///|
priv struct SteerPayload {
  text : String
  run_id : Int?
} derive(FromJson)

///|
/// Reply to `steer`. `steered: false` means the text never reached the
/// engine — no `steer_applied`/`steer_dropped` event will follow, so the
/// frontend must settle its acknowledgment from this reply alone.
priv struct SteerReply {
  steered : Bool
  run_id : Int?
} derive(ToJson)

///|
/// Reply to `connect`, delivered only when the pump stops — in practice
/// never, since the webview holds the call open for the app's lifetime.
priv struct PumpReply {
  disconnected : Bool
} derive(ToJson)

///|
priv struct InstallSkillPayload {
  module_name : String
  version : String
  package_path : String?
} derive(FromJson)

///|
priv struct UninstallSkillPayload {
  id : String
} derive(FromJson)

///|
/// Reply to `skills_catalog`: the registry's installable skills.
priv struct SkillsCatalogReply {
  skills : Array[@skillmarket.MarketSkill]
} derive(ToJson)

///|
/// Reply to `skills_installed`: the global skills library's contents,
/// registry installs and hand-written skills alike.
priv struct InstalledSkillsReply {
  skills : Array[@skillmarket.InstalledSkill]
} derive(ToJson)

///|
priv struct InstallSkillReply {
  installed : @skillmarket.InstalledSkill
} derive(ToJson)

///|
priv struct UninstallSkillReply {
  removed : Bool
} derive(ToJson)

///|
/// Every outbound event the runner can send to the frontend. `emit` is the
/// single place that maps a variant to its wire name and payload, so the
/// name/payload pairing can never drift out of sync.
priv enum OutEvent {
  Connected(ConnectedPayload)
  Started(StartedPayload)
  Event(EventPayload)
  Error(ErrorPayload)
  Finished(FinishedPayload)
}

///|
async fn emit(
  context : @app.AppCommandExtensionContext,
  event : OutEvent,
) -> Unit {
  match event {
    Connected(payload) => context.emit("connected", payload)
    Started(payload) => context.emit("started", payload)
    Event(payload) => context.emit("event", payload)
    Error(payload) => context.emit("error", payload)
    Finished(payload) => context.emit("finished", payload)
  }
}

///|
async fn emit_error(
  context : @app.AppCommandExtensionContext,
  message : String,
  run_id? : Int,
  exit_code? : Int,
  diagnostics? : String,
) -> Unit {
  emit(context, Error({ run_id, message, exit_code, diagnostics }))
}

///|
async fn emit_finished(
  context : @app.AppCommandExtensionContext,
  run_id : Int,
  status : RunStatus,
  answer? : String,
  exit_code? : Int,
) -> Unit {
  emit(context, Finished({ run_id, status: status.wire(), answer, exit_code }))
}
