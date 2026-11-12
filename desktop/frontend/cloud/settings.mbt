///|
/// Engine options travel beside the native command, as they do for Local.
#derive(Eq)
pub(all) struct CommandSettings {
  model : @deepseek.DsVariant
  thinking : @protocol.OpenSeekThinking
}

///|
pub fn CommandSettings::default() -> CommandSettings {
  { model: V4Flash, thinking: ThinkingHigh, }
}

///|
pub impl ToJson for CommandSettings with fn to_json(self) {
  {
    "model": Json(@deepseek.Deepseek(self.model).to_string()),
    "thinking": self.thinking.to_json(),
  }
}

///|
pub impl FromJson for CommandSettings with fn from_json(json, path) {
  let fields : Map[String, Json] = @json.from_json(json, path~)
  let model : @deepseek.DsVariant = match fields.get("model") {
    Some(String("deepseek-flash")) => V4Flash
    Some(String("deepseek-v4-pro")) => V4Pro
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("model"), "expected a Cloud model"),
      )
  }
  let thinking : @protocol.OpenSeekThinking = match fields.get("thinking") {
    None =>
      raise @json.JsonDecodeError(
        (path.add_key("thinking"), "missing thinking"),
      )
    Some(value) => @json.from_json(value, path=path.add_key("thinking"))
  }
  { model, thinking, }
}

///|
pub extend CommandSettings with Eq::{equal, not_equal}

///|
pub extend CommandSettings with ToJson::{to_json}

///|
pub extend CommandSettings with FromJson::{from_json}
