// The native endpoint catalog behind both Desktop transports. Each entry
// pairs one typed command descriptor with its typed operation once; Proton
// binds the captured types directly, while remote JSON-RPC invokes the JSON
// closure retained by the same endpoint.

///|
/// Everything the methods operate on: the app-lifetime engine actor and its
/// request-side manager (one serve process per conversation), the host-op
/// state (LSP pool and updates), and the notification hub. One per host
/// process; each transport connection supplies its own `HostConnection` when
/// dispatching filesystem watch methods.
struct ApiState {
  engine : @engine.EngineActor
  manager : @engine.EngineManager
  host : @host.HostState
  hub : Hub
  // The host's relay sign-in state, shared with the relay actor.
  auth : @auth.AuthStore
  // Called for every finished run, alongside the notification fan-out — the
  // desktop posts its system notification here.
  on_finished : ((@engine.FinishedPayload) -> Unit)?
}

///|
/// `engine` is the engine executable; `executable` is the host's own
/// binary, which self-update uses to locate the running .app bundle (absent
/// or non-bundle layouts only lose the in-app install, never the
/// announcement).
pub fn ApiState::new(
  engine~ : String,
  runtime_dir? : @path.Path,
  executable? : String,
  auth? : @auth.AuthStore,
  on_finished? : (@engine.FinishedPayload) -> Unit,
) -> ApiState {
  let engine_actor = @engine.new_engine_actor(engine, runtime_dir?)
  {
    engine: engine_actor,
    manager: engine_actor.manager(),
    host: @host.new_host_state(engine, runtime_dir?, executable?),
    hub: Hub::new(),
    auth: match auth {
      Some(store) => store
      None => @auth.AuthStore::empty()
    },
    on_finished,
  }
}

///|
/// The app-lifetime engine actor. Its `run` task owns all serve processes and
/// per-session follower children.
pub fn ApiState::engine_actor(self : ApiState) -> @engine.EngineActor {
  self.engine
}

///|
/// The sign-in store used by the relay actor running beside this dispatcher.
pub fn ApiState::auth_store(self : ApiState) -> @auth.AuthStore {
  self.auth
}

///|
/// The engine event sink: fan out to every subscriber, and hand finished
/// runs to the notification hook.
pub fn ApiState::sink(self : ApiState) -> @engine.EventSink {
  self.hub.sink(on_finished?=self.on_finished)
}

///|
/// Register a notification subscriber: a bounded queue the hub pushes every
/// notification into. The caller drains it with `get` and MUST `unsubscribe`
/// when done (a defer next to the subscribe). A subscriber that stops
/// draining is kicked by the hub: its queue is closed, which ends the
/// drain loop.
pub fn ApiState::subscribe(
  self : ApiState,
) -> @async.Queue[@protocol.Notification] {
  self.hub.subscribe()
}

///|
pub fn ApiState::unsubscribe(
  self : ApiState,
  queue : @async.Queue[@protocol.Notification],
) -> Unit {
  self.hub.unsubscribe(queue)
}

///|
/// Publish one notification to every subscriber — shared host pumps such as
/// `lsp.diagnostics` go through here. Connection-owned `fs.changed` events
/// bypass the hub and return only to their owning connection.
pub fn ApiState::publish(
  self : ApiState,
  notification : @protocol.Notification,
) -> Unit {
  self.hub.publish(notification)
}

///|
/// The host-op state, for the pumps spawned beside the dispatcher.
pub fn ApiState::host_state(self : ApiState) -> @host.HostState {
  self.host
}

///|
/// The request-side engine coordination handle.
pub fn ApiState::manager(self : ApiState) -> @engine.EngineManager {
  self.manager
}

