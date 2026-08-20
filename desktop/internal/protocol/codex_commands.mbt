// Typed Desktop contracts for the curated Codex app-server surface. These
// records describe the stable boundary owned by SeekMoon; nested app-server
// documents remain JSON where their schema is versioned independently.

///|
/// The explicit Codex codecs intentionally ignore unknown object fields so a
/// newer app-server may add metadata. Each concrete codec below still names
/// every field it consumes and decides how `null` differs from absence.
priv struct CodexJsonObject {
  fields : Map[String, Json]
  path : @json.JsonPath
}

///|
fn CodexJsonObject::decode(
  json : Json,
  path : @json.JsonPath,
  expected : String,
) -> CodexJsonObject raise @json.JsonDecodeError {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected " + expected + " object"))
  }
  { fields, path }
}

///|
fn CodexJsonObject::required_json(
  self : CodexJsonObject,
  name : String,
) -> Json raise @json.JsonDecodeError {
  match self.fields.get(name) {
    Some(value) => value
    None =>
      raise JsonDecodeError((self.path.add_key(name), "missing required field"))
  }
}

///|
fn CodexJsonObject::optional_json(
  self : CodexJsonObject,
  name : String,
) -> Json? {
  match self.fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

///|
fn CodexJsonObject::required_string(
  self : CodexJsonObject,
  name : String,
) -> String raise @json.JsonDecodeError {
  guard self.required_json(name) is String(value) else {
    raise JsonDecodeError((self.path.add_key(name), "expected string"))
  }
  value
}

///|
fn CodexJsonObject::optional_string(
  self : CodexJsonObject,
  name : String,
) -> String? raise @json.JsonDecodeError {
  guard self.optional_json(name) is Some(value) else { return None }
  guard value is String(value) else {
    raise JsonDecodeError((self.path.add_key(name), "expected string or null"))
  }
  Some(value)
}

///|
fn CodexJsonObject::required_bool(
  self : CodexJsonObject,
  name : String,
) -> Bool raise @json.JsonDecodeError {
  match self.required_json(name) {
    True => true
    False => false
    _ => raise JsonDecodeError((self.path.add_key(name), "expected boolean"))
  }
}

///|
fn CodexJsonObject::optional_bool(
  self : CodexJsonObject,
  name : String,
) -> Bool? raise @json.JsonDecodeError {
  guard self.optional_json(name) is Some(value) else { return None }
  match value {
    True => Some(true)
    False => Some(false)
    _ =>
      raise JsonDecodeError(
        (self.path.add_key(name), "expected boolean or null"),
      )
  }
}

///|
fn CodexJsonObject::required_int(
  self : CodexJsonObject,
  name : String,
) -> Int raise @json.JsonDecodeError {
  @json.from_json(self.required_json(name), path=self.path.add_key(name))
}

///|
fn CodexJsonObject::required_array(
  self : CodexJsonObject,
  name : String,
) -> Array[Json] raise @json.JsonDecodeError {
  guard self.required_json(name) is Array(values) else {
    raise JsonDecodeError((self.path.add_key(name), "expected array"))
  }
  values
}

///|
pub(all) struct CodexDraftOpenPayload {
  draft_id : String
  cwd : String
} derive(Debug, Eq)

///|
pub(all) struct CodexDraftClosePayload {
  draft_id : String
} derive(Debug, Eq)

///|
pub(all) struct CodexServerRequestRespondPayload {
  request_id : Json
  result : Json
} derive(Debug, Eq)

///|
pub(all) struct CodexFileSearchPayload {
  thread_id : String
  cwd : String
  query : String
} derive(Debug, Eq)

///|
pub(all) struct CodexSkillsListPayload {
  thread_id : String
  cwd : String
  force_reload : Bool
} derive(Debug, Eq)

///|
pub(all) struct CodexAccountReadPayload {
  refresh_token : Bool
} derive(Debug, Eq)

///|
pub(all) struct CodexAccountLoginStartPayload {
  kind_ : String
  use_hosted_login_success_page : Bool
  app_brand : String
} derive(Debug, Eq)

///|
pub(all) struct CodexAccountLoginCancelPayload {
  login_id : String
} derive(Debug, Eq)

///|
pub(all) struct CodexModelListPayload {
  limit : Int
  include_hidden : Bool
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadStartPayload {
  cwd : String?
  model : String?
  draft_id : String?
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadPayload {
  thread_id : String
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadReadPayload {
  thread_id : String
  include_turns : Bool?
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadListPayload {
  limit : Int
  archived : Bool
  cursor : String?
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadArchivePayload {
  thread_id : String
  force : Bool
} derive(Debug, Eq)

///|
pub(all) struct CodexReviewTarget {
  kind_ : String
} derive(Debug, Eq)

///|
pub(all) struct CodexReviewStartPayload {
  thread_id : String
  target : CodexReviewTarget
} derive(Debug, Eq)

///|
pub(all) struct CodexTurnStartPayload {
  thread_id : String
  input : Array[Json]
  model : String?
  cwd : String?
} derive(Debug, Eq)

///|
pub(all) struct CodexTurnSteerPayload {
  thread_id : String
  input : Array[Json]
  expected_turn_id : String
} derive(Debug, Eq)

///|
pub(all) struct CodexTurnInterruptPayload {
  thread_id : String
  turn_id : String
} derive(Debug, Eq)

///|
pub(all) struct CodexStatusReply {
  status : String
  message : String?
} derive(Debug, Eq)

///|
pub(all) struct CodexDraftOpenReply {
  draft_id : String
  cwd : String
  project_root : String
} derive(Debug, Eq)

///|
/// The list envelope is stable across app-server catalogs. Individual rows
/// remain JSON because Codex can add fields without changing this Desktop API.
pub(all) struct CodexDataReply {
  data : Array[Json]
  next_cursor : String?
} derive(Debug, Eq)

///|
/// Reverse-request snapshots carry the actor's ordering generation. Unlike a
/// catalog cursor, this value orders the snapshot against live request and
/// resolution notifications delivered on the same app-server connection.
pub(all) struct CodexServerRequestsReply {
  data : Array[Json]
  generation : Int
} derive(Debug, Eq)

///|
pub(all) struct CodexAccountReply {
  account : Json?
  requires_openai_auth : Bool
} derive(Debug, Eq)

///|
pub(all) struct CodexLoginStartReply {
  login_id : String
  auth_url : String
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadReply {
  thread : Json
} derive(Debug, Eq)

///|
/// `thread/resume` returns a thread on success and Desktop's explicit
/// `{status:"activeWriter"}` state when another client owns the writer.
pub(all) struct CodexThreadResumeReply {
  thread : Json?
  status : String?
} derive(Debug, Eq)

///|
/// A start reply may contain the complete turn while a steer reply may contain
/// only `turnId`. Both are successful deliveries of the same composer action.
pub(all) struct CodexTurnReply {
  turn : Json?
  turn_id : String?
} derive(Debug, Eq)

///|
pub impl FromJson for CodexDraftOpenPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex draft open payload")
  {
    draft_id: object.required_string("draft_id"),
    cwd: object.required_string("cwd"),
  }
}

///|
pub impl ToJson for CodexDraftOpenPayload with fn to_json(self) {
  { "draft_id": Json::string(self.draft_id), "cwd": Json::string(self.cwd) }
}

///|
pub impl FromJson for CodexDraftClosePayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex draft close payload")
  { draft_id: object.required_string("draft_id") }
}

///|
pub impl ToJson for CodexDraftClosePayload with fn to_json(self) {
  { "draft_id": Json::string(self.draft_id) }
}

///|
pub impl FromJson for CodexServerRequestRespondPayload with fn from_json(
  json,
  path,
) {
  let object = CodexJsonObject::decode(
    json, path, "Codex server request response payload",
  )
  {
    request_id: object.required_json("request_id"),
    result: object.required_json("result"),
  }
}

///|
pub impl ToJson for CodexServerRequestRespondPayload with fn to_json(self) {
  { "request_id": self.request_id, "result": self.result }
}

///|
pub impl FromJson for CodexFileSearchPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex file search payload")
  {
    thread_id: object.required_string("thread_id"),
    cwd: object.required_string("cwd"),
    query: object.required_string("query"),
  }
}

///|
pub impl ToJson for CodexFileSearchPayload with fn to_json(self) {
  {
    "thread_id": Json::string(self.thread_id),
    "cwd": Json::string(self.cwd),
    "query": Json::string(self.query),
  }
}

///|
pub impl FromJson for CodexSkillsListPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex skills list payload")
  {
    thread_id: object.required_string("thread_id"),
    cwd: object.required_string("cwd"),
    force_reload: object.required_bool("force_reload"),
  }
}

///|
pub impl ToJson for CodexSkillsListPayload with fn to_json(self) {
  {
    "thread_id": Json::string(self.thread_id),
    "cwd": Json::string(self.cwd),
    "force_reload": Json::boolean(self.force_reload),
  }
}

///|
pub impl FromJson for CodexAccountReadPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex account read payload")
  { refresh_token: object.required_bool("refreshToken") }
}

///|
pub impl ToJson for CodexAccountReadPayload with fn to_json(self) {
  { "refreshToken": Json::boolean(self.refresh_token) }
}

///|
pub impl FromJson for CodexAccountLoginStartPayload with fn from_json(
  json,
  path,
) {
  let object = CodexJsonObject::decode(
    json, path, "Codex account login start payload",
  )
  {
    kind_: object.required_string("type"),
    use_hosted_login_success_page: object.required_bool(
      "useHostedLoginSuccessPage",
    ),
    app_brand: object.required_string("appBrand"),
  }
}

///|
pub impl ToJson for CodexAccountLoginStartPayload with fn to_json(self) {
  {
    "type": Json::string(self.kind_),
    "useHostedLoginSuccessPage": Json::boolean(
      self.use_hosted_login_success_page,
    ),
    "appBrand": Json::string(self.app_brand),
  }
}

///|
pub impl FromJson for CodexAccountLoginCancelPayload with fn from_json(
  json,
  path,
) {
  let object = CodexJsonObject::decode(
    json, path, "Codex account login cancel payload",
  )
  { login_id: object.required_string("loginId") }
}

///|
pub impl ToJson for CodexAccountLoginCancelPayload with fn to_json(self) {
  { "loginId": Json::string(self.login_id) }
}

///|
pub impl FromJson for CodexModelListPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex model list payload")
  {
    limit: object.required_int("limit"),
    include_hidden: object.required_bool("includeHidden"),
  }
}

///|
pub impl ToJson for CodexModelListPayload with fn to_json(self) {
  {
    "limit": Json::number(self.limit.to_double()),
    "includeHidden": Json::boolean(self.include_hidden),
  }
}

///|
pub impl FromJson for CodexThreadStartPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex thread start payload")
  {
    cwd: object.optional_string("cwd"),
    model: object.optional_string("model"),
    draft_id: object.optional_string("openseekDraftId"),
  }
}

