///|
/// Tool definition for `review`: a model-initiated worktree audit — the
/// same reviewer child the goal-met gate spawns, callable mid-run before
/// claiming substantial work complete.
///
/// `context` supplies the live standing goal and its baseline (serve wires
/// a closure over its session; one-shot mirrors the latest appended
/// session). The model may narrow the audit with `focus`; when no goal
/// stands, `focus` supplies the criteria outright and is required.
fn review_tool_definition(
  self_exe~ : String,
  model~ : @deepseek.Model,
  workspace_root~ : String,
  review_deadline_ms? : Int = GateDeadlineMs,
  budget~ : @agent_subrun.SubrunBudget,
  context~ : () -> (String?, @agent_session.GoalBaseline?),
  api_url? : String,
  child_session? : @agent_subrun.ChildSession,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="review",
    concurrent_safe=true,
    description=(
      #|Request an INDEPENDENT audit of the current worktree by a review subagent — use it
      #|before declaring substantial work or a standing goal complete, or when you want a
      #|skeptical second reading of what you built. The auditor reads files, runs the
      #|project's own checks, hunts for vacuous success (tests asserting nothing,
      #|hardcoded outputs, quietly narrowed criteria), and returns severity-tagged
      #|findings with file:line citations. It audits against the standing goal when one
      #|exists; pass `focus` to narrow the criteria (with no standing goal, `focus` IS the
      #|criteria). Costs a bounded subagent run from the shared per-turn budget.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "focus": {
          "type": "string",
          "description": "What to audit against: specific criteria, a component, or a claim to verify. Optional when a standing goal exists (the goal is the default criteria).",
        },
      },
    }),
    execute=Async(arguments => {
      execute_review(
        self_exe,
        model,
        workspace_root,
        budget,
        context,
        api_url,
        child_session,
        arguments,
        review_deadline_ms~,
      )
    }),
  )
}

///|
async fn execute_review(
  self_exe : String,
  model : @deepseek.Model,
  workspace_root : String,
  budget : @agent_subrun.SubrunBudget,
  context : () -> (String?, @agent_session.GoalBaseline?),
  api_url : String?,
  child_session : @agent_subrun.ChildSession?,
  arguments : Json,
  review_deadline_ms~ : Int,
) -> @agent_tool.ToolAction {
  let focus : String? = match arguments {
    { "focus": String(focus), .. } if !focus.is_blank() => Some(focus)
    _ => None
  }
  let (standing_goal, baseline) = context()
  let criteria = match (focus, standing_goal) {
    (Some(focus), Some(goal)) => "\{goal}\n\nAudit focus:\n\{focus}"
    (Some(focus), None) => focus
    (None, Some(goal)) => goal
    (None, None) =>
      return @agent_tool.respond(
        "error: no standing goal exists — pass `focus` with the criteria to audit against",
        is_error=true,
      )
  }
  guard budget.reserve(@agent_review.default_audit_max_steps)
    is Some(granted_steps) else {
    return @agent_tool.respond(
      "review budget exhausted for this turn — validate directly (run the checks yourself).",
      is_error=true,
      brief="review (budget exhausted)",
    )
  }
  let args = subrun_args("review", model~, max_steps=granted_steps, api_url~)
  let input = review_subrun_input(criteria, baseline)
  let result = @agent_subrun.run_subrun(
    command=self_exe,
    args~,
    input~,
    parse_report=parse_audit_report,
    wall_deadline_ms=review_deadline_ms,
    kind="review",
    label=@agent_tool.brief_line(criteria, limit=48),
    cwd=workspace_root,
    child_session?,
  )
  // The sub-run id in the brief pairs the result with its lifecycle
  // brackets and names the child's sibling session for the viewer.
  // Display-only: the model never sees briefs.
  match result.value() {
    Some(report) =>
      @agent_tool.respond(
        report.digest(),
        is_error=report.findings.any(f => f.severity == "blocker"),
        brief="review \{result.subrun_id()} (\{report.findings.length()} finding(s), \{result.steps_used()} step(s))",
      )
    None =>
      @agent_tool.respond(
        "review produced no report (\{@agent_tool.brief_line("\{Repr(result.terminal())}", limit=200)}) — validate directly instead.",
        is_error=true,
        brief="review \{result.subrun_id()} (no report)",
      )
  }
}

///|
async test "review without a goal or focus errors before spending anything" {
  let budget = @agent_subrun.SubrunBudget(max_calls_per_turn=1)
  let tool = review_tool_definition(
    self_exe="/nonexistent/openseek-not-here",
    model=Deepseek(V4Flash),
    workspace_root=".",
    budget~,
    context=() => (None, None),
  )
  guard tool.execute is Async(execute) else { fail("review should be async") }
  let action = execute(Json::empty_object())
  guard action is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("no standing goal"))
  // Nothing was reserved or spawned.
  assert_true(budget.reserve(10) is Some(10))
}

///|
async test "review budget exhaustion refuses before spawning" {
  let budget = @agent_subrun.SubrunBudget(max_calls_per_turn=0)
  let tool = review_tool_definition(
    self_exe="/nonexistent/openseek-not-here",
    model=Deepseek(V4Flash),
    workspace_root=".",
    budget~,
    context=() => (Some("ship it"), None),
  )
  guard tool.execute is Async(execute) else { fail("review should be async") }
  let action = execute(Json::empty_object())
  guard action is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("budget exhausted"))
}
