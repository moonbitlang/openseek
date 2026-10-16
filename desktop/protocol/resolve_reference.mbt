///|
/// Pure working-host path resolution. Absolute paths are URI paths; directory
/// targets are relative to the supplied checkout. No variant opens an OS app.
pub(all) enum ResolveReferenceReply {
  ReferenceText(path~ : String, line~ : Int32?, column~ : Int32?)
  ReferenceDirectory(path~ : String)
  ReferenceBinary(path~ : String)
  ReferenceRefused(message~ : String)
} derive(Debug, Eq)

///|
pub impl ToJson for ResolveReferenceReply with fn to_json(self) {
  match self {
    ReferenceText(path~, line~, column~) => {
      let fields : Map[String, Json] = { "kind": "text", "path": Json(path) }
      if line is Some(value) {
        fields["line"] = Json(value)
      }
      if column is Some(value) {
        fields["column"] = Json(value)
      }
      Json(fields)
    }
    ReferenceDirectory(path~) => { "kind": "directory", "path": path }
    ReferenceBinary(path~) => { "kind": "binary", "path": path }
    ReferenceRefused(message~) => { "kind": "refused", "message": message }
  }
}

///|
pub impl FromJson for ResolveReferenceReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ResolveReferenceReply")
  match object.required_string("kind") {
    "text" => {
      let file = object.required_string("path")
      let line = object.optional_int("line")
      let column = object.optional_int("column")
      guard file.has_prefix("/") &&
        !file.has_prefix("//") &&
        !(line is Some(value) && value <= 0) &&
        !(column is Some(value) && (value <= 0 || line is None)) else {
        raise JsonDecodeError((path, "invalid resolved text reference"))
      }
      ReferenceText(path=file, line~, column~)
    }
    "directory" => {
      let directory = object.required_string("path")
      guard !directory.has_prefix("/") &&
        !directory.contains("\\") &&
        !directory.split("/").any(part => part == "..") else {
        raise JsonDecodeError(
          (path, "directory reference must remain inside the checkout"),
        )
      }
      ReferenceDirectory(path=directory)
    }
    "binary" => {
      let file = object.required_string("path")
      guard file.has_prefix("/") && !file.has_prefix("//") else {
        raise JsonDecodeError((path, "invalid resolved binary reference"))
      }
      ReferenceBinary(path=file)
    }
    "refused" => ReferenceRefused(message=object.required_string("message"))
    _ => raise JsonDecodeError((path, "invalid resolved reference kind"))
  }
}

///|
pub extend ResolveReferenceReply with ToJson::{to_json}

///|
pub extend ResolveReferenceReply with FromJson::{from_json}

///|
pub extend ResolveReferenceReply with Debug::{to_repr}

///|
pub extend ResolveReferenceReply with Eq::{equal, not_equal}
