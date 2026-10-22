// User-activated session suggestions. The source session owns this durable state.

///|
pub(all) struct SessionStartRequest {
  request_id : String
  title : String
  task : String
  workspace : String
  model : String?
  thinking : OpenSeekThinking?
  max_steps : Int32?
  workspace_mode : String
} derive(Debug, Eq)

///|
pub(all) struct SessionStartProposal {
  id : String
  request_id : String
  title : String
  task : String
  workspace : String
  model : String?
  thinking : OpenSeekThinking?
  max_steps : Int32?
  workspace_mode : String
  status : String
  target_session : String?
  error : String?
} derive(Debug, Eq)

///|
pub(all) struct SessionStartsSnapshot {
  session : String
  generation : Int32
  proposals : Array[SessionStartProposal]
} derive(Debug, Eq)

///|
pub(all) struct SessionStartsListPayload {
  session : String
} derive(Debug, Eq)

///|
pub(all) struct SessionStartHereOptions {
  model : String?
  thinking : OpenSeekThinking?
  approval : OpenSeekApproval?
  max_steps : Int32?
  followup_behavior : String
} derive(Debug, Eq)

///|
pub(all) struct SessionStartDecision {
  session : String
  request_id : String
  action : String
  // Missing keeps the suggested model; null explicitly selects project defaults.
  model : String??
  workspace_mode : String?
  here : SessionStartHereOptions?
} derive(Debug, Eq)

///|
fn start_nonblank(
  object : JsonObject,
  name : String,
) -> String raise @json.JsonDecodeError {
  let value = object.required_string(name)
  guard !value.is_blank() else {
    raise JsonDecodeError((object.path.add_key(name), "must not be blank"))
  }
  value
}

///|
pub impl FromJson for SessionStartRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session start request")
  let workspace_mode = object
    .optional_string("workspace_mode")
    .unwrap_or("local")
  guard workspace_mode == "local" || workspace_mode == "worktree" else {
    raise JsonDecodeError(
      (path.add_key("workspace_mode"), "expected local or worktree"),
    )
  }
  let model = object.optional_string("model")
  guard !model.map_or(false, value => value.is_blank()) else {
    raise JsonDecodeError((path.add_key("model"), "must not be blank"))
  }
  let max_steps = object.optional_int("max_steps")
  guard !max_steps.map_or(false, value => value <= 0) else {
    raise JsonDecodeError((path.add_key("max_steps"), "must be positive"))
  }
  {
    request_id: start_nonblank(object, "request_id"),
    title: start_nonblank(object, "title"),
    task: start_nonblank(object, "task"),
    workspace: start_nonblank(object, "workspace"),
    model,
    thinking: object
    .optional_json("thinking")
    .map(value => @json.from_json(value, path=path.add_key("thinking"))),
    max_steps,
    workspace_mode,
  }
}

///|
pub impl ToJson for SessionStartRequest with fn to_json(self) {
  let fields : Map[String, Json] = {
    "request_id": Json(self.request_id),
    "title": Json(self.title),
    "task": Json(self.task),
    "workspace": Json(self.workspace),
    "workspace_mode": Json(self.workspace_mode),
  }
  if self.model is Some(value) {
    fields["model"] = Json(value)
  }
  if self.thinking is Some(value) {
    fields["thinking"] = value.to_json()
  }
  if self.max_steps is Some(value) {
    fields["max_steps"] = Json(value)
  }
  Json(fields)
}

///|
pub fn SessionStartProposal::request(
  self : SessionStartProposal,
) -> SessionStartRequest {
  {
    request_id: self.request_id,
    title: self.title,
    task: self.task,
    workspace: self.workspace,
    model: self.model,
    thinking: self.thinking,
    max_steps: self.max_steps,
    workspace_mode: self.workspace_mode,
  }
}

///|
pub fn SessionStartRequest::proposal(
  self : SessionStartRequest,
  id : String,
) -> SessionStartProposal {
  {
    id,
    request_id: self.request_id,
    title: self.title,
    task: self.task,
    workspace: self.workspace,
    model: self.model,
    thinking: self.thinking,
    max_steps: self.max_steps,
    workspace_mode: self.workspace_mode,
    status: "pending",
    target_session: None,
    error: None,
  }
}

