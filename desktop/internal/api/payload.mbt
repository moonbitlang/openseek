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
type ArchivedSessionPayload = @protocol.ArchivedSessionPayload

///|
fn ArchivedSessionPayload::canonical_session(
  self : ArchivedSessionPayload,
) -> String {
  self.session.trim().to_owned()
}

///|
/// The opaque reverse-request id and the method-specific result selected by
/// the user. The host matches this id only against its live app-server map.
priv struct CodexResponsePayload {
  request_id : Json
  result : Json
} derive(FromJson)

///|
/// A Codex `#` query names the active app-server thread and the cwd learned
/// from that thread's authoritative reply. The host revalidates the pair
/// before giving the directory to app-server's fuzzy file search.
priv struct CodexFileSearchPayload {
  thread_id : String
  cwd : String
  query : String
} derive(FromJson)

///|
/// A skill catalog request is scoped to the cwd previously authorized by this
/// exact app-server thread. The page cannot scan an arbitrary directory.
priv struct CodexSkillsListPayload {
  thread_id : String
  cwd : String
  force_reload : Bool
} derive(FromJson)

///|
/// A browser-local draft uses this id only as a process-local Files/Terminal
/// owner. It is never forwarded to app-server as a Codex thread id.
priv struct CodexDraftPayload {
  draft_id : String
  cwd : String
} derive(FromJson)

///|
/// Desktop accepts only the thread/start fields its Codex composer owns. In
/// particular, a browser cannot choose app-server sandbox or approval policy.
priv struct CodexThreadStartPayload {
  cwd : String?
  model : String?
  draft_id : String?
}

///|
fn CodexThreadStartPayload::decode(value : Json) -> CodexThreadStartPayload? {
  guard value is Object(fields) else { return None }
  for key, _ in fields {
    guard key == "cwd" || key == "model" || key == "openseekDraftId" else {
      return None
    }
  }
  let cwd = match fields.get("cwd") {
    Some(String(value)) => Some(value)
    None => None
    _ => return None
  }
  let model = match fields.get("model") {
    Some(String(value)) => Some(value)
    None => None
    _ => return None
  }
  let draft_id = match fields.get("openseekDraftId") {
    Some(String(value)) => Some(value)
    None => None
    _ => return None
  }
  Some({ cwd, model, draft_id })
}

///|
fn CodexThreadStartPayload::app_server_params(
  self : CodexThreadStartPayload,
) -> Json {
  let fields : Map[String, Json] = {
    "serviceName": Json::string("openseek_desktop"),
  }
  if self.cwd is Some(cwd) {
    fields["cwd"] = Json::string(cwd)
  }
  if self.model is Some(model) && !model.trim().is_empty() {
    fields["model"] = Json::string(model)
  }
  Json::object(fields)
}

///|
/// turn/start retains app-server's evolving input/model fields, but Desktop
/// validates the two fields that establish filesystem ownership.
priv struct CodexTurnStartPayload {
  thread_id : String
  cwd : String?
  params : Map[String, Json]
}

///|
fn CodexTurnStartPayload::decode(value : Json) -> CodexTurnStartPayload? {
  guard value is Object(fields) &&
    fields.get("threadId") is Some(String(thread_id)) &&
    !thread_id.trim().is_empty() else {
    return None
  }
  let cwd = match fields.get("cwd") {
    Some(String(value)) => Some(value)
    None => None
    _ => return None
  }
  Some({ thread_id, cwd, params: fields })
}

///|
priv struct CodexDraftClosePayload {
  draft_id : String
} derive(FromJson)

///|
/// Draft authority is reserved for ids minted by this Desktop process. The
/// close endpoint must not accept an app-server thread id and revoke that
/// task's independently established cwd binding.
fn CodexDraftClosePayload::validated_id(
  self : CodexDraftClosePayload,
) -> String? {
  let id = self.draft_id.trim().to_owned()
  guard id == self.draft_id &&
    id.has_prefix("desktop-") &&
    !id.contains("/") &&
    !id.contains("\\") else {
    return None
  }
  Some(id)
}

///|
test "Codex thread start accepts only composer-owned fields" {
  let request = CodexThreadStartPayload::decode({
    "cwd": "/work/project",
    "model": "gpt-test",
    "openseekDraftId": "desktop-draft-1",
  }).unwrap()
  assert_eq(request.app_server_params(), {
    "cwd": "/work/project",
    "model": "gpt-test",
    "serviceName": "openseek_desktop",
  })
  assert_true(
    CodexThreadStartPayload::decode({
      "cwd": "/work/project",
      "sandbox": "danger-full-access",
    })
    is None,
  )
}

///|
test "Codex turn start requires a thread id and typed cwd" {
  assert_true(
    CodexTurnStartPayload::decode({
      "threadId": "thread-1",
      "cwd": "/work/project",
      "input": [],
    })
    is Some(_),
  )
  assert_true(CodexTurnStartPayload::decode({ "cwd": "/work/project" }) is None)
  assert_true(
    CodexTurnStartPayload::decode({ "threadId": "thread-1", "cwd": 42 }) is None,
  )
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
