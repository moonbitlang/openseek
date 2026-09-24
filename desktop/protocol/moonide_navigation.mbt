// Operational failures travel as replies so Proton preserves their details.

///|
pub(all) enum MoonIdeNavigationReply {
  NavigationLocations(MoonIdeLocationsReply)
  NavigationError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for MoonIdeNavigationReply with fn to_json(self) {
  match self {
    NavigationLocations(reply) =>
      { "kind": "locations", "locations": reply.locations.to_json() }
    NavigationError(message) => { "kind": "error", "message": message }
  }
}

///|
pub impl FromJson for MoonIdeNavigationReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Moon IDE navigation reply")
  match object.required_string("kind") {
    "locations" => NavigationLocations(FromJson::from_json(json, path))
    "error" => NavigationError(object.required_string("message"))
    _ =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown navigation reply kind"),
      )
  }
}

///|
pub extend MoonIdeNavigationReply with Debug::{to_repr}

///|
pub extend MoonIdeNavigationReply with Eq::{equal, not_equal}

///|
pub extend MoonIdeNavigationReply with ToJson::{to_json}

///|
pub extend MoonIdeNavigationReply with FromJson::{from_json}