///|
pub impl FromJson for SessionStartProposal with fn from_json(json, path) {
  let request : SessionStartRequest = @json.from_json(json, path~)
  let object = JsonObject::decode(json, path, "session start proposal")
  let status = object.required_string("status")
  let target_session = object.optional_string("target_session")
  let error = object.optional_string("error")
  guard ["pending", "starting", "started", "here", "dismissed", "failed"].contains(
    status,
  ) else {
    raise JsonDecodeError(
      (path.add_key("status"), "unknown session start status"),
    )
  }
  guard !target_session.map_or(false, value => value.is_blank()) &&
    !error.map_or(false, value => value.is_blank()) else {
    raise JsonDecodeError((path, "target session and error must not be blank"))
  }
  guard (status != "started" && status != "starting" && status != "here") ||
    target_session is Some(_) else {
    raise JsonDecodeError(
      (path.add_key("target_session"), "required for an accepted session start"),
    )
  }
  guard status != "failed" || error is Some(_) else {
    raise JsonDecodeError(
      (path.add_key("error"), "required for a failed session start"),
    )
  }
  guard status != "pending" || target_session is None else {
    raise JsonDecodeError(
      (path.add_key("target_session"), "pending suggestions have no target"),
    )
  }
  guard status == "failed" || error is None else {
    raise JsonDecodeError((path.add_key("error"), "unexpected error"))
  }
  {
    ..request.proposal(start_nonblank(object, "id")),
    status,
    target_session,
    error,
  }
}

///|
pub impl ToJson for SessionStartProposal with fn to_json(self) {
  let fields = match self.request().to_json() {
    Object(fields) => fields
    _ => Map([])
  }
  fields["id"] = Json(self.id)
  fields["status"] = Json(self.status)
  if self.target_session is Some(value) {
    fields["target_session"] = Json(value)
  }
  if self.error is Some(value) {
    fields["error"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for SessionStartsSnapshot with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session starts snapshot")
  let generation = object.required_int("generation")
  guard generation >= 0 else {
    raise JsonDecodeError((path.add_key("generation"), "must not be negative"))
  }
  let proposals : Array[SessionStartProposal] = object.required_array_of(
    "proposals",
  )
  let seen : Set[String] = Set([])
  let seen_ids : Set[String] = Set([])
  let session = start_nonblank(object, "session")
  for proposal in proposals {
    guard !seen.contains(proposal.request_id) else {
      raise JsonDecodeError((path, "duplicate proposal request id"))
    }
    seen.add(proposal.request_id)
    guard !seen_ids.contains(proposal.id) else {
      raise JsonDecodeError((path, "duplicate proposal identity"))
    }
    seen_ids.add(proposal.id)
    guard proposal.status != "here" || proposal.target_session == Some(session) else {
      raise JsonDecodeError((path, "Work here must target the source session"))
    }
    guard proposal.status != "started" ||
      proposal.target_session != Some(session) else {
      raise JsonDecodeError(
        (path, "a new session must have a different target"),
      )
    }
  }
  { session, generation, proposals, }
}

///|
pub impl ToJson for SessionStartsSnapshot with fn to_json(self) {
  {
    "session": self.session,
    "generation": self.generation,
    "proposals": Json(self.proposals),
  }
}

///|
pub impl FromJson for SessionStartsListPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session starts list payload")
  { session: start_nonblank(object, "session"), }
}

///|
pub impl ToJson for SessionStartsListPayload with fn to_json(self) {
  { "session": self.session }
}

///|
pub impl FromJson for SessionStartDecision with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session start decision")
  let action = object.required_string("action")
  guard ["start", "here", "dismiss"].contains(action) else {
    raise JsonDecodeError(
      (path.add_key("action"), "expected start, here or dismiss"),
    )
  }
  let model : String?? = if object.fields.contains("model") {
    Some(object.optional_string("model"))
  } else {
    None
  }
  guard !model.bind(value => value).map_or(false, value => value.is_blank()) else {
    raise JsonDecodeError((path.add_key("model"), "must not be blank"))
  }
  let workspace_mode = object.optional_string("workspace_mode")
  guard !workspace_mode.map_or(false, value => {
    value != "local" && value != "worktree"
  }) else {
    raise JsonDecodeError(
      (path.add_key("workspace_mode"), "expected local or worktree"),
    )
  }
  {
    session: start_nonblank(object, "session"),
    request_id: start_nonblank(object, "request_id"),
    action,
    model,
    workspace_mode,
    here: object
    .optional_json("here")
    .map(value => @json.from_json(value, path=path.add_key("here"))),
  }
}

