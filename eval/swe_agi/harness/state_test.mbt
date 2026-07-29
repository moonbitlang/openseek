///|
test "goal completion waits for the finishing terminal" {
  let state = @harness.GoalTrialState("ship it")
  assert_true(state.observe(GoalUpdated(goal=Some("ship it"))) is None)
  assert_true(state.acknowledged())
  assert_true(state.observe(GoalUpdated(goal=None)) is None)
  let stop : @harness.TrialStop? = state.observe(AgentFinished(answer="done"))
  guard stop is Some(stop) else { fail("expected goal completion") }
  assert_eq(stop.label(), "goal_met")
  assert_eq(state.turns(), 1)
}

///|
test "ordinary finished turns continue while the goal stands" {
  let state = @harness.GoalTrialState("ship it")
  state.observe(GoalUpdated(goal=Some("ship it"))) |> ignore
  assert_true(state.observe(AgentFinished(answer="more remains")) is None)
  state.observe(GoalContinue(remaining=19)) |> ignore
  assert_eq(state.turns(), 1)
}

///|
test "blocked goals stop at the finishing terminal" {
  let state = @harness.GoalTrialState("ship it")
  state.observe(GoalBlocked(reason="missing access")) |> ignore
  let stop : @harness.TrialStop? = state.observe(
    AgentFinished(answer="blocked"),
  )
  guard stop is Some(stop) else { fail("expected blocked completion") }
  assert_eq(stop.label(), "goal_blocked")
  assert_eq(stop.detail(), "missing access")
}

///|
test "usage and steps accumulate across turns" {
  let state = @harness.GoalTrialState("ship it")
  state.observe(AgentStep(step=1)) |> ignore
  state.observe(
    Usage(usage={
      prompt_tokens: 10,
      completion_tokens: 4,
      total_tokens: 14,
      prompt_cache_hit_tokens: 0,
      prompt_cache_miss_tokens: 10,
    }),
  )
  |> ignore
  state.observe(AgentStep(step=1)) |> ignore
  state.observe(
    Usage(usage={
      prompt_tokens: 8,
      completion_tokens: 3,
      total_tokens: 11,
      prompt_cache_hit_tokens: 4,
      prompt_cache_miss_tokens: 4,
    }),
  )
  |> ignore
  assert_eq(state.steps(), 2)
  assert_eq(state.prompt_tokens(), 18)
  assert_eq(state.completion_tokens(), 7)
  assert_eq(state.total_tokens(), 25)
}

///|
test "transport retries are counted independently of finished turns" {
  let state = @harness.GoalTrialState("ship it")
  state.record_transport_retry()
  assert_eq(state.transport_retries(), 1)
  assert_eq(state.consecutive_transport_failures(), 1)
  assert_eq(state.transport_retry_delay_ms(), 5_000)
  assert_eq(state.turns(), 0)
}

///|
test "a completed model response resets consecutive recovery limits" {
  let state = @harness.GoalTrialState("ship it")
  state.record_transport_retry()
  state.record_transport_retry()
  state.record_engine_restart()
  assert_eq(state.transport_retry_delay_ms(), 10_000)
  assert_eq(state.consecutive_engine_restarts(), 1)
  state.observe(AgentStep(step=1)) |> ignore
  assert_eq(state.consecutive_transport_failures(), 2)
  assert_eq(state.consecutive_engine_restarts(), 1)
  state.observe(
    Usage(usage={
      prompt_tokens: 1,
      completion_tokens: 1,
      total_tokens: 2,
      prompt_cache_hit_tokens: 0,
      prompt_cache_miss_tokens: 1,
    }),
  )
  |> ignore
  assert_eq(state.transport_retries(), 2)
  assert_eq(state.engine_restarts(), 1)
  assert_eq(state.consecutive_transport_failures(), 0)
  assert_eq(state.consecutive_engine_restarts(), 0)
}

///|
test "transport retry delay caps at one minute" {
  let state = @harness.GoalTrialState("ship it")
  for i = 0; i < 8; i = i + 1 {
    state.record_transport_retry()
  }
  assert_eq(state.transport_retry_delay_ms(), 60_000)
}

///|
test "a restarted connection must acknowledge the goal again" {
  let state = @harness.GoalTrialState("ship it")
  state.observe(GoalUpdated(goal=Some("ship it"))) |> ignore
  assert_true(state.acknowledged())
  state.expect_goal_acknowledgement()
  assert_false(state.acknowledged())
}

///|
test "a new goal acknowledgement clears stale terminal markers" {
  let state = @harness.GoalTrialState("ship it")
  state.observe(GoalUpdated(goal=None)) |> ignore
  state.observe(GoalBlocked(reason="old process")) |> ignore
  state.expect_goal_acknowledgement()
  state.observe(GoalUpdated(goal=Some("ship it"))) |> ignore
  assert_true(state.observe(AgentFinished(answer="keep working")) is None)
}
