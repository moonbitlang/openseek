// Transport-agnostic host operations: file browsing, language services,
// skills, self-update, app launching, and connection-owned filesystem/PTY
// state. Typed payloads enter here only after an Endpoint has decoded them.

///|
/// A host-side failure with a user-facing message. Ops raise it; the
/// transport boundary stringifies it into the error the client displays.
#derive(Debug)
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
#derive(Debug)
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
  moon : @language.MoonCliState
  updates : SelfUpdate
  resources : HostResources
  skills : @skills.BuiltinSkills
}

///|
/// State owned by one client connection. A desktop page and each remote
/// WebSocket create separate values, so filesystem watches and PTY sessions
/// cannot leak into another client.
struct HostConnection {
  fs_watch : @files.Watcher
  file_search : @search.FileSearchService
  text_search : @search.TextSearchService
  semantic_search : @search.SemanticSearchService
  terminal : @terminal.TerminalState
}

///|
pub fn HostConnection::HostConnection() -> HostConnection {
  {
    fs_watch: Watcher(),
    file_search: FileSearchService(),
    text_search: TextSearchService(),
    semantic_search: SemanticSearchService(),
    terminal: TerminalState(),
  }
}

///|
/// `engine` is the engine executable; `resources` selects the tools and assets
/// this working host uses; `executable` is the host's own binary, which
/// only self-update needs, because replacing the running application is the
/// one job whose meaning depends on this exact process. Absent paths retain
/// external-tool defaults but disable installed-only work. Desktop callers
/// pass `desktop_resources`; other embedders provide explicit paths.
pub fn new_host_state(
  engine : String,
  runtime_dir? : @pathx.Path,
  executable? : String,
  app_version~ : String = "development",
  resources~ : HostResources = HostResources::from_path(),
) -> HostState {
  {
    engine,
    runtime_dir,
    moon: MoonCliState(engine, runtime_dir?, source=resources.moonbit),
    updates: SelfUpdate(runtime_dir, executable, app_version~),
    resources,
    skills: BuiltinSkills(),
  }
}

///|
/// Install or update the built-in skills once for this host, reporting each
/// library change through `on_changed`.
pub async fn HostState::sync_builtin_skills(
  self : HostState,
  on_changed : () -> Unit,
) -> Unit {
  self.skills.sync(on_changed)
}

