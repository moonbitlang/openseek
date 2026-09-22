// Transport-agnostic host operations: file browsing, language services,
// skills, self-update, app launching, and connection-owned filesystem/PTY
// state. Typed payloads enter here only after an Endpoint has decoded them.

///|
/// A host-side failure with a user-facing message. Ops raise it; the
/// transport boundary stringifies it into the error the client displays.
pub(all) suberror HostError {
  HostError(String)
} derive(Debug)

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
} derive(Debug)

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
  text_search : TextSearchService
  semantic_search : SemanticSearchService
  terminal : @terminal.TerminalState
}

///|
pub fn HostConnection::HostConnection() -> HostConnection {
  {
    fs_watch: FsWatchActor(),
    file_search: FileSearchService(),
    text_search: TextSearchService(),
    semantic_search: SemanticSearchService(),
    terminal: @terminal.new_terminal_state(),
  }
}

///|
/// `engine` is the engine executable (the language services resolve the
/// bundled `moon` next to it); `executable` is the host's own binary, which
/// only self-update needs, because replacing the running application is the
/// one job whose meaning depends on this exact process. Absent paths retain
/// development fallbacks but disable installed-only work. Proton owns
/// resource-directory resolution directly in the operations that need it.
pub fn new_host_state(
  engine : String,
  runtime_dir? : @pathx.Path,
  executable? : String,
  app_version? : String = "development",
) -> HostState {
  {
    engine,
    runtime_dir,
    moon: MoonCliState(engine, runtime_dir?),
    updates: SelfUpdate(runtime_dir, executable, app_version~),
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
    state.moon.forward_diagnostics(push => {
      emit(
        LspDiagnostics({
          root: push.root,
          path: push.path,
          diagnostics: push.diagnostics,
        }),
      )
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
  emit_progress : async (@protocol.Notification) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    // Closing the request queue is the terminal pump's normal connection-end
    // signal. It must not be tied to the page-reload session sweep below.
    defer self.terminal.shutdown()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(self.terminal, push => {
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
            let payload : TerminalExitPayload = { id, code, }
            emit(TerminalExit({ id: payload.id, code: payload.code, }))
          }
        }
      })
    })
    group.spawn_bg(() => self.file_search.run())
    group.spawn_bg(() => self.text_search.run())
    group.spawn_bg(() => self.semantic_search.run(emit_progress))
    self.fs_watch.run(
      push => {
        emit(
          FsChanged({
            root: push.root,
            baseline: push.baseline,
            events: push.events.map(event => {
              kind_: event.kind_,
              path: event.path,
              old_path: event.old_path,
            }),
            generation: push.generation,
          }),
        )
      },
      failure => {
        emit(
          FsWatchFailed({
            root: failure.root,
            message: failure.message,
            generation: failure.generation,
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
  manager : @engine.EngineManager,
  on_skills_changed : () -> Unit,
) -> Array[@endpoint.Endpoint] {
  [
    Endpoint(@commands.fs_read_file, payload => read_file_op(payload)),
    Endpoint(@commands.fs_materialize_semantic_selection, payload => {
      materialize_semantic_selection_op(payload)
    }),
    Endpoint(@commands.fs_read_directory, payload => read_directory_op(payload)),
    Endpoint(@commands.fs_search_files, payload => {
      search_files_op(connection.file_search, payload)
    }),
    Endpoint(@commands.fs_cancel_search_files, payload => {
      cancel_search_files_op(connection.file_search, payload)
    }),
    Endpoint(@commands.fs_search_text, payload => {
      search_text_op(connection.text_search, payload)
    }),
    Endpoint(@commands.fs_cancel_search_text, payload => {
      cancel_search_text_op(connection.text_search, payload)
    }),
    Endpoint(@commands.fs_search_semantic, payload => {
      search_semantic_op(connection.semantic_search, payload)
    }),
    Endpoint(@commands.fs_cancel_search_semantic, payload => {
      cancel_search_semantic_op(connection.semantic_search, payload)
    }),
    Endpoint(@commands.pattern_repair, payload => {
      match @engine.pattern_repair_environment(manager, model=payload.model) {
        Ready(env) => pattern_repair_op(state, env, payload)
        Configuration(message) =>
          pattern_repair_failure(payload, Unavailable, None, message, [])
        Unavailable =>
          pattern_repair_failure(
            payload,
            Unavailable,
            None,
            "Pattern Repair settings are unavailable.",
            [],
          )
      }
    }),
    Endpoint(@commands.fs_clear_file_search_cache, payload => {
      clear_file_search_cache_op(connection.file_search, payload)
    }),
    Endpoint(@commands.fs_stat_files, payload => stat_files_op(payload)),
    Endpoint(@commands.fs_watch, payload => {
      connection.fs_watch.watch(payload)
      Acknowledged
    }),
    Endpoint(@commands.fs_unwatch, _ => {
      connection.fs_watch.unwatch()
      Acknowledged
    }),
    Endpoint(@commands.fs_browse, payload => browse_directory_op(payload)),
    Endpoint(@commands.fs_create_unnamed_workspace, _ => {
      create_unnamed_workspace_op()
    }),
    Endpoint(@commands.fs_create_directory, payload => {
      create_directory_op(payload)
    }),
    Endpoint(@commands.terminal_open, payload => {
      terminal_open_op(state, connection.terminal, payload)
    }),
    Endpoint(@commands.terminal_input, payload => {
      terminal_input_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_resize, payload => {
      terminal_resize_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_ack, payload => {
      terminal_ack_op(connection.terminal, payload)
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_close, payload => {
      terminal_close_op(connection.terminal, payload)
      Acknowledged
    }),
    Endpoint(@commands.moon_package_graph, payload => {
      moon_package_graph_op(state.moon, payload)
    }),
    Endpoint(@commands.lsp_open, payload => lsp_open_op(state.moon, payload)),
    Endpoint(@commands.lsp_hover, payload => lsp_hover_op(state.moon, payload)),
    Endpoint(@commands.lsp_workspace_symbols, payload => {
      workspace_symbols_op(state.moon, payload)
    }),
    Endpoint(@commands.moonide_definition, payload => {
      moonide_definition_op(state, payload)
    }),
    Endpoint(@commands.moonide_references, payload => {
      moonide_references_op(state, payload)
    }),
    Endpoint(@commands.moonide_codelens, payload => {
      moonide_codelens_op(state, payload)
    }),
    Endpoint(@commands.skills_catalog, _ => skills_catalog_op()),
    Endpoint(@commands.skills_content, payload => skills_content_op(payload)),
    Endpoint(@commands.skills_installed_content, payload => {
      installed_skill_content_op(payload)
    }),
    Endpoint(@commands.skills_installed, _ => installed_skills_op()),
    Endpoint(@commands.skills_install, payload => {
      install_skill_op(payload, on_skills_changed)
    }),
    Endpoint(@commands.skills_uninstall, payload => {
      uninstall_skill_op(payload, on_skills_changed)
    }),
    Endpoint(@commands.update_check, _ => state.updates.check()),
    @endpoint.Endpoint::sync(@commands.update_download, _ => {
      state.updates.start_download()
    }),
    Endpoint(@commands.update_apply, _ => state.updates.apply()),
    Endpoint(@commands.git_branch, payload => git_branch_op(payload)),
    Endpoint(@commands.git_pull_request, payload => git_pull_request_op(payload)),
    Endpoint(@commands.github_list, payload => github_list_op(payload)),
    Endpoint(@commands.github_review, payload => github_review_op(payload)),
    Endpoint(@commands.github_review_file, payload => {
      github_review_file_op(payload)
    }),
    Endpoint(@commands.github_review_mutate, payload => {
      github_review_mutate_op(payload)
    }),
    Endpoint(@commands.github_pull_request, payload => {
      github_pull_request_op(payload)
    }),
    Endpoint(@commands.github_checkout, payload => github_checkout_op(payload)),
    Endpoint(@commands.github_checkout_status, payload => {
      github_checkout_status_op(payload)
    }),
    Endpoint(@commands.git_changes, payload => git_changes_op(payload)),
    Endpoint(@commands.git_history, payload => git_history_op(payload)),
    Endpoint(@commands.git_commit_changes, payload => {
      git_commit_changes_op(payload)
    }),
    Endpoint(@commands.git_original_file, payload => {
      git_original_file_op(payload)
    }),
    Endpoint(@commands.host_open_path, payload => open_path_op(payload)),
    Endpoint(@commands.host_reveal_path, payload => reveal_path_op(payload)),
  ]
}

///|
pub extend HostError with Debug::{to_repr}

///|
pub extend PayloadError with Debug::{to_repr}
