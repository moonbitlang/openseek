///|
/// The extra tools a turn's registry carries on top of the built-ins: the
/// configured MCP servers' tools and `web_search` when a key the official
/// DeepSeek endpoint accepts is in hand.
/// Model-initiated scouts and reviews run through hosted `mbtx` workflows.
///
/// `run`'s one-shot turn and `serve`'s long-lived loop wire the identical
/// set. They used to build it from two copies of the same expression, which is
/// two chances for one entry point to grow a tool surface the other does not
/// have.
///
/// `mcp` is what `connect_mcp` made of the configured servers. The caller
/// connects first and passes it in because a long-lived loop goes on holding
/// it, to report as `mcp_status`; a one-shot turn has no other use for it.
pub fn build_extra_tools(
  mcp : McpRegistry,
  model~ : @deepseek.Model,
  api_key~ : String,
  deepseek_api_key? : String,
  api_url? : String,
) -> Array[@agent_tool.AgentToolDefinition] {
  let tools = mcp.tools()
  if web_search_api_key(model, api_key, api_url, deepseek_api_key)
    is Some(web_search_key) {
    tools.push(@web_search.definition(api_key=web_search_key))
  }
  tools
}

///|
/// The DeepSeek API key the `web_search` tool should use, if any. A DeepSeek
/// model run reuses the turn's own key; any other provider needs the dedicated
/// `--deepseek-api-key`/`$DEEPSEEK` credential, because native web search rides
/// DeepSeek's Anthropic-compatible endpoint regardless of the chat provider.
/// `None` simply leaves the tool unregistered — a run without a DeepSeek key
/// keeps working, minus web search.
///
/// A custom `--api-url` disables the tool entirely: with a custom chat
/// endpoint in effect, the key in hand is whatever THAT endpoint accepts —
/// often a gateway credential, and the desktop host exports the custom key as
/// `$DEEPSEEK` too — so every credential this function could reach may belong
/// to a third party, and web search always POSTs to the official
/// `api.deepseek.com` Messages endpoint. Not registering is the only option
/// that cannot ship someone else's token there.
fn web_search_api_key(
  model : @deepseek.Model,
  api_key : String,
  api_url : String?,
  deepseek_api_key : String?,
) -> String? {
  guard api_url is None else { return None }
  match (model, deepseek_api_key) {
    (Deepseek(_), _) => Some(api_key)
    (_, Some(key)) => Some(key)
    _ => None
  }
}