///|
pub impl ToJson for CodexThreadStartPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.cwd is Some(cwd) {
    fields["cwd"] = Json::string(cwd)
  }
  if self.model is Some(model) {
    fields["model"] = Json::string(model)
  }
  if self.draft_id is Some(draft_id) {
    fields["openseekDraftId"] = Json::string(draft_id)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexThreadPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex thread payload")
  { thread_id: object.required_string("threadId") }
}

///|
pub impl ToJson for CodexThreadPayload with fn to_json(self) {
  { "threadId": Json::string(self.thread_id) }
}

///|
pub impl FromJson for CodexThreadReadPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex thread read payload")
  {
    thread_id: object.required_string("threadId"),
    include_turns: object.optional_bool("includeTurns"),
  }
}

///|
pub impl ToJson for CodexThreadReadPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "threadId": Json::string(self.thread_id) }
  if self.include_turns is Some(include_turns) {
    fields["includeTurns"] = Json::boolean(include_turns)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexThreadListPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex thread list payload")
  {
    limit: object.required_int("limit"),
    archived: object.required_bool("archived"),
    cursor: object.optional_string("cursor"),
  }
}

///|
pub impl ToJson for CodexThreadListPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "limit": Json::number(self.limit.to_double()),
    "archived": Json::boolean(self.archived),
  }
  if self.cursor is Some(cursor) {
    fields["cursor"] = Json::string(cursor)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexThreadArchivePayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(
    json, path, "Codex thread archive payload",
  )
  {
    thread_id: object.required_string("threadId"),
    force: object.required_bool("force"),
  }
}

