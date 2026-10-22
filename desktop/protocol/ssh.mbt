///|
pub(all) struct SshProfile {
  id : String
  command : String
  display_name : String?
  projects : Array[String]?
} derive(Eq)

///|
pub impl FromJson for SshProfile with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "SSH profile")
  {
    id: obj.required_string("id"),
    command: obj.required_string("command"),
    display_name: obj.optional_string("display_name"),
    projects: obj
    .optional_json("projects")
    .map(value => @json.from_json(value, path=path.add_key("projects"))),
  }
}

///|
pub impl ToJson for SshProfile with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": Json(self.id),
    "command": Json(self.command),
  }
  if self.display_name is Some(name) {
    fields["display_name"] = Json(name)
  }
  if self.projects is Some(projects) {
    fields["projects"] = Json(projects)
  }
  Json(fields)
}

///|
pub extend SshProfile with Eq::{equal, not_equal}

///|
pub(all) struct SshProjects {
  id : String
  projects : Array[String]
}

///|
pub impl FromJson for SshProjects with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "SSH projects")
  {
    id: obj.required_string("id"),
    projects: obj.required_array_of("projects"),
  }
}

///|
pub impl ToJson for SshProjects with fn to_json(self) {
  { "id": self.id, "projects": Json(self.projects) }
}

///|
pub(all) struct SshProfileTarget {
  id : String
}

///|
pub impl FromJson for SshProfileTarget with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SshProfileTarget")
  { id: object.required_string("id"), }
}

///|
pub impl ToJson for SshProfileTarget with fn to_json(self) {
  let fields : Map[String, Json] = Map([])

  fields["id"] = Json(self.id)

  Json(fields)
}

///|
pub extend SshProfileTarget with FromJson::{from_json}

///|
pub extend SshProfileTarget with ToJson::{to_json}

///|
pub(all) struct SshProfiles {
  hosts : Array[SshProfile]
}

///|
pub impl FromJson for SshProfiles with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SshProfiles")
  { hosts: object.required_array_of("hosts"), }
}

///|
pub impl ToJson for SshProfiles with fn to_json(self) {
  let fields : Map[String, Json] = Map([])

  fields["hosts"] = Json(self.hosts)

  Json(fields)
}

///|
pub extend SshProfiles with FromJson::{from_json}

///|
pub extend SshProfiles with ToJson::{to_json}

///|
pub(all) struct SshRequest {
  host_id : String
  epoch : Int32
  method_ : String
  params : Json
}

///|
pub impl FromJson for SshRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SshRequest")
  {
    host_id: object.required_string("host_id"),
    epoch: object.required_int("epoch"),
    method_: object.required_string("method"),
    params: object.required_json("params"),
  }
}

///|
pub impl ToJson for SshRequest with fn to_json(self) {
  let fields : Map[String, Json] = Map([])

  fields["host_id"] = Json(self.host_id)

  fields["epoch"] = Json(self.epoch)

  fields["method"] = Json(self.method_)

  fields["params"] = self.params

  Json(fields)
}

///|
pub extend SshRequest with FromJson::{from_json}

///|
pub extend SshRequest with ToJson::{to_json}

///|
/// Proton failures may redact errors, so preserve the transport outcome in a
/// typed reply. Only success carries a command-specific JSON result.
pub(all) enum SshReply {
  SshSuccess(Json)
  SshUnsent(String)
  SshRefused(String)
  SshUnknown(String)
}

///|
pub impl ToJson for SshReply with fn to_json(self) {
  match self {
    SshSuccess(value) => { "outcome": "success", "value": value }
    SshUnsent(message) => { "outcome": "unsent", "message": message }
    SshRefused(message) => { "outcome": "refused", "message": message }
    SshUnknown(message) => { "outcome": "unknown", "message": message }
  }
}

///|
pub impl FromJson for SshReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH reply")
  match object.required_string("outcome") {
    "success" => SshSuccess(object.required_json("value"))
    "unsent" => SshUnsent(object.required_string("message"))
    "refused" => SshRefused(object.required_string("message"))
    "unknown" => SshUnknown(object.required_string("message"))
    _ => raise JsonDecodeError((path, "invalid SSH request outcome"))
  }
}

///|
pub extend SshReply with ToJson::{to_json}

///|
pub extend SshReply with FromJson::{from_json}

///|
pub extend SshProfile with FromJson::{from_json}

///|
pub extend SshProfile with ToJson::{to_json}

///|
pub(all) struct SshConnect {
  id : String
  attempt : Int32
}

///|
pub impl FromJson for SshConnect with fn from_json(json, path) {
  let o = JsonObject::decode(json, path, "SSH connection attempt")
  { id: o.required_string("id"), attempt: o.required_int("attempt"), }
}

///|
pub impl ToJson for SshConnect with fn to_json(self) {
  { "id": self.id, "attempt": self.attempt }
}

