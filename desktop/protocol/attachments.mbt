///|
/// Browser uploads carry bytes; native selections carry a host-local path.
pub(all) enum AttachmentSource {
  AttachmentPath(String)
  AttachmentBytes(name~ : String, data_base64~ : String)
} derive(Debug, Eq)

///|
pub(all) struct PrepareAttachmentPayload {
  session : String
  workspace : String
  source : AttachmentSource
} derive(Debug, Eq)

///|
pub(all) enum PrepareAttachmentReply {
  WorkspaceAttachment(path~ : String)
  AttachmentUploadRequired(name~ : String)
  AttachmentImage(name~ : String, url~ : String)
} derive(Debug, Eq)

///|
pub(all) struct ImportAttachmentReply {
  path : String
} derive(Debug, Eq)

///|
pub(all) struct PickAttachmentReply {
  path : String?
} derive(Debug, Eq)

///|
pub(all) struct StageAttachmentsPayload {
  session : String
  workspace : String
  source_root : String
  paths : Array[String]
} derive(Debug, Eq)

///|
pub impl FromJson for StageAttachmentsPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "attachment staging payload")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    source_root: object.required_string("source_root"),
    paths: object.required_string_array("paths"),
  }
}

///|
pub impl ToJson for StageAttachmentsPayload with fn to_json(self) {
  {
    "session": self.session,
    "workspace": self.workspace,
    "source_root": self.source_root,
    "paths": self.paths,
  }
}

///|
pub extend StageAttachmentsPayload with Eq::{equal, not_equal}

///|
pub extend StageAttachmentsPayload with Debug::{to_repr}

///|
pub extend StageAttachmentsPayload with FromJson::{from_json}

///|
pub extend StageAttachmentsPayload with ToJson::{to_json}

///|
pub impl FromJson for AttachmentSource with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "attachment source")
  match object.required_string("kind") {
    "path" => AttachmentPath(object.required_string("path"))
    "bytes" =>
      AttachmentBytes(
        name=object.required_string("name"),
        data_base64=object.required_string("data_base64"),
      )
    _ =>
      raise JsonDecodeError((path.add_key("kind"), "unknown attachment source"))
  }
}

///|
pub impl ToJson for AttachmentSource with fn to_json(self) {
  match self {
    AttachmentPath(path) => { "kind": "path", "path": path }
    AttachmentBytes(name~, data_base64~) =>
      { "kind": "bytes", "name": name, "data_base64": data_base64 }
  }
}

///|
pub impl FromJson for PrepareAttachmentPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "attachment payload")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    source: @json.from_json(
      object.required_json("source"),
      path=path.add_key("source"),
    ),
  }
}

///|
pub impl ToJson for PrepareAttachmentPayload with fn to_json(self) {
  {
    "session": self.session,
    "workspace": self.workspace,
    "source": self.source,
  }
}

///|
pub impl FromJson for PrepareAttachmentReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "attachment preparation reply")
  match object.required_string("kind") {
    "reference" => WorkspaceAttachment(path=object.required_string("path"))
    "upload_required" =>
      AttachmentUploadRequired(name=object.required_string("name"))
    "image" =>
      AttachmentImage(
        name=object.required_string("name"),
        url=object.required_string("url"),
      )
    _ =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown attachment preparation reply"),
      )
  }
}

///|
pub impl ToJson for PrepareAttachmentReply with fn to_json(self) {
  match self {
    WorkspaceAttachment(path~) => { "kind": "reference", "path": path }
    AttachmentUploadRequired(name~) =>
      { "kind": "upload_required", "name": name }
    AttachmentImage(name~, url~) =>
      { "kind": "image", "name": name, "url": url }
  }
}

///|
pub impl FromJson for ImportAttachmentReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "attachment import reply")
  { path: object.required_string("path"), }
}

///|
pub impl ToJson for ImportAttachmentReply with fn to_json(self) {
  { "path": self.path }
}

///|
pub impl FromJson for PickAttachmentReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "attachment picker reply")
  { path: object.optional_string("path"), }
}

///|
pub impl ToJson for PickAttachmentReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.path is Some(path) {
    fields["path"] = Json(path)
  }
  Json::object(fields)
}

///|
pub extend AttachmentSource with Eq::{equal, not_equal}

///|
pub extend AttachmentSource with Debug::{to_repr}

///|
pub extend PrepareAttachmentReply with Eq::{equal, not_equal}

///|
pub extend PrepareAttachmentReply with Debug::{to_repr}

///|
pub extend AttachmentSource with FromJson::{from_json}

///|
pub extend AttachmentSource with ToJson::{to_json}

///|
pub extend PrepareAttachmentPayload with Eq::{equal, not_equal}

///|
pub extend PrepareAttachmentPayload with Debug::{to_repr}

///|
pub extend PrepareAttachmentPayload with FromJson::{from_json}

///|
pub extend PrepareAttachmentPayload with ToJson::{to_json}

///|
pub extend PrepareAttachmentReply with FromJson::{from_json}

///|
pub extend PrepareAttachmentReply with ToJson::{to_json}

///|
pub extend ImportAttachmentReply with Eq::{equal, not_equal}

///|
pub extend ImportAttachmentReply with Debug::{to_repr}

///|
pub extend ImportAttachmentReply with FromJson::{from_json}

///|
pub extend ImportAttachmentReply with ToJson::{to_json}

///|
pub extend PickAttachmentReply with Eq::{equal, not_equal}

///|
pub extend PickAttachmentReply with Debug::{to_repr}

///|
pub extend PickAttachmentReply with FromJson::{from_json}

///|
pub extend PickAttachmentReply with ToJson::{to_json}
