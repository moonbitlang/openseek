///|
/// Window-local HTML preview. Paths use the same absolute resource spelling
/// as fs.read_file. An absent root selects the file's parent directory.
#derive(Debug, Eq)
pub(all) struct BrowserPreviewPayload {
  id : Int32
  path : String
  root : String?
  dark : Bool
  session : String?
}

///|
pub impl ToJson for BrowserPreviewPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": Json(self.id),
    "path": Json(self.path),
    "dark": Json(self.dark),
  }
  if self.root is Some(root) {
    fields["root"] = Json(root)
  }
  if self.session is Some(session) {
    fields["session"] = Json(session)
  }
  Json(fields)
}

///|
pub impl FromJson for BrowserPreviewPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowserPreviewPayload")
  {
    id: object.required_int("id"),
    path: object.required_string("path"),
    root: object.optional_string("root"),
    dark: object.required_bool("dark"),
    session: object.optional_string("session"),
  }
}

///|
#derive(Debug, Eq)
pub(all) struct BrowserPreviewReply {
  url : String
}

///|
pub impl ToJson for BrowserPreviewReply with fn to_json(self) {
  { "url": Json(self.url) }
}

///|
pub impl FromJson for BrowserPreviewReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowserPreviewReply")
  { url: object.required_string("url"), }
}

///|
pub extend BrowserPreviewPayload with Debug::{to_repr}

///|
pub extend BrowserPreviewPayload with Eq::{equal, not_equal}

///|
pub extend BrowserPreviewPayload with ToJson::{to_json}

///|
pub extend BrowserPreviewPayload with FromJson::{from_json}

///|
pub extend BrowserPreviewReply with Debug::{to_repr}

///|
pub extend BrowserPreviewReply with Eq::{equal, not_equal}

///|
pub extend BrowserPreviewReply with ToJson::{to_json}

///|
pub extend BrowserPreviewReply with FromJson::{from_json}
