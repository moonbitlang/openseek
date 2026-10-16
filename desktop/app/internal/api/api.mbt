///|
/// Desktop/relay composition. All working-host handlers belong to backend ApiState.
struct DesktopState {
  service : @backend_api.ApiState
  host : @host.HostState
  auth : @auth.AuthStore
  manager : @engine.EngineManager
  hub : @broadcast.Channel[@protocol.Notification]
  app_version : String
  console_url : String?
}

///|
pub fn DesktopState::DesktopState(
  runtime~ : @runtime.HostRuntime = @runtime.HostRuntime::without_terminal(),
  engine~ : String,
  codex~ : @codex.CodexSettings = @codex.CodexSettings::default(),
  runtime_dir~ : @pathx.Path,
  executable? : String,
  auth? : @auth.AuthStore,
  app_version~ : String = "development",
  console_url? : String,
  resources~ : @working_host.HostResources = @working_host.HostResources::from_path(),
  host_mcp? : @mcp.Server,
  on_finished? : (@protocol.FinishedPayload) -> Unit,
) -> DesktopState {
  let hub : @broadcast.Channel[@protocol.Notification] = Channel()
  let service = @backend_api.ApiState(
    {
      data_dir: runtime_dir,
      engine_executable: engine,
      codex,
      resources,
      build_id: app_version,
      mode: Embedded,
    },
    runtime,
    host_mcp?,
    on_notification=notification => {
      let notification = @protocol.Notification::from_host(notification)
      if notification is AgentFinished(payload) && on_finished is Some(notify) {
        notify(payload)
      }
      hub.publish(notification)
    },
  )
  {
    service,
    host: @host.new_host_state(engine, runtime_dir~, executable?, app_version~),
    manager: service.manager(),
    hub,
    auth: match auth {
      Some(store) => store
      None => @auth.AuthStore::empty(app_version~)
    },
    app_version,
    console_url,
  }
}

///|
pub fn DesktopState::codex_actor(self : DesktopState) -> @codex.Actor {
  self.service.codex_actor()
}

///|
pub fn DesktopState::auth_store(self : DesktopState) -> @auth.AuthStore {
  self.auth
}

///|
pub fn DesktopState::manager(self : DesktopState) -> @engine.EngineManager {
  self.manager
}

///|
pub fn DesktopState::host_state(self : DesktopState) -> @host.HostState {
  self.host
}

///|
pub fn[T] DesktopState::subscribe(
  self : DesktopState,
  inbox : @async.Queue[T],
  map~ : (@protocol.Notification) -> T?,
  on_lag~ : (@broadcast.Subscription[@protocol.Notification]) -> Unit,
) -> @broadcast.Subscription[@protocol.Notification] {
  self.hub.subscribe(inbox, map~, on_lag~)
}

///|
pub fn DesktopState::publish(
  self : DesktopState,
  notification : @protocol.Notification,
) -> Unit {
  self.hub.publish(notification)
}

///|
pub fn DesktopState::service(self : DesktopState) -> @backend_api.ApiState {
  self.service
}

///|
pub fn DesktopState::new_connection(
  self : DesktopState,
) -> @host.HostConnection {
  @host.HostConnection::from_shared(self.service.new_connection())
}

///|
pub fn endpoints(
  state : DesktopState,
  connection : @host.HostConnection,
  on_share_progress~ : async (@protocol.SessionShareProgress) -> Unit = _ => (),
) -> Array[@endpoint.Endpoint] {
  let endpoints = @backend_api.endpoints(state.service, connection.shared()).map(endpoint => {
      if endpoint.name() != "settings.set" {
        endpoint
      } else {
        Endpoint(@commands.settings_set, payload => {
          @async.protect_from_cancel(() => {
            let reply = endpoint.invoke(payload.to_json())
            sign_out_after_server_switch(state)
            @json.from_json(reply)
          })
        })
      }
    },
  )
  endpoints.append([
    Endpoint(@commands.session_share, payload => {
      SessionShare::{ state, payload: payload.source, }.publish(on_progress=progress => {
        on_share_progress({ generation: payload.generation, progress, }) catch {
          _ => ()
        }
      })
    }),
    @endpoint.Endpoint::codex(@commands.codex_config_open, _ => {
      @host.open_codex_config(state.codex_actor().config_home())
      Acknowledged
    }),
    @endpoint.Endpoint::sync(@commands.app_info, _ => {
      version: state.app_version,
      console_url: state.console_url,
    }),
    Endpoint(@commands.auth_status, _ => auth_status(state)),
    Endpoint(@commands.auth_connect, _ => auth_connect(state)),
    Endpoint(@commands.auth_disconnect, _ => auth_disconnect(state)),
    Endpoint(@commands.auth_cancel, _ => auth_cancel(state)),
  ])
  endpoints.append(
    @host.endpoints(state.host, connection, state.manager, () => ()),
  )
  endpoints
}

///|
test "remote endpoint catalog has one entry per command name" {
  let state = DesktopState::DesktopState(
    engine="unused",
    runtime_dir=Path("/unused-test-host"),
  )
  assert_eq(remote_server_base(state.manager()), Some(RelayServerOrigin))
  let connection = @host.HostConnection()
  let names : Array[String] = []
  for endpoint in endpoints(state, connection) {
    let name = endpoint.name()
    if names.contains(name) {
      fail("duplicate endpoint: " + name)
    }
    names.push(name)
  }
  assert_true(names.contains("codex.config.open"))
  assert_true(names.contains("codex.draft.open"))
  assert_true(names.contains("codex.draft.close"))
  assert_true(names.contains("codex.file.search"))
  assert_true(names.contains("codex.skills.list"))
  assert_true(names.contains("codex.review.start"))
  assert_true(names.contains("codex.thread.history.read"))
  assert_true(names.contains("codex.thread.list"))
  assert_true(names.contains("agent.start"))
  assert_true(names.contains("agent.goal"))
  assert_true(names.contains("session.load_archived"))
  assert_true(names.contains("session.delete_archived"))
  assert_true(names.contains("workspace.settings_get"))
  assert_true(names.contains("workspace.settings_set"))
  assert_true(names.contains("app.info"))
  assert_true(names.contains("git.changes"))
  assert_true(names.contains("git.history"))
  assert_true(names.contains("git.commit_changes"))
  assert_true(names.contains("git.pull_request"))
  assert_true(names.contains("git.original_file"))
  assert_true(names.contains("terminal.close"))
  assert_true(names.contains("fs.search_files"))
  assert_true(names.contains("fs.cancel_search_files"))
  assert_true(names.contains("fs.clear_file_search_cache"))
  assert_true(names.contains("fs.create_directory"))
  assert_true(names.contains("fs.search_text"))
  assert_true(names.contains("fs.cancel_search_text"))
  assert_true(names.contains("moonide.references"))
  assert_true(names.contains("moonide.codelens"))
  assert_false(names.contains("host.connect"))
  assert_false(names.contains("shell.open_external"))
}

///|
pub fn DesktopState::subscribe_with(
  self : DesktopState,
  offer~ : (@protocol.Notification) -> Bool raise,
  on_lag~ : (@broadcast.Subscription[@protocol.Notification]) -> Unit,
) -> @broadcast.Subscription[@protocol.Notification] {
  self.hub.subscribe_with(offer~, on_lag~)
}
