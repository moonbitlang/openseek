///|
pub(all) enum SessionArtifactType {
  PullRequest
  Branch
} derive(Eq, Debug)

///|
pub impl FromJson for SessionArtifactType with fn from_json(json, path) {
  match json {
    String("pull_request") => PullRequest
    String("branch") => Branch
    _ => raise JsonDecodeError((path, "expected pull_request or branch"))
  }
}

///|
pub impl ToJson for SessionArtifactType with fn to_json(self) {
  Json::string(
    match self {
      PullRequest => "pull_request"
      Branch => "branch"
    },
  )
}

///|
/// The declared type and normalized URL identify a session artifact.
/// Display metadata is fetched separately and never changes that identity.
pub struct SessionArtifact {
  type_ : SessionArtifactType
  url : String
} derive(Eq, Debug)

///|
pub impl FromJson for SessionArtifact with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session artifact")
  guard object.fields.length() == 2 else {
    raise JsonDecodeError((path, "an artifact contains only type and url"))
  }
  {
    type_: @json.from_json(
      object.required_json("type"),
      path=path.add_key("type"),
    ),
    url: normalize_pr_url(object.required_string("url"), path),
  }
}

///|
pub impl ToJson for SessionArtifact with fn to_json(self) {
  { "type": self.type_.to_json(), "url": self.url }
}

///|
/// Stored/listed artifacts in insertion order, deduplicated by (type, URL).
/// This snapshot is not a replacement mutation exposed to agents.
pub struct SessionArtifacts {
  artifacts : Array[SessionArtifact]
} derive(Eq, Debug)

///|
pub impl FromJson for SessionArtifacts with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session artifacts")
  let entries : Array[SessionArtifact] = @json.from_json(
    object.required_json("artifacts"),
    path=path.add_key("artifacts"),
  )
  let artifacts : Array[SessionArtifact] = []
  for entry in entries {
    if !artifacts.contains(entry) {
      artifacts.push(entry)
    }
  }
  { artifacts, }
}

///|
pub impl ToJson for SessionArtifacts with fn to_json(self) {
  { "artifacts": Json(self.artifacts) }
}

///|
pub fn SessionArtifacts::empty() -> SessionArtifacts {
  { artifacts: [], }
}

///|
pub fn SessionArtifacts::attach(
  self : SessionArtifacts,
  artifact : SessionArtifact,
) -> SessionArtifacts {
  if self.artifacts.contains(artifact) {
    return self
  }
  { artifacts: self.artifacts + [artifact], }
}

///|
pub fn SessionArtifacts::without(
  self : SessionArtifacts,
  artifact : SessionArtifact,
) -> SessionArtifacts {
  { artifacts: self.artifacts.filter(item => item != artifact), }
}

///|
/// UI-only removal uses the exact artifact identity against the latest list.
pub(all) struct SessionArtifactRemovePayload {
  session : String
  artifact : SessionArtifact
} derive(Eq, Debug)

///|
pub impl FromJson for SessionArtifactRemovePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session artifact removal")
  {
    session: object.required_string("session"),
    artifact: @json.from_json(
      object.required_json("artifact"),
      path=path.add_key("artifact"),
    ),
  }
}

///|
pub impl ToJson for SessionArtifactRemovePayload with fn to_json(self) {
  { "session": self.session, "artifact": self.artifact.to_json() }
}

///|
pub(all) struct SessionArtifactsChangedPayload {
  session : String
} derive(Eq, Debug)

///|
pub impl FromJson for SessionArtifactsChangedPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "session artifacts identity")
  { session: object.required_string("session"), }
}

///|
pub impl ToJson for SessionArtifactsChangedPayload with fn to_json(self) {
  { "session": self.session }
}

///|
pub extend SessionArtifactType with Eq::{equal, not_equal}

///|
pub extend SessionArtifactType with Debug::{to_repr}

///|
pub extend SessionArtifactType with ToJson::{to_json}

///|
pub extend SessionArtifactType with FromJson::{from_json}

///|
pub extend SessionArtifact with Eq::{equal, not_equal}

///|
pub extend SessionArtifact with Debug::{to_repr}

///|
pub extend SessionArtifact with ToJson::{to_json}

///|
pub extend SessionArtifact with FromJson::{from_json}

///|
pub extend SessionArtifacts with Eq::{equal, not_equal}

///|
pub extend SessionArtifacts with Debug::{to_repr}

///|
pub extend SessionArtifacts with ToJson::{to_json}

///|
pub extend SessionArtifacts with FromJson::{from_json}

///|
pub extend SessionArtifactRemovePayload with Eq::{equal, not_equal}

///|
pub extend SessionArtifactRemovePayload with Debug::{to_repr}

///|
pub extend SessionArtifactRemovePayload with ToJson::{to_json}

///|
pub extend SessionArtifactRemovePayload with FromJson::{from_json}

///|
pub extend SessionArtifactsChangedPayload with Eq::{equal, not_equal}

///|
pub extend SessionArtifactsChangedPayload with Debug::{to_repr}

///|
pub extend SessionArtifactsChangedPayload with ToJson::{to_json}

///|
pub extend SessionArtifactsChangedPayload with FromJson::{from_json}
