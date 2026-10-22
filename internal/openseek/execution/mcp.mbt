///|
/// The client version openseek advertises to MCP servers in the handshake.
pub const McpClientVersion : String = "0.2.2"

///|
/// What this engine holds of MCP: each configuration file and what came of
/// reading it, and for each server of the merged configuration what
/// connecting came to. Built once at startup and kept for the engine's life,
/// because the connections are — it is what an `mcp_status` event reports.
struct McpRegistry {
  configs : Array[@protocol.McpConfigStatus]
  /// Each server of the merged configuration, in order.
  servers : Array[@mcptools.ServerEntry]
}

///|
/// Connect the servers of every configuration file in `config_paths`, in
/// order; a later file's server replaces an earlier one of the same name.
/// Nothing here fails the engine: a file that cannot be used and a server that
/// cannot be reached are recorded in the registry and reported as the events
/// they always were. The connections' reader/writer tasks run on `scope`'s
/// group.
pub async fn[X] connect_mcp(
  scope : @agent_runtime.AgentTaskScope[X],
  config_paths : Array[String],
  workspace_root~ : String,
) -> McpRegistry {
  let configs : Array[@protocol.McpConfigStatus] = []
  let loaded : Array[Array[@mcpconfig.McpServer]] = []
  for path in config_paths {
    let text = @fs.read_file(path).text() catch {
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
  guard !loaded.is_empty() else { return { configs, servers: [], } }
  let servers = @mcpconfig.merge(loaded)
  let entries = @mcptools.connect(
    scope,
    servers,
    client_name="openseek",
    client_version=McpClientVersion,
    workspace_root~,
  )
  let names : Array[String] = []
  for entry in entries {
    for tool in entry.tools {
      names.push("\{entry.server.name()}/\{tool.name}")
    }
  }
  @emit.emit(
    McpToolsRegistered(servers=servers.length(), tools=names.length(), names~),
  )
  { configs, servers: entries, }
}

///|
/// Serve these servers to scripts through an MCP host on `scope`'s group,
/// which lives as long as the connections do. Calls go to the named server,
/// and the catalog lists the servers as they stand now (a lost one as
/// unavailable). Images in results are saved under `image_directory`. Without
/// a configured server there is nothing to serve, and no host starts.
pub async fn[X] McpRegistry::serve(
  self : McpRegistry,
  scope : @agent_runtime.AgentTaskScope[X],
  image_directory? : String,
) -> @mcphost.Service? {
  guard !self.servers.is_empty() else { return None }
  let servers = self.servers
  Some(
    @mcphost.Service::start(
      scope.group(),
      call=(server, tool, arguments) => {
        match servers.search_by(entry => entry.server.name() == server) {
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
/// Run `handler` each time a connected server's connection closes — the one
/// way this registry's status changes after it is built. The handler must not
/// block. A connection that closed before this call does not run it, so a
/// caller reads `status` after installing and reports from there.
pub fn McpRegistry::on_connection_closed(
  self : McpRegistry,
  handler : () -> Unit,
) -> Unit {
  for entry in self.servers {
    if entry.connection is Live(client) {
      client.set_close_handler(handler)
    }
  }
}

///|
/// The registry as the `mcp_status` event reports it, with tools under the
/// servers' own names. A server's state is read now, not remembered: one that
/// connected at startup and has since lost its connection is `Lost`, with the
/// tools it offered.
pub fn McpRegistry::status(self : McpRegistry) -> @protocol.McpStatus {
  let servers : Array[@protocol.McpServerStatus] = []
  for entry in self.servers {
    let tools : Array[@protocol.McpTool] = entry.tools.map(tool => {
      name: tool.name,
      description: tool.description,
    })
    let state : @protocol.McpServerState = match entry.connection {
      Live(client) =>
        if client.is_closed() {
          Lost(tools)
        } else {
          Connected(tools)
        }
      NoTools => NoTools
      Failed(error) => Failed(error)
    }
    servers.push({
      name: entry.server.name(),
      transport: match entry.server {
        Stdio(..) => Stdio
        Http(..) => Http
      },
      target: entry.server.target(),
      state,
    })
  }
  { configs: self.configs, servers, }
}
