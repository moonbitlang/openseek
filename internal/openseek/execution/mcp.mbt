///|
/// The client version openseek advertises to MCP servers in the handshake.
pub const McpClientVersion : String = "0.2.2"

///|
/// Build the agent tools contributed by the configured MCP servers. `[]` when no
/// config is set, or on any failure (emitted as events). The connections' reader/writer
/// tasks run on `scope`'s group.
async fn[X] resolve_mcp_tools(
  config_path : String?,
  scope : @agent_runtime.AgentTaskScope[X],
  workspace_root~ : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  guard config_path is Some(path) else { return [] }
  let text = @fs.read_file(path).text() catch {
    error => {
      @emit.emit(McpConfigUnreadable(path~, error="\{error}"))
      return []
    }
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error => {
      @emit.emit(McpConfigInvalid(path~, error="\{error}"))
      return []
    }
  }
  let tools = @mcptools.build(
    scope,
    servers,
    client_name="openseek",
    client_version=McpClientVersion,
    workspace_root~,
  )
  @emit.emit(
    McpToolsRegistered(
      servers=servers.length(),
      tools=tools.length(),
      names=[ for tool in tools => tool.name ],
    ),
  )
  tools
}
