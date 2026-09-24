///|
test "goal markers parse exactly and other goal-family notices never match" {
  assert_true(
    @transcript.goal_marker("[goal]\nship the feature")
    is Some(@transcript.GoalSet("ship the feature")),
  )
  assert_true(
    @transcript.goal_marker("[goal]\nline one\nline two")
    is Some(@transcript.GoalSet("line one\nline two")),
  )
  assert_true(
    @transcript.goal_marker("[goal cleared]") is Some(@transcript.GoalCleared),
  )
  assert_true(
    @transcript.goal_marker("[goal blocked]\nneeds a decision")
    is Some(@transcript.GoalBlocked("needs a decision")),
  )
  assert_true(
    @transcript.goal_marker("[goal unblocked]")
    is Some(@transcript.GoalUnblocked),
  )
  // Reminders, checks and the baseline record are transport/model-directed.
  assert_true(
    @transcript.goal_marker("[goal reminder]\nThe standing goal…") is None,
  )
  assert_true(
    @transcript.goal_marker("[goal check]\nThe standing goal…") is None,
  )
  assert_true(
    @transcript.goal_marker("[goal baseline] sha=abc dirty=false") is None,
  )
  // A bare `[goal]` with no text line is not a set.
  assert_true(@transcript.goal_marker("[goal]") is None)
  assert_true(@transcript.goal_marker("plain notice") is None)
}

///|
test "the goal reducer follows last-marker-wins with guarded transitions" {
  let set = @transcript.apply_goal_marker(None, @transcript.GoalSet("ship it"))
  assert_true(set is Some({ text: "ship it", blocked: None, }))
  let blocked = @transcript.apply_goal_marker(
    set,
    @transcript.GoalBlocked("needs access"),
  )
  assert_true(
    blocked is Some({ text: "ship it", blocked: Some("needs access"), }),
  )
  let resumed = @transcript.apply_goal_marker(
    blocked,
    @transcript.GoalUnblocked,
  )
  assert_true(resumed is Some({ text: "ship it", blocked: None, }))
  // A newer set resets a standing block.
  let replaced = @transcript.apply_goal_marker(
    blocked,
    @transcript.GoalSet("polish it"),
  )
  assert_true(replaced is Some({ text: "polish it", blocked: None, }))
  assert_true(
    @transcript.apply_goal_marker(blocked, @transcript.GoalCleared) is None,
  )
  // Stray transitions on a goalless record stay goalless.
  assert_true(
    @transcript.apply_goal_marker(None, @transcript.GoalBlocked("orphan"))
    is None,
  )
  assert_true(
    @transcript.apply_goal_marker(None, @transcript.GoalUnblocked) is None,
  )
}
