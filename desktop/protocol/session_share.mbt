///|
/// Publication finishes before the desktop receives a link. Explicit failures
/// preserve actionable messages across Proton's otherwise generic RPC errors.
pub(all) enum SessionShareReply {
  Shared(url~ : String)
  SignInRequired
  Failed(message~ : String)
} derive(Debug, Eq)

///|
/// Required fields must be strings; missing, null and unknown status values
/// are rejected. Extra metadata from the server is deliberately ignored.
pub impl FromJson for SessionShareReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session share reply")
  match object.required_string("status") {
    "shared" => Shared(url=object.required_string("url"))
    "sign_in_required" => SignInRequired
    "failed" => Failed(message=object.required_string("message"))
    _ => raise JsonDecodeError((path, "invalid session share status"))
  }
}

///|
pub impl ToJson for SessionShareReply with fn to_json(self) {
  match self {
    Shared(url~) => { "status": "shared", "url": url }
    SignInRequired => { "status": "sign_in_required" }
    Failed(message~) => { "status": "failed", "message": message }
  }
}

///|
pub extend SessionShareReply with Eq::{equal, not_equal}

///|
pub extend SessionShareReply with @debug.Debug::{to_repr}

///|
pub extend SessionShareReply with FromJson::{from_json}

///|
pub extend SessionShareReply with ToJson::{to_json}