///|
/// The commands shared by the embedded page and remote WebSocket. A generic
/// Endpoint constructor checks each payload/reply pair, then erases those
/// types only inside the two transport closures it creates.
pub fn endpoints(
  state : ApiState,
  connection : @host.HostConnection,
) -> Array[@endpoint.Endpoint] {
  [
    @endpoint.Endpoint::remote(@commands.agent_start, async fn(payload) {
      @engine.start_run(state.sink(), state.manager, payload.to_request())
    }),
    @endpoint.Endpoint::remote(@commands.agent_cancel, async fn(payload) {
      @engine.cancel_run(state.manager, payload.to_request())
    }),
    @endpoint.Endpoint::remote(@commands.agent_steer, async fn(payload) {
      @engine.steer_run(state.manager, payload.to_request())
    }),
    @endpoint.Endpoint::remote(@commands.agent_compact, async fn(payload) {
      @engine.compact_run(state.manager, payload.to_request())
    }),
    @endpoint.Endpoint::remote_sync(@commands.agent_runs, payload => {
      state.hub.runs(known?=payload.known)
    }),
    @endpoint.Endpoint::remote(@commands.session_list, async fn(_) {
      @engine.list_sessions(state.manager)
    }),
    @endpoint.Endpoint::remote(@commands.session_load, async fn(payload) {
      @engine.load_session(state.manager, payload.to_request())
    }),
    @endpoint.Endpoint::remote(@commands.session_list_archived, async fn(_) {
      @engine.archived_sessions(state.manager, session => {
        publish_session_changed(state, "archived", session)
      })
    }),
    @endpoint.Endpoint::remote(@commands.session_archive, async fn(payload) {
      let session = payload.canonical_session()
      // The callback runs inside the rename's cancellation shield. Every
      // other client learns the canonical id before any cancellable list
      // reply, so a cancelled requester cannot suppress invalidation.
      @engine.archive_session(state.manager, session, () => {
        publish_session_changed(state, "archived", session)
      })
    }),
    @endpoint.Endpoint::remote(@commands.session_unarchive, async fn(payload) {
      let session = payload.canonical_session()
      @engine.unarchive_session(state.manager, session, () => {
        publish_session_changed(state, "unarchived", session)
      })
    }),
    @endpoint.Endpoint::remote(@commands.settings_get, async fn(_) {
      @engine.settings_status(state.manager)
    }),
    @endpoint.Endpoint::remote(@commands.settings_set, async fn(payload) {
      // The store commit and its broadcast are one finite cancellation-
      // shielded linearization point. `update_settings` invokes the callback
      // while its manager-owned lock is still held, preserving revision order
      // across concurrent clients even if the requester disconnects.
      @async.protect_from_cancel(() => {
        let status = @engine.update_settings(
          state.manager,
          payload.to_patch(),
          legacy_migration=payload.legacy_migration == Some(true),
          on_committed=fn(status) {
            // Every client renders these settings; clients that did not ask
            // must learn about the committed revision too.
            state.hub.publish(SettingsChanged(status))
          },
        )
        // Credentials belong to the server that issued them. Clear stale
        // credentials before this request can complete or be cancelled.
        sign_out_after_server_switch(state)
        status
      })
    }),
    @endpoint.Endpoint::remote(@commands.workspace_list, async fn(_) {
      @engine.list_workspaces()
    }),
    @endpoint.Endpoint::remote(@commands.workspace_add, async fn(payload) {
      @engine.attach_workspace(payload.path, workspaces => {
        state.hub.publish(WorkspaceChanged({ workspaces, }))
      })
    }),
    @endpoint.Endpoint::remote(@commands.workspace_remove, async fn(payload) {
      @engine.detach_workspace(state.manager, payload.path, workspaces => {
        state.hub.publish(WorkspaceChanged({ workspaces, }))
      })
    }),
    @endpoint.Endpoint::remote(@commands.auth_status, async fn(_) {
      auth_status(state)
    }),
    @endpoint.Endpoint::remote(@commands.auth_connect, async fn(_) {
      auth_connect(state)
    }),
    @endpoint.Endpoint::remote(@commands.auth_disconnect, async fn(_) {
      auth_disconnect(state)
    }),
    @endpoint.Endpoint::remote(@commands.auth_cancel, async fn(_) {
      auth_cancel(state)
    }),
    @endpoint.Endpoint::remote(@commands.fs_read_file, async fn(payload) {
      @host.read_file(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_read_directory, async fn(payload) {
      @host.read_directory(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_list_files, async fn(payload) {
      @host.list_files(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_stat_files, async fn(payload) {
      @host.stat_files(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_watch, async fn(payload) {
      connection.watch(payload)
    }),
    @endpoint.Endpoint::remote(@commands.fs_unwatch, async fn(_) {
      connection.unwatch()
    }),
    @endpoint.Endpoint::remote(@commands.fs_browse, async fn(payload) {
      @host.browse_directory(payload)
    }),
    @endpoint.Endpoint::remote(@commands.terminal_open, async fn(payload) {
      connection.terminal_open(payload)
    }),
    @endpoint.Endpoint::remote(@commands.terminal_input, async fn(payload) {
      connection.terminal_input(payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.terminal_resize, payload => {
      connection.terminal_resize(payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.terminal_ack, payload => {
      connection.terminal_ack(payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.terminal_close, payload => {
      connection.terminal_close(payload)
    }),
    @endpoint.Endpoint::remote(@commands.lsp_open, async fn(payload) {
      state.host.lsp_open(payload)
    }),
    @endpoint.Endpoint::remote(@commands.lsp_hover, async fn(payload) {
      state.host.lsp_hover(payload)
    }),
    @endpoint.Endpoint::remote(@commands.lsp_workspace_symbols, async fn(
      payload,
    ) {
      state.host.lsp_workspace_symbols(payload)
    }),
    @endpoint.Endpoint::remote(@commands.moonide_definition, async fn(payload) {
      state.host.moonide_definition(payload)
    }),
    @endpoint.Endpoint::remote(@commands.moonide_references, async fn(payload) {
      state.host.moonide_references(payload)
    }),
    @endpoint.Endpoint::remote(@commands.skills_catalog, async fn(_) {
      @host.skills_catalog()
    }),
    @endpoint.Endpoint::remote(@commands.skills_installed, async fn(_) {
      @host.skills_installed()
    }),
    @endpoint.Endpoint::remote(@commands.skills_install, async fn(payload) {
      @host.skills_install(payload, () => state.publish(SkillsChanged))
    }),
    @endpoint.Endpoint::remote(@commands.skills_uninstall, async fn(payload) {
      @host.skills_uninstall(payload, () => state.publish(SkillsChanged))
    }),
    @endpoint.Endpoint::remote(@commands.update_check, async fn(payload) {
      state.host.update_check(payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.update_download, payload => {
      state.host.update_download(payload)
    }),
    @endpoint.Endpoint::remote(@commands.update_apply, async fn(_) {
      state.host.update_apply()
    }),
    @endpoint.Endpoint::remote(@commands.app_list, async fn(_) {
      @host.app_list()
    }),
    @endpoint.Endpoint::remote(@commands.app_launch, async fn(payload) {
      @host.app_launch(payload)
    }),
    @endpoint.Endpoint::remote(@commands.git_branch, async fn(payload) {
      @host.git_branch_info(payload)
    }),
    @endpoint.Endpoint::remote(@commands.host_open_path, async fn(payload) {
      @host.open_path(payload)
    }),
  ]
}

///|
test "remote endpoint catalog has one entry per command name" {
  let state = ApiState::new(engine="unused")
  let connection = @host.HostConnection::new()
  let names : Array[String] = []
  for endpoint in endpoints(state, connection) {
    let name = endpoint.name()
    if names.contains(name) {
      fail("duplicate endpoint: " + name)
    }
    names.push(name)
  }
  assert_eq(names.length(), 47)
  assert_true(names.contains("agent.start"))
  assert_true(names.contains("terminal.close"))
  assert_true(names.contains("moonide.references"))
  assert_false(names.contains("host.connect"))
  assert_false(names.contains("shell.open_external"))
}

///|
/// Tell every client a conversation moved between the live and archived
/// stores, so the ones that did not ask re-read both lists and drop live
/// state for the moved record.
fn publish_session_changed(
  state : ApiState,
  change : String,
  session : String,
) -> Unit {
  state.hub.publish(SessionChanged({ change, session }))
}
