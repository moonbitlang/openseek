///|
/// The extra tools a turn's registry carries on top of the built-ins: the
/// configured MCP servers' tools, the model-callable subrun tool
/// (`review`; read-only scouts are fanned out from an `mbtx` workflow
/// instead), and `web_search` when a key the official
/// DeepSeek endpoint accepts is in hand.
///
/// `main`'s one-shot turn and `serve`'s long-lived loop wire the identical
/// set. They used to build it from two copies of the same expression, which is
/// two chances for one entry point to grow a tool surface the other does not
/// have.
///
/// `budget` is the shared per-turn subrun allowance; `review_context` is read
/// at call time so the `review` tool audits against the LIVE standing goal
/// rather than a turn-start snapshot.
async fn[X] build_extra_tools(
  matches : @argparse.Matches,
  scope : @agent_runtime.AgentTaskScope[X],
  self_exe~ : String,
  model~ : @deepseek.Model,
  api_key~ : String,
  workspace_root~ : String,
  budget~ : @agent_subrun.SubrunBudget,
  review_context~ : () -> (String?, @agent_session.GoalBaseline?),
  review_deadline_ms~ : Int?,
  api_url? : String,
  child_session? : @agent_subrun.ChildSession,
) -> Array[@agent_tool.AgentToolDefinition] {
  let extra_tools = resolve_mcp_tools(matches, scope, workspace_root~) +
    [
      review_tool_definition(
        self_exe~,
        model~,
        workspace_root~,
        review_deadline_ms?,
        budget~,
        context=review_context,
        api_url?,
        child_session?,
      ),
    ]
  if web_search_api_key(model, api_key, api_url, matches)
    is Some(web_search_key) {
    extra_tools.push(@web_search.definition(api_key=web_search_key))
  }
  extra_tools
}
