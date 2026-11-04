///|
/// `submit_verdict` is the reviewer's structured-output tool: the model calls
/// it once with its decision, the executor validates and captures it, and the
/// run ends. A malformed verdict is rejected so the model retries instead of
/// finishing with none. A control tool, so the ceiling salvage honors a
/// pending submission rather than skip-closing it.
fn submit_verdict_tool(
  captured : Ref[Verdict?],
) -> @agent_tool.AgentToolDefinition {
  @agent_kind.capture_tool(
    name="submit_verdict",
    description=(
      #|Submit your decision on the permission request and end the review. Call this
      #|exactly once. decision is allow, deny, or escalate; reason says what you checked
      #|and what it showed.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "decision": { "type": "string", "enum": ["allow", "deny", "escalate"] },
        "reason": { "type": "string" },
      },
      "required": ["decision", "reason"],
    }),
    parse=args => Verdict::parse(args).map_err(problem => [problem]),
    captured,
    finished_note=verdict => "verdict submitted: \{verdict.decision.word()}",
  )
}
