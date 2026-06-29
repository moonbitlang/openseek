// The package's public face: the proton command-extension spec that exposes
// the host to the webview, and the error type its op boundary translates.

///|
/// The extension id; the proton app enables it under this name.
pub const ExtensionId = "openseek-desktop"

///|
const ExtensionNamespace = "openseek"

///|
/// A host-side failure with a user-facing message. Ops raise it; the IPC
/// boundary stringifies it into the `Err` the webview displays.
priv suberror HostError {
  HostError(String)
}

///|
impl Show for HostError with fn output(self, logger) {
  match self {
    HostError(message) => logger.write_string(message)
  }
}

///|
/// The `openseek` IPC extension: every command the webview can invoke, bound
/// to a fresh engine manager. `engine` is the engine executable to spawn.
pub fn openseek_extension(
  engine : String,
  runtime_dir? : @path.Path,
) -> @app.AppCommandExtensionSpec {
  let manager = @engine.new_engine_manager(engine, runtime_dir?)
  let lsp = new_lsp_manager(engine, runtime_dir?)
  // Mirror LSP wire traffic to its own log next to the host's runtime state, so
  // a broken hover/symbol round-trip can be read back without the per-message
  // noise landing in the main app log.
  if runtime_dir is Some(dir) {
    @lsp.enable_traffic_log(dir.join("lsp.log").to_string())
  }
  @app.AppCommandExtensionSpec::new(
    ExtensionId,
    ExtensionNamespace,
    [
      @app.AppCommandApiDescriptor::new("connect"),
      @app.AppCommandApiDescriptor::new("start"),
      @app.AppCommandApiDescriptor::new("cancel"),
      @app.AppCommandApiDescriptor::new("steer"),
      @app.AppCommandApiDescriptor::new("compact"),
      @app.AppCommandApiDescriptor::new("list_sessions"),
      @app.AppCommandApiDescriptor::new("load_session"),
      @app.AppCommandApiDescriptor::new("skills_catalog"),
      @app.AppCommandApiDescriptor::new("skill_install"),
      @app.AppCommandApiDescriptor::new("skills_installed"),
      @app.AppCommandApiDescriptor::new("skill_uninstall"),
      @app.AppCommandApiDescriptor::new("open_path"),
      @app.AppCommandApiDescriptor::new("list_apps"),
      @app.AppCommandApiDescriptor::new("launch_app"),
      @app.AppCommandApiDescriptor::new("read_directory"),
      @app.AppCommandApiDescriptor::new("read_file"),
      @app.AppCommandApiDescriptor::new("hover"),
      @app.AppCommandApiDescriptor::new("workspace_symbols"),
    ],
    context => {
      let sink = event_sink(context)
      context.op_async("connect", (_ : Json) => {
        @engine.run_engine_pump(sink, manager) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("start", (payload : StartPayload) => {
        @engine.start_run(sink, manager, payload.to_request()) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("cancel", async fn(payload : CancelPayload) {
        @engine.cancel_run(manager, payload.to_request()) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("steer", async fn(payload : SteerPayload) {
        @engine.steer_run(manager, payload.to_request()) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("compact", async fn(payload : CompactPayload) {
        @engine.compact_run(manager, payload.to_request()) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("list_sessions", async fn(_ : Json) {
        @engine.list_sessions(manager) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("load_session", async fn(payload : LoadSessionPayload) {
        @engine.load_session(manager, payload.to_request()) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("skills_catalog", async fn(_ : Json) {
        skills_catalog_op()
      })
      context.op_async("skill_install", async fn(
        payload : InstallSkillPayload,
      ) {
        install_skill_op(payload)
      })
      context.op_async("skills_installed", async fn(_ : Json) {
        installed_skills_op()
      })
      context.op_async("skill_uninstall", async fn(
        payload : UninstallSkillPayload,
      ) {
        uninstall_skill_op(payload)
      })
      context.op_async("open_path", async fn(payload : OpenPathPayload) {
        open_path_op(payload)
      })
      context.op_async("list_apps", async fn(_ : Json) { list_apps_op() })
      context.op_async("launch_app", async fn(payload : LaunchAppPayload) {
        launch_app_op(payload)
      })
      context.op_async("read_directory", async fn(payload : ReadDirPayload) {
        read_directory_op(payload)
      })
      context.op_async("read_file", async fn(payload : ReadFilePayload) {
        read_file_op(payload)
      })
      context.op_async("hover", async fn(payload : LspHoverPayload) {
        lsp_hover_op(lsp, payload)
      })
      context.op_async("workspace_symbols", async fn(
        payload : WorkspaceSymbolsPayload,
      ) {
        workspace_symbols_op(lsp, payload)
      })
      Ok(())
    },
  )
}
