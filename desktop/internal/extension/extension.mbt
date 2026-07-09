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
/// to a fresh engine manager. `engine` is the engine executable to spawn;
/// `executable` is the host's own binary, which self-update uses to locate
/// the running .app bundle (absent or non-bundle layouts only lose the
/// in-app install, never the announcement).
pub fn openseek_extension(
  engine : String,
  runtime_dir? : @path.Path,
  executable? : String,
) -> @app.AppCommandExtensionSpec {
  let manager = @engine.new_engine_manager(engine, runtime_dir?)
  let lsp = new_lsp_manager(engine, runtime_dir?)
  let updates = new_update_state(runtime_dir, executable)
  let watches = new_watch_state()
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
      @app.AppCommandApiDescriptor::new("list_workspaces"),
      @app.AppCommandApiDescriptor::new("add_workspace"),
      @app.AppCommandApiDescriptor::new("remove_workspace"),
      @app.AppCommandApiDescriptor::new("pick_workspace"),
      @app.AppCommandApiDescriptor::new("skills_catalog"),
      @app.AppCommandApiDescriptor::new("skill_install"),
      @app.AppCommandApiDescriptor::new("skills_installed"),
      @app.AppCommandApiDescriptor::new("skill_uninstall"),
      @app.AppCommandApiDescriptor::new("open_path"),
      @app.AppCommandApiDescriptor::new("check_update"),
      @app.AppCommandApiDescriptor::new("download_update"),
      @app.AppCommandApiDescriptor::new("apply_update"),
      @app.AppCommandApiDescriptor::new("workspace_branch"),
      @app.AppCommandApiDescriptor::new("archive_session"),
      @app.AppCommandApiDescriptor::new("unarchive_session"),
      @app.AppCommandApiDescriptor::new("archived_sessions"),
      @app.AppCommandApiDescriptor::new("list_apps"),
      @app.AppCommandApiDescriptor::new("launch_app"),
      @app.AppCommandApiDescriptor::new("read_directory"),
      @app.AppCommandApiDescriptor::new("list_files"),
      @app.AppCommandApiDescriptor::new("read_file"),
      @app.AppCommandApiDescriptor::new("stat_files"),
      @app.AppCommandApiDescriptor::new("watch_workspace"),
      @app.AppCommandApiDescriptor::new("hover"),
      @app.AppCommandApiDescriptor::new("lsp_open"),
      @app.AppCommandApiDescriptor::new("workspace_symbols"),
    ],
    context => {
      let sink = event_sink(context)
      context.op_async("connect", (_ : Json) => {
        // The connect op is the app-lifetime host task, so its group owns the
        // moon-lsp servers too: they run alongside the engine pump and are torn
        // down together when the webview disconnects. The LSP pump is
        // best-effort (`allow_failure`), so a hover/symbol subsystem hiccup
        // never drops the engine connection.
        @async.with_task_group(group => {
          group.spawn_bg(allow_failure=true, () => run_lsp_pump(group, lsp))
          group.spawn_bg(allow_failure=true, () => {
            run_diagnostics_pump(lsp, async fn(push) {
              context.emit("diagnostics", push)
            })
          })
          // The workspace watcher behind the editor panel's live updates —
          // best-effort for the same reason as the LSP pumps.
          group.spawn_bg(allow_failure=true, () => {
            run_watch_pump(watches, async fn(push) {
              context.emit("fs_changed", push)
            })
          })
          // Sweep what a previous update left behind; checking for new
          // releases is the frontend's call (`check_update`), not the
          // host's.
          group.spawn_bg(allow_failure=true, () => cleanup_updates(updates))
          @engine.run_engine_pump(sink, manager) catch {
            @engine.EngineError(message) => raise HostError(message)
            error => raise error
          }
        })
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
      context.op_async("list_workspaces", async fn(_ : Json) {
        @engine.list_workspaces() catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("add_workspace", async fn(payload : WorkspacePayload) {
        @engine.attach_workspace(payload.path) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async("remove_workspace", async fn(
        payload : WorkspacePayload,
      ) {
        @engine.detach_workspace(payload.path) catch {
          @engine.EngineError(message) => raise HostError(message)
          error => raise error
        }
      })
      context.op_async_result_with_context("pick_workspace", async fn(
        request_context : @app.AppCommandRequestContext,
        _ : Json,
      ) {
        pick_workspace_op(request_context)
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
      context.op_async("check_update", async fn(
        payload : UpdateChannelPayload,
      ) {
        check_update_op(updates, payload)
      })
      context.op_async("download_update", async fn(
        payload : UpdateChannelPayload,
      ) {
        download_update_op(updates, payload)
      })
      context.op_async("apply_update", async fn(_ : Json) {
        apply_update_op(updates)
      })
      context.op_async("workspace_branch", async fn(
        payload : WorkspaceBranchPayload,
      ) {
        workspace_branch_op(payload)
      })
      context.op_async("archive_session", async fn(
        payload : ArchiveSessionPayload,
      ) {
        archive_session_op(manager, payload)
      })
      context.op_async("unarchive_session", async fn(
        payload : ArchiveSessionPayload,
      ) {
        unarchive_session_op(manager, payload)
      })
      context.op_async("archived_sessions", async fn(_ : Json) {
        archived_sessions_op(manager)
      })
      context.op_async("list_apps", async fn(_ : Json) { list_apps_op() })
      context.op_async("launch_app", async fn(payload : LaunchAppPayload) {
        launch_app_op(payload)
      })
      context.op_async("read_directory", async fn(payload : ReadDirPayload) {
        read_directory_op(payload)
      })
      context.op_async("list_files", async fn(payload : ListFilesPayload) {
        list_files_op(payload)
      })
      context.op_async("read_file", async fn(payload : ReadFilePayload) {
        read_file_op(payload)
      })
      context.op_async("stat_files", async fn(payload : StatFilesPayload) {
        stat_files_op(payload)
      })
      context.op_async("watch_workspace", async fn(
        payload : WatchWorkspacePayload,
      ) {
        watch_workspace_op(watches, payload)
      })
      context.op_async("hover", async fn(payload : LspHoverPayload) {
        lsp_hover_op(lsp, payload)
      })
      context.op_async("lsp_open", async fn(payload : LspOpenPayload) {
        lsp_open_op(lsp, payload)
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
