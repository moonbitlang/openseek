///|
/// The extra tools a turn's registry carries on top of the built-ins: the
/// configured MCP servers' tools and `web_search` when a key the official
/// DeepSeek endpoint accepts is in hand.
/// Model-initiated scouts and reviews run through hosted `mbtx` workflows.
///
/// `main`'s one-shot turn and `serve`'s long-lived loop wire the identical
/// set. They used to build it from two copies of the same expression, which is
/// two chances for one entry point to grow a tool surface the other does not
/// have.
async fn[X] build_extra_tools(
  matches : @argparse.Matches,
  scope : @agent_runtime.AgentTaskScope[X],
  model~ : @deepseek.Model,
  api_key~ : String,
  workspace_root~ : String,
  api_url? : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  let extra_tools = resolve_mcp_tools(matches, scope, workspace_root~)
  if web_search_api_key(model, api_key, api_url, matches)
    is Some(web_search_key) {
    extra_tools.push(@web_search.definition(api_key=web_search_key))
  }
  extra_tools
}
