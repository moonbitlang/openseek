// Deliberate exports whose consumers `moon ide analyze` cannot see (see
// shrink_package.md). The window host in `desktop/app` builds in its own
// `desktop/app/moon.work`, outside the root workspace this package is measured
// in, so its uses of these blocks never reach the analyzer; one block is a
// test seam another package's suite drives. Each entry names its consumer.

///|
/// The engine executable to run. Installed apps use canonical `seekmoon/`
/// below the resource directory. The supported development launcher
/// declares `desktop/` as that directory and always builds the native debug
/// host and engine together, so no executable path needs to cross this API.
///
/// Exported for the window host, which resolves it once at startup to launch
/// the engine (`desktop/app/main.mbt`).
pub async fn engine_command(resources : @resources.Resources) -> String {
  if resources.packaged {
    return resources.dir.join(PackagedEnginePath).normalize().to_string()
  }
  let engine_dir = resources.dir
    .dirname()
    .join("_build/native/debug/build/moonbitlang/openseek")
  for candidate in ["openseek.exe", "openseek"] {
    let path = engine_dir.join(candidate).normalize().to_string()
    if @fs.exists(path) {
      return path
    }
  }
  DefaultEngine
}

///|
/// Forward only the selected local credential through the released CLI's
/// existing key variables. The remote host keeps its own endpoint settings
/// and uses this credential only where its normal environment fallback applies.
///
/// Exported for the window host's remote-session settings
/// (`desktop/app/internal/extension/extension.mbt`).
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

///|
/// Render the captured records once, sharing the serialized dataset between
/// the standalone HTML and the downloadable JSON.
///
/// Test seam: `desktop/backend/api/session_share_wbtest.mbt` builds an export
/// from its own fixtures instead of reading a real session.
pub fn ConversationExport::ConversationExport(
  exporter : @viz_export.StandaloneExport,
  sessions : Array[@viz_export.Session],
) -> ConversationExport raise {
  let json = exporter.json(sessions)
  { html: exporter.render_json(json), json, }
}
