// Resolve the configured MCP servers into agent tools. Any problem — no config,
// an unreadable file, malformed JSON, a bad config shape, a server that fails to
// start — yields no tools and is logged, so MCP never breaks a session; the
// engine simply runs with its built-in tools.

///|
/// The client version openseek advertises to MCP servers in the handshake.
const McpClientVersion : String = "0.2.2"

///|
/// The `--mcp-config` path, or "" when unset.
fn mcp_config_path(matches : @argparse.Matches) -> String {
  match matches {
    { values: { "mcp-config": [path, ..], .. }, .. } => path
    _ => ""
  }
}

///|
/// Build the agent tools contributed by the configured MCP servers. `[]` when no
/// config is set or on any failure (logged). The connections' reader/writer
/// tasks run on `scope`'s group.
async fn[X] resolve_mcp_tools(
  matches : @argparse.Matches,
  scope : @agent_runtime.AgentTaskScope[X],
  workspace_root~ : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  let path = mcp_config_path(matches)
  if path == "" {
    return []
  }
  let text = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn() <?
        { "event": "mcp_config_unreadable", "path": path, "error": "\{error}" }
      return []
    }
  }
  let servers = @mcpconfig.decode(@json.parse(text)) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn() <?
        { "event": "mcp_config_invalid", "path": path, "error": "\{error}" }
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
  @xlog.info() <?
    {
      "event": "mcp_tools_registered",
      "servers": servers.length(),
      "tools": tools.length(),
      "names": [
        for tool in tools => Json::string(tool.name)
      ],
    }
  tools
}
