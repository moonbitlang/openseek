///|
async test "capture_goal_baseline probes the enclosing repo" {
  // Needs git and spawn permission; this checkout is a git repo. Guarded
  // rather than asserted: sandboxes without spawn or git report the
  // unavailable record.
  let notice = capture_goal_baseline(".")
  guard notice != GoalBaselineUnavailable else {
    println("skipped: git probe unavailable")
    return
  }
  guard @agent_session.parse_goal_baseline(notice) is Some(baseline) else {
    fail("expected a parseable baseline notice: \{notice}")
  }
  // A full commit id, not a short one: the gate resolves it exactly.
  assert_eq(baseline.sha.length(), 40)
}

///|
test "the unavailable record is not a parseable baseline" {
  assert_true(
    @agent_session.parse_goal_baseline(GoalBaselineUnavailable) is None,
  )
}
