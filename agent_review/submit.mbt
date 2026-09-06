///|
/// `submit_review` is the structured-output tool for the review engine. The
/// model calls it exactly once with the full report; the executor parses and
/// validates the arguments, captures a valid report into `captured`, and ends
/// the run via Finish. Malformed output is rejected with an error so the model
/// retries instead of finishing with no report.
///
/// Declared a control tool: its action is loop flow with a few bytes of
/// result, so the loop's ceiling salvage honors a pending `submit_review`
/// instead of skip-closing it — without this, a review that hits the
/// context ceiling on its submitting step would lose its finished report
/// and fail with `ReviewError`.
fn submit_review_tool(
  captured : Ref[ReviewReport?],
) -> @agent_tool.AgentToolDefinition {
  @agent_kind.capture_tool(
    name="submit_review",
    description=(
      #|Submit the final structured code-review report and end the review. Call this
      #|exactly once, when the review is complete. Every finding must cite a file (and a
      #|line when known) and a severity of blocker|high|medium|low|nit.
    ),
    schema=JsonSchema(report_schema()),
    parse=parse_submission,
    captured,
    finished_note=report => {
      "review submitted (\{report.findings.length()} finding(s))"
    },
  )
}

///|
/// Parse-and-validate for the capture tool: JSON decode problems and contract
/// violations both reject, so the model retries instead of finishing with no
/// report.
fn parse_submission(args : Json) -> Result[ReviewReport, Array[String]] {
  @agent_kind.validated(ReviewReport::parse(args), ReviewReport::validate)
}

///|
/// JSON schema mirroring `ReviewReport`. `line` and `suggestion` are optional.
fn report_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "schema_version": { "type": "integer" },
      "scope": {
        "type": "object",
        "properties": {
          "base": { "type": "string" },
          "head": { "type": "string" },
          "files": { "type": "array", "items": { "type": "string" } },
        },
        "required": ["base", "head", "files"],
      },
      "findings": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "file": { "type": "string" },
            "line": { "type": "integer" },
            "severity": {
              "type": "string",
              "enum": ["blocker", "high", "medium", "low", "nit"],
            },
            "category": { "type": "string" },
            "title": { "type": "string" },
            "detail": { "type": "string" },
            "suggestion": { "type": "string" },
          },
          "required": ["file", "severity", "category", "title", "detail"],
        },
      },
      "summary": { "type": "string" },
      "stats": {
        "type": "object",
        "properties": {
          "files_reviewed": { "type": "integer" },
          "findings": { "type": "integer" },
          "build": { "type": "string" },
          "tests": { "type": "string" },
        },
        "required": ["files_reviewed", "findings", "build", "tests"],
      },
    },
    "required": ["schema_version", "scope", "findings", "summary", "stats"],
  }
}

///|
/// Run the submit tool's Sync executor directly, as the loop would.
fn submit_action(
  captured : Ref[ReviewReport?],
  args : Json,
) -> @agent_tool.ToolAction raise {
  guard submit_review_tool(captured).execute is Sync(execute) else {
    fail("submit_review should be a Sync executor")
  }
  execute(args)
}

///|
test "submit_review declares itself a control tool" {
  // The ceiling salvage honors control-declared completions; without this
  // a review hitting the context ceiling on its submitting step would
  // skip-close submit_review and fail with ReviewError.
  let captured : Ref[ReviewReport?] = { val: None, }
  assert_true(submit_review_tool(captured).is_control())
}

///|
test "submit captures a valid report and finishes" {
  let captured : Ref[ReviewReport?] = { val: None, }
  let action = submit_action(captured, ToJson::to_json(sample_report()))
  guard action is Control(Finish(note)) else { fail("expected Finish") }
  assert_true(note.contains("2 finding(s)"))
  guard captured.val is Some(_) else { fail("expected captured report") }
}

///|
test "submit rejects an invalid report without capturing" {
  let captured : Ref[ReviewReport?] = { val: None, }
  let bad = {
    ..sample_report(),
    findings: [
      {
        file: "",
        line: None,
        severity: "urgent",
        category: "x",
        title: "",
        detail: "d",
        suggestion: None,
      },
    ],
  }
  let action = submit_action(captured, ToJson::to_json(bad))
  guard action is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("submit_review rejected"))
  guard captured.val is None else { fail("must not capture an invalid report") }
}
