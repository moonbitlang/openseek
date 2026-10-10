///|
/// The origin and local identifier of a skill. A user directory name never
/// changes which library owns it.
pub(all) enum SkillRef {
  User(String)
  Builtin(String)
} derive(Debug, Eq, Hash)

///|
/// The directory or catalog identifier, without encoding its origin in text.
pub fn SkillRef::value(self : SkillRef) -> String {
  match self {
    User(id) | Builtin(id) => id
  }
}

///|
pub impl ToJson for SkillRef with fn to_json(self) {
  match self {
    User(id) => { "kind": "user", "id": id }
    Builtin(id) => { "kind": "builtin", "id": id }
  }
}

///|
/// Both fields are required; unknown fields are ignored, as in other desktop
/// payloads. Unknown variants and wrong field types are decoding errors.
pub impl FromJson for SkillRef with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SkillRef")
  let id = object.required_string("id")
  match object.required_string("kind") {
    "user" => User(id)
    "builtin" => Builtin(id)
    _ => raise JsonDecodeError((path.add_key("kind"), "unknown skill kind"))
  }
}

///|
pub impl ToJson for InstalledSkill with fn to_json(self) {
  {
    "skill": self.skill.to_json(),
    "name": self.name,
    "description": self.description,
    "source": self.source,
  }
}

///|
pub impl FromJson for InstalledSkill with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "InstalledSkill")
  {
    skill: @json.from_json(
      object.required_json("skill"),
      path=path.add_key("skill"),
    ),
    name: object.required_string("name"),
    description: object.required_string("description"),
    source: object.required_string("source"),
  }
}

///|
pub impl ToJson for UninstallSkillPayload with fn to_json(self) {
  { "skill": self.skill.to_json() }
}

///|
pub impl FromJson for UninstallSkillPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UninstallSkillPayload")
  {
    skill: @json.from_json(
      object.required_json("skill"),
      path=path.add_key("skill"),
    ),
  }
}

///|
pub extend SkillRef with Debug::{to_repr}

///|
pub extend SkillRef with Eq::{equal, not_equal}

///|
pub extend SkillRef with Hash::{hash, hash_combine}

///|
pub extend SkillRef with FromJson::{from_json}

///|
pub extend SkillRef with ToJson::{to_json}
