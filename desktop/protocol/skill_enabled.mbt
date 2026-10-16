///|
pub(all) struct SetSkillEnabledPayload {
  id : String
  enabled : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for SetSkillEnabledPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SetSkillEnabledPayload")
  {
    id: object.required_string("id"),
    enabled: object.required_bool("enabled"),
  }
}

///|
pub impl ToJson for SetSkillEnabledPayload with fn to_json(self) {
  { "id": self.id, "enabled": self.enabled }
}

///|
pub(all) enum SetSkillEnabledReply {
  SkillEnabledSet
  SkillEnabledError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for SetSkillEnabledReply with fn to_json(self) {
  match self {
    SkillEnabledSet => { "ok": true }
    SkillEnabledError(message) => { "error": Json(message) }
  }
}

///|
pub impl FromJson for SetSkillEnabledReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SetSkillEnabledReply")
  if object.fields.contains("error") {
    SkillEnabledError(object.required_string("error"))
  } else {
    guard object.required_json("ok") is True else {
      raise JsonDecodeError((path.add_key("ok"), "expected true"))
    }
    SkillEnabledSet
  }
}

///|
pub extend SetSkillEnabledPayload with Debug::{to_repr}

///|
pub extend SetSkillEnabledPayload with Eq::{equal, not_equal}

///|
pub extend SetSkillEnabledPayload with FromJson::{from_json}

///|
pub extend SetSkillEnabledPayload with ToJson::{to_json}

///|
pub extend SetSkillEnabledReply with Debug::{to_repr}

///|
pub extend SetSkillEnabledReply with Eq::{equal, not_equal}

///|
pub extend SetSkillEnabledReply with FromJson::{from_json}

///|
pub extend SetSkillEnabledReply with ToJson::{to_json}
