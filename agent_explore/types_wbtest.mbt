///|
fn sample_report() -> ExploreReport {
  {
    schema_version: 1,
    answer: "Use @buffer.new(size_hint?) and Buffer::to_bytes.",
    citations: [
      { file: "protocol/event.mbt", line: Some(14), note: Some("Event enum"), },
      { file: "moonbitlang/core/buffer", line: None, note: None, },
    ],
    unresolved: Some("did not check the js backend"),
  }
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

///|
test "explore report round-trips through json" {
  let report = sample_report()
  guard ExploreReport::parse(ToJson::to_json(report)) is Ok(parsed) else {
    fail("parse failed")
  }
  assert_eq(parsed, report)
}

///|
test "validate rejects empties and oversizes" {
  assert_true({ ..sample_report(), answer: "  ", }.validate().length() > 0)
  assert_true({ ..sample_report(), schema_version: 2, }.validate().length() > 0)
  let long = "a".repeat(max_answer_chars + 1)
  assert_true({ ..sample_report(), answer: long, }.validate().length() > 0)
  let many : Array[Citation] = []
  for i in 0..<=max_citations {
    many.push({ file: "f\{i}.mbt", line: None, note: None, })
  }
  assert_true({ ..sample_report(), citations: many, }.validate().length() > 0)
  assert_true(
    { ..sample_report(), citations: [{ file: "", line: None, note: None, }], }
    .validate()
    .length() >
    0,
  )
}