///|
pub(all) enum SshAuthKind {
  Password
  Passphrase
  Challenge
  Confirm
} derive(Eq)

///|
pub impl ToJson for SshAuthKind with fn to_json(self) {
  Json(
    match self {
      Password => "password"
      Passphrase => "passphrase"
      Challenge => "challenge"
      Confirm => "confirm"
    },
  )
}

///|
pub impl FromJson for SshAuthKind with fn from_json(json, path) {
  match json {
    "password" => Password
    "passphrase" => Passphrase
    "challenge" => Challenge
    "confirm" => Confirm
    _ => raise JsonDecodeError((path, "invalid SSH authentication kind"))
  }
}

///|
pub(all) struct SshAuthRequest {
  request_id : Int32
  kind : SshAuthKind
  prompt : String
  target : String?
  retry : Bool
} derive(Eq)

///|
pub impl FromJson for SshAuthRequest with fn from_json(json, path) {
  let o = JsonObject::decode(json, path, "SSH authentication request")
  {
    request_id: o.required_int("request_id"),
    kind: @json.from_json(o.required_json("kind"), path=path.add_key("kind")),
    prompt: o.required_string("prompt"),
    target: o.optional_string("target"),
    retry: o.required_bool("retry"),
  }
}

///|
pub impl ToJson for SshAuthRequest with fn to_json(self) {
  let fields : Map[String, Json] = {
    "request_id": Json(self.request_id),
    "kind": self.kind.to_json(),
    "prompt": Json(self.prompt),
    "retry": Json(self.retry),
  }
  if self.target is Some(target) {
    fields["target"] = Json(target)
  }
  Json(fields)
}

///|
pub(all) enum SshAuthAnswer {
  Value(String)
  Accept
  Cancel
}

///|
pub impl FromJson for SshAuthAnswer with fn from_json(json, path) {
  let o = JsonObject::decode(json, path, "SSH authentication answer")
  match o.required_string("action") {
    "value" => Value(o.required_string("value"))
    "accept" => Accept
    "cancel" => Cancel
    _ => raise JsonDecodeError((path, "invalid SSH authentication action"))
  }
}

///|
pub impl ToJson for SshAuthAnswer with fn to_json(self) {
  match self {
    Value(value) => { "action": "value", "value": value }
    Accept => { "action": "accept" }
    Cancel => { "action": "cancel" }
  }
}

///|
pub(all) struct SshAuthResponse {
  host_id : String
  attempt : Int32
  epoch : Int32
  request_id : Int32
  answer : SshAuthAnswer
}

///|
pub impl FromJson for SshAuthResponse with fn from_json(json, path) {
  let o = JsonObject::decode(json, path, "SSH authentication response")
  {
    host_id: o.required_string("host_id"),
    attempt: o.required_int("attempt"),
    epoch: o.required_int("epoch"),
    request_id: o.required_int("request_id"),
    answer: @json.from_json(
      o.required_json("answer"),
      path=path.add_key("answer"),
    ),
  }
}

///|
pub impl ToJson for SshAuthResponse with fn to_json(self) {
  {
    "host_id": self.host_id,
    "attempt": self.attempt,
    "epoch": self.epoch,
    "request_id": self.request_id,
    "answer": self.answer.to_json(),
  }
}

///|
pub extend SshConnect with ToJson::{to_json}

///|
pub extend SshConnect with FromJson::{from_json}

///|
pub extend SshAuthKind with ToJson::{to_json}

///|
pub extend SshAuthKind with FromJson::{from_json}

///|
pub extend SshAuthRequest with ToJson::{to_json}

///|
pub extend SshAuthRequest with FromJson::{from_json}

///|
pub extend SshAuthAnswer with ToJson::{to_json}

///|
pub extend SshAuthAnswer with FromJson::{from_json}

///|
pub extend SshAuthResponse with ToJson::{to_json}

///|
pub extend SshAuthResponse with FromJson::{from_json}

///|
pub extend SshAuthKind with Eq::{equal, not_equal}

///|
pub extend SshAuthRequest with Eq::{equal, not_equal}

///|
pub(all) struct SshEvent {
  host_id : String
  attempt : Int32
  epoch : Int32
  event : Json
}

///|
pub impl FromJson for SshEvent with fn from_json(json, path) {
  let o = JsonObject::decode(json, path, "SSH event")
  {
    host_id: o.required_string("host_id"),
    attempt: o.required_int("attempt"),
    epoch: o.required_int("epoch"),
    event: o.required_json("event"),
  }
}

///|
pub impl ToJson for SshEvent with fn to_json(self) {
  {
    "host_id": self.host_id,
    "attempt": self.attempt,
    "epoch": self.epoch,
    "event": self.event,
  }
}

///|
pub extend SshEvent with FromJson::{from_json}

///|
pub extend SshEvent with ToJson::{to_json}

///|
pub extend SshProjects with FromJson::{from_json}

///|
pub extend SshProjects with ToJson::{to_json}
