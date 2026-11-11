///|
/// The client version openseek advertises to MCP servers in the handshake.
pub const McpClientVersion : String = "0.2.2"

///|
/// What this engine holds of MCP: each configuration file and what came of
/// reading it, and for each server of the merged configuration what
/// connecting came to, which settles in the background. Built once at startup
/// and kept for the engine's life, because the connections are — it is what an
/// `mcp_status` event reports.
struct McpRegistry {
  configs : Array[@protocol.McpConfigStatus]
  /// Each server of the merged configuration, in order, being connected.
  servers : Array[@mcptools.Server]
  /// The task that reports `McpToolsRegistered` once every server has
  /// settled; `None` when no configuration file loaded, which reports nothing.
  registered : @async.Task[Unit]?
}

///|
/// Read every configuration file in `config_paths`, in order — a later file's
/// server replaces an earlier one of the same name — and start connecting the
/// merged servers in the background on `scope`'s group, without waiting for
/// any: a server that takes long to connect (or never does, like a headers
/// helper waiting on the user) does not hold up the engine. The servers each
/// of `skills` brings in its `mcp.json` join them, ahead of the files, so a
/// file's server replaces a skill's of the same name; a skill's server
/// connects only when a script first reaches it. A skill's configuration may
/// reference its own directory as `${OPENSEEK_SKILL_DIR}`, which its stdio
/// servers also find in their environment. `on_change` runs each time
/// `status` may have changed since — a server started connecting or settled,
/// or a connected server's connection closed — and must not block. Once every
/// server from the files has settled, `McpToolsRegistered` is reported.
/// Nothing here fails the engine: a file that cannot be used and a server that
/// cannot be reached are recorded in the registry and reported as the events
/// they always were.
pub async fn start_mcp(
  scope : @agent_runtime.AgentTaskScope,
  config_paths : Array[String],
  skills~ : Array[@agent_skill.Skill] = [],
  workspace_root~ : String,
  on_change? : () -> Unit,
) -> McpRegistry {
  let configs : Array[@protocol.McpConfigStatus] = []
  async fn load(
    path : String,
    env : Map[String, String],
  ) -> Array[@mcpconfig.McpServer]? {
    let text = @fs.read_text(path) catch {
      error => {
        let error = "\{error}"
        @emit.emit(McpConfigUnreadable(path~, error~))
        configs.push({ path, state: Failed(error), })
        return None
      }
    }
    let servers = @mcpconfig.decode(@json.parse(text), env~) catch {
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

  let skill_servers : Array[@mcpconfig.McpServer] = []
  for skill in skills {
    guard skill.mcp_config() is Some(path) else { continue }
    let dir = match path.rev_split_once("/") {
      Some((dir, _)) => dir.to_owned()
      None => "."
    }
    let env = @env.get_env_vars()
    env[SkillDirEnv] = dir
    guard load(path, env) is Some(servers) else { continue }
    for server in servers {
      skill_servers.push(
        match server {
          Stdio(name~, command~, args~, env~) => {
            let env = env.copy()
            env[SkillDirEnv] = dir
            Stdio(name~, command~, args~, env~)
          }
          Http(..) => server
        },
      )
    }
  }
  let loaded : Array[Array[@mcpconfig.McpServer]] = []
  for path in config_paths {
    if load(path, @env.get_env_vars()) is Some(servers) {
      loaded.push(servers)
    }
  }
  // A file's server replaces a skill's of the same name, and connects as the
  // engine starts, like every server from the files.
  let from_files : Set[String] = Set([])
  for servers in loaded {
    for server in servers {
      from_files.add(server.name())
    }
  }
  let on_demand : Set[String] = Set(
    [
      for server in skill_servers if !from_files.contains(server.name()) => {
        server.name()
      }
    ],
  )
  let servers = @mcptools.start(
    scope,
    @mcpconfig.merge([skill_servers, ..loaded]),
    client_name="openseek",
    client_version=McpClientVersion,
    workspace_root~,
    on_demand~,
    on_change?,
  )
  // Preserve the single-file failure contract: no registration event when
  // every file failed to load (or none was given). A valid empty file still
  // registers normally.
  guard !loaded.is_empty() else {
    return { configs, servers, registered: None, }
  }
  let registered = scope
    .group()
    .spawn(no_wait=true, () => {
      let names : Array[String] = []
      let eager = servers.filter(server => !server.on_demand)
      for server in eager {
        for tool in server.settled().tools {
          names.push("\{server.config.name()}/\{tool.name}")
        }
      }
      @emit.emit(
        McpToolsRegistered(servers=eager.length(), tools=names.length(), names~),
      )
    })
  { configs, servers, registered: Some(registered), }
}

///|
/// The variable naming the directory of the skill whose `mcp.json` is being
/// read: its configuration may reference it as `${OPENSEEK_SKILL_DIR}`, and
/// its stdio servers find it in their environment.
pub const SkillDirEnv : String = "OPENSEEK_SKILL_DIR"

///|
/// Wait until every server from the configuration files has settled and
/// `McpToolsRegistered` has been reported — for a one-shot run, whose turn
/// should see every tool there will be. A skill's servers are not waited for:
/// they connect when a script reaches them.
pub async fn McpRegistry::wait(self : McpRegistry) -> Unit {
  if self.registered is Some(registered) {
    registered.wait()
  }
}

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