///|
/// The background tasks behind the host ops, spawned into the caller's
/// app-lifetime task group: the moon-check diagnostics forwarder and the
/// self-update pump with its startup leftover sweep. These are shared by
/// every connection;
/// connection-owned filesystem watcher tasks start in `HostConnection::run`.
/// Every background task is best-effort: a language-service hiccup degrades
/// that feature, never the connection.
pub fn spawn_host_pumps(
  group : @async.TaskGroup,
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
      self.terminal.run_pump(push => {
        match push {
          Output(id~, sequence~, data~) =>
            emit(TerminalOutput({ id, sequence, data: @base64.encode(data), }))
          Exited(id~, code~) => emit(TerminalExit({ id, code, }))
        }
      })
    })
    group.spawn_bg(() => self.file_search.run())
    group.spawn_bg(() => self.text_search.run())
    group.spawn_bg(() => self.semantic_search.run(emit_progress))
    self.fs_watch.run(emit)
  })
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
    Endpoint(@commands.github_drafts_get, payload => {
      @github.read_drafts(
        state.runtime_dir.map(dir => dir.to_string()),
        payload,
      )
    }),
    Endpoint(@commands.github_drafts_set, payload => {
      @github.write_drafts(
        state.runtime_dir.map(dir => dir.to_string()),
        payload,
      )
    }),
    Endpoint(@commands.app_language_get, _ => {
      read_ui_language(state.runtime_dir.map(dir => dir.to_string()))
    }),
    Endpoint(@commands.app_language_set, payload => {
      write_ui_language(state.runtime_dir.map(dir => dir.to_string()), payload)
    }),
    Endpoint(@commands.fs_read_file, payload => @files.read_file(payload)),
    Endpoint(@commands.fs_prepare_attachment, payload => {
      @files.prepare_attachment(payload)
    }),
    Endpoint(@commands.fs_import_attachment, payload => {
      @files.import_attachment(payload)
    }),
    Endpoint(@commands.fs_stage_attachments, payload => {
      @files.stage_attachments(payload)
    }),
    Endpoint(@commands.fs_materialize_semantic_selection, payload => {
      @files.materialize_semantic_selection(payload)
    }),
    Endpoint(@commands.fs_read_directory, payload => {
      @files.read_directory(payload)
    }),
    Endpoint(@commands.fs_search_files, payload => {
      @search.search_files(
        connection.file_search,
        @pathx.Absolute::parse_resource_path(payload.path),
        payload,
      )
    }),
    Endpoint(@commands.fs_cancel_search_files, payload => {
      @search.cancel_search_files(connection.file_search, payload)
    }),
    Endpoint(@commands.fs_search_text, payload => {
      @search.search_text(
        state.moonx_provider(),
        connection.text_search,
        @pathx.Absolute::parse_resource_path(payload.root),
        payload,
      )
    }),
    Endpoint(@commands.fs_cancel_search_text, payload => {
      @search.cancel_search_text(connection.text_search, payload)
    }),
    Endpoint(@commands.fs_search_semantic, payload => {
      @search.search_semantic(
        connection.semantic_search,
        @pathx.Absolute::parse_resource_path(payload.root),
        payload,
        state.moonx_provider(),
      )
    }),
    Endpoint(@commands.fs_cancel_search_semantic, payload => {
      @search.cancel_search_semantic(connection.semantic_search, payload)
    }),
    Endpoint(@commands.pattern_repair, payload => {
      @pattern_repair.repair(
        state.engine,
        state.moonx_provider(),
        @engine.pattern_repair_environment(manager, model=payload.model),
        payload,
      )
    }),
    Endpoint(@commands.fs_clear_file_search_cache, payload => {
      @search.clear_file_search_cache(connection.file_search, payload)
    }),
    Endpoint(@commands.fs_stat_files, payload => @files.stat_files(payload)),
    Endpoint(@commands.fs_watch, payload => {
      connection.fs_watch.watch(payload)
      Acknowledged
    }),
    Endpoint(@commands.fs_unwatch, _ => {
      connection.fs_watch.unwatch()
      Acknowledged
    }),
    Endpoint(@commands.fs_browse, payload => @files.browse(payload)),
    Endpoint(@commands.fs_create_directory, payload => {
      @files.create_directory(payload)
    }),
    Endpoint(@commands.terminal_open, payload => {
      connection.terminal.open(
        payload,
        engine=state.engine,
        runtime_dir?=state.runtime_dir,
        source=state.resources.moonbit,
      )
    }),
    Endpoint(@commands.terminal_input, payload => {
      connection.terminal.input(payload)
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_resize, payload => {
      connection.terminal.resize(
        id=payload.id,
        cols=payload.cols,
        rows=payload.rows,
      )
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_ack, payload => {
      connection.terminal.ack(id=payload.id, sequence=payload.sequence)
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.terminal_close, payload => {
      connection.terminal.close(id=payload.id)
      Acknowledged
    }),
    Endpoint(@commands.moon_package_graph, payload => {
      @language.moon_package_graph(state.moon, payload)
    }),
    Endpoint(@commands.lsp_open, payload => {
      @language.lsp_open(state.moon, payload)
    }),
    Endpoint(@commands.lsp_hover, payload => {
      @language.lsp_hover(state.moon, payload)
    }),
    Endpoint(@commands.lsp_workspace_symbols, payload => {
      @language.workspace_symbols(state.moon, payload)
    }),
    Endpoint(@commands.moonide_definition, payload => {
      @language.moonide_definition(state.moon, payload)
    }),
    Endpoint(@commands.moonide_references, payload => {
      @language.moonide_references(state.moon, payload)
    }),
    Endpoint(@commands.moonide_codelens, payload => {
      @language.moonide_codelens(state.moon, payload)
    }),
    Endpoint(@commands.skills_catalog, _ => @skills.catalog()),
    Endpoint(@commands.skills_content, payload => @skills.content(payload)),
    Endpoint(@commands.skills_installed_content, payload => {
      @skills.installed_content(payload)
    }),
    Endpoint(@commands.skills_installed, _ => state.skills.installed()),
    Endpoint(@commands.skills_install, payload => {
      state.skills.install(payload, on_skills_changed)
    }),
    Endpoint(@commands.skills_uninstall, payload => {
      @skills.uninstall(payload, on_skills_changed)
    }),
    Endpoint(@commands.skills_set_enabled, payload => {
      @skills.set_enabled(payload, on_skills_changed)
    }),
    Endpoint(@commands.update_check, _ => state.updates.check()),
    @endpoint.Endpoint::sync(@commands.update_download, _ => {
      state.updates.start_download()
    }),
    Endpoint(@commands.update_apply, _ => state.updates.apply()),
    Endpoint(@commands.git_branch, payload => @git.branch(payload)),
    Endpoint(@commands.git_pull_request, payload => {
      @github.current_pull_request(payload)
    }),
    Endpoint(@commands.github_list, payload => @github.list(payload)),
    Endpoint(@commands.github_review, payload => @github.review(payload)),
    Endpoint(@commands.github_review_file, payload => {
      @github.review_file(payload)
    }),
    Endpoint(@commands.github_review_mutate, payload => {
      @github.mutate_review(payload)
    }),
    Endpoint(@commands.github_pull_request, payload => {
      @github.pull_request(payload)
    }),
    Endpoint(@commands.github_pull_request_summary, payload => {
      @github.pull_request_summary(payload)
    }),
    Endpoint(@commands.github_checkout, payload => @github.checkout(payload)),
    Endpoint(@commands.github_checkout_status, payload => {
      @github.checkout_status(payload)
    }),
    Endpoint(@commands.git_changes, payload => @git.changes(payload)),
    Endpoint(@commands.git_history, payload => @git.history(payload)),
    Endpoint(@commands.git_commit_changes, payload => {
      @git.commit_changes(payload)
    }),
    Endpoint(@commands.git_original_file, payload => @git.original_file(payload)),
    Endpoint(@commands.host_open_path, payload => @opener.open_path(payload)),
    Endpoint(@commands.host_reveal_path, payload => @opener.reveal_path(payload)),
  ]
}

///|
pub extend HostError with Debug::{to_repr}

///|
pub extend PayloadError with Debug::{to_repr}
