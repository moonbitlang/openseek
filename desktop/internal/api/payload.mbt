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
/// Translate one Desktop permission choice into the current experimental
/// app-server fields. Auto-review changes the reviewer, not the sandbox; full
/// access deliberately removes both the approval prompt and sandbox boundary.
fn @protocol.CodexPermissionMode::write_app_server_settings(
  self : @protocol.CodexPermissionMode,
  fields : Map[String, Json],
) -> Unit {
  match self {
    RequestApproval => {
      fields["approvalPolicy"] = Json::string("on-request")
      fields["approvalsReviewer"] = Json::string("user")
      fields["permissions"] = Json::string(":workspace")
    }
    AutoReview => {
      fields["approvalPolicy"] = Json::string("on-request")
      fields["approvalsReviewer"] = Json::string("auto_review")
      fields["permissions"] = Json::string(":workspace")
    }
    FullAccess => {
      fields["approvalPolicy"] = Json::string("never")
      fields["permissions"] = Json::string(":danger-full-access")
    }
  }
}

///|
/// Reduce Desktop's typed thread/start request to the fields owned by the
/// app-server. The draft id exists only to prove the selected cwd below.
fn @protocol.CodexThreadStartPayload::app_server_params(
  self : @protocol.CodexThreadStartPayload,
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
  self.permission_mode.write_app_server_settings(fields)
  Json::object(fields)
}

///|
/// Resume acquires the task writer and installs the selected permission mode
/// in the same request, so no turn can slip through under stale settings.
fn @protocol.CodexThreadResumePayload::app_server_params(
  self : @protocol.CodexThreadResumePayload,
) -> Json {
  let fields : Map[String, Json] = { "threadId": Json::string(self.thread_id) }
  self.permission_mode.write_app_server_settings(fields)
  Json::object(fields)
}

///|
/// A turn-level override becomes app-server's default for later turns too.
/// Carrying the mode here covers already-writable tasks without a separate
/// settings mutation between the user's selection and Send.
fn @protocol.CodexTurnStartPayload::app_server_params(
  self : @protocol.CodexTurnStartPayload,
) -> Json {
  let fields : Map[String, Json] = {
    "threadId": Json::string(self.thread_id),
    "input": Json::array(self.input),
  }
  if self.model is Some(model) {
    fields["model"] = Json::string(model)
  }
  if self.effort is Some(effort) {
    fields["effort"] = Json::string(effort)
  }
  if self.cwd is Some(cwd) {
    fields["cwd"] = Json::string(cwd)
  }
  self.permission_mode.write_app_server_settings(fields)
  Json::object(fields)
}

///|
/// Draft authority is reserved for ids minted by this Desktop process. The
/// close endpoint must not accept an app-server thread id and revoke that
/// task's independently established cwd binding.
fn @protocol.CodexDraftClosePayload::validated_id(
  self : @protocol.CodexDraftClosePayload,
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
test "Codex thread start maps the Desktop envelope to app-server" {
  let request : @protocol.CodexThreadStartPayload = @json.from_json({
    "cwd": "/work/project",
    "model": "gpt-test",
    "openseekDraftId": "desktop-draft-1",
    "permissionMode": "autoReview",
  })
  assert_eq(request.app_server_params(), {
    "approvalPolicy": "on-request",
    "approvalsReviewer": "auto_review",
    "cwd": "/work/project",
    "model": "gpt-test",
    "permissions": ":workspace",
    "serviceName": "openseek_desktop",
  })
}

///|
test "Codex resume and turn map full access without a reviewer" {
  let resume_request : @protocol.CodexThreadResumePayload = @json.from_json({
    "threadId": "thread-1",
    "permissionMode": "fullAccess",
  })
  assert_eq(resume_request.app_server_params(), {
    "threadId": "thread-1",
    "approvalPolicy": "never",
    "permissions": ":danger-full-access",
  })
  let request : @protocol.CodexTurnStartPayload = @json.from_json({
    "threadId": "thread-1",
    "cwd": "/work/project",
    "input": [{ "type": "text", "text": "hello" }],
    "model": "gpt-test",
    "effort": "high",
    "permissionMode": "requestApproval",
  })
  assert_eq(request.app_server_params(), {
    "approvalPolicy": "on-request",
    "approvalsReviewer": "user",
    "threadId": "thread-1",
    "cwd": "/work/project",
    "input": [{ "type": "text", "text": "hello" }],
    "model": "gpt-test",
    "effort": "high",
    "permissions": ":workspace",
  })
}

///|
test "start and steer payloads preserve submission ids" {
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "workspace": "/work/project",
    "submission_id": "submission-start",
    "thinking": "high",
  })
  assert_eq(start.submission_id, Some("submission-start"))
  assert_eq(start.thinking, Some(ThinkingHigh))
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
    "workspace": "/work/project",
  })
  assert_true(start.submission_id is None)
  let steer : @protocol.SteerPayload = @json.from_json({ "text": "more detail" })
  assert_true(steer.submission_id is None)
}

///|
test "client-authored session roots are ignored" {
  // A client names its store as `workspace`, which the host validates against
  // its registry. `session_root` is a host-derived fact it reports back, never
  // one it accepts: a payload carrying one is decoded without it.
  let start : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "workspace": "/work/project",
    "session_root": "/client/chosen/store",
  })
  assert_eq(start.session, "s-start")
  assert_eq(start.workspace, "/work/project")
  let compact : @protocol.CompactPayload = @json.from_json({
    "session": "s-compact",
    "workspace": "/work/project",
    "session_root": "/client/chosen/store",
  })
  assert_eq(compact.session, "s-compact")
  assert_eq(compact.workspace, "/work/project")
}