///|
pub impl ToJson for CodexThreadArchivePayload with fn to_json(self) {
  {
    "threadId": Json::string(self.thread_id),
    "force": Json::boolean(self.force),
  }
}

///|
pub impl FromJson for CodexReviewTarget with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex review target")
  { kind_: object.required_string("type") }
}

///|
pub impl ToJson for CodexReviewTarget with fn to_json(self) {
  { "type": Json::string(self.kind_) }
}

///|
pub impl FromJson for CodexReviewStartPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex review start payload")
  {
    thread_id: object.required_string("threadId"),
    target: @json.from_json(
      object.required_json("target"),
      path=path.add_key("target"),
    ),
  }
}

///|
pub impl ToJson for CodexReviewStartPayload with fn to_json(self) {
  {
    "threadId": Json::string(self.thread_id),
    "target": ToJson::to_json(self.target),
  }
}

///|
pub impl FromJson for CodexTurnStartPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex turn start payload")
  {
    thread_id: object.required_string("threadId"),
    input: object.required_array("input"),
    model: object.optional_string("model"),
    cwd: object.optional_string("cwd"),
  }
}

///|
pub impl ToJson for CodexTurnStartPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "threadId": Json::string(self.thread_id),
    "input": Json::array(self.input),
  }
  if self.model is Some(model) {
    fields["model"] = Json::string(model)
  }
  if self.cwd is Some(cwd) {
    fields["cwd"] = Json::string(cwd)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexTurnSteerPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex turn steer payload")
  {
    thread_id: object.required_string("threadId"),
    input: object.required_array("input"),
    expected_turn_id: object.required_string("expectedTurnId"),
  }
}

