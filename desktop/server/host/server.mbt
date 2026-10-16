///|
/// A window-independent SeekMoon server. The same backend and endpoint catalog
/// serve native terminal clients and the browser frontend loaded by Proton.
struct Server {
  console : @remote.LocalConsole
  state : @api.ApiState
  tools : @mcp.Server
}

///|
/// Bind a token-protected loopback listener. Port zero selects an unused port.
/// The owning host chooses the engine executable and runtime directory.
pub async fn Server::bind(
  engine~ : String = "openseek",
  port~ : Int32 = 0,
  runtime_dir? : @pathx.Path,
  resources~ : @backend_host.HostResources = @backend_host.HostResources::from_path(),
) -> Server {
  let codex_home = runtime_dir.map(dir => @codex.home_dir(dir))
  let codex = @codex.CodexSettings(
    command=@codex.command(),
    home=codex_home,
    require_home=true,
  )
  let auth = @auth.AuthStore::load(
    runtime_dir?,
    env_override?=relay_environment(@env.get_env_vars()),
    app_version="development",
  )
  let tools = @mcp.Server([], version="development")
  errdefer tools.close()
  let console = @remote.LocalConsole::bind(port~)
  {
    console,
    tools,
    state: ApiState(
      engine~,
      codex~,
      auth~,
      runtime_dir?,
      resources~,
      console_url=console.entry_url(),
      host_mcp=tools,
    ),
  }
}

///|
/// The JSON-RPC WebSocket endpoint; authenticate with `token()`.
pub fn Server::url(self : Server) -> String {
  self.console.socket_url()
}

///|
/// This launch's secret capability, shared only with authorized clients.
pub fn Server::token(self : Server) -> String {
  self.console.token
}

///|
/// The token-bearing frontend URL a desktop window or browser can open.
pub fn Server::entry_url(self : Server) -> String {
  self.console.entry_url()
}

///|
/// Start all backend services, then accept clients until the owner cancels.
/// Supplying frontend assets also lets desktop windows use this same server.
pub async fn Server::run(
  self : Server,
  root? : String,
  entry~ : String = "index.html",
  on_ready? : async () -> Unit,
) -> Unit {
  defer self.close()
  if root is Some(root) {
    guard @fs.kind(root) is Directory else {
      raise @backend_host.HostError("frontend root is not a directory: " + root)
    }
    guard @fs.kind(root + "/" + entry) is Regular else {
      raise @backend_host.HostError("frontend entry is not a file: " + entry)
    }
  }
  @async.with_task_group(group => {
    self.state.start_services(group)
    let relay = @remote.RelayActor(self.state, announce=device => ignore(device))
    group.spawn_bg(allow_failure=true, () => relay.run())
    if on_ready is Some(on_ready) {
      on_ready()
    }
    self.console.run(self.state, root?, entry~)
  })
}

///|
/// Release both listener capabilities, including when the host is never run.
pub fn Server::close(self : Server) -> Unit {
  self.console.server.close()
  self.tools.close()
}

///|
fn relay_environment(variables : Map[String, String]) -> @auth.ConnectorConfig? {
  guard variables.get("OPENSEEK_RELAY_URL") is Some(relay_url) &&
    variables.get("OPENSEEK_DEVICE_TOKEN") is Some(device_token) else {
    return None
  }
  Some({
    relay_url,
    device_token,
    device_name: variables.get("OPENSEEK_DEVICE_NAME").unwrap_or("desktop"),
  })
}
