///|
/// A bounded working-host document. Only supported raster/PDF formats are
/// accepted; a filename or an arbitrary remote MIME type cannot enable HTML.
pub(all) struct FilePreviewContent {
  media_type : String
  data_base64 : String
} derive(Debug, Eq)

///|
pub impl FromJson for FilePreviewContent with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "file preview content")
  let media_type = object.required_string("media_type")
  guard media_type
    is ("image/png"
    | "image/jpeg"
    | "image/gif"
    | "image/webp"
    | "application/pdf") else {
    raise JsonDecodeError((path, "unsupported preview media type"))
  }
  { media_type, data_base64: object.required_string("data_base64"), }
}

///|
pub impl ToJson for FilePreviewContent with fn to_json(self) {
  { "media_type": self.media_type, "data_base64": self.data_base64 }
}

///|
pub extend FilePreviewContent with ToJson::{to_json}

///|
pub extend FilePreviewContent with FromJson::{from_json}

///|
pub extend FilePreviewContent with Debug::{to_repr}

///|
pub extend FilePreviewContent with Eq::{equal, not_equal}
