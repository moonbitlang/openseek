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
/// helper waiting on the user) does not hold up the engine. `on_change` runs
/// each time `status` may have changed since — a server settled, or a
/// connected server's connection closed — and must not block. Once every
/// server has settled, `McpToolsRegistered` is reported. Nothing here fails
/// the engine: a file that cannot be used and a server that cannot be reached
/// are recorded in the registry and reported as the events they always were.
pub async fn start_mcp(
  scope : @agent_runtime.AgentTaskScope,
  config_paths : Array[String],
  workspace_root~ : String,
  on_change? : () -> Unit,
) -> McpRegistry {
  let configs : Array[@protocol.McpConfigStatus] = []
  let loaded : Array[Array[@mcpconfig.McpServer]] = []
  for path in config_paths {
    let text = @fs.read_text(path) catch {
      error => {
        let error = "\{error}"
        @emit.emit(McpConfigUnreadable(path~, error~))
        configs.push({ path, state: Failed(error), })
        continue
      }
    }
    let servers = @mcpconfig.decode(@json.parse(text), env=@env.get_env_vars()) catch {
      error => {
        let error = "\{error}"
        @emit.emit(McpConfigInvalid(path~, error~))
        configs.push({ path, state: Failed(error), })
        continue
      }
    }
    configs.push({ path, state: Loaded, })
    loaded.push(servers)
  }
  // Preserve the single-file failure contract: no registration event when
  // every input failed to load. A valid empty config still registers normally.
  guard !loaded.is_empty() else {
    return { configs, servers: [], registered: None, }
  }
  let servers = @mcptools.start(
    scope,
    @mcpconfig.merge(loaded),
    client_name="openseek",
    client_version=McpClientVersion,
    workspace_root~,
  )
  if on_change is Some(on_change) {
    for server in servers {
      scope
      .group()
      .spawn_bg(no_wait=true, () => {
        let entry = server.connecting.wait()
        // The close handler goes on first, so a connection that closes from
        // here on reports itself, and one already closed shows as lost.
        if entry.connection is Live(client) {
          client.set_close_handler(on_change)
        }
        on_change()
      })
    }
  }
  let registered = scope
    .group()
    .spawn(no_wait=true, () => {
      let names : Array[String] = []
      for server in servers {
        for tool in server.connecting.wait().tools {
          names.push("\{server.config.name()}/\{tool.name}")
        }
      }
      @emit.emit(
        McpToolsRegistered(
          servers=servers.length(),
          tools=names.length(),
          names~,
        ),
      )
    })
  { configs, servers, registered: Some(registered), }
}

///|
/// Wait until every server has settled and `McpToolsRegistered` has been
/// reported — for a one-shot run, whose turn should see every tool there will
/// be.
pub async fn McpRegistry::wait(self : McpRegistry) -> Unit {
  if self.registered is Some(registered) {
    registered.wait()
  }
}

///|
/// Serve these servers to scripts through an MCP host on `scope`'s group,
/// which lives as long as the connections do. Calls go to the named server,
/// and the catalog lists the servers as they stand now (a lost or
/// still-connecting one as unavailable). Images in results are saved under
/// `image_directory`. Without a configured server there is nothing to serve,
/// and no host starts.
pub async fn McpRegistry::serve(
  self : McpRegistry,
  scope : @agent_runtime.AgentTaskScope,
  image_directory? : String,
) -> @mcphost.Service? {
  guard !self.servers.is_empty() else { return None }
  let servers = self.servers
  Some(
    @mcphost.Service::start(
      scope.group(),
      call=(server, tool, arguments) => {
        match
          servers.search_by(configured => configured.config.name() == server) {
          Some(index) => servers[index].call(tool, arguments)
          None =>
            @agent_tool.respond(
              "no MCP server `\{@agent_tool.brief_line(server, limit=128)}`; list them with `@mcp.search()`",
              is_error=true,
            )
        }
      },
      items=() => @mcptools.catalog_items(servers),
      image_directory?,
    ),
  )
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
