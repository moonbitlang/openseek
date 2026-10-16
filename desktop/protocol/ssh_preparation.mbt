///|
pub(all) enum SshPreparationTarget {
  New(name~ : String, destination~ : String, data_dir~ : String)
  Existing(id~ : String)
} derive(Eq)

///|
pub impl ToJson for SshPreparationTarget with fn to_json(self) {
  match self {
    New(name~, destination~, data_dir~) =>
      {
        "kind": "new",
        "name": name,
        "destination": destination,
        "data_dir": data_dir,
      }
    Existing(id~) => { "kind": "existing", "id": id }
  }
}

///|
pub impl FromJson for SshPreparationTarget with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH preparation target")
  match object.required_string("kind") {
    "new" =>
      New(
        name=object.required_string("name"),
        destination=object.required_string("destination"),
        data_dir=object.required_string("data_dir"),
      )
    "existing" => Existing(id=object.required_string("id"))
    _ => raise JsonDecodeError((path, "invalid SSH preparation target"))
  }
}

///|
pub(all) struct SshPreparationRequest {
  target : SshPreparationTarget
  directory : String
} derive(Eq)

///|
pub impl ToJson for SshPreparationRequest with fn to_json(self) {
  { "target": self.target, "directory": self.directory }
}

///|
pub impl FromJson for SshPreparationRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH preparation request")
  {
    target: @json.from_json(
      object.required_json("target"),
      path=path.add_key("target"),
    ),
    directory: object.required_string("directory"),
  }
}

///|
pub(all) struct SshPreparationToken {
  id : String
} derive(Eq)

///|
pub impl ToJson for SshPreparationToken with fn to_json(self) {
  { "id": self.id }
}

///|
pub impl FromJson for SshPreparationToken with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH preparation token")
  { id: object.required_string("id"), }
}

///|
pub(all) struct SshPreparationProgress {
  stage : String?
} derive(Eq)

///|
pub impl ToJson for SshPreparationProgress with fn to_json(self) {
  match self.stage {
    Some(stage) => { "stage": stage }
    None => {}
  }
}

///|
pub impl FromJson for SshPreparationProgress with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SSH preparation progress")
  { stage: object.optional_string("stage"), }
}

///|
/// Preserve actionable diagnostics across Proton's rejected-promise boundary.
pub(all) enum SshOperation[T] {
  SshCompleted(T)
  SshFailed(String)
}

///|
pub impl[T : ToJson] ToJson for SshOperation[T] with fn to_json(self) {
  match self {
    SshCompleted(value) => { "status": "completed", "value": value }
    SshFailed(message) => { "status": "failed", "message": message }
  }
}

///|
pub impl[T : FromJson] FromJson for SshOperation[T] with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "SSH operation")
  match object.required_string("status") {
    "completed" =>
      SshCompleted(
        @json.from_json(
          object.required_json("value"),
          path=path.add_key("value"),
        ),
      )
    "failed" => SshFailed(object.required_string("message"))
    _ => raise JsonDecodeError((path, "invalid SSH operation status"))
  }
}

///|
pub extend SshPreparationTarget with ToJson::{to_json}

///|
pub extend SshPreparationTarget with FromJson::{from_json}

///|
pub extend SshPreparationTarget with Eq::{equal, not_equal}

///|
pub extend SshPreparationRequest with ToJson::{to_json}

///|
pub extend SshPreparationRequest with FromJson::{from_json}

///|
pub extend SshPreparationRequest with Eq::{equal, not_equal}

///|
pub extend SshPreparationToken with ToJson::{to_json}

///|
pub extend SshPreparationToken with FromJson::{from_json}

///|
pub extend SshPreparationToken with Eq::{equal, not_equal}

///|
pub extend SshPreparationProgress with ToJson::{to_json}

///|
pub extend SshPreparationProgress with FromJson::{from_json}

///|
pub extend SshPreparationProgress with Eq::{equal, not_equal}

///|
pub extend SshOperation with ToJson::{to_json}

///|
pub extend SshOperation with FromJson::{from_json}
