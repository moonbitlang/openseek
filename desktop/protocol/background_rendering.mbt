///|
#derive(Eq, Debug)
pub(all) struct BackgroundRenderingSettings {
  supported : Bool
  enabled : Bool
  launch_enabled : Bool
  error : String?
}

///|
pub impl FromJson for BackgroundRenderingSettings with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "background rendering settings")
  {
    supported: object.required_bool("supported"),
    enabled: object.required_bool("enabled"),
    launch_enabled: object.required_bool("launch_enabled"),
    error: object.optional_string("error"),
  }
}

///|
pub impl ToJson for BackgroundRenderingSettings with fn to_json(self) {
  let fields : Map[String, Json] = {
    "supported": Json(self.supported),
    "enabled": Json(self.enabled),
    "launch_enabled": Json(self.launch_enabled),
  }
  if self.error is Some(error) {
    fields["error"] = Json(error)
  }
  Json(fields)
}

///|
#derive(Eq, Debug)
pub(all) struct BackgroundRenderingSetPayload {
  enabled : Bool
}

///|
pub impl FromJson for BackgroundRenderingSetPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "background rendering preference")
  { enabled: object.required_bool("enabled"), }
}

///|
pub impl ToJson for BackgroundRenderingSetPayload with fn to_json(self) {
  { "enabled": Json(self.enabled) }
}

///|
pub extend BackgroundRenderingSettings with FromJson::{from_json}

///|
pub extend BackgroundRenderingSettings with ToJson::{to_json}

///|
pub extend BackgroundRenderingSettings with Eq::{equal, not_equal}

///|
pub extend BackgroundRenderingSettings with Debug::{to_repr}

///|
pub extend BackgroundRenderingSetPayload with FromJson::{from_json}

///|
pub extend BackgroundRenderingSetPayload with ToJson::{to_json}

///|
pub extend BackgroundRenderingSetPayload with Eq::{equal, not_equal}

///|
pub extend BackgroundRenderingSetPayload with Debug::{to_repr}
