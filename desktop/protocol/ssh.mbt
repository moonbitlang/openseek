// Desktop SSH configuration contains no model credentials. Optional identity
// means the profile has not yet completed its first verified initialize.
// Decoders reject malformed fields and ignore unknown fields; optional fields
// accept missing/null and are omitted by the encoder.

///|
pub(all) struct SshProfile {
  id : String
  name : String
  destination : String
  launcher : String
  data_dir : String
  build_id : String
  server_id : String?
} derive(Eq)

///|
pub impl FromJson for SshProfile with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SshProfile")
  {
    id: object.required_string("id"),
    name: object.required_string("name"),
    destination: object.required_string("destination"),
    launcher: object.required_string("launcher"),
    data_dir: object.required_string("data_dir"),
    build_id: object.required_string("build_id"),
    server_id: object.optional_string("server_id"),
  }
}

///|
pub impl ToJson for SshProfile with fn to_json(self) {
  let fields : Map[String, Json] = Map([])

  fields["id"] = Json(self.id)

  fields["name"] = Json(self.name)

  fields["destination"] = Json(self.destination)

  fields["launcher"] = Json(self.launcher)

  fields["data_dir"] = Json(self.data_dir)

  fields["build_id"] = Json(self.build_id)

  if self.server_id is Some(value) {
    fields["server_id"] = Json(value)
  }

  Json(fields)
}

///|
pub extend SshProfile with FromJson::{from_json}

///|
pub extend SshProfile with ToJson::{to_json}

///|
pub(all) struct SshProfileWrite {
  id : String?
  name : String
  destination : String
  launcher : String
  data_dir : String
  build_id : String
}

///|
pub impl FromJson for SshProfileWrite with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SshProfileWrite")
  {
    id: object.optional_string("id"),
    name: object.required_string("name"),
    destination: object.required_string("destination"),
    launcher: object.required_string("launcher"),
    data_dir: object.required_string("data_dir"),
    build_id: object.required_string("build_id"),
  }
}

///|
pub impl ToJson for SshProfileWrite with fn to_json(self) {
  let fields : Map[String, Json] = Map([])

  if self.id is Some(value) {
    fields["id"] = Json(value)
  }

  fields["name"] = Json(self.name)

  fields["destination"] = Json(self.destination)

  fields["launcher"] = Json(self.launcher)

  fields["data_dir"] = Json(self.data_dir)

  fields["build_id"] = Json(self.build_id)

  Json(fields)
}

///|
pub extend SshProfileWrite with FromJson::{from_json}

///|
pub extend SshProfileWrite with ToJson::{to_json}

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
pub extend SshProfile with Eq::{equal, not_equal}
