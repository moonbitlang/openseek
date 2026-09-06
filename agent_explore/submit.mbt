///|
/// The `submit_answer` capture tool: parse + validate against the bounded
/// contract, reject-with-retry on problems, capture and end the child run.
/// Control-declared via `capture_tool`, so a child hitting its context
/// ceiling on the submitting step still seals with its report.
fn submit_answer_tool(
  captured : Ref[ExploreReport?],
) -> @agent_tool.AgentToolDefinition {
  @agent_kind.capture_tool(
    name="submit_answer",
    description=(
      #|Submit the final explore report and end the run. Call this exactly once, when the
      #|question is answered. Every workspace claim needs a file (and line when known)
      #|citation; put what you could not determine in `unresolved`.
    ),
    schema=JsonSchema(report_schema()),
    parse=parse_submission,
    captured,
    finished_note=report => {
      "explore answered (\{report.citations.length()} citation(s))"
    },
  )
}

///|
fn parse_submission(args : Json) -> Result[ExploreReport, Array[String]] {
  @agent_kind.validated(ExploreReport::parse(args), ExploreReport::validate)
}

///|
/// JSON schema mirroring `ExploreReport`. `line` and `note` are optional per
/// citation; `unresolved` is optional.
fn report_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "schema_version": { "type": "integer" },
      "answer": {
        "type": "string",
        "description": "The complete answer, at most \{max_answer_chars} characters.",
      },
      "citations": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "file": { "type": "string" },
            "line": { "type": "integer" },
            "note": { "type": "string" },
          },
          "required": ["file"],
        },
        "description": "Supporting references, at most \{max_citations}.",
      },
      "unresolved": {
        "type": "string",
        "description": "What could not be determined, stated plainly.",
      },
    },
    "required": ["schema_version", "answer", "citations"],
  }
}

///|
test "submit_answer declares itself a control tool" {
  let captured : Ref[ExploreReport?] = { val: None, }
  assert_true(submit_answer_tool(captured).is_control())
}

///|
test "submission parse rejects contract violations" {
  guard parse_submission(ToJson::to_json(sample_report())) is Ok(_) else {
    fail("expected a valid submission")
  }
  guard parse_submission({ "answer": "no version" }) is Err(_) else {
    fail("expected a parse rejection")
  }
  guard parse_submission(ToJson::to_json({ ..sample_report(), answer: "", }))
    is Err(problems) else {
    fail("expected a validation rejection")
  }
  assert_true(problems.length() > 0)
}
