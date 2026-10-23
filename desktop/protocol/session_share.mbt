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

///|
/// Publication stages; no client claims unobservable upload byte progress.
pub(all) enum ShareProgress {
  Preparing
  Connecting(attempt~ : Int32)
  Uploading(attempt~ : Int32)
  Waiting(attempt~ : Int32)
} derive(Debug, Eq)

///|
pub(all) struct SessionShareProgress {
  generation : Int32
  progress : ShareProgress
} derive(Debug, Eq)

///|
pub extend ShareProgress with Debug::{to_repr}

///|
pub extend ShareProgress with Eq::{equal, not_equal}

///|
pub extend ShareProgress with ToJson::{to_json}

///|
pub extend ShareProgress with FromJson::{from_json}

///|
pub extend SessionShareProgress with Debug::{to_repr}

///|
pub extend SessionShareProgress with Eq::{equal, not_equal}

///|
pub extend SessionShareProgress with ToJson::{to_json}

///|
pub extend SessionShareProgress with FromJson::{from_json}

///|
/// Preserve the window-local tagged progress format. Stage payload fields are
/// required, null and malformed fields are rejected, and extra fields ignored.
pub impl FromJson for ShareProgress with fn from_json(json, path) {
  match json {
    "Preparing" => Preparing
    ["Connecting", fields] => {
      let object = JsonObject::decode(
        fields,
        path.add_index(1),
        "share connection progress",
      )
      Connecting(attempt=object.required_int("attempt"))
    }
    ["Uploading", fields] => {
      let object = JsonObject::decode(
        fields,
        path.add_index(1),
        "share upload progress",
      )
      Uploading(attempt=object.required_int("attempt"))
    }
    ["Waiting", fields] => {
      let object = JsonObject::decode(
        fields,
        path.add_index(1),
        "share response progress",
      )
      Waiting(attempt=object.required_int("attempt"))
    }
    _ => raise JsonDecodeError((path, "invalid share progress stage"))
  }
}

///|
pub impl ToJson for ShareProgress with fn to_json(self) {
  match self {
    Preparing => "Preparing"
    Connecting(attempt~) => ["Connecting", { "attempt": attempt }]
    Uploading(attempt~) => ["Uploading", { "attempt": attempt }]
    Waiting(attempt~) => ["Waiting", { "attempt": attempt }]
  }
}

///|
pub impl FromJson for SessionShareProgress with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session share progress")
  {
    generation: object.required_int("generation"),
    progress: @json.from_json(
      object.required_json("progress"),
      path=path.add_key("progress"),
    ),
  }
}

///|
pub impl ToJson for SessionShareProgress with fn to_json(self) {
  { "generation": self.generation, "progress": self.progress.to_json() }
}

///|
/// Native-window account authority or a single remote upload permission.
pub(all) enum ShareAuthorization {
  LocalAccount(user_id~ : String)
  UploadGrant(upload_token~ : String)
} derive(Eq, Debug)

///|
/// A share request carries source metadata; the owning host captures the files.
pub(all) struct SessionSharePayload {
  generation : Int32
  source : SessionExportPayload
  idempotency_key : String
  authorization : ShareAuthorization
} derive(Eq, Debug)

///|
pub impl FromJson for ShareAuthorization with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "share authorization")
  match object.required_string("kind") {
    "local_account" => LocalAccount(user_id=object.required_string("user_id"))
    "upload_grant" => {
      let upload_token = object.required_string("upload_token")
      guard upload_token.has_prefix("sug_") else {
        raise JsonDecodeError((path, "expected a share upload grant"))
      }
      UploadGrant(upload_token~)
    }
    _ => raise JsonDecodeError((path, "invalid share authorization"))
  }
}

///|
pub impl ToJson for ShareAuthorization with fn to_json(self) {
  match self {
    LocalAccount(user_id~) => { "kind": "local_account", "user_id": user_id }
    UploadGrant(upload_token~) =>
      { "kind": "upload_grant", "upload_token": upload_token }
  }
}

///|
pub impl FromJson for SessionSharePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session share request")
  {
    generation: object.required_int("generation"),
    source: @json.from_json(
      object.required_json("source"),
      path=path.add_key("source"),
    ),
    idempotency_key: object.required_string("idempotency_key"),
    authorization: @json.from_json(
      object.required_json("authorization"),
      path=path.add_key("authorization"),
    ),
  }
}

///|
pub impl ToJson for SessionSharePayload with fn to_json(self) {
  {
    "generation": self.generation,
    "source": self.source.to_json(),
    "idempotency_key": self.idempotency_key,
    "authorization": self.authorization.to_json(),
  }
}

///|
pub extend ShareAuthorization with Eq::{equal, not_equal}

///|
pub extend ShareAuthorization with Debug::{to_repr}

///|
pub extend SessionSharePayload with Eq::{equal, not_equal}

///|
pub extend SessionSharePayload with Debug::{to_repr}

///|
pub extend ShareAuthorization with FromJson::{from_json}

///|
pub extend ShareAuthorization with ToJson::{to_json}

///|
pub extend SessionSharePayload with FromJson::{from_json}

///|
pub extend SessionSharePayload with ToJson::{to_json}

///|
/// The owning host reads the original file; no preview data crosses this request.
pub(all) struct FileSharePayload {
  source : ReadFilePayload
  idempotency_key : String
  authorization : ShareAuthorization
} derive(Eq, Debug)

///|
pub impl FromJson for FileSharePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "file share request")
  {
    source: @json.from_json(
      object.required_json("source"),
      path=path.add_key("source"),
    ),
    idempotency_key: object.required_string("idempotency_key"),
    authorization: @json.from_json(
      object.required_json("authorization"),
      path=path.add_key("authorization"),
    ),
  }
}

///|
pub impl ToJson for FileSharePayload with fn to_json(self) {
  {
    "source": self.source.to_json(),
    "idempotency_key": self.idempotency_key,
    "authorization": self.authorization.to_json(),
  }
}

///|
pub extend FileSharePayload with Eq::{equal, not_equal}

///|
pub extend FileSharePayload with Debug::{to_repr}

///|
pub extend FileSharePayload with FromJson::{from_json}

///|
pub extend FileSharePayload with ToJson::{to_json}
