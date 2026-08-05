// The engine-side methods' request payloads (docs/remote-protocol.md),
// decoded from `params` and translated to the engine package's requests.
// Host-side method payloads live in internal/host/protocol.mbt.

///|
type StartPayload = @protocol.StartPayload

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
type CancelPayload = @protocol.CancelPayload

///|
fn CancelPayload::to_request(self : CancelPayload) -> @engine.CancelRequest {
  { run_id: self.run_id }
}

///|
type SteerPayload = @protocol.SteerPayload

///|
fn SteerPayload::to_request(self : SteerPayload) -> @engine.SteerRequest {
  { text: self.text, run_id: self.run_id, submission_id: self.submission_id }
}

///|
/// One lifecycle identity the caller still needs the host to settle. `session`
/// is always present; before Started is observed the client may know only the
/// submission id, and after it is observed the run id is authoritative.
type KnownRunPayload = @protocol.KnownRunPayload

///|
/// `agent.runs` remains compatible with the original empty-object request.
/// Omitting `known` asks only for the active-run snapshot and cannot replay
/// the process-lifetime settlement ledger.
/// A compact carries the same engine settings as a start (minus the task):
/// a conversation resumed after a restart has no live serve process, and
/// compacting it spawns one with these settings.
type CompactPayload = @protocol.CompactPayload

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
/// string field is trimmed, and empty clears the stored value.
type SettingsSetPayload = @protocol.SettingsSetPayload

///|
fn SettingsSetPayload::to_patch(
  self : SettingsSetPayload,
) -> @engine.SettingsPatch {
  {
    provider: self.provider,
    custom_api_url: self.custom_api_url,
    deepseek_api_key: self.deepseek_api_key,
    custom_api_key: self.custom_api_key,
  }
}

///|
type LoadSessionPayload = @protocol.LoadSessionPayload

///|
fn LoadSessionPayload::to_request(
  self : LoadSessionPayload,
) -> @engine.LoadSessionRequest {
  { session: self.session, workspace: self.workspace }
}

///|
/// `workspace.add` / `workspace.remove` name the project directory to
/// attach or detach.
/// `session.archive` / `session.unarchive` address a conversation by its
/// durable session id.
type SessionPayload = @protocol.SessionPayload

///|
fn SessionPayload::canonical_session(self : SessionPayload) -> String {
  self.session.trim().to_owned()
}

///|
test "start and steer payloads preserve submission ids" {
  let start : StartPayload = @json.from_json({
    "task": "hello",
    "submission_id": "submission-start",
  })
  assert_eq(start.to_request().submission_id, Some("submission-start"))
  let steer : SteerPayload = @json.from_json({
    "text": "more detail",
    "run_id": "r1",
    "submission_id": "submission-steer",
  })
  assert_eq(steer.to_request().submission_id, Some("submission-steer"))
}

///|
test "legacy start and steer payloads omit submission ids" {
  let start : StartPayload = @json.from_json({ "task": "hello" })
  assert_true(start.to_request().submission_id is None)
  let steer : SteerPayload = @json.from_json({ "text": "more detail" })
  assert_true(steer.to_request().submission_id is None)
}

///|
test "client-authored session roots are ignored" {
  let start : StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "session_root": "/client/chosen/store",
  })
  let start_request = start.to_request()
  assert_eq(start_request.session, Some("s-start"))
  assert_true(start_request.workspace is None)
  let compact : CompactPayload = @json.from_json({
    "session": "s-compact",
    "session_root": "/client/chosen/store",
  })
  let compact_request = compact.to_request()
  assert_eq(compact_request.session, "s-compact")
  assert_true(compact_request.workspace is None)
}

///|
test "session move payload has one canonical id" {
  let payload : SessionPayload = @json.from_json({
    "session": "  s-canonical  ",
  })
  assert_eq(payload.canonical_session(), "s-canonical")
}
