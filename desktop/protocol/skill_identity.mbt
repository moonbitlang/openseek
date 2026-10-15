///|
/// A registry skill's module and package, independent of name and version.
pub(all) struct RegistrySkillIdentity {
  module_name : String
  package_path : String
} derive(Debug, Eq)

///|
pub impl FromJson for RegistrySkillIdentity with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "RegistrySkillIdentity")
  {
    module_name: object.required_string("module_name"),
    package_path: object.required_string("package_path"),
  }
}

///|
pub impl ToJson for RegistrySkillIdentity with fn to_json(self) {
  { "module_name": self.module_name, "package_path": self.package_path }
}

///|
pub extend RegistrySkillIdentity with Debug::{to_repr}

///|
pub extend RegistrySkillIdentity with Eq::{equal, not_equal}

///|
pub extend RegistrySkillIdentity with FromJson::{from_json}

///|
pub extend RegistrySkillIdentity with ToJson::{to_json}
