///|
pub(all) enum SessionImportSource {
  JsonFile(text~ : String)
  ShareLink(url~ : String)
} derive(Debug, Eq)

///|
pub(all) struct SessionImportPayload {
  source : SessionImportSource
  workspace : String
  worktree_of : String?
} derive(Debug, Eq)

///|
pub(all) struct SessionImported {
  session_id : String
  workspace : String
  sessions : Array[SessionListEntry]
  worktrees : Array[WorktreeInfo]
} derive(Debug, Eq)

///|
/// Carry diagnostics through native and remote transports without redaction.
pub(all) enum SessionImportReply {
  Success(SessionImported)
  Failed(String)
} derive(Debug, Eq)

///|
pub extend SessionImportSource with Debug::{to_repr}

///|
pub extend SessionImportSource with Eq::{equal, not_equal}

///|
pub extend SessionImportSource with ToJson::{to_json}

///|
pub extend SessionImportSource with FromJson::{from_json}

///|
pub extend SessionImportPayload with Debug::{to_repr}

///|
pub extend SessionImportPayload with Eq::{equal, not_equal}

///|
pub extend SessionImportPayload with ToJson::{to_json}

///|
pub extend SessionImportPayload with FromJson::{from_json}

///|
pub extend SessionImportReply with Debug::{to_repr}

///|
pub extend SessionImportReply with Eq::{equal, not_equal}

///|
pub extend SessionImportReply with ToJson::{to_json}

///|
pub extend SessionImportReply with FromJson::{from_json}

///|
pub extend SessionImported with Debug::{to_repr}

///|
pub extend SessionImported with Eq::{equal, not_equal}

///|
pub extend SessionImported with ToJson::{to_json}

///|
pub extend SessionImported with FromJson::{from_json}

///|
pub impl FromJson for SessionImportSource with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "import source")
  match obj.required_string("kind") {
    "json" => JsonFile(text=obj.required_string("text"))
    "share" => ShareLink(url=obj.required_string("url"))
    _ => raise JsonDecodeError((path.add_key("kind"), "unknown import source"))
  }
}

///|
pub impl ToJson for SessionImportSource with fn to_json(self) {
  match self {
    JsonFile(text~) => { "kind": "json", "text": text }
    ShareLink(url~) => { "kind": "share", "url": url }
  }
}

///|
/// A missing or null worktree source means workspace placement. Other fields
/// are required; malformed optional values are rejected, extra fields ignored.
pub impl FromJson for SessionImportPayload with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session import request")
  {
    source: @json.from_json(
      obj.required_json("source"),
      path=path.add_key("source"),
    ),
    workspace: obj.required_string("workspace"),
    worktree_of: obj.optional_string("worktree_of"),
  }
}

///|
pub impl ToJson for SessionImportPayload with fn to_json(self) {
  {
    "source": self.source.to_json(),
    "workspace": self.workspace,
    "worktree_of": self.worktree_of.map_or(Json::null(), value => Json(value)),
  }
}

///|
pub impl FromJson for SessionImported with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "imported conversation")
  {
    session_id: obj.required_string("session_id"),
    workspace: obj.required_string("workspace"),
    sessions: @json.from_json(
      obj.required_json("sessions"),
      path=path.add_key("sessions"),
    ),
    worktrees: @json.from_json(
      obj.required_json("worktrees"),
      path=path.add_key("worktrees"),
    ),
  }
}

///|
pub impl ToJson for SessionImported with fn to_json(self) {
  {
    "session_id": self.session_id,
    "workspace": self.workspace,
    "sessions": Json(self.sessions),
    "worktrees": Json(self.worktrees),
  }
}

///|
pub impl FromJson for SessionImportReply with fn from_json(json, path) {
  let obj = JsonObject::decode(json, path, "session import reply")
  match obj.required_string("status") {
    "success" =>
      Success(
        @json.from_json(
          obj.required_json("result"),
          path=path.add_key("result"),
        ),
      )
    "failed" => Failed(obj.required_string("message"))
    _ =>
      raise JsonDecodeError((path.add_key("status"), "unknown import status"))
  }
}

///|
pub impl ToJson for SessionImportReply with fn to_json(self) {
  match self {
    Success(value) => { "status": "success", "result": value.to_json() }
    Failed(message) => { "status": "failed", "message": message }
  }
}