///|
test "start payload requires a session" {
  let decoded : @protocol.StartPayload? = Some(
    @json.from_json({ "task": "hello", "workspace": "/work/project" }),
  ) catch {
    _ => None
  }
  assert_true(decoded is None)
}

///|
test "a run payload without a store is not a valid request" {
  // Half of a record's identity. A start, compaction, or goal that omitted it
  // would leave the host inferring the store from the id — the search that
  // hands one store's command to another store's record.
  let start : @protocol.StartPayload? = Some(
    @json.from_json({ "task": "hello", "session": "s-start" }),
  ) catch {
    _ => None
  }
  assert_true(start is None)
  let compact : @protocol.CompactPayload? = Some(
    @json.from_json({ "session": "s-compact" }),
  ) catch {
    _ => None
  }
  assert_true(compact is None)
  let goal : @protocol.GoalPayload? = Some(
    @json.from_json({ "session": "s-goal", "text": "ship it" }),
  ) catch {
    _ => None
  }
  assert_true(goal is None)
}

///|
test "a required field is not satisfied by null or a wrong type" {
  // `null` is not a store: reading it as an absent field would leave the host
  // guessing which store the request meant, the silent misplacement the
  // required field exists to prevent.
  let null_store : @protocol.SessionPayload? = Some(
    @json.from_json({ "session": "s-move", "workspace": Json::null() }),
  ) catch {
    _ => None
  }
  assert_true(null_store is None)
  let wrong_type : @protocol.LoadSessionPayload? = Some(
    @json.from_json({ "session": "s-load", "workspace": 7 }),
  ) catch {
    _ => None
  }
  assert_true(wrong_type is None)
}

///|
test "an absent optional reads the same as an explicit null" {
  let absent : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "workspace": "/work/project",
  })
  let explicit : @protocol.StartPayload = @json.from_json({
    "task": "hello",
    "session": "s-start",
    "workspace": "/work/project",
    "model": Json::null(),
    "max_steps": Json::null(),
    "submission_id": Json::null(),
  })
  assert_true(
    absent.model is None &&
    absent.max_steps is None &&
    absent.submission_id is None,
  )
  assert_true(
    explicit.model is None &&
    explicit.max_steps is None &&
    explicit.submission_id is None,
  )
  // A malformed optional is still refused: absence is a value, a number is a
  // client defect.
  let malformed : @protocol.StartPayload? = Some(
    @json.from_json({
      "task": "hello",
      "session": "s-start",
      "workspace": "/work/project",
      "model": 7,
    }),
  ) catch {
    _ => None
  }
  assert_true(malformed is None)
}

///|
test "a step count that is not an integer is refused, not truncated" {
  // `1.9` is a malformed request, not a request for one step: running a
  // different limit than the client sent is the silent divergence the
  // explicit codec exists to prevent.
  let start : @protocol.StartPayload? = Some(
    @json.from_json({
      "task": "hello",
      "session": "s-start",
      "workspace": "/work/project",
      "max_steps": 1.9,
    }),
  ) catch {
    _ => None
  }
  assert_true(start is None)
  let compact : @protocol.CompactPayload? = Some(
    @json.from_json({
      "session": "s-compact",
      "workspace": "/work/project",
      "max_steps": 1.9,
    }),
  ) catch {
    _ => None
  }
  assert_true(compact is None)
  let goal : @protocol.GoalPayload? = Some(
    @json.from_json({
      "session": "s-goal",
      "workspace": "/work/project",
      "max_steps": 1.9,
    }),
  ) catch {
    _ => None
  }
  assert_true(goal is None)
  // A whole number written as JSON still decodes; only the fractional part is
  // the defect.
  let whole : @protocol.CompactPayload = @json.from_json({
    "session": "s-compact",
    "workspace": "/work/project",
    "max_steps": 1000,
  })
  assert_eq(whole.max_steps, Some(1000))
}

///|
test "an absent optional is encoded as an absent key, never as null" {
  let payload : @protocol.GoalPayload = {
    session: "s-goal",
    workspace: "/work/project",
    text: None,
    auto: None,
    model: None,
    thinking: None,
    max_steps: None,
  }
  guard payload.to_json() is Object(fields) else {
    fail("goal payload is a JSON object")
  }
  assert_eq(fields.get("session"), Some(Json::string("s-goal")))
  assert_eq(fields.get("workspace"), Some(Json::string("/work/project")))
  for name in ["text", "auto", "model", "max_steps"] {
    assert_true(fields.get(name) is None)
  }
}

///|
test "goal payload distinguishes set from clear by the text field" {
  let set : @protocol.GoalPayload = @json.from_json({
    "session": "s-goal",
    "workspace": "/work/project",
    "text": "ship the feature",
    "model": "deepseek-v4-pro",
    "thinking": "max",
  })
  assert_eq(set.text, Some("ship the feature"))
  assert_eq(set.model, Some("deepseek-v4-pro"))
  assert_eq(set.thinking, Some(ThinkingMax))
  let clear : @protocol.GoalPayload = @json.from_json({
    "session": "s-goal",
    "workspace": "/work/project",
  })
  assert_true(clear.text is None)
}

///|
test "session move payload has one canonical id and a required store" {
  let payload : SessionPayload = @json.from_json({
    "session": "  s-canonical  ",
    "workspace": "/work/project",
  })
  assert_eq(payload.canonical_session(), "s-canonical")
  assert_eq(payload.workspace, "/work/project")
  // The store is half the record's identity, so a payload without it is not
  // a valid move request — it would leave the host searching again.
  let storeless = try {
    let decoded : SessionPayload = @json.from_json({ "session": "s-canonical" })
    Some(decoded)
  } catch {
    _ => None
  }
  assert_true(storeless is None)
}
