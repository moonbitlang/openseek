///|
/// Forward only the selected local credential through the released CLI's
/// existing key variables. The remote host keeps its own endpoint settings
/// and uses this credential only where its normal environment fallback applies.
pub async fn ssh_model_credentials(
  manager : EngineManager,
) -> Map[String, String] {
  let (settings, _) = manager.settings_snapshot()
  let (name, key) = match settings.provider {
    Deepseek => {
      let key = match settings.deepseek_api_key {
        Some(_) as key => key
        None => @env.get("DEEPSEEK")
      }
      ("DEEPSEEK", key)
    }
    Glm => {
      let key = match settings.glm_api_key {
        Some(_) as key => key
        None => @env.get("GLM")
      }
      ("GLM", key)
    }
    Custom => {
      let model = @env.get("OPENSEEK_MODEL").unwrap_or(
        settings.provider.default_model(),
      )
      (model_key_env(model), settings.custom_api_key)
    }
  }
  let values : Map[String, String] = Map([])
  if key is Some(key) {
    values[name] = key
  }
  values
}
