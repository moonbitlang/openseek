///|
/// The local operating system preference, independent of the window theme.
pub(all) struct AppSystemAppearanceReply {
  dark : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for AppSystemAppearanceReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "system appearance reply")
  { dark: object.required_bool("dark"), }
}

///|
pub impl ToJson for AppSystemAppearanceReply with fn to_json(self) {
  { "dark": self.dark.to_json() }
}

///|
pub extend AppSystemAppearanceReply with Debug::{to_repr}

///|
pub extend AppSystemAppearanceReply with Eq::{equal, not_equal}

///|
pub extend AppSystemAppearanceReply with FromJson::{from_json}

///|
pub extend AppSystemAppearanceReply with ToJson::{to_json}
