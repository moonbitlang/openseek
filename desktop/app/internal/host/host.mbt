///|
pub using @working_host {
  type HostError,
  type PayloadError,
  type VizAssets,
  chat_workspace_root,
  read_github_drafts,
  write_github_drafts,
}

///|
struct HostState {
  updates : SelfUpdate
}

///|
pub fn new_host_state(
  _engine : String,
  runtime_dir? : @pathx.Path,
  executable? : String,
  app_version~ : String = "development",
) -> HostState {
  { updates: SelfUpdate(runtime_dir, executable, app_version~), }
}

///|
struct HostConnection {
  connection : @working_host.HostConnection
}

///|
pub fn HostConnection::HostConnection() -> HostConnection {
  {
    connection: HostConnection(runtime=@runtime.HostRuntime::without_terminal()),
  }
}

///|
/// Adapt a connection created with its service's runtime capabilities.
pub fn HostConnection::from_shared(
  connection : @working_host.HostConnection,
) -> HostConnection {
  { connection, }
}

///|
pub fn HostConnection::shared(
  self : HostConnection,
) -> @working_host.HostConnection {
  self.connection
}

///|
pub fn HostConnection::close_terminals(self : HostConnection) -> Unit {
  self.connection.close_terminals()
}

///|
pub async fn HostConnection::run(
  self : HostConnection,
  emit : async (@protocol.Notification) -> Unit,
  emit_progress : async (@protocol.Notification) -> Unit,
) -> Unit {
  self.connection.run(event => emit(@protocol.Notification::from_host(event)), event => {
    emit_progress(@protocol.Notification::from_host(event))
  })
}

///|
pub fn[G] spawn_host_pumps(
  group : @async.TaskGroup[G],
  state : HostState,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  group.spawn_bg(allow_failure=true, () => state.updates.run(emit))
}

///|
pub fn endpoints(
  state : HostState,
  _connection : HostConnection,
  _manager : @engine.EngineManager,
  _on_skills_changed : () -> Unit,
) -> Array[@endpoint.Endpoint] {
  [
    Endpoint(@commands.update_check, _ => state.updates.check()),
    @endpoint.Endpoint::sync(@commands.update_download, _ => {
      state.updates.start_download()
    }),
    Endpoint(@commands.update_apply, _ => state.updates.apply()),
    Endpoint(@commands.host_open_path, payload => open_path_op(payload)),
    Endpoint(@commands.host_reveal_path, payload => reveal_path_op(payload)),
  ]
}

///|
/// Resolve tool resources once at the native bundle boundary.
pub async fn resources(
  resources : @resources.Resources,
) -> @working_host.HostResources {
  {
    moonbit: DesktopBundle,
    viz: Some(viz_assets(Some(resources))),
    bin_dir: PackagedTools::resolve(Some(resources)).map(tools => tools.bin_dir),
    ripgrep: ripgrep_command(Some(resources)),
    moongrep: moongrep_command(Some(resources)),
  }
}
