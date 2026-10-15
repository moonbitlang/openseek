///|
/// The registry coordinates and version recorded for an installed skill.
pub(all) struct RegistrySkillSource {
  module_name : String
  package_path : String
  version : String
} derive(Debug, Eq)

///|
pub impl FromJson for RegistrySkillSource with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "RegistrySkillSource")
  {
    module_name: object.required_string("module_name"),
    package_path: object.required_string("package_path"),
    version: object.required_string("version"),
  }
}

///|
pub impl ToJson for RegistrySkillSource with fn to_json(self) {
  {
    "module_name": self.module_name,
    "package_path": self.package_path,
    "version": self.version,
  }
}

///|
pub extend RegistrySkillSource with Debug::{to_repr}

///|
pub extend RegistrySkillSource with Eq::{equal, not_equal}

///|
pub extend RegistrySkillSource with FromJson::{from_json}

///|
pub extend RegistrySkillSource with ToJson::{to_json}
