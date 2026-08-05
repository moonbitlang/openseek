// Transport-agnostic host operations: file browsing, language services,
// skills, self-update, app launching, and connection-owned filesystem/PTY
// state. Typed payloads enter here only after an Endpoint has decoded them.

///|
/// A host-side failure with a user-facing message. Ops raise it; the
/// transport boundary stringifies it into the error the client displays.
pub(all) suberror HostError {
  HostError(String)
}

///|
impl Show for HostError with fn output(self, logger) {
  match self {
    HostError(message) => logger.write_string(message)
  }
}

///|
/// A request payload that failed to decode — the client sent a shape the
/// method does not accept. Kept apart from `HostError` so transports can
/// report it as a malformed request (JSON-RPC -32602) rather than a failed
/// operation.
pub(all) suberror PayloadError {
  PayloadError(String)
}

///|
impl Show for PayloadError with fn output(self, logger) {
  match self {
    PayloadError(message) => logger.write_string(message)
  }
}

///|
/// The host ops' process-wide state: the language-server pool and the
/// self-update staging state. Filesystem watches are connection-owned below,
/// because two clients may watch different workspaces at the same time.
struct HostState {
  engine : String
  runtime_dir : @path.Path?
  lsp : LspPoolActor
  updates : SelfUpdate
}

///|
/// State owned by one client connection. A desktop page and each remote
/// WebSocket create separate values, so filesystem watches and PTY sessions
/// cannot leak into another client.
struct HostConnection {
  fs_watch : FsWatchActor
  terminal : @terminal.TerminalState
}

///|
pub fn HostConnection::new() -> HostConnection {
  { fs_watch: FsWatchActor::new(), terminal: @terminal.new_terminal_state() }
}

///|
/// `engine` is the engine executable (the LSP pool spawns the bundled
/// `moon-lsp` resolved next to it); `executable` is the host's own binary,
/// which self-update uses to locate the running .app bundle (absent or
/// non-bundle layouts only lose the in-app install, never the announcement).
pub fn new_host_state(
  engine : String,
  runtime_dir? : @path.Path,
  executable? : String,
) -> HostState {
  let lsp = LspPoolActor::new(engine, runtime_dir?)
  // Mirror LSP wire traffic to its own log next to the host's runtime
  // state, so a broken hover/symbol round-trip can be read back without the
  // per-message noise landing in the main app log.
  if runtime_dir is Some(dir) {
    @lsp.enable_traffic_log(dir.join("lsp.log").to_string())
  }
  {
    engine,
    runtime_dir,
    lsp,
    updates: SelfUpdate::new(runtime_dir, executable),
  }
}

///|
/// The background tasks behind the host ops, spawned into the caller's
/// app-lifetime task group: the LSP pool actor, diagnostics forwarder, and the
/// self-update pump with its startup leftover sweep. These are shared by every
/// connection;
/// connection-owned filesystem watcher tasks start in `HostConnection::run`.
/// Every background task is best-effort: a language-service hiccup degrades
/// that feature, never the connection.
pub fn[G] spawn_host_pumps(
  group : @async.TaskGroup[G],
  state : HostState,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  group.spawn_bg(allow_failure=true, () => state.lsp.run())
  group.spawn_bg(allow_failure=true, () => {
    state.lsp.forward_diagnostics(async fn(push) {
      emit(LspDiagnostics({ path: push.path, diagnostics: push.diagnostics }))
    })
  })
  group.spawn_bg(allow_failure=true, () => state.updates.run(emit))
}

///|
/// Run the filesystem watcher and PTY pump owned by this connection. Their
/// notifications return only to the same transport instead of entering the
/// process-wide hub.
pub async fn HostConnection::run(
  self : HostConnection,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    // Closing the request queue is the terminal pump's normal connection-end
    // signal. It must not be tied to the page-reload session sweep below.
    defer self.terminal.shutdown()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(self.terminal, async fn(push) {
        match push {
          Output(id~, sequence~, data~) => {
            let payload : TerminalOutputPayload = {
              id,
              sequence,
              data: @base64.encode(data),
            }
            emit(
              TerminalOutput({
                id: payload.id,
                sequence: payload.sequence,
                data: payload.data,
              }),
            )
          }
          Exited(id~, code~) => {
            let payload : TerminalExitPayload = { id, code }
            emit(TerminalExit({ id: payload.id, code: payload.code }))
          }
        }
      })
    })
    self.fs_watch.run(
      async fn(push) {
        emit(
          FsChanged({
            session: Some(push.session),
            root: Some(push.root),
            baseline: Some(push.baseline),
            events: Some(
              push.events.map(event => {
                kind_: event.kind_,
                path: event.path,
                old_path: event.old_path,
              }),
            ),
          }),
        )
      },
      async fn(failure) {
        emit(
          FsWatchFailed({
            session: failure.session,
            root: failure.root,
            message: failure.message,
          }),
        )
      },
    )
  })
}

///|
/// A desktop page reload cannot reclaim its old emulator instances. Retire
/// those PTYs before attaching the new page; WebSocket-owned sessions are
/// cancelled automatically with their connection task group.
pub fn HostConnection::close_terminals(self : HostConnection) -> Unit {
  @terminal.close_all_terminals(self.terminal)
}

///|
/// Typed host methods are the native API consumed by the endpoint registry.
/// Transport names and JSON never enter this package.
pub async fn skills_catalog() -> @protocol.SkillsCatalogReply {
  skills_catalog_op()
}

