///|
/// One edit request; the host owns fork/new, submission, and source deletion.
pub(all) struct SessionEditPayload {
  session : String
  workspace : String
  through : Int32?
  model : String
  source_title : String
  source_sequence : Int32
  task : String
  images : Array[String]
  attachment_paths : Array[String]
  thinking : OpenSeekThinking?
  // Who answers the engine's permission questions; absent means ask.
  approval : OpenSeekApproval?
  max_steps : Int32?
} derive(Debug, Eq)

///|
pub impl FromJson for SessionEditPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session edit")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    through: object
    .optional_json("through")
    .map(value => @json.from_json(value, path=path.add_key("through"))),
    model: object.required_string("model"),
    source_title: object.required_string("source_title"),
    source_sequence: object.required_int("source_sequence"),
    task: object.required_string("task"),
    images: @json.from_json(
      object.required_json("images"),
      path=path.add_key("images"),
    ),
    attachment_paths: @json.from_json(
      object.required_json("attachment_paths"),
      path=path.add_key("attachment_paths"),
    ),
    thinking: object
    .optional_json("thinking")
    .map(value => @json.from_json(value, path=path.add_key("thinking"))),
    approval: object
    .optional_json("approval")
    .map(value => @json.from_json(value, path=path.add_key("approval"))),
    max_steps: object
    .optional_json("max_steps")
    .map(value => @json.from_json(value, path=path.add_key("max_steps"))),
  }
}

///|
pub impl ToJson for SessionEditPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": Json(self.session),
    "workspace": Json(self.workspace),
    "model": Json(self.model),
    "source_title": Json(self.source_title),
    "source_sequence": Json(self.source_sequence),
    "task": Json(self.task),
    "images": Json(self.images),
    "attachment_paths": Json(self.attachment_paths),
  }
  if self.through is Some(value) {
    fields["through"] = Json(value)
  }
  if self.thinking is Some(value) {
    fields["thinking"] = Json(value)
  }
  if self.approval is Some(value) {
    fields["approval"] = Json(value)
  }
  if self.max_steps is Some(value) {
    fields["max_steps"] = Json(value)
  }
  Json(fields)
}

///|
pub extend SessionEditPayload with Debug::{to_repr}

///|
pub extend SessionEditPayload with Eq::{equal, not_equal}

///|
pub extend SessionEditPayload with FromJson::{from_json}

///|
pub extend SessionEditPayload with ToJson::{to_json}