///|
pub impl ToJson for CodexTurnSteerPayload with fn to_json(self) {
  {
    "threadId": Json::string(self.thread_id),
    "input": Json::array(self.input),
    "expectedTurnId": Json::string(self.expected_turn_id),
  }
}

///|
pub impl FromJson for CodexTurnInterruptPayload with fn from_json(json, path) {
  let object = CodexJsonObject::decode(
    json, path, "Codex turn interrupt payload",
  )
  {
    thread_id: object.required_string("threadId"),
    turn_id: object.required_string("turnId"),
  }
}

///|
pub impl ToJson for CodexTurnInterruptPayload with fn to_json(self) {
  {
    "threadId": Json::string(self.thread_id),
    "turnId": Json::string(self.turn_id),
  }
}

///|
pub impl FromJson for CodexStatusReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex status reply")
  {
    status: object.required_string("status"),
    message: object.optional_string("message"),
  }
}

///|
pub impl ToJson for CodexStatusReply with fn to_json(self) {
  let fields : Map[String, Json] = { "status": Json::string(self.status) }
  if self.message is Some(message) {
    fields["message"] = Json::string(message)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexDraftOpenReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex draft open reply")
  {
    draft_id: object.required_string("draftId"),
    cwd: object.required_string("cwd"),
    project_root: object.required_string("projectRoot"),
  }
}

///|
pub impl ToJson for CodexDraftOpenReply with fn to_json(self) {
  {
    "draftId": Json::string(self.draft_id),
    "cwd": Json::string(self.cwd),
    "projectRoot": Json::string(self.project_root),
  }
}

///|
pub impl FromJson for CodexDataReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex data reply")
  {
    data: object.required_array("data"),
    next_cursor: object.optional_string("nextCursor"),
  }
}

