///|
/// Skill errors travel inside the reply so Proton preserves their detail.
pub(all) enum SkillCommandReply[Reply] {
  SkillCommandSuccess(Reply)
  SkillCommandError(String)
}

///|
pub impl[Reply : FromJson] FromJson for SkillCommandReply[Reply] with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "skill command reply")
  if json is Object(fields) && fields.contains("error") {
    SkillCommandError(object.required_string("error"))
  } else {
    SkillCommandSuccess(FromJson::from_json(json, path))
  }
}

///|
pub impl[Reply : ToJson] ToJson for SkillCommandReply[Reply] with fn to_json(
  self,
) {
  match self {
    SkillCommandSuccess(reply) => reply.to_json()
    SkillCommandError(message) => { "error": Json(message) }
  }
}

///|
pub extend SkillCommandReply with FromJson::{from_json}

///|
pub extend SkillCommandReply with ToJson::{to_json}
