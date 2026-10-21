///|
/// The Cloud API origin is shared by browser requests and window-only downloads.
pub const CloudOrigin = "https://cloud.moonbitlang.cn"

///|
/// Only complete original bytes belong here, never a rendered preview.
pub(all) struct CloudFileCache {
  etag : String
  data_base64 : String
} derive(Eq, Debug)

///|
pub(all) struct CloudFileDownloadPayload {
  account : String
  session : String
  path : String
  cached : CloudFileCache?
} derive(Eq, Debug)

///|
/// Saved bytes and revealing them are separate outcomes.
pub(all) enum CloudFileDownloadReply {
  Saved(path~ : String, revealed~ : Bool)
  Failed(message~ : String)
} derive(Eq, Debug)

///|
pub impl FromJson for CloudFileCache with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud file cache")
  {
    etag: object.required_string("etag"),
    data_base64: object.required_string("data_base64"),
  }
}

///|
pub impl ToJson for CloudFileCache with fn to_json(self) {
  { "etag": self.etag, "data_base64": self.data_base64 }
}

///|
pub impl FromJson for CloudFileDownloadPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud file download")
  {
    account: object.required_string("account"),
    session: object.required_string("session"),
    path: object.required_string("path"),
    cached: object
    .optional_json("cached")
    .map(value => @json.from_json(value, path=path.add_key("cached"))),
  }
}

///|
pub impl ToJson for CloudFileDownloadPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "account": Json(self.account),
    "session": Json(self.session),
    "path": Json(self.path),
  }
  if self.cached is Some(cached) {
    fields["cached"] = cached.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for CloudFileDownloadReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud file download reply")
  match object.required_string("kind") {
    "saved" =>
      Saved(
        path=object.required_string("path"),
        revealed=object.required_bool("revealed"),
      )
    "failed" => Failed(message=object.required_string("message"))
    _ =>
      raise JsonDecodeError((path.add_key("kind"), "unknown download outcome"))
  }
}

///|
pub impl ToJson for CloudFileDownloadReply with fn to_json(self) {
  match self {
    Saved(path~, revealed~) =>
      { "kind": "saved", "path": path, "revealed": revealed }
    Failed(message~) => { "kind": "failed", "message": message }
  }
}

///|
pub extend CloudFileCache with Eq::{equal, not_equal}

///|
pub extend CloudFileCache with Debug::{to_repr}

///|
pub extend CloudFileCache with FromJson::{from_json}

///|
pub extend CloudFileCache with ToJson::{to_json}

///|
pub extend CloudFileDownloadPayload with Eq::{equal, not_equal}

///|
pub extend CloudFileDownloadPayload with Debug::{to_repr}

///|
pub extend CloudFileDownloadPayload with FromJson::{from_json}

///|
pub extend CloudFileDownloadPayload with ToJson::{to_json}

///|
pub extend CloudFileDownloadReply with Eq::{equal, not_equal}

///|
pub extend CloudFileDownloadReply with Debug::{to_repr}

///|
pub extend CloudFileDownloadReply with FromJson::{from_json}

///|
pub extend CloudFileDownloadReply with ToJson::{to_json}