///|
pub impl ToJson for SessionStartDecision with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": Json(self.session),
    "request_id": Json(self.request_id),
    "action": Json(self.action),
  }
  if self.model is Some(value) {
    fields["model"] = value.map_or(null, value => Json(value))
  }
  if self.workspace_mode is Some(value) {
    fields["workspace_mode"] = Json(value)
  }
  if self.here is Some(value) {
    fields["here"] = value.to_json()
  }
  Json(fields)
}

///|
pub extend SessionStartRequest with Debug::{to_repr}

///|
pub extend SessionStartRequest with Eq::{equal, not_equal}

///|
pub extend SessionStartRequest with ToJson::{to_json}

///|
pub extend SessionStartRequest with FromJson::{from_json}

///|
pub extend SessionStartProposal with Debug::{to_repr}

///|
pub extend SessionStartProposal with Eq::{equal, not_equal}

///|
pub extend SessionStartProposal with ToJson::{to_json}

///|
pub extend SessionStartProposal with FromJson::{from_json}

///|
pub extend SessionStartsSnapshot with Debug::{to_repr}

///|
pub extend SessionStartsSnapshot with Eq::{equal, not_equal}

///|
pub extend SessionStartsSnapshot with ToJson::{to_json}

///|
pub extend SessionStartsSnapshot with FromJson::{from_json}

///|
pub extend SessionStartsListPayload with Debug::{to_repr}

///|
pub extend SessionStartsListPayload with Eq::{equal, not_equal}

///|
pub extend SessionStartsListPayload with ToJson::{to_json}

///|
pub extend SessionStartsListPayload with FromJson::{from_json}

///|
pub extend SessionStartDecision with Debug::{to_repr}

///|
pub extend SessionStartDecision with Eq::{equal, not_equal}

///|
pub extend SessionStartDecision with ToJson::{to_json}

///|
pub extend SessionStartDecision with FromJson::{from_json}

///|
pub impl FromJson for SessionStartHereOptions with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "current-session input options")
  let followup_behavior = object.required_string("followup_behavior")
  guard followup_behavior == "steer" || followup_behavior == "queue" else {
    raise JsonDecodeError(
      (path.add_key("followup_behavior"), "expected steer or queue"),
    )
  }
  let model = object.optional_string("model")
  guard !model.map_or(false, value => value.is_blank()) else {
    raise JsonDecodeError((path.add_key("model"), "must not be blank"))
  }
  let max_steps = object.optional_int("max_steps")
  guard !max_steps.map_or(false, value => value <= 0) else {
    raise JsonDecodeError((path.add_key("max_steps"), "must be positive"))
  }
  {
    model,
    max_steps,
    followup_behavior,
    thinking: object
    .optional_json("thinking")
    .map(value => @json.from_json(value, path=path.add_key("thinking"))),
    approval: object
    .optional_json("approval")
    .map(value => @json.from_json(value, path=path.add_key("approval"))),
  }
}

///|
pub impl ToJson for SessionStartHereOptions with fn to_json(self) {
  let fields : Map[String, Json] = {
    "followup_behavior": Json(self.followup_behavior),
  }
  if self.model is Some(value) {
    fields["model"] = Json(value)
  }
  if self.thinking is Some(value) {
    fields["thinking"] = value.to_json()
  }
  if self.approval is Some(value) {
    fields["approval"] = value.to_json()
  }
  if self.max_steps is Some(value) {
    fields["max_steps"] = Json(value)
  }
  Json(fields)
}

///|
pub extend SessionStartHereOptions with Debug::{to_repr}

///|
pub extend SessionStartHereOptions with Eq::{equal, not_equal}

///|
pub extend SessionStartHereOptions with FromJson::{from_json}

///|
pub extend SessionStartHereOptions with ToJson::{to_json}
