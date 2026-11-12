///|
/// The client version openseek advertises to MCP servers in the handshake.
pub const McpClientVersion : String = "0.2.2"

///|
/// What this engine holds of MCP: each configuration file and what came of
/// reading it, and each server of the merged configuration with what
/// connecting it came to once a script has reached it. Built once at startup
/// and kept for the engine's life, because the connections are — it is what an
/// `mcp_status` event reports.
struct McpRegistry {
  configs : Array[@protocol.McpConfigStatus]
  /// Each server of the merged configuration, in order.
  servers : Array[@mcptools.Server]
}

///|
/// Read every configuration file in `config_paths`, in order — a later file's
/// server replaces an earlier one of the same name. The servers each of
/// `skills` brings in its `mcp.json` join them, ahead of the files, so a
/// file's server replaces a skill's of the same name. A skill's configuration
/// expands only `${OPENSEEK_SKILL_DIR}`, its own directory, and the variables
/// named in `skill_env`; its stdio servers run through `moonx` inside a
/// moonrun policy written under `policy_dir` (see `confine_skill_servers`). No
/// server connects here: each connects in the background on `scope`'s group
/// when a script first reaches it. `on_change` runs each time `status` may
/// have changed since — a server started connecting or settled, or a connected
/// server's connection closed — and must not block. Nothing here fails the
/// engine: a file that cannot be used and a server that cannot be reached are
/// recorded in the registry and reported as the events they always were.
pub async fn start_mcp(
  scope : @agent_runtime.AgentTaskScope,
  config_paths : Array[String],
  skills~ : Array[@agent_skill.Skill] = [],
  skill_env~ : Array[String] = [],
  policy_dir~ : String,
  workspace_root~ : String,
  on_change? : () -> Unit,
) -> McpRegistry {
  let configs : Array[@protocol.McpConfigStatus] = []
  async fn load(
    path : String,
    env : Map[String, String],
    confine : async (Array[@mcpconfig.McpServer]) -> Array[@mcpconfig.McpServer],
  ) -> Array[@mcpconfig.McpServer]? {
    let text = @fs.read_text(path) catch {
      error => {
        let error = "\{error}"
        @emit.emit(McpConfigUnreadable(path~, error~))
        configs.push({ path, state: Failed(error), })
        return None
      }
    }
    let servers = confine(@mcpconfig.decode(@json.parse(text), env~)) catch {
      error => {
        let error = "\{error}"
        @emit.emit(McpConfigInvalid(path~, error~))
        configs.push({ path, state: Failed(error), })
        return None
      }
    }
    configs.push({ path, state: Loaded, })
    Some(servers)
  }

  let host_env = @env.get_env_vars()
  let skill_servers : Array[@mcpconfig.McpServer] = []
  let moonx = if skills.any(skill => skill.mcp_config_path() is Some(_)) {
    trusted_moonx(host_env.get("PATH").unwrap_or(""))
  } else {
    None
  }
  let mut policies = 0
  for skill in skills {
    guard skill.mcp_config_path() is Some(path) else { continue }
    let dir = match path.rev_split_once("/") {
      Some((dir, _)) => dir.to_owned()
      None => "."
    }
    let env : Map[String, String] = Map([])
    for name in skill_env {
      if host_env.get(name) is Some(value) {
        env[name] = value
      }
    }
    env[SkillDirEnv] = dir
    let confined = load(path, env, servers => {
      confine_skill_servers(servers, skill_dir=dir, workspace_root~, moonx~, policy=() => {
        policies += 1
        "\{policy_dir}/\{policies}.json"
      })
    })
    if confined is Some(servers) {
      skill_servers.append(servers)
    }
  }
  let loaded : Array[Array[@mcpconfig.McpServer]] = []
  for path in config_paths {
    if load(path, host_env, servers => servers) is Some(servers) {
      loaded.push(servers)
    }
  }
  let servers = @mcpconfig.merge([skill_servers, ..loaded]).map(server => {
    @mcptools.Server::new(
      scope,
      server,
      client_name="openseek",
      client_version=McpClientVersion,
      workspace_root~,
      on_change?,
    )
  })
  { configs, servers, }
}

///|
/// The variable naming the directory of the skill whose `mcp.json` is being
/// read: its configuration may reference it as `${OPENSEEK_SKILL_DIR}`, and
/// its stdio servers find it in their environment.
pub const SkillDirEnv : String = "OPENSEEK_SKILL_DIR"

///|
/// Serve these servers to scripts through an MCP host on `scope`'s group,
/// which lives as long as the connections do; calls and listings wait, a
/// bounded time, for the servers they need (see `@mcphost.Service::start`).
/// Images in results are saved under `image_directory`. Without a configured
/// server there is nothing to serve, and no host starts.
pub async fn McpRegistry::serve(
  self : McpRegistry,
  scope : @agent_runtime.AgentTaskScope,
  image_directory? : String,
) -> @mcphost.Service? {
  guard !self.servers.is_empty() else { return None }
  Some(@mcphost.Service::start(scope.group(), self.servers, image_directory?))
}

///|
/// The registry as the `mcp_status` event reports it, with tools under the
/// servers' own names. A server's state is read now, not remembered: one that
/// connected and has since lost its connection is `Lost`, with the tools it
/// offered.
pub fn McpRegistry::status(self : McpRegistry) -> @protocol.McpStatus {
  let servers : Array[@protocol.McpServerStatus] = []
  for configured in self.servers {
    let server = configured.config
    fn tools(entry : @mcptools.ServerEntry) -> Array[@protocol.McpTool] {
      entry.tools.map(tool => {
        name: tool.name,
        description: tool.description,
      })
    }

    let state : @protocol.McpServerState = match configured.try_wait() {
      None if !configured.started() => Idle
      None => Connecting
      Some({ connection: Live(client), .. } as entry) if client.is_closed() =>
        Lost(tools(entry))
      Some({ connection: Live(_), .. } as entry) => Connected(tools(entry))
      Some({ connection: NoTools, .. }) => NoTools
      Some({ connection: Failed(error), .. }) => Failed(error)
    }
    servers.push({
      name: server.name(),
      transport: match server {
        Stdio(..) => Stdio
        Http(..) => Http
      },
      target: server.target(),
      state,
    })
  }
  { configs: self.configs, servers, }
}