///|
pub impl ToJson for CodexDataReply with fn to_json(self) {
  let fields : Map[String, Json] = { "data": Json::array(self.data) }
  if self.next_cursor is Some(next_cursor) {
    fields["nextCursor"] = Json::string(next_cursor)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexServerRequestsReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(
    json, path, "Codex server requests reply",
  )
  {
    data: object.required_array("data"),
    generation: object.required_int("generation"),
  }
}

///|
pub impl ToJson for CodexServerRequestsReply with fn to_json(self) {
  { "data": Json::array(self.data), "generation": self.generation }
}

///|
pub impl FromJson for CodexAccountReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex account reply")
  {
    account: object.optional_json("account"),
    requires_openai_auth: object.required_bool("requiresOpenaiAuth"),
  }
}

///|
pub impl ToJson for CodexAccountReply with fn to_json(self) {
  let fields : Map[String, Json] = {
    "requiresOpenaiAuth": Json::boolean(self.requires_openai_auth),
  }
  if self.account is Some(account) {
    fields["account"] = account
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexLoginStartReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex login start reply")
  {
    login_id: object.required_string("loginId"),
    auth_url: object.required_string("authUrl"),
  }
}

///|
pub impl ToJson for CodexLoginStartReply with fn to_json(self) {
  {
    "loginId": Json::string(self.login_id),
    "authUrl": Json::string(self.auth_url),
  }
}

///|
pub impl FromJson for CodexThreadReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex thread reply")
  { thread: object.required_json("thread") }
}

///|
pub impl ToJson for CodexThreadReply with fn to_json(self) {
  { "thread": self.thread }
}

///|
pub impl FromJson for CodexThreadResumeReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex thread resume reply")
  {
    thread: object.optional_json("thread"),
    status: object.optional_string("status"),
  }
}

///|
pub impl ToJson for CodexThreadResumeReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.thread is Some(thread) {
    fields["thread"] = thread
  }
  if self.status is Some(status) {
    fields["status"] = Json::string(status)
  }
  Json::object(fields)
}

///|
pub impl FromJson for CodexTurnReply with fn from_json(json, path) {
  let object = CodexJsonObject::decode(json, path, "Codex turn reply")
  {
    turn: object.optional_json("turn"),
    turn_id: object.optional_string("turnId"),
  }
}

///|
pub impl ToJson for CodexTurnReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.turn is Some(turn) {
    fields["turn"] = turn
  }
  if self.turn_id is Some(turn_id) {
    fields["turnId"] = Json::string(turn_id)
  }
  Json::object(fields)
}

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

///|
pub extend CodexAccountLoginCancelPayload with Debug::{to_repr}

///|
pub extend CodexAccountLoginCancelPayload with FromJson::{from_json}

///|
pub extend CodexAccountLoginCancelPayload with Eq::{equal, not_equal}

///|
pub extend CodexAccountLoginCancelPayload with ToJson::{to_json}

///|
pub extend CodexAccountLoginStartPayload with Debug::{to_repr}

///|
pub extend CodexAccountLoginStartPayload with FromJson::{from_json}

///|
pub extend CodexAccountLoginStartPayload with Eq::{equal, not_equal}

///|
pub extend CodexAccountLoginStartPayload with ToJson::{to_json}

