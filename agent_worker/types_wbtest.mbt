///|
fn sample_worker_report() -> WorkerReport {
  {
    schema_version: 1,
    status: "done",
    summary: "Replaced the deprecated to_repr calls in lib/ and cmd/.",
    verification: "moon check clean (0 warnings in scope); moon test lib: 12/12.",
  }
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

///|
test "validate accepts a good report and rejects contract violations" {
  assert_eq(sample_worker_report().validate().length(), 0)
  assert_true(
    { ..sample_worker_report(), status: "excellent", }.validate().length() > 0,
  )
  assert_true(
    { ..sample_worker_report(), schema_version: 2, }.validate().length() > 0,
  )
  assert_true(
    { ..sample_worker_report(), summary: "  ", }.validate().length() > 0,
  )
  assert_true(
    { ..sample_worker_report(), verification: "", }.validate().length() > 0,
  )
  let long = "a".repeat(max_summary_chars + 1)
  assert_true(
    { ..sample_worker_report(), summary: long, }.validate().length() > 0,
  )
}

///|
test "worker report round-trips through json" {
  let report = sample_worker_report()
  guard WorkerReport::parse(ToJson::to_json(report)) is Ok(parsed) else {
    fail("parse failed")
  }
  assert_eq(parsed, report)
}
