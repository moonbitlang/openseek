// The engine-side methods' request payloads (docs/remote-protocol.md),
// decoded from `params` and translated to the engine package's requests.
// Host-side method payloads live in internal/host/protocol.mbt.

///|
priv struct StartPayload {
  task : String
  submission_id : String?
  model : String?
  max_steps : Int?
  session : String?
  // A registered workspace directory to run in; absent = scratch workspace.
  workspace : String?
} derive(FromJson)

///|
fn StartPayload::to_request(self : StartPayload) -> @engine.StartRequest {
  {
    task: self.task,
    submission_id: self.submission_id,
    model: self.model,
    max_steps: self.max_steps,
    session: self.session,
    workspace: self.workspace,
  }
}

///|
priv struct CancelPayload {
  run_id : String?
} derive(FromJson)

///|
fn CancelPayload::to_request(self : CancelPayload) -> @engine.CancelRequest {
  { run_id: self.run_id }
}

///|
priv struct SteerPayload {
  text : String
  run_id : String?
  submission_id : String?
} derive(FromJson)

///|
fn SteerPayload::to_request(self : SteerPayload) -> @engine.SteerRequest {
  { text: self.text, run_id: self.run_id, submission_id: self.submission_id }
}

///|
/// One lifecycle identity the caller still needs the host to settle. `session`
/// is always present; before Started is observed the client may know only the
/// submission id, and after it is observed the run id is authoritative.
priv struct KnownRunPayload {
  session : String
  run_id : String?
  submission_id : String?
} derive(FromJson)

///|
/// `agent.runs` remains compatible with the original empty-object request.
/// Omitting `known` asks only for the active-run snapshot and cannot replay
/// the process-lifetime settlement ledger.
priv struct RunsPayload {
  known : Array[KnownRunPayload]?
} derive(FromJson)

///|
/// A compact carries the same engine settings as a start (minus the task):
/// a conversation resumed after a restart has no live serve process, and
/// compacting it spawns one with these settings.
priv struct CompactPayload {
  session : String
  model : String?
  max_steps : Int?
  workspace : String?
} derive(FromJson)

///|
fn CompactPayload::to_request(self : CompactPayload) -> @engine.CompactRequest {
  {
    session: self.session,
    model: self.model,
    max_steps: self.max_steps,
    workspace: self.workspace,
  }
}

///|
/// `settings.set`: every field optional (absent = unchanged); a present
/// string field is trimmed, and empty clears the stored value; a present
/// `wsl` replaces the whole group.
priv struct SettingsSetPayload {
  provider : String?
  custom_api_url : String?
  deepseek_api_key : String?
  custom_api_key : String?
  wsl : SettingsWslPayload?
} derive(FromJson)

///|
priv struct SettingsWslPayload {
  enabled : Bool
  distro : String?
  engine : String?
} derive(FromJson)

///|
fn SettingsSetPayload::to_patch(
  self : SettingsSetPayload,
) -> @engine.SettingsPatch {
  {
    provider: self.provider,
    custom_api_url: self.custom_api_url,
    deepseek_api_key: self.deepseek_api_key,
    custom_api_key: self.custom_api_key,
    wsl: self.wsl.map(wsl => {
      (
        { enabled: wsl.enabled, distro: wsl.distro, engine: wsl.engine } :
        @engine.WslPatch)
    }),
  }
}

///|
priv struct LoadSessionPayload {
  session : String
  // The workspace whose store holds the session, when the client knows it.
  workspace : String?
} derive(FromJson)

///|
fn LoadSessionPayload::to_request(
  self : LoadSessionPayload,
) -> @engine.LoadSessionRequest {
  { session: self.session, workspace: self.workspace }
}

///|
/// `workspace.add` / `workspace.remove` name the project directory to
/// attach or detach.
priv struct WorkspacePayload {
  path : String
} derive(FromJson)

///|
/// `session.archive` / `session.unarchive` address a conversation by its
/// durable session id.
priv struct SessionPayload {
  session : String
} derive(FromJson)

///|
fn SessionPayload::canonical_session(self : SessionPayload) -> String {
  self.session.trim().to_owned()
}

///|
test "start and steer payloads preserve submission ids" {
  let start : StartPayload = decode({
    "task": "hello",
    "submission_id": "submission-start",
  })
  assert_eq(start.to_request().submission_id, Some("submission-start"))
  let steer : SteerPayload = decode({
    "text": "more detail",
    "run_id": "r1",
    "submission_id": "submission-steer",
  })
  assert_eq(steer.to_request().submission_id, Some("submission-steer"))
}

///|
test "legacy start and steer payloads omit submission ids" {
  let start : StartPayload = decode({ "task": "hello" })
  assert_true(start.to_request().submission_id is None)
  let steer : SteerPayload = decode({ "text": "more detail" })
  assert_true(steer.to_request().submission_id is None)
}

///|
test "client-authored session roots are ignored" {
  let start : StartPayload = decode({
    "task": "hello",
    "session": "s-start",
    "session_root": "/client/chosen/store",
  })
  let start_request = start.to_request()
  assert_eq(start_request.session, Some("s-start"))
  assert_true(start_request.workspace is None)
  let compact : CompactPayload = decode({
    "session": "s-compact",
    "session_root": "/client/chosen/store",
  })
  let compact_request = compact.to_request()
  assert_eq(compact_request.session, "s-compact")
  assert_true(compact_request.workspace is None)
}

///|
test "session move payload has one canonical id" {
  let payload : SessionPayload = decode({ "session": "  s-canonical  " })
  assert_eq(payload.canonical_session(), "s-canonical")
}
