///|
/// The client version openseek advertises to MCP servers in the handshake.
pub const McpClientVersion : String = "0.2.2"

///|
/// Build the agent tools contributed by the configured MCP servers. `[]` when no
/// config is set. Invalid files are reported and skipped independently. The
/// connections' reader/writer tasks run on `scope`'s group.
async fn[X] resolve_mcp_tools(
  config_paths : Array[String],
  scope : @agent_runtime.AgentTaskScope[X],
  workspace_root~ : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  guard !config_paths.is_empty() else { return [] }
  let configs : Array[Array[@mcpconfig.McpServer]] = []
  for path in config_paths {
    let text = @fs.read_file(path).text() catch {
      error => {
        @emit.emit(McpConfigUnreadable(path~, error="\{error}"))
        continue
      }
    }
    let servers = @mcpconfig.decode(@json.parse(text), env=@env.get_env_vars()) catch {
      error => {
        @emit.emit(McpConfigInvalid(path~, error="\{error}"))
        continue
      }
    }
    configs.push(servers)
  }
  // Preserve the single-file failure contract: no registration event when
  // every input failed to load. A valid empty config still registers normally.
  guard !configs.is_empty() else { return [] }
  let servers = @mcpconfig.merge(configs)
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
