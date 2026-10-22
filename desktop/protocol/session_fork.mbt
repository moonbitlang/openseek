///|
pub(all) struct SessionForkPayload {
  session : String
  workspace : String
  through : Int32
  model : String
  source_title : String
  // Fork as a side chat of `session` (see `side_chat_id`) rather than as a
  // conversation of its own. Absent on the wire means an ordinary fork.
  side_chat : Bool?
} derive(Debug, Eq)

///|
pub(all) struct SessionForkReply {
  session : String
  title : String
} derive(Debug, Eq)

///|
pub impl FromJson for SessionForkPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session fork payload")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    through: object.required_int("through"),
    model: object.required_string("model"),
    source_title: object.required_string("source_title"),
    side_chat: object.optional_bool("side_chat"),
  }
}

///|
pub impl ToJson for SessionForkPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": Json(self.session),
    "workspace": Json(self.workspace),
    "through": Json(self.through),
    "model": Json(self.model),
    "source_title": Json(self.source_title),
  }
  if self.side_chat is Some(value) {
    fields["side_chat"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for SessionForkReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session fork reply")
  {
    session: object.required_string("session"),
    title: object.required_string("title"),
  }
}

///|
pub impl ToJson for SessionForkReply with fn to_json(self) {
  { "session": self.session, "title": self.title }
}

///|
pub extend SessionForkPayload with Debug::{to_repr}

///|
pub extend SessionForkPayload with Eq::{equal, not_equal}

///|
pub extend SessionForkPayload with FromJson::{from_json}

///|
pub extend SessionForkPayload with ToJson::{to_json}

///|
pub extend SessionForkReply with Debug::{to_repr}

///|
pub extend SessionForkReply with Eq::{equal, not_equal}

///|
pub extend SessionForkReply with FromJson::{from_json}

///|
pub extend SessionForkReply with ToJson::{to_json}
