///|
fn submit_pattern_repair_tool(
  captured : Ref[PatternRepairReport?],
) -> @agent_tool.AgentToolDefinition {
  @agent_subrun.capture_tool(
    name="submit_pattern_repair",
    description="Submit one repaired structural pattern and a short explanation.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "candidate_pattern": { "type": "string" },
        "message": { "type": "string" },
      },
      "required": ["candidate_pattern", "message"],
    }),
    parse=args => {
      @agent_subrun.validated(
        PatternRepairReport::parse(args),
        PatternRepairReport::validate,
      )
    },
    captured,
    finished_note=_ => "pattern repair candidate submitted",
  )
}

///|
/// Run one bounded Pattern Repair Agent turn without exposing workspace tools.
pub async fn run(
  pattern : String,
  instruction : String,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  workspace_root? : String = ".",
) -> PatternRepairReport? {
  @agent_subrun.execute_kind(
    session_id="pattern-repair",
    system_prompt=pattern_repair_system_prompt(),
    task=pattern_repair_task(pattern, instruction),
    tools=captured => @agent_tool.Tools([submit_pattern_repair_tool(captured)]),
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    workspace_root~,
  )
}
