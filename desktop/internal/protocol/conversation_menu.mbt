// Typed contracts for the native conversation-row popup and OpenSeek title
// persistence. The popup is window-local presentation; rename remains a
// regular remote-capable session operation because the selected conversation
// may belong to another connected device.

///|
pub(all) enum ConversationMenuKind {
  LiveConversationMenu
  ArchivedConversationMenu
} derive(Debug, Eq)

///|
pub fn ConversationMenuKind::wire(self : ConversationMenuKind) -> String {
  match self {
    LiveConversationMenu => "live"
    ArchivedConversationMenu => "archived"
  }
}

///|
pub(all) enum ConversationMenuAction {
  RenameConversation
  ArchiveConversation
  RestoreConversation
  DeleteConversation
} derive(Debug, Eq)

///|
pub fn ConversationMenuAction::wire(self : ConversationMenuAction) -> String {
  match self {
    RenameConversation => "conversation.rename"
    ArchiveConversation => "conversation.archive"
    RestoreConversation => "conversation.restore"
    DeleteConversation => "conversation.delete"
  }
}

///|
pub fn ConversationMenuAction::parse(value : String) -> ConversationMenuAction? {
  match value {
    "conversation.rename" => Some(RenameConversation)
    "conversation.archive" => Some(ArchiveConversation)
    "conversation.restore" => Some(RestoreConversation)
    "conversation.delete" => Some(DeleteConversation)
    _ => None
  }
}

///|
pub(all) struct ConversationMenuPayload {
  x : Int
  y : Int
  kind : ConversationMenuKind
  archive_enabled : Bool
  delete_enabled : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for ConversationMenuKind with fn from_json(json, path) {
  guard json is String(value) else {
    raise JsonDecodeError((path, "expected live or archived"))
  }
  match value {
    "live" => LiveConversationMenu
    "archived" => ArchivedConversationMenu
    _ => raise JsonDecodeError((path, "expected live or archived"))
  }
}

///|
pub impl ToJson for ConversationMenuKind with fn to_json(self) {
  Json(self.wire())
}

///|
pub impl FromJson for ConversationMenuPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "conversation menu payload")
  {
    x: object.required_int("x"),
    y: object.required_int("y"),
    kind: @json.from_json(
      object.required_json("kind"),
      path=path.add_key("kind"),
    ),
    archive_enabled: object.required_bool("archive_enabled"),
    delete_enabled: object.required_bool("delete_enabled"),
  }
}

///|
pub impl ToJson for ConversationMenuPayload with fn to_json(self) {
  {
    "x": self.x,
    "y": self.y,
    "kind": self.kind,
    "archive_enabled": self.archive_enabled,
    "delete_enabled": self.delete_enabled,
  }
}

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
pub extend ConversationMenuKind with FromJson::{from_json}

///|
pub extend ConversationMenuKind with ToJson::{to_json}

///|
pub extend ConversationMenuPayload with FromJson::{from_json}

///|
pub extend ConversationMenuPayload with ToJson::{to_json}

///|
pub extend SessionRenamePayload with FromJson::{from_json}

///|
pub extend SessionRenamePayload with ToJson::{to_json}

///|
pub extend CodexThreadRenamePayload with FromJson::{from_json}

///|
pub extend CodexThreadRenamePayload with ToJson::{to_json}

///|
pub extend ConversationMenuKind with Debug::{to_repr}

///|
pub extend ConversationMenuKind with Eq::{equal, not_equal}

///|
pub extend ConversationMenuAction with Debug::{to_repr}

///|
pub extend ConversationMenuAction with Eq::{equal, not_equal}

///|
pub extend ConversationMenuPayload with Debug::{to_repr}

///|
pub extend ConversationMenuPayload with Eq::{equal, not_equal}

///|
pub extend SessionRenamePayload with Debug::{to_repr}

///|
pub extend SessionRenamePayload with Eq::{equal, not_equal}

///|
pub extend CodexThreadRenamePayload with Debug::{to_repr}

///|
pub extend CodexThreadRenamePayload with Eq::{equal, not_equal}
