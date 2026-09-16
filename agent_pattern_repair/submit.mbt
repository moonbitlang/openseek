///|
fn submit_pattern_repair_tool(
  captured : Ref[PatternRepairReport?],
  validated_pattern : Ref[String?],
) -> @agent_tool.AgentToolDefinition {
  @agent_kind.capture_tool(
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
    parse=args => parse_pattern_repair_submission(args, validated_pattern.val),
    captured,
    finished_note=_ => "pattern repair candidate submitted",
  )
}

///|
fn parse_pattern_repair_submission(
  args : Json,
  validated_pattern : String?,
) -> Result[PatternRepairReport, Array[String]] {
  guard validated_pattern is Some(validated) else {
    return Err(["validate_pattern must succeed before submit_pattern_repair"])
  }
  match
    @agent_kind.validated(
      PatternRepairReport::parse(args),
      PatternRepairReport::validate,
    ) {
    Ok(report) if report.candidate_pattern == validated => Ok(report)
    Ok(_) => Err(["candidate_pattern must match the last validated pattern"])
    Err(problems) => Err(problems)
  }
}

///|
/// Run one Pattern Repair Agent turn. It has no workspace tools: its only
/// non-submit capability is the Host-owned syntax validator. The caller may
/// impose a step ceiling; the normal Host path relies on its wall timeout.
pub async fn run(
  pattern : String,
  instruction : String,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  retry_attempts? : Int,
  retry_backoff_ms? : Int,
  workspace_root? : String = ".",
) -> PatternRepairReport? {
  let validated_pattern : Ref[String?] = { val: None, }
  @agent_kind.execute_kind(
    session_id="pattern-repair",
    system_prompt=pattern_repair_system_prompt(),
    task=pattern_repair_task(pattern, instruction),
    tools=captured => {
      Tools([
        validate_pattern_tool(workspace_root, validated_pattern),
        submit_pattern_repair_tool(captured, validated_pattern),
      ])
    },
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    retry_attempts?,
    retry_backoff_ms?,
    workspace_root~,
  )
}

///|
test "pattern repair submission requires the last validated pattern" {
  let args = (
    { "candidate_pattern": "inspect($(x:arg))", "message": "fixed" } : Json)
  guard parse_pattern_repair_submission(args, None) is Err(problems) else {
    fail("submission without validation should be rejected")
  }
  assert_eq(problems, [
    "validate_pattern must succeed before submit_pattern_repair",
  ])
  guard parse_pattern_repair_submission(args, Some("other")) is Err(problems) else {
    fail("submission of a different pattern should be rejected")
  }
  assert_eq(problems, [
    "candidate_pattern must match the last validated pattern",
  ])
  guard parse_pattern_repair_submission(args, Some("inspect($(x:arg))"))
    is Ok(report) else {
    fail("submission of the validated pattern should be accepted")
  }
  assert_eq(report.candidate_pattern, "inspect($(x:arg))")
}
