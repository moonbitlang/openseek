///|
/// Content rendered by the working host. Saving or publishing it is a client
/// operation; no destination path or credential belongs in this reply.
pub(all) struct SessionExportContent {
  html : String
  json : String
} derive(Debug, Eq)

///|
pub impl FromJson for SessionExportContent with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session export content")
  {
    html: object.required_string("html"),
    json: object.required_string("json"),
  }
}

///|
pub impl ToJson for SessionExportContent with fn to_json(self) {
  { "html": self.html, "json": self.json }
}

///|
pub extend SessionExportContent with ToJson::{to_json}

///|
pub extend SessionExportContent with FromJson::{from_json}

///|
pub extend SessionExportContent with Debug::{to_repr}

///|
pub extend SessionExportContent with Eq::{equal, not_equal}
