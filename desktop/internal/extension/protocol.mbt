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
fn WslPayload::to_request(self : WslPayload) -> @engine.WslRequest {
  { distro: self.distro, engine: self.engine }
}

///|
fn StartPayload::to_request(self : StartPayload) -> @engine.StartRequest {
  {
    task: self.task,
    api_key: self.api_key,
    api_url: self.api_url,
    model: self.model,
    max_steps: self.max_steps,
    session: self.session,
    session_root: self.session_root,
    wsl: self.wsl.map(wsl => wsl.to_request()),
  }
}

///|
priv struct CancelPayload {
  run_id : Int?
} derive(FromJson)

///|
fn CancelPayload::to_request(self : CancelPayload) -> @engine.CancelRequest {
  { run_id: self.run_id }
}

///|
priv struct LoadSessionPayload {
  session : String
} derive(FromJson)

///|
fn LoadSessionPayload::to_request(
  self : LoadSessionPayload,
) -> @engine.LoadSessionRequest {
  { session: self.session }
}

///|
priv struct SteerPayload {
  text : String
  run_id : Int?
} derive(FromJson)

///|
fn SteerPayload::to_request(self : SteerPayload) -> @engine.SteerRequest {
  { text: self.text, run_id: self.run_id }
}

///|
priv struct CompactPayload {
  session : String
} derive(FromJson)

///|
fn CompactPayload::to_request(self : CompactPayload) -> @engine.CompactRequest {
  { session: self.session }
}

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
/// Open a transcript-referenced file in the user's system. `path` is the
/// literal path the webview displayed; a relative one is taken against the
/// conversation's working directory — `cwd` when the frontend has it (a live
/// run), otherwise derived from `session` (a resumed conversation). No
/// workspace containment is applied — the user clicked a path the agent itself
/// surfaced.
priv struct OpenPathPayload {
  session : String
  cwd : String
  path : String
} derive(FromJson)

///|
/// Reply to `open_path`: whether the file was handed to the system opener.
priv struct OpenPathReply {
  opened : Bool
} derive(ToJson)

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
fn event_sink(context : @app.AppCommandExtensionContext) -> @engine.EventSink {
  EventSink(async fn(event) { emit_engine_event(context, event) })
}

///|
async fn emit_engine_event(
  context : @app.AppCommandExtensionContext,
  event : @engine.EngineEvent,
) -> Unit {
  match event {
    Connected(payload) => context.emit("connected", payload)
    Started(payload) => context.emit("started", payload)
    StreamEvent(payload) => context.emit("event", payload)
    Error(payload) => context.emit("error", payload)
    Finished(payload) => context.emit("finished", payload)
  }
}
