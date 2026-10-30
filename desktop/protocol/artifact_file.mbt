///|
/// A file reference is scoped by its owning conversation and registered
/// workspace. The host resolves its relative artifact path.
pub(all) struct ArtifactFilePayload {
  session : String
  workspace : String
  archived : Bool
  reference : String
} derive(Debug, Eq)

///|
pub(all) struct ArtifactFileReply {
  path : String
  content : String?
} derive(Debug, Eq)

///|
pub impl FromJson for ArtifactFilePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "artifact file request")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    archived: object.required_bool("archived"),
    reference: object.required_string("reference"),
  }
}

///|
pub impl ToJson for ArtifactFilePayload with fn to_json(self) {
  {
    "session": self.session,
    "workspace": self.workspace,
    "archived": self.archived,
    "reference": self.reference,
  }
}

///|
pub impl FromJson for ArtifactFileReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "artifact file reply")
  {
    path: object.required_string("path"),
    content: object.optional_string("content"),
  }
}

///|
pub impl ToJson for ArtifactFileReply with fn to_json(self) {
  {
    "path": self.path,
    "content": match self.content {
      Some(content) => Json(content)
      None => null
    },
  }
}

///|
pub extend ArtifactFilePayload with Debug::{to_repr}

///|
pub extend ArtifactFilePayload with Eq::{equal, not_equal}

///|
pub extend ArtifactFilePayload with FromJson::{from_json}

///|
pub extend ArtifactFilePayload with ToJson::{to_json}

///|
pub extend ArtifactFileReply with Debug::{to_repr}

///|
pub extend ArtifactFileReply with Eq::{equal, not_equal}

///|
pub extend ArtifactFileReply with FromJson::{from_json}

///|
pub extend ArtifactFileReply with ToJson::{to_json}
