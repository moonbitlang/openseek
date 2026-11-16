///|
const OpenRouterChatCompletionsUrl = "https://openrouter.ai/api/v1/chat/completions"

///|
priv struct Provider {
  api_url : String?
  api_key : String?
}

///|
fn EngineSettings::provider_config(
  self : EngineSettings,
  provider : ApiProvider,
) -> Provider {
  self.providers
  .get(provider.wire())
  .unwrap_or({ api_url: None, api_key: None, })
}

///|
/// Old OpenRouter presets occupied Custom's slot. Migrate that slot only to
/// OpenRouter; an older custom URL overwritten by the preset is not recoverable.
/// Keep unknown fields in both the outer object and provider objects.
fn migrate_provider_settings(raw : Map[String, Json]) -> Unit {
  if raw.get("providers") is Some(Object(_)) {
    return
  }
  if raw.get("version") is Some(Number(version, ..)) && version >= 3 {
    return
  }
  let providers : Map[String, Json] = Map([])
  for
    (name, legacy_key) in [
      ("deepseek", "deepseek_api_key"),
      ("glm", "glm_api_key"),
    ] {
    let fields : Map[String, Json] = Map([])
    if settings_text(raw, legacy_key) is Some(key) {
      fields["api_key"] = Json(key)
    }
    providers[name] = Json(fields)
  }
  let fields : Map[String, Json] = Map([])
  let url = settings_text(raw, "custom_api_url")
  let openrouter = url is Some(OpenRouterChatCompletionsUrl)
  if !openrouter && url is Some(url) {
    fields["api_url"] = Json(url)
  }
  if settings_text(raw, "custom_api_key") is Some(key) {
    fields["api_key"] = Json(key)
  }
  providers[if openrouter { "openrouter" } else { "custom" }] = Json(fields)
  if openrouter && settings_text(raw, "provider") is Some("custom") {
    raw["provider"] = Json("openrouter")
  }
  raw["providers"] = Json(providers)
  for
    key in [
      "deepseek_api_key", "glm_api_key", "custom_api_key", "custom_api_url",
    ] {
    raw.remove(key)
  }
}

///|
/// Root and version-root URLs are base URLs. Other paths are complete custom
/// endpoints and must not be rewritten. Queries belong after the appended path.
fn normalize_custom_api_url(value : String) -> String raise EngineError {
  let value = value.trim()
  let url = @url.Url::parse(value) catch {
    _ => raise EngineError("Enter a valid HTTP or HTTPS endpoint URL")
  }
  guard (url.scheme == "http" || url.scheme == "https") && url.host is Some(_) else {
    raise EngineError("Enter a valid HTTP or HTTPS endpoint URL")
  }
  guard url.fragment is None else {
    raise EngineError("Endpoint URL must not contain a fragment (#)")
  }
  let path = url.pathname().trim_end(chars="/").to_owned()
  if path.is_empty() || path =~ re"/v[0-9]+$" {
    url.set_pathname(path + "/chat/completions")
    url.to_string()
  } else {
    value.to_owned()
  }
}
