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
/// The host ops' process-wide state: the moon-CLI state behind the language
/// services (hover, check diagnostics, symbol search), the engine identity
/// the Moon IDE navigation ops resolve their `moon` from, and the
/// self-update staging state. Filesystem watches are connection-owned below,
/// because two clients may watch different workspaces at the same time.
struct HostState {
  engine : String
  runtime_dir : @pathx.Path?
  moon : MoonCliState
  updates : SelfUpdate
}

///|
/// State owned by one client connection. A desktop page and each remote
/// WebSocket create separate values, so filesystem watches and PTY sessions
/// cannot leak into another client.
struct HostConnection {
  fs_watch : FsWatchActor
  file_search : FileSearchService
  terminal : @terminal.TerminalState
}

///|
pub fn HostConnection::new() -> HostConnection {
  {
    fs_watch: FsWatchActor::new(),
    file_search: FileSearchService::new(),
    terminal: @terminal.new_terminal_state(),
  }
}

///|
/// `engine` is the engine executable (the language services resolve the
/// bundled `moon` next to it); `executable` is the host's own binary, which
/// self-update uses to locate the running .app bundle (absent or non-bundle
/// layouts only lose the in-app install, never the announcement).
pub fn new_host_state(
  engine : String,
  runtime_dir? : @pathx.Path,
  executable? : String,
  app_version? : String = "development",
) -> HostState {
  {
    engine,
    runtime_dir,
    moon: MoonCliState::new(engine, runtime_dir?),
    updates: SelfUpdate::new(runtime_dir, executable, app_version~),
  }
}

///|
/// The background tasks behind the host ops, spawned into the caller's
/// app-lifetime task group: the moon-check diagnostics forwarder and the
/// self-update pump with its startup leftover sweep. These are shared by
/// every connection;
/// connection-owned filesystem watcher tasks start in `HostConnection::run`.
/// Every background task is best-effort: a language-service hiccup degrades
/// that feature, never the connection.
pub fn[G] spawn_host_pumps(
  group : @async.TaskGroup[G],
  state : HostState,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  group.spawn_bg(allow_failure=true, () => {
    state.moon.forward_diagnostics(async fn(push) {
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
    group.spawn_bg(() => self.file_search.run())
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
/// Host-owned endpoints are assembled next to the private operations they
/// invoke. The API package concatenates this catalog with engine/auth
/// endpoints, so these operations do not need one public forwarding method
/// apiece.
pub fn endpoints(
  state : HostState,
  connection : HostConnection,
  on_skills_changed : () -> Unit,
) -> Array[@endpoint.Endpoint] {
  [
    @endpoint.Endpoint::remote(@commands.fs_read_file, async fn(payload) {
      read_file_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_read_directory, async fn(payload) {
      read_directory_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_search_files, async fn(payload) {
      search_files_op(connection.file_search, payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_cancel_search_files, async fn(
      payload,
    ) {
      cancel_search_files_op(connection.file_search, payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_clear_file_search_cache, async fn(
      payload,
    ) {
      clear_file_search_cache_op(connection.file_search, payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_stat_files, async fn(payload) {
      stat_files_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_watch, async fn(payload) {
      connection.fs_watch.watch(payload)
      Acknowledged
    }),
    @endpoint.Endpoint::remote(@commands.fs_unwatch, async fn(_) {
      connection.fs_watch.unwatch()
      Acknowledged
    }),
    @endpoint.Endpoint::remote(@commands.fs_browse, async fn(payload) {
      browse_directory_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.terminal_open, async fn(payload) {
      terminal_open_op(connection.terminal, payload)
    }),
    @endpoint.Endpoint::remote(@commands.terminal_input, async fn(payload) {
      terminal_input_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::remote_sync(@commands.terminal_resize, payload => {
      terminal_resize_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::remote_sync(@commands.terminal_ack, payload => {
      terminal_ack_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::remote_sync(@commands.terminal_close, payload => {
      terminal_close_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::remote(@commands.lsp_open, async fn(payload) {
      lsp_open_op(state.moon, payload)
    }),
    @endpoint.Endpoint::remote(@commands.lsp_hover, async fn(payload) {
      lsp_hover_op(state.moon, payload)
    }),
    @endpoint.Endpoint::remote(@commands.lsp_workspace_symbols, async fn(
      payload,
    ) {
      workspace_symbols_op(state.moon, payload)
    }),
    @endpoint.Endpoint::remote(@commands.moonide_definition, async fn(payload) {
      moonide_definition_op(state, payload)
    }),
    @endpoint.Endpoint::remote(@commands.moonide_references, async fn(payload) {
      moonide_references_op(state, payload)
    }),
    @endpoint.Endpoint::remote(@commands.skills_catalog, async fn(_) {
      skills_catalog_op()
    }),
    @endpoint.Endpoint::remote(@commands.skills_installed, async fn(_) {
      installed_skills_op()
    }),
    @endpoint.Endpoint::remote(@commands.skills_install, async fn(payload) {
      install_skill_op(payload, on_skills_changed)
    }),
    @endpoint.Endpoint::remote(@commands.skills_uninstall, async fn(payload) {
      uninstall_skill_op(payload, on_skills_changed)
    }),
    @endpoint.Endpoint::remote(@commands.update_check, async fn(payload) {
      state.updates.check(payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.update_download, payload => {
      state.updates.start_download(payload)
    }),
    @endpoint.Endpoint::remote(@commands.update_apply, async fn(_) {
      state.updates.apply()
    }),
    @endpoint.Endpoint::remote(@commands.app_list, async fn(_) {
      list_apps_op()
    }),
    @endpoint.Endpoint::remote(@commands.app_launch, async fn(payload) {
      launch_app_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.git_branch, async fn(payload) {
      git_branch_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.git_pull_request, async fn(payload) {
      git_pull_request_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.git_changes, async fn(payload) {
      git_changes_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.git_original_file, async fn(payload) {
      git_original_file_op(payload)
    }),
    @endpoint.Endpoint::remote(@commands.host_open_path, async fn(payload) {
      open_path_op(payload)
    }),
  ]
}
