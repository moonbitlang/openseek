///|
fn sample_report() -> ReviewReport {
  {
    schema_version: 1,
    scope: { base: "origin/main", head: "HEAD", files: ["a.mbt", "b.mbt"], },
    findings: [
      {
        file: "a.mbt",
        line: Some(42),
        severity: "high",
        category: "correctness",
        title: "off-by-one in loop bound",
        detail: "uses < where <= is intended",
        suggestion: Some("change < to <="),
      },
      {
        file: "b.mbt",
        line: None,
        severity: "nit",
        category: "style",
        title: "unclear name",
        detail: "rename x to count",
        suggestion: None,
      },
    ],
    summary: "two findings",
    stats: { files_reviewed: 2, findings: 2, build: "pass", tests: "skipped", },
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

///|
test "json string carries the flat string-typed contract" {
  let s = sample_report().to_json_string()
  assert_true(s.contains("\"schema_version\""))
  assert_true(s.contains("\"findings\""))
  // severity renders as a plain string, not a tagged enum
  assert_true(s.contains("\"high\""))
  assert_true(s.contains("\"nit\""))
}

///|
test "review report round-trips through json" {
  let report = sample_report()
  let json = ToJson::to_json(report)
  guard ReviewReport::parse(json) is Ok(parsed) else { fail("parse failed") }
  assert_eq(parsed.to_json_string(), report.to_json_string())
}

///|
test "validate rejects a bad severity" {
  let report = {
    ..sample_report(),
    findings: [
      {
        file: "a.mbt",
        line: None,
        severity: "urgent",
        category: "correctness",
        title: "t",
        detail: "d",
        suggestion: None,
      },
    ],
  }
  assert_true(report.validate().length() > 0)
}

///|
test "validate rejects a wrong schema version" {
  let report = { ..sample_report(), schema_version: 2, }
  assert_true(report.validate().length() > 0)
}

///|
test "validate rejects an empty summary" {
  assert_true({ ..sample_report(), summary: "", }.validate().length() > 0)
  assert_true({ ..sample_report(), summary: "   ", }.validate().length() > 0)
}