///|
pub extend CodexAccountReadPayload with Debug::{to_repr}

///|
pub extend CodexAccountReadPayload with FromJson::{from_json}

///|
pub extend CodexAccountReadPayload with Eq::{equal, not_equal}

///|
pub extend CodexAccountReadPayload with ToJson::{to_json}

///|
pub extend CodexAccountReply with Debug::{to_repr}

///|
pub extend CodexAccountReply with FromJson::{from_json}

///|
pub extend CodexAccountReply with Eq::{equal, not_equal}

///|
pub extend CodexAccountReply with ToJson::{to_json}

///|
pub extend CodexArchiveReply with FromJson::{from_json}

///|
pub extend CodexArchiveReply with ToJson::{to_json}

///|
pub extend CodexDataReply with Debug::{to_repr}

///|
pub extend CodexDataReply with FromJson::{from_json}

///|
pub extend CodexDataReply with Eq::{equal, not_equal}

///|
pub extend CodexDataReply with ToJson::{to_json}

///|
pub extend CodexDraftClosePayload with Debug::{to_repr}

///|
pub extend CodexDraftClosePayload with FromJson::{from_json}

///|
pub extend CodexDraftClosePayload with Eq::{equal, not_equal}

///|
pub extend CodexDraftClosePayload with ToJson::{to_json}

///|
pub extend CodexDraftOpenPayload with Debug::{to_repr}

///|
pub extend CodexDraftOpenPayload with FromJson::{from_json}

///|
pub extend CodexDraftOpenPayload with Eq::{equal, not_equal}

///|
pub extend CodexDraftOpenPayload with ToJson::{to_json}

///|
pub extend CodexDraftOpenReply with Debug::{to_repr}

///|
pub extend CodexDraftOpenReply with FromJson::{from_json}

///|
pub extend CodexDraftOpenReply with Eq::{equal, not_equal}

///|
pub extend CodexDraftOpenReply with ToJson::{to_json}

///|
pub extend CodexFileSearchPayload with Debug::{to_repr}

///|
pub extend CodexFileSearchPayload with FromJson::{from_json}

///|
pub extend CodexFileSearchPayload with Eq::{equal, not_equal}

///|
pub extend CodexFileSearchPayload with ToJson::{to_json}

///|
pub extend CodexFileSearchReply with FromJson::{from_json}

///|
pub extend CodexFileSearchReply with ToJson::{to_json}

///|
pub extend CodexLoginStartReply with Debug::{to_repr}

///|
pub extend CodexLoginStartReply with FromJson::{from_json}

///|
pub extend CodexLoginStartReply with Eq::{equal, not_equal}

///|
pub extend CodexLoginStartReply with ToJson::{to_json}

///|
pub extend CodexModelListPayload with Debug::{to_repr}

///|
pub extend CodexModelListPayload with FromJson::{from_json}

///|
pub extend CodexModelListPayload with Eq::{equal, not_equal}

///|
pub extend CodexModelListPayload with ToJson::{to_json}

///|
pub extend CodexReviewStartPayload with Debug::{to_repr}

///|
pub extend CodexReviewStartPayload with FromJson::{from_json}

///|
pub extend CodexReviewStartPayload with Eq::{equal, not_equal}

///|
pub extend CodexReviewStartPayload with ToJson::{to_json}

///|
pub extend CodexReviewTarget with Debug::{to_repr}

///|
pub extend CodexReviewTarget with FromJson::{from_json}

///|
pub extend CodexReviewTarget with Eq::{equal, not_equal}

///|
pub extend CodexReviewTarget with ToJson::{to_json}

///|
pub extend CodexServerRequestRespondPayload with Debug::{to_repr}

///|
pub extend CodexServerRequestRespondPayload with FromJson::{from_json}

///|
pub extend CodexServerRequestRespondPayload with Eq::{equal, not_equal}

///|
pub extend CodexServerRequestRespondPayload with ToJson::{to_json}

