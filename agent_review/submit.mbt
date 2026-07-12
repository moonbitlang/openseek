///|
/// `submit_review` is the structured-output tool for the review engine. The
/// model calls it exactly once with the full report; the executor parses and
/// validates the arguments, captures a valid report into `captured`, and ends
/// the run via Finish. Malformed output is rejected with an error so the model
/// retries instead of finishing with no report.
pub fn submit_review_tool(
  captured : Ref[ReviewReport?],
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="submit_review",
    description="Submit the final structured code-review report and end the review. Call this exactly once, when the review is complete. Every finding must cite a file (and a line when known) and a severity of blocker|high|medium|low|nit.",
    schema=JsonSchema(report_schema()),
    execute=Sync(args => submit(captured, args)),
  )
}

///|
fn submit(captured : Ref[ReviewReport?], args : Json) -> @agent_tool.ToolAction {
  match ReviewReport::parse(args) {
    Err(msg) => reject(msg)
    Ok(report) => {
      let problems = report.validate()
      if problems.length() > 0 {
        reject(problems.join("; "))
      } else {
        captured.val = Some(report)
        @agent_tool.ToolAction::finish(
          "review submitted (\{report.findings.length()} finding(s))",
        )
      }
    }
  }
}

///|
/// Reject malformed `submit_review` output with an error response so the model
/// retries instead of finishing with no report.
fn reject(reason : String) -> @agent_tool.ToolAction {
  @agent_tool.ToolAction::respond(
    "submit_review rejected: \{reason}",
    is_error=true,
    brief="submit_review",
  )
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
test "submit captures a valid report and finishes" {
  let captured : Ref[ReviewReport?] = { val: None }
  let action = submit(captured, sample_report().to_json())
  guard action is Control(Finish(_)) else { fail("expected Finish") }
  guard captured.val is Some(_) else { fail("expected captured report") }
}

///|
test "submit rejects an invalid report without capturing" {
  let captured : Ref[ReviewReport?] = { val: None }
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
  let action = submit(captured, bad.to_json())
  guard action is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  guard captured.val is None else { fail("must not capture an invalid report") }
}
