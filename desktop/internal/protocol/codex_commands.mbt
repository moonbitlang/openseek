// Typed Desktop contracts for the curated Codex app-server surface. These
// records describe the stable boundary owned by SeekMoon; nested app-server
// documents remain JSON where their schema is versioned independently.

///|
pub(all) struct CodexDraftOpenPayload {
  draft_id : String
  cwd : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexDraftClosePayload {
  draft_id : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexServerRequestRespondPayload {
  request_id : Json
  result : Json
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexFileSearchPayload {
  thread_id : String
  cwd : String
  query : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexSkillsListPayload {
  thread_id : String
  cwd : String
  force_reload : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexAccountReadPayload {
  refresh_token : Bool
} derive (
  Debug,
  Eq,
  FromJson(fields(refresh_token(rename="refreshToken"))),
  ToJson(fields(refresh_token(rename="refreshToken"))),
)

///|
pub(all) struct CodexAccountLoginStartPayload {
  kind_ : String
  use_hosted_login_success_page : Bool
  app_brand : String
} derive (
  Debug,
  Eq,
  FromJson(
    fields(
      kind_(rename="type"),
      use_hosted_login_success_page(rename="useHostedLoginSuccessPage"),
      app_brand(rename="appBrand"),
    ),
  ),
  ToJson(
    fields(
      kind_(rename="type"),
      use_hosted_login_success_page(rename="useHostedLoginSuccessPage"),
      app_brand(rename="appBrand"),
    ),
  ),
)

///|
pub(all) struct CodexAccountLoginCancelPayload {
  login_id : String
} derive (
  Debug,
  Eq,
  FromJson(fields(login_id(rename="loginId"))),
  ToJson(fields(login_id(rename="loginId"))),
)

///|
pub(all) struct CodexModelListPayload {
  limit : Int
  include_hidden : Bool
} derive (
  Debug,
  Eq,
  FromJson(fields(include_hidden(rename="includeHidden"))),
  ToJson(fields(include_hidden(rename="includeHidden"))),
)

///|
pub(all) struct CodexThreadStartPayload {
  cwd : String?
  model : String?
  draft_id : String?
} derive (
  Debug,
  Eq,
  FromJson(fields(draft_id(rename="openseekDraftId"))),
  ToJson(fields(draft_id(rename="openseekDraftId"))),
)

///|
pub(all) struct CodexThreadPayload {
  thread_id : String
} derive (
  Debug,
  Eq,
  FromJson(fields(thread_id(rename="threadId"))),
  ToJson(fields(thread_id(rename="threadId"))),
)

///|
pub(all) struct CodexThreadReadPayload {
  thread_id : String
  include_turns : Bool?
} derive (
  Debug,
  Eq,
  FromJson(
    fields(thread_id(rename="threadId"), include_turns(rename="includeTurns")),
  ),
  ToJson(
    fields(thread_id(rename="threadId"), include_turns(rename="includeTurns")),
  ),
)

///|
pub(all) struct CodexThreadListPayload {
  limit : Int
  archived : Bool
  cursor : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexThreadArchivePayload {
  thread_id : String
  force : Bool
} derive (
  Debug,
  Eq,
  FromJson(fields(thread_id(rename="threadId"))),
  ToJson(fields(thread_id(rename="threadId"))),
)

///|
pub(all) struct CodexReviewTarget {
  kind_ : String
} derive (
  Debug,
  Eq,
  FromJson(fields(kind_(rename="type"))),
  ToJson(fields(kind_(rename="type"))),
)

///|
pub(all) struct CodexReviewStartPayload {
  thread_id : String
  target : CodexReviewTarget
} derive (
  Debug,
  Eq,
  FromJson(fields(thread_id(rename="threadId"))),
  ToJson(fields(thread_id(rename="threadId"))),
)

///|
pub(all) struct CodexTurnStartPayload {
  thread_id : String
  input : Array[Json]
  model : String?
  cwd : String?
} derive (
  Debug,
  Eq,
  FromJson(fields(thread_id(rename="threadId"))),
  ToJson(fields(thread_id(rename="threadId"))),
)

///|
pub(all) struct CodexTurnSteerPayload {
  thread_id : String
  input : Array[Json]
  expected_turn_id : String
} derive (
  Debug,
  Eq,
  FromJson(
    fields(
      thread_id(rename="threadId"),
      expected_turn_id(rename="expectedTurnId"),
    ),
  ),
  ToJson(
    fields(
      thread_id(rename="threadId"),
      expected_turn_id(rename="expectedTurnId"),
    ),
  ),
)

///|
pub(all) struct CodexTurnInterruptPayload {
  thread_id : String
  turn_id : String
} derive (
  Debug,
  Eq,
  FromJson(fields(thread_id(rename="threadId"), turn_id(rename="turnId"))),
  ToJson(fields(thread_id(rename="threadId"), turn_id(rename="turnId"))),
)

///|
pub(all) struct CodexStatusReply {
  status : String
  message : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CodexDraftOpenReply {
  draft_id : String
  cwd : String
  project_root : String
} derive (
  Debug,
  Eq,
  FromJson(
    fields(draft_id(rename="draftId"), project_root(rename="projectRoot")),
  ),
  ToJson(fields(draft_id(rename="draftId"), project_root(rename="projectRoot"))),
)

///|
/// The list envelope is stable across app-server catalogs. Individual rows
/// remain JSON because Codex can add fields without changing this Desktop API.
pub(all) struct CodexDataReply {
  data : Array[Json]
  next_cursor : String?
} derive (
  Debug,
  Eq,
  FromJson(fields(next_cursor(rename="nextCursor"))),
  ToJson(fields(next_cursor(rename="nextCursor"))),
)

///|
pub(all) struct CodexAccountReply {
  account : Json?
  requires_openai_auth : Bool
} derive (
  Debug,
  Eq,
  FromJson(fields(requires_openai_auth(rename="requiresOpenaiAuth"))),
  ToJson(fields(requires_openai_auth(rename="requiresOpenaiAuth"))),
)

///|
pub(all) struct CodexLoginStartReply {
  login_id : String
  auth_url : String
} derive (
  Debug,
  Eq,
  FromJson(fields(login_id(rename="loginId"), auth_url(rename="authUrl"))),
  ToJson(fields(login_id(rename="loginId"), auth_url(rename="authUrl"))),
)

///|
pub(all) struct CodexThreadReply {
  thread : Json
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `thread/resume` returns a thread on success and Desktop's explicit
/// `{status:"activeWriter"}` state when another client owns the writer.
pub(all) struct CodexThreadResumeReply {
  thread : Json?
  status : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// A start reply may contain the complete turn while a steer reply may contain
/// only `turnId`. Both are successful deliveries of the same composer action.
pub(all) struct CodexTurnReply {
  turn : Json?
  turn_id : String?
} derive (
  Debug,
  Eq,
  FromJson(fields(turn_id(rename="turnId"))),
  ToJson(fields(turn_id(rename="turnId"))),
)

///|
/// File search is a versioned app-server result. The Desktop gives it a
/// command-specific type while preserving the upstream object unchanged.
pub(all) struct CodexFileSearchReply {
  value : Json
}

///|
pub impl ToJson for CodexFileSearchReply with fn to_json(self) {
  self.value
}

///|
pub impl FromJson for CodexFileSearchReply with fn from_json(json, path) {
  guard json is Object(_) else {
    raise JsonDecodeError((path, "expected Codex file search reply"))
  }
  { value: json }
}

///|
/// Archive has three object-shaped outcomes: archived, needs confirmation,
/// and archived while retaining a checkout that became dirty concurrently.
pub(all) struct CodexArchiveReply {
  value : Json
}

///|
pub impl ToJson for CodexArchiveReply with fn to_json(self) {
  self.value
}

///|
pub impl FromJson for CodexArchiveReply with fn from_json(json, path) {
  guard json is Object(_) else {
    raise JsonDecodeError((path, "expected Codex archive reply"))
  }
  { value: json }
}
