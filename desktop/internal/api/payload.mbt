// Domain-specific normalization that cannot be represented by sharing the
// typed protocol payload directly with the engine.

///|
/// One lifecycle identity the caller still needs the host to settle. Before
/// `Started`, the submission id may be all the client knows; afterward, the
/// run id is authoritative.
type KnownRunPayload = @protocol.KnownRunPayload

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
/// `session.archive` / `session.unarchive` address a conversation by its
/// durable session id, normalized before it reaches the engine.
type SessionPayload = @protocol.SessionPayload

///|
fn SessionPayload::canonical_session(self : SessionPayload) -> String {
  self.session.trim().to_owned()
}

///|
test "start and steer payloads preserve submission ids" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "submission_id": "submission-start",
  })
  assert_eq(start.submission_id, Some("submission-start"))
  let steer : @protocol.SteerPayload = @json.from_json({
    "text": "more detail",
    "run_id": "r1",
    "submission_id": "submission-steer",
  })
  assert_eq(steer.submission_id, Some("submission-steer"))
}

///|
test "start and steer payloads may omit submission ids" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
  })
  assert_true(start.submission_id is None)
  let steer : @protocol.SteerPayload = @json.from_json({ "text": "more detail" })
  assert_true(steer.submission_id is None)
}

///|
test "client-authored session roots are ignored" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "session_root": "/client/chosen/store",
  })
  assert_eq(start.session, "s-start")
  assert_true(start.workspace is None)
  let compact : @protocol.CompactPayload = @json.from_json({
    "session": "s-compact",
    "session_root": "/client/chosen/store",
  })
  assert_eq(compact.session, "s-compact")
  assert_true(compact.workspace is None)
}

///|
test "start payload requires a session" {
  let decoded : @protocol.StartPayload? = Some(
    @json.from_json({ "task": "hello" }),
  ) catch {
    _ => None
  }
  assert_true(decoded is None)
}

///|
test "goal payload distinguishes set from clear by the text field" {
  let set : @protocol.GoalPayload = @json.from_json({
    "session": "s-goal",
    "text": "ship the feature",
    "model": "deepseek-v4-pro",
  })
  assert_eq(set.text, Some("ship the feature"))
  assert_eq(set.model, Some("deepseek-v4-pro"))
  let clear : @protocol.GoalPayload = @json.from_json({ "session": "s-goal" })
  assert_true(clear.text is None)
}

///|
test "session move payload has one canonical id" {
  let payload : SessionPayload = @json.from_json({
    "session": "  s-canonical  ",
  })
  assert_eq(payload.canonical_session(), "s-canonical")
}
