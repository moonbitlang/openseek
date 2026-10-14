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
} derive(Debug, Eq)

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
