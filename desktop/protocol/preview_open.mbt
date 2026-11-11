///|
/// A workspace-relative file name, independent of the selected conversation.
pub(all) struct PreviewOpenArgs {
  path : String
}

///|
pub impl FromJson for PreviewOpenArgs with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "preview_open arguments")
  let file = object.required_string("path")
  guard !file.is_blank() &&
    !file.has_prefix("/") &&
    !file.contains("\\") &&
    !file.contains("://") &&
    !(file is [_, ':', ..]) &&
    !file.contains("\u0000") &&
    !file.split("/").any(part => part == "..") else {
    raise JsonDecodeError(
      (
        path.add_key("path"),
        "expected a workspace-relative file path using forward slashes",
      ),
    )
  }
  { path: file, }
}

///|
#derive(Debug, Eq)
pub(all) enum PreviewOpenRequest {
  Local(session~ : String, workspace~ : String, path~ : String)
  Cloud(account~ : String, session~ : String, path~ : String)
}

///|
pub impl FromJson for PreviewOpenRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "preview open request")
  let args : PreviewOpenArgs = @json.from_json(json, path~)
  let session = object.required_string("session")
  match object.required_string("kind") {
    "local" =>
      Local(
        session~,
        workspace=object.required_string("workspace"),
        path=args.path,
      )
    "cloud" =>
      Cloud(account=object.required_string("account"), session~, path=args.path)
    _ => raise JsonDecodeError((path, "unknown preview owner"))
  }
}

///|
pub impl ToJson for PreviewOpenRequest with fn to_json(self) {
  match self {
    Local(session~, workspace~, path~) =>
      {
        "kind": "local",
        "session": Json(session),
        "workspace": Json(workspace),
        "path": Json(path),
      }
    Cloud(account~, session~, path~) =>
      {
        "kind": "cloud",
        "account": Json(account),
        "session": Json(session),
        "path": Json(path),
      }
  }
}

///|
pub extend PreviewOpenArgs with FromJson::{from_json}

///|
pub extend PreviewOpenRequest with Debug::{to_repr}

///|
pub extend PreviewOpenRequest with Eq::{equal, not_equal}

///|
pub extend PreviewOpenRequest with FromJson::{from_json}

///|
pub extend PreviewOpenRequest with ToJson::{to_json}
