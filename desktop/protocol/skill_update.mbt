///|
/// Update the existing installation to the exact version shown by the UI.
pub(all) struct UpdateSkillPayload {
  id : String
  target_version : String
} derive(Debug, Eq)

///|
pub impl FromJson for UpdateSkillPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UpdateSkillPayload")
  {
    id: object.required_string("id"),
    target_version: object.required_string("target_version"),
  }
}

///|
pub impl ToJson for UpdateSkillPayload with fn to_json(self) {
  { "id": self.id, "target_version": self.target_version }
}

///|
pub(all) enum UpdateSkillReply {
  SkillUpdated(InstalledSkill)
  SkillAlreadyCurrent(InstalledSkill)
  SkillInstallationChanged
  SkillUpdateError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for UpdateSkillReply with fn to_json(self) {
  match self {
    SkillUpdated(installed) =>
      { "status": "updated", "installed": installed.to_json() }
    SkillAlreadyCurrent(installed) =>
      { "status": "current", "installed": installed.to_json() }
    SkillInstallationChanged => { "status": "changed" }
    SkillUpdateError(message) => { "error": message }
  }
}

///|
pub impl FromJson for UpdateSkillReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UpdateSkillReply")
  if object.fields.contains("error") {
    return SkillUpdateError(object.required_string("error"))
  }
  match object.required_string("status") {
    "updated" =>
      SkillUpdated(
        @json.from_json(
          object.required_json("installed"),
          path=path.add_key("installed"),
        ),
      )
    "current" =>
      SkillAlreadyCurrent(
        @json.from_json(
          object.required_json("installed"),
          path=path.add_key("installed"),
        ),
      )
    "changed" => SkillInstallationChanged
    _ =>
      raise JsonDecodeError(
        (path.add_key("status"), "unknown skill update status"),
      )
  }
}

///|
pub extend UpdateSkillPayload with Debug::{to_repr}

///|
pub extend UpdateSkillPayload with Eq::{equal, not_equal}

///|
pub extend UpdateSkillPayload with FromJson::{from_json}

///|
pub extend UpdateSkillPayload with ToJson::{to_json}

///|
pub extend UpdateSkillReply with Debug::{to_repr}

///|
pub extend UpdateSkillReply with Eq::{equal, not_equal}

///|
pub extend UpdateSkillReply with FromJson::{from_json}

///|
pub extend UpdateSkillReply with ToJson::{to_json}
