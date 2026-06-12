///|
fn main {
  let framework_command = match @app.current_executable_command() {
    Ok(command) => command
    Err(error) => abort(error)
  }
  append_launch_log(framework_command, "start")
  if @app.is_framework_process() {
    append_launch_log(framework_command, "framework process start")
    match @app.run_framework_process_from_cli() {
      Ok(_) => append_launch_log(framework_command, "framework process exit ok")
      Err(error) => {
        append_launch_log(
          framework_command,
          "framework process error: " + error,
        )
        abort(error)
      }
    }
    return
  }
  let frontend_entry = @appdirs.frontend_entry_path(framework_command)
  let engine = @appdirs.engine_command(framework_command)
  append_launch_log(framework_command, "host process start")
  append_launch_log(framework_command, "frontend entry: " + frontend_entry)
  append_launch_log(framework_command, "engine: " + engine)
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
    Ok(_) => append_launch_log(framework_command, "host process exit ok")
    Err(error) => {
      append_launch_log(framework_command, "host process error: " + error)
      abort(error)
    }
  }
}
