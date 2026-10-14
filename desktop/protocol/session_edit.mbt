///|
pub(all) struct SessionEditPreparePayload {
  session : String
  workspace : String
  through : Int32?
  model : String
  source_title : String
} derive(Debug, Eq)

///|
pub(all) struct SessionEditCommitPayload {
  session : String
  workspace : String
  replacement : String
  submission_id : String
  source_sequence : Int32
  source_descendants : Array[SessionEditDescendant]
} derive(Debug, Eq)

///|
pub(all) struct SessionEditDescendant {
  session : String
  sequence : Int32
} derive(Debug, Eq)

///|
pub(all) struct SessionEditPrepareReply {
  session : String
  title : String
  source_descendants : Array[SessionEditDescendant]
} derive(Debug, Eq)

///|
pub impl FromJson for SessionEditDescendant with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "edit descendant baseline")
  {
    session: object.required_string("session"),
    sequence: object.required_int("sequence"),
  }
}

///|
pub impl ToJson for SessionEditDescendant with fn to_json(self) {
  { "session": self.session, "sequence": self.sequence }
}

///|
pub impl FromJson for SessionEditPrepareReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session edit preparation reply")
  {
    session: object.required_string("session"),
    title: object.required_string("title"),
    source_descendants: @json.from_json(
      object.required_json("source_descendants"),
      path=path.add_key("source_descendants"),
    ),
  }
}

///|
pub impl ToJson for SessionEditPrepareReply with fn to_json(self) {
  {
    "session": self.session,
    "title": self.title,
    "source_descendants": Json(self.source_descendants),
  }
}

///|
pub impl FromJson for SessionEditPreparePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session edit preparation")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    through: match object.optional_json("through") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("through")))
    },
    model: object.required_string("model"),
    source_title: object.required_string("source_title"),
  }
}

///|
pub impl ToJson for SessionEditPreparePayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": Json(self.session),
    "workspace": Json(self.workspace),
    "model": Json(self.model),
    "source_title": Json(self.source_title),
  }
  if self.through is Some(through) {
    fields["through"] = Json(through)
  }
  Json(fields)
}

///|
pub impl FromJson for SessionEditCommitPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session edit commit")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    replacement: object.required_string("replacement"),
    submission_id: object.required_string("submission_id"),
    source_sequence: object.required_int("source_sequence"),
    source_descendants: @json.from_json(
      object.required_json("source_descendants"),
      path=path.add_key("source_descendants"),
    ),
  }
}

///|
pub impl ToJson for SessionEditCommitPayload with fn to_json(self) {
  {
    "session": self.session,
    "workspace": self.workspace,
    "replacement": self.replacement,
    "submission_id": self.submission_id,
    "source_sequence": self.source_sequence,
    "source_descendants": Json(self.source_descendants),
  }
}

///|
pub extend SessionEditPreparePayload with Debug::{to_repr}

///|
pub extend SessionEditPreparePayload with Eq::{equal, not_equal}

///|
pub extend SessionEditPreparePayload with FromJson::{from_json}

///|
pub extend SessionEditPreparePayload with ToJson::{to_json}

///|
pub extend SessionEditCommitPayload with Debug::{to_repr}

///|
pub extend SessionEditCommitPayload with Eq::{equal, not_equal}

///|
pub extend SessionEditCommitPayload with FromJson::{from_json}

///|
pub extend SessionEditCommitPayload with ToJson::{to_json}

///|
pub extend SessionEditDescendant with Debug::{to_repr}

///|
pub extend SessionEditDescendant with Eq::{equal, not_equal}

///|
pub extend SessionEditDescendant with FromJson::{from_json}

///|
pub extend SessionEditDescendant with ToJson::{to_json}

///|
pub extend SessionEditPrepareReply with Debug::{to_repr}

///|
pub extend SessionEditPrepareReply with Eq::{equal, not_equal}

///|
pub extend SessionEditPrepareReply with FromJson::{from_json}

///|
pub extend SessionEditPrepareReply with ToJson::{to_json}