///|
pub extend CodexServerRequestsReply with Debug::{to_repr}

///|
pub extend CodexServerRequestsReply with FromJson::{from_json}

///|
pub extend CodexServerRequestsReply with Eq::{equal, not_equal}

///|
pub extend CodexServerRequestsReply with ToJson::{to_json}

///|
pub extend CodexSkillsListPayload with Debug::{to_repr}

///|
pub extend CodexSkillsListPayload with FromJson::{from_json}

///|
pub extend CodexSkillsListPayload with Eq::{equal, not_equal}

///|
pub extend CodexSkillsListPayload with ToJson::{to_json}

///|
pub extend CodexStatusReply with Debug::{to_repr}

///|
pub extend CodexStatusReply with FromJson::{from_json}

///|
pub extend CodexStatusReply with Eq::{equal, not_equal}

///|
pub extend CodexStatusReply with ToJson::{to_json}

///|
pub extend CodexThreadArchivePayload with Debug::{to_repr}

///|
pub extend CodexThreadArchivePayload with FromJson::{from_json}

///|
pub extend CodexThreadArchivePayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadArchivePayload with ToJson::{to_json}

///|
pub extend CodexThreadListPayload with Debug::{to_repr}

///|
pub extend CodexThreadListPayload with FromJson::{from_json}

///|
pub extend CodexThreadListPayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadListPayload with ToJson::{to_json}

///|
pub extend CodexThreadPayload with Debug::{to_repr}

///|
pub extend CodexThreadPayload with FromJson::{from_json}

///|
pub extend CodexThreadPayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadPayload with ToJson::{to_json}

///|
pub extend CodexThreadReadPayload with Debug::{to_repr}

///|
pub extend CodexThreadReadPayload with FromJson::{from_json}

///|
pub extend CodexThreadReadPayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadReadPayload with ToJson::{to_json}

///|
pub extend CodexThreadReply with Debug::{to_repr}

///|
pub extend CodexThreadReply with FromJson::{from_json}

///|
pub extend CodexThreadReply with Eq::{equal, not_equal}

///|
pub extend CodexThreadReply with ToJson::{to_json}

///|
pub extend CodexThreadResumeReply with Debug::{to_repr}

///|
pub extend CodexThreadResumeReply with FromJson::{from_json}

///|
pub extend CodexThreadResumeReply with Eq::{equal, not_equal}

///|
pub extend CodexThreadResumeReply with ToJson::{to_json}

///|
pub extend CodexThreadStartPayload with Debug::{to_repr}

///|
pub extend CodexThreadStartPayload with FromJson::{from_json}

///|
pub extend CodexThreadStartPayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadStartPayload with ToJson::{to_json}

///|
pub extend CodexTurnInterruptPayload with Debug::{to_repr}

///|
pub extend CodexTurnInterruptPayload with FromJson::{from_json}

///|
pub extend CodexTurnInterruptPayload with Eq::{equal, not_equal}

///|
pub extend CodexTurnInterruptPayload with ToJson::{to_json}

///|
pub extend CodexTurnReply with Debug::{to_repr}

///|
pub extend CodexTurnReply with FromJson::{from_json}

///|
pub extend CodexTurnReply with Eq::{equal, not_equal}

///|
pub extend CodexTurnReply with ToJson::{to_json}

///|
pub extend CodexTurnStartPayload with Debug::{to_repr}

///|
pub extend CodexTurnStartPayload with FromJson::{from_json}

///|
pub extend CodexTurnStartPayload with Eq::{equal, not_equal}

///|
pub extend CodexTurnStartPayload with ToJson::{to_json}

///|
pub extend CodexTurnSteerPayload with Debug::{to_repr}

///|
pub extend CodexTurnSteerPayload with FromJson::{from_json}

///|
pub extend CodexTurnSteerPayload with Eq::{equal, not_equal}

///|
pub extend CodexTurnSteerPayload with ToJson::{to_json}
