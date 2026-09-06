///|
/// The `submit_result` capture tool: parse + validate against the bounded
/// contract, reject-with-retry on problems, capture and end the child run.
/// Control-declared via `capture_tool`, so a child hitting its context
/// ceiling on the submitting step still seals with its report.
fn submit_result_tool(
  captured : Ref[WorkerReport?],
) -> @agent_tool.AgentToolDefinition {
  @agent_kind.capture_tool(
    name="submit_result",
    description=(
      #|Submit the final worker report and end the run. Call this exactly once, when your
      #|slice of work is done (or when you must stop): status is done, partial, or failed;
      #|summary says what changed; verification names the commands you ran and their
      #|outcomes. The harness validates your actual changes against the task's allowed
      #|paths — the report describes, it does not decide.
    ),
    schema=JsonSchema(report_schema()),
    parse=parse_submission,
    captured,
    finished_note=report => "worker \{report.status}",
  )
}

///|
fn parse_submission(args : Json) -> Result[WorkerReport, Array[String]] {
  @agent_kind.validated(WorkerReport::parse(args), WorkerReport::validate)
}

///|
/// JSON schema mirroring `WorkerReport`.
fn report_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "schema_version": { "type": "integer" },
      "status": {
        "type": "string",
        "enum": ["done", "partial", "failed"],
        "description": "done = complete and verified; partial = honest progress with work remaining; failed = nothing mergeable.",
      },
      "summary": {
        "type": "string",
        "description": "What changed, at most \{max_summary_chars} characters.",
      },
      "verification": {
        "type": "string",
        "description": "The commands you ran to verify and their outcomes, at most \{max_verification_chars} characters.",
      },
    },
    "required": ["schema_version", "status", "summary", "verification"],
  }
}

///|
test "submit_result declares itself a control tool" {
  let captured : Ref[WorkerReport?] = { val: None, }
  assert_true(submit_result_tool(captured).is_control())
}

///|
test "submission parse rejects contract violations" {
  guard parse_submission(ToJson::to_json(sample_worker_report())) is Ok(_) else {
    fail("expected a valid submission")
  }
  guard parse_submission({ "status": "done" }) is Err(_) else {
    fail("expected a parse rejection")
  }
  guard parse_submission(
      ToJson::to_json({ ..sample_worker_report(), status: "sideways", }),
    )
    is Err(problems) else {
    fail("expected a validation rejection")
  }
  assert_true(problems.length() > 0)
}
