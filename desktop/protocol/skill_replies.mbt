// Each skill operation owns its success and error reply. Failures travel as
// JSON replies so Proton does not redact their user-facing messages.

///|
pub(all) enum SkillsCatalogReply {
  SkillsCatalog(Array[MarketSkill])
  SkillsCatalogError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for SkillsCatalogReply with fn to_json(self) {
  match self {
    SkillsCatalog(value) => { "skills": value.to_json() }
    SkillsCatalogError(message) => { "error": Json(message) }
  }
}

///|
pub impl FromJson for SkillsCatalogReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SkillsCatalogReply")
  if object.fields.contains("error") {
    SkillsCatalogError(object.required_string("error"))
  } else {
    SkillsCatalog(
      @json.from_json(
        object.required_json("skills"),
        path=path.add_key("skills"),
      ),
    )
  }
}

///|
pub(all) enum InstalledSkillsReply {
  InstalledSkills(Array[InstalledSkill])
  InstalledSkillsError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for InstalledSkillsReply with fn to_json(self) {
  match self {
    InstalledSkills(value) => { "skills": value.to_json() }
    InstalledSkillsError(message) => { "error": Json(message) }
  }
}

///|
pub impl FromJson for InstalledSkillsReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "InstalledSkillsReply")
  if object.fields.contains("error") {
    InstalledSkillsError(object.required_string("error"))
  } else {
    InstalledSkills(
      @json.from_json(
        object.required_json("skills"),
        path=path.add_key("skills"),
      ),
    )
  }
}

///|
pub(all) enum InstallSkillReply {
  SkillInstalled(InstalledSkill)
  SkillInstallError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for InstallSkillReply with fn to_json(self) {
  match self {
    SkillInstalled(value) => { "installed": value.to_json() }
    SkillInstallError(message) => { "error": Json(message) }
  }
}

///|
pub impl FromJson for InstallSkillReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "InstallSkillReply")
  if object.fields.contains("error") {
    SkillInstallError(object.required_string("error"))
  } else {
    SkillInstalled(
      @json.from_json(
        object.required_json("installed"),
        path=path.add_key("installed"),
      ),
    )
  }
}

///|
pub(all) enum UninstallSkillReply {
  SkillUninstalled
  SkillUninstallError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for UninstallSkillReply with fn to_json(self) {
  match self {
    SkillUninstalled => { "removed": true }
    SkillUninstallError(message) => { "error": Json(message) }
  }
}

///|
pub impl FromJson for UninstallSkillReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UninstallSkillReply")
  if object.fields.contains("error") {
    SkillUninstallError(object.required_string("error"))
  } else {
    guard object.required_json("removed") is True else {
      raise JsonDecodeError((path.add_key("removed"), "expected true"))
    }
    SkillUninstalled
  }
}

///|
pub(all) enum SkillContentReply {
  SkillContent(String)
  SkillContentError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for SkillContentReply with fn to_json(self) {
  match self {
    SkillContent(value) => { "content": value.to_json() }
    SkillContentError(message) => { "error": Json(message) }
  }
}

///|
pub impl FromJson for SkillContentReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SkillContentReply")
  if object.fields.contains("error") {
    SkillContentError(object.required_string("error"))
  } else {
    SkillContent(
      @json.from_json(
        object.required_json("content"),
        path=path.add_key("content"),
      ),
    )
  }
}

///|
pub extend SkillContentReply with Debug::{to_repr}

///|
pub extend SkillContentReply with Eq::{equal, not_equal}

///|
pub extend SkillContentReply with FromJson::{from_json}

///|
pub extend SkillContentReply with ToJson::{to_json}
