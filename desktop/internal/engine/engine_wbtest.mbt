///|
test "terminal failures are normalized by the host" {
  assert_false(host_reports_terminal_error(AgentStep))
  assert_false(host_reports_terminal_error(AgentFinished("done")))
  assert_true(host_reports_terminal_error(AgentAborted("interrupted")))
  assert_true(host_reports_terminal_error(MaxStepsExhausted))
  assert_true(host_reports_terminal_error(AgentError("boom")))
}

///|
test "trailing steer settle events keep the terminal run id" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  tracker.record_sent("old steer")
  tracker.record_terminal(41)
  tracker.begin_run()
  tracker.record_sent("fresh steer")
  let old_drop : Json = { "event": "steer_dropped", "content": "old steer" }
  let fresh_apply : Json = {
    "event": "steer_applied",
    "content": "fresh steer",
  }
  assert_eq(tracker.run_id_for_event(old_drop, 42), 41)
  assert_eq(tracker.run_id_for_event(fresh_apply, 42), 42)
}

///|
test "new turn events clear stale settling state" {
  let tracker = SteerRunTracker::new()
  tracker.begin_run()
  tracker.record_sent("old steer")
  tracker.record_terminal(7)
  assert_eq(
    tracker.run_id_for_event({ "event": "agent_step", "step": 1 }, 8),
    8,
  )
  assert_eq(
    tracker.run_id_for_event(
      { "event": "steer_dropped", "content": "old steer" },
      8,
    ),
    8,
  )
}

///|
test "bundled moonbit bin is prepended to native engine path" {
  assert_eq(prepend_to_path_env("/toolchain/bin", None), "/toolchain/bin")
  assert_eq(prepend_to_path_env("/toolchain/bin", Some("")), "/toolchain/bin")
  assert_eq(
    prepend_to_path_env("/toolchain/bin", Some("/usr/bin")),
    "/toolchain/bin\{PathSep}/usr/bin",
  )
}
