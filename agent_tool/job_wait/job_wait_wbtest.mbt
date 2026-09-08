///|
test "job_wait validates and deduplicates its selection" {
  for
    args in [
      Json::null(),
      {},
      { "job_ids": [] },
      { "job_ids": [""] },
      { "job_ids": ["  "] },
      { "job_ids": [1] },
      { "job_ids": ["bg-1"], "timeout": 120000 },
    ] {
    guard execute(args) is Respond(output) else {
      fail("expected argument error")
    }
    assert_true(output.is_error)
  }
  guard execute({ "job_ids": ["bg-2", "bg-1", "bg-2"] })
    is Control(WaitJobs(ids)) else {
    fail("expected wait control")
  }
  assert_eq(ids, ["bg-2", "bg-1"])
  assert_false(definition().is_concurrent_safe())
  assert_false(definition().is_control()) // Not safe to salvage at a ceiling.
}
