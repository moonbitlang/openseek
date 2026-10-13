///|
/// The client version openseek advertises to MCP servers in the handshake.
pub const McpClientVersion : String = "0.2.2"

///|
/// What this engine holds of MCP: whether it was configured, and for each
/// configured server what connecting came to. Built once at startup and kept
/// for the engine's life, because the connections are — it is what an
/// `mcp_status` event reports.
enum McpRegistry {
  NotConfigured
  /// The configuration could not be read or decoded, so there are no servers.
  Failed(path~ : String, error~ : String)
  Loaded(path~ : String, entries~ : Array[@mcptools.ServerEntry])
}

///|
/// Connect the configured MCP servers. Nothing here fails the engine: a
/// configuration that cannot be used and a server that cannot be reached are
/// recorded in the registry and reported as the events they always were. The
/// connections' reader/writer tasks run on `scope`'s group.
pub async fn[X] connect_mcp(
  scope : @agent_runtime.AgentTaskScope[X],
  workspace_root~ : String,
  config_path? : String,
) -> McpRegistry {
  guard config_path is Some(path) else { return NotConfigured }
  let text = @fs.read_file(path).text() catch {
    error => {
      @emit.emit(McpConfigUnreadable(path~, error="\{error}"))
      return Failed(path~, error="\{error}")
    }
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error => {
      @emit.emit(McpConfigInvalid(path~, error="\{error}"))
      return Failed(path~, error="\{error}")
    }
  }
  let entries = @mcptools.connect(
    scope,
    servers,
    client_name="openseek",
    client_version=McpClientVersion,
    workspace_root~,
  )
  let registry = Loaded(path~, entries~)
  let tools = registry.tools()
  @emit.emit(
    McpToolsRegistered(
      servers=servers.length(),
      tools=tools.length(),
      names=[ for tool in tools => tool.name ],
    ),
  )
  registry
}

///|
/// The agent tools the connected servers contributed, in config order.
fn McpRegistry::tools(
  self : McpRegistry,
) -> Array[@agent_tool.AgentToolDefinition] {
  guard self is Loaded(entries~, ..) else { return [] }
  entries.map(entry => entry.tools).flatten()
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
  guard self is Loaded(entries~, ..) else { return }
  for entry in entries {
    if entry.connection is Live(client) {
      client.set_close_handler(handler)
    }
  }
}

///|
/// The registry as the `mcp_status` event reports it. A server's state is
/// read now, not remembered: one that connected at startup and has since lost
/// its connection is `Lost`, with the tools that are still registered.
pub fn McpRegistry::status(self : McpRegistry) -> @protocol.McpStatus {
  match self {
    NotConfigured => NotConfigured
    Failed(path~, error~) => ConfigFailed(path~, error~)
    Loaded(path~, entries~) =>
      Configured(
        path~,
        servers=entries.map(entry => {
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
            Skipped => Skipped
          }
          {
            name: entry.server.name(),
            transport: match entry.server {
              Stdio(..) => Stdio
              Http(..) => Http
            },
            target: entry.server.target(),
            state,
          }
        }),
      )
  }
}
