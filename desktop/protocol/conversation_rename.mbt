// Typed contracts for renaming OpenSeek and Codex conversations. Rename is a
// regular remote-capable operation because the selected row may belong to a
// connected device rather than the local desktop host.

///|
pub(all) struct SessionRenamePayload {
  session : String
  workspace : String
  title : String
} derive(Debug, Eq)

///|
pub(all) struct CodexThreadRenamePayload {
  thread_id : String
  name : String
} derive(Debug, Eq)

///|
pub impl FromJson for SessionRenamePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session rename payload")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    title: object.required_string("title"),
  }
}

///|
pub impl ToJson for SessionRenamePayload with fn to_json(self) {
  { "session": self.session, "workspace": self.workspace, "title": self.title }
}

///|
pub impl FromJson for CodexThreadRenamePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Codex thread rename payload")
  {
    thread_id: object.required_string("threadId"),
    name: object.required_string("name"),
  }
}

///|
pub impl ToJson for CodexThreadRenamePayload with fn to_json(self) {
  { "threadId": self.thread_id, "name": self.name }
}

///|
pub extend SessionRenamePayload with FromJson::{from_json}

///|
pub extend SessionRenamePayload with ToJson::{to_json}

///|
pub extend CodexThreadRenamePayload with FromJson::{from_json}

///|
pub extend CodexThreadRenamePayload with ToJson::{to_json}

///|
pub extend SessionRenamePayload with Debug::{to_repr}

///|
pub extend SessionRenamePayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadRenamePayload with Debug::{to_repr}

///|
pub extend CodexThreadRenamePayload with Eq::{equal, not_equal}