///|
pub async fn skills_install(
  payload : @protocol.InstallSkillPayload,
  on_changed : () -> Unit,
) -> @protocol.InstallSkillReply {
  install_skill_op(payload, on_changed)
}

///|
pub async fn skills_installed() -> @protocol.InstalledSkillsReply {
  installed_skills_op()
}

///|
pub async fn skills_uninstall(
  payload : @protocol.UninstallSkillPayload,
  on_changed : () -> Unit,
) -> @protocol.UninstallSkillReply {
  uninstall_skill_op(payload, on_changed)
}

///|
pub async fn open_path(
  payload : @protocol.OpenPathPayload,
) -> @protocol.OpenPathReply {
  open_path_op(payload)
}

///|
pub async fn HostState::update_check(
  self : HostState,
  payload : @protocol.UpdateChannelPayload,
) -> @protocol.CheckUpdateReply {
  self.updates.check(payload)
}

///|
pub fn HostState::update_download(
  self : HostState,
  payload : @protocol.UpdateChannelPayload,
) -> @protocol.DownloadUpdateAcceptedReply raise {
  self.updates.start_download(payload)
}

///|
pub async fn HostState::update_apply(
  self : HostState,
) -> @protocol.ApplyUpdateReply {
  self.updates.apply()
}

///|
pub async fn git_branch_info(
  payload : @protocol.GitBranchPayload,
) -> @protocol.GitBranchReply {
  git_branch_op(payload)
}

///|
pub async fn app_list() -> @protocol.ListAppsReply {
  list_apps_op()
}

///|
pub async fn app_launch(
  payload : @protocol.LaunchAppPayload,
) -> @protocol.LaunchAppReply {
  launch_app_op(payload)
}

///|
pub async fn read_directory(
  payload : @protocol.ReadDirPayload,
) -> @protocol.ReadDirReply {
  read_directory_op(payload)
}

///|
pub async fn list_files(
  payload : @protocol.ListFilesPayload,
) -> @protocol.ListFilesReply {
  list_files_op(payload)
}

///|
pub async fn read_file(
  payload : @protocol.ReadFilePayload,
) -> @protocol.ReadFileReply {
  read_file_op(payload)
}

///|
pub async fn stat_files(
  payload : @protocol.StatFilesPayload,
) -> @protocol.StatFilesReply {
  stat_files_op(payload)
}

///|
pub async fn HostConnection::watch(
  self : HostConnection,
  payload : @protocol.WatchWorkspacePayload,
) -> @protocol.EmptyReply {
  self.fs_watch.watch(payload)
  Acknowledged
}

///|
pub async fn HostConnection::unwatch(
  self : HostConnection,
) -> @protocol.EmptyReply {
  self.fs_watch.unwatch()
  Acknowledged
}

///|
pub async fn HostConnection::terminal_open(
  self : HostConnection,
  payload : @protocol.TerminalOpenPayload,
) -> @protocol.TerminalOpenReply {
  terminal_open_op(self.terminal, payload)
}

///|
pub async fn HostConnection::terminal_input(
  self : HostConnection,
  payload : @protocol.TerminalInputPayload,
) -> @protocol.EmptyReply {
  terminal_input_op(self.terminal, payload)
  Acknowledged
}

///|
pub fn HostConnection::terminal_resize(
  self : HostConnection,
  payload : @protocol.TerminalResizePayload,
) -> @protocol.EmptyReply raise {
  terminal_resize_op(self.terminal, payload)
  Acknowledged
}

///|
pub fn HostConnection::terminal_ack(
  self : HostConnection,
  payload : @protocol.TerminalAckPayload,
) -> @protocol.EmptyReply {
  terminal_ack_op(self.terminal, payload)
  Acknowledged
}

///|
pub fn HostConnection::terminal_close(
  self : HostConnection,
  payload : @protocol.TerminalClosePayload,
) -> @protocol.EmptyReply {
  terminal_close_op(self.terminal, payload)
  Acknowledged
}

///|
pub async fn HostState::lsp_hover(
  self : HostState,
  payload : @protocol.LspHoverPayload,
) -> @protocol.LspHoverReply {
  lsp_hover_op(self.lsp, payload)
}

///|
pub async fn HostState::lsp_open(
  self : HostState,
  payload : @protocol.LspOpenPayload,
) -> @protocol.LspDiagnosticsReply {
  lsp_open_op(self.lsp, payload)
}

///|
pub async fn HostState::lsp_workspace_symbols(
  self : HostState,
  payload : @protocol.WorkspaceSymbolsPayload,
) -> @protocol.WorkspaceSymbolsReply {
  workspace_symbols_op(self.lsp, payload)
}

///|
pub async fn HostState::moonide_definition(
  self : HostState,
  payload : @protocol.MoonIdeNavigationPayload,
) -> @protocol.MoonIdeLocationsReply {
  moonide_definition_op(self, payload)
}

///|
pub async fn HostState::moonide_references(
  self : HostState,
  payload : @protocol.MoonIdeNavigationPayload,
) -> @protocol.MoonIdeLocationsReply {
  moonide_references_op(self, payload)
}

///|
pub async fn browse_directory(
  payload : @protocol.BrowseDirectoryPayload,
) -> @protocol.BrowseDirectoryReply {
  browse_directory_op(payload)
}
