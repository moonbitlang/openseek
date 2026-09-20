///|
test "job event decoding is selected by metadata source" {
  assert_true(
    JobEvent::from_tool_brief("mbtx", "mbtx → bg bg-1")
    is Some(Backgrounded("bg-1")),
  )
  assert_true(
    JobEvent::from_tool_brief(
      "job_output", "job bg-1 (running): Run tests: native",
    )
    is Some(
      OutputRead(
        { id: "bg-1", description: "Run tests: native", status: Running, }
      )
    ),
  )
  assert_true(JobEvent::from_tool_brief("read", "mbtx → bg bg-1") is None)
  assert_true(
    JobEvent::from_tool_brief("mbtx", "job bg-1 (exit=0): Tests") is None,
  )
  assert_true(
    JobEvent::from_tool_brief("job_output", "mbtx → bg bg-1") is None,
  )
  assert_true(JobEvent::from_tool_brief("mbtx", "mbtx → bg ") is None)
  assert_true(
    JobEvent::from_tool_brief("job_output", "job bg-1 (exit=0): ") is None,
  )
}

///|
test "recorded job statuses retain terminal diagnostics" {
  for
    (text, expected) in [
      ("running", JobStatus::Running),
      ("exit=0", Exited(0)),
      ("exit=-9", Exited(-9)),
      ("stopped", Stopped),
      ("stopped killed_at_output_cap=true", StoppedAtLimit("output_cap=true")),
      ("stopped killed_at_time_cap=true", StoppedAtLimit("time_cap=true")),
      ("cleanup failed: disk error", CleanupFailed("disk error")),
      ("output capture failed: read error", OutputCaptureFailed("read error")),
      (
        "killed: flooded past the output cap",
        Killed("flooded past the output cap"),
      ),
    ] {
    assert_true(JobStatus::parse(text) == expected)
  }
  for
    text in [
      "future-status", "exit=", "exit=oops", "exit=999999999999999999999",
    ] {
    assert_true(JobStatus::parse(text) is Unrecognized(raw) && raw == text)
  }
}

///|
test "notice decoder separates command instructions and rejects incomplete notices" {
  assert_true(
    JobEvent::from_notice(
      "background job bg-1 finished (exit=0): `Run `native` tests · mbtx run: code` — read its output with job_output (job_id=\"bg-1\").",
    )
    is Some(
      Finished(
        { id: "bg-1", description: "Run `native` tests", status: Exited(0), }
      )
    ),
  )
  assert_true(
    JobEvent::from_notice("background job bg-1 finished (stopped): Run tests")
    is Some(
      Finished({ id: "bg-1", description: "Run tests", status: Stopped, })
    ),
  )
  for
    text in [
      "An unrelated runtime notice", "background job bg-1 finished (running): Run tests",
      "background job bg-1 finished (future-status): Run tests", "background job bg-1 finished (exit=0): `Incomplete notice",
      "background job bg-1 finished (exit=0): ",
    ] {
    assert_true(JobEvent::from_notice(text) is None)
  }
}

///|
test "unrecognized output metadata is available without rewriting its caption" {
  guard JobEvent::from_tool_brief(
      "job_output", "job bg-1 (future-status): Tests",
    )
    is Some(event) else {
    fail("an unfamiliar status should preserve job identity and description")
  }
  assert_true(event is OutputRead({ id: "bg-1", description: "Tests", .. }))
  assert_true(event.minimal_caption(English) is None)
}
