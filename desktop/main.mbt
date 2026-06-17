///|
async fn main {
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  let log = launch_logger()
  log.info() <? { "message": "start" }
  if @app.is_framework_process() {
    log.info() <? { "message": "framework process start" }
    @menu.install_main_menu()
    match @app.run_framework_process_from_cli() {
      Ok(_) => log.info() <? { "message": "framework process exit ok" }
      Err(error) => {
        log.error() <? { "message": "framework process error", "error": error }
        abort(error)
      }
    }
    return
  }
  let frontend_entry = @appdirs.frontend_entry_path(framework_command)
  let engine = @appdirs.engine_command(framework_command)
  log.info() <? { "message": "host process start" }
  log.info() <? { "message": "frontend entry", "path": frontend_entry }
  log.info() <? { "message": "engine", "path": engine }
  let extensions : Map[String, @manifest.ExtensionSetting] = {}
  extensions[@host.ExtensionId] = @manifest.ExtensionSetting::enabled()
  extensions["justjavac/lepus-clipboard"] = @manifest.ExtensionSetting::enabled()
  let manifest = @manifest.AppManifest::new(
    @manifest.WindowManifest::new("OpenSeek Desktop", 1120, 760, size_hint=None),
    File(frontend_entry),
    debug=1,
    extensions~,
  )
  let registry = @app.AppCommandExtensionRegistry::new()
  let _ = registry.register(@host.openseek_extension(engine))
  let _ = registry.register(@clipboard.generated_app_command_extension())
  // Keep all runtime state out of the bundle: the framework IPC config is
  // written to the per-user runtime dir, and the framework child runs there
  // too, so neither process depends on the bundle directory being writable —
  // or on it continuing to exist while the app runs.
  let runtime_dir = @appdirs.prepared_runtime_dir()
  let framework_config_path = match runtime_dir {
    Some(dir) => {
      @appdirs.remove_stale_framework_configs(dir)
      Some("\{dir}/lepus-framework-\{@env.now()}.json")
    }
    None => None
  }
  match
    @app.run_app_command_extensions_with_framework_process(
      manifest,
      framework_command,
      registry,
      framework_args=[@app.framework_process_arg()],
      framework_cwd=runtime_dir,
      framework_config_path~,
    ) {
    Ok(_) => log.info() <? { "message": "host process exit ok" }
    Err(error) => {
      log.error() <? { "message": "host process error", "error": error }
      abort(error)
    }
  }
}
