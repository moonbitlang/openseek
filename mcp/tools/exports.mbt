// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// The namespaced, provider-safe tool name openseek exposes for `tool` from
/// server `server`: `mcp__<server>__<tool>` with every character outside the
/// provider's `[A-Za-z0-9_-]` function-name alphabet replaced by `-`, capped at
/// 64 characters. The `mcp__` prefix keeps MCP tools from colliding with
/// built-ins, and the server segment keeps two servers' identically named tools
/// distinct. (Uniqueness after sanitization is enforced by `build`.)
pub fn tool_name(server : String, tool : String) -> String {
  cap_name("mcp__\{sanitize_segment(server)}__\{sanitize_segment(tool)}")
}

///|
/// Discover `client`'s tools and wrap each as a namespaced agent tool. Raises if
/// the server's `tools/list` fails.
pub async fn tools_for_client(
  server : String,
  client : @mcp.McpClient,
) -> Array[@agent_tool.AgentToolDefinition] {
  // Skip exact repeats of one raw name (a misbehaving server aliasing one
  // method) so they cannot eat the tool budget; `build`'s suffixing stays
  // reserved for *distinct* names that collide after sanitization.
  let seen_raw : Set[String] = Set([])
  let bridged = []
  for tool in client.list_tools() {
    if seen_raw.contains(tool.name) {
      @emit.emit(McpToolDuplicate(server~, tool=tool.name))
      continue
    }
    seen_raw.add(tool.name)
    bridged.push(bridge_tool(server, client, tool))
  }
  bridged
}
