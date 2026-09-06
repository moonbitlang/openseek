///|
/// Step ceiling requested for one explore child. Generous enough that a
/// scout answering a real question never dies mid-search (a truncated child
/// burns its whole allowance and returns nothing); the answer-early rule in
/// the prompt, not this ceiling, is what keeps exploration cheap.
pub let default_explore_max_steps : Int = 100

///|
/// The entry for `openseek subrun explore`: decode the input line
/// (`{"query": ..., "hints"?: ...}` — what `wf.agent(prompt=, kind="explore")`
/// sends), run the scout kind in this process, and return the report (the
/// dispatch prints it as the final `subrun_report` line). `None` when the
/// child finished without a valid submission or the input is malformed.
pub async fn run_child(
  input : Json,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  workspace_root? : String = ".",
  session_id? : String = "explore",
  append_item? : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  scratch_dir? : String,
) -> ExploreReport? {
  guard input is { "query": String(query), .. } && !query.is_blank() else {
    return None
  }
  let hints : String? = match input {
    { "hints": String(hints), .. } if !hints.is_blank() => Some(hints)
    _ => None
  }
  @agent_kind.execute_kind(
    session_id~,
    append_item?,
    system_prompt=explore_system_prompt(),
    task=explore_task(query, hints, scratch_dir),
    tools=captured => {
      @agent_tool.Tools([
        @read.definition(workspace_root~),
        @mbtx.definition(workspace_root~, read_only=true, scratch_dir?),
        submit_answer_tool(captured),
      ])
    },
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    workspace_root~,
  )
}
