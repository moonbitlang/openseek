///|
test "raising goal decoder errors stay actionable at the agent boundary" {
  debug_inspect(
    decode_goal_status({ "status": "continuing" }),
    content=(
      #|Err("goal requires a string \"remaining\" when status is \"continuing\"")
    ),
  )
}

///|
/// A session whose standing goal is durably blocked: `[goal]` then a
/// `[goal blocked]` marker, so `current_goal().blocked()` is true and a fresh
/// cadence seeds `durably_blocked = true`.
fn blocked_goal_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("blocked"), system_prompt="sys")
  .append(Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship it")))
  .append(User(UserMessage(Content([Text("work")]))))
  .append(Runtime(RuntimeNotice("\{@agent_session.GoalBlockedPrefix}\nstuck")))
}

///|
/// A session with a plain standing goal (never blocked).
fn open_goal_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("open"), system_prompt="sys").append(
    Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship it")),
  )
}

///|
/// Batch orderings, both starting durable states. `continue` keys off the
/// durable state, so a same-batch block+continue cancels when the goal was
/// open but resolves to an unblock when it was already blocked.
test "block/continue batch orderings resolve to the right pending marker" {
  // open + block -> continue  ==> nothing durable (block cancelled)
  let a = GoalCadence(open_goal_session(), tool_registered=true)
  a.record_goal_blocked("x")
  a.record_goal_continuing()
  assert_true(a.pending_block is NoBlockTransition)

  // blocked + block -> continue  ==> unblock (the durable block is rescinded)
  let b = GoalCadence(blocked_goal_session(), tool_registered=true)
  b.record_goal_blocked("x")
  b.record_goal_continuing()
  assert_true(b.pending_block is PendingUnblock)

  // blocked + block -> continue -> block  ==> block wins (stays blocked)
  let c = GoalCadence(blocked_goal_session(), tool_registered=true)
  c.record_goal_blocked("x")
  c.record_goal_continuing()
  c.record_goal_blocked("y")
  assert_true(c.pending_block is PendingBlock("y"))

  // blocked + continue -> block -> continue  ==> unblock
  let d = GoalCadence(blocked_goal_session(), tool_registered=true)
  d.record_goal_continuing()
  d.record_goal_blocked("x")
  d.record_goal_continuing()
  assert_true(d.pending_block is PendingUnblock)

  // open + continue -> block -> continue  ==> nothing durable
  let e = GoalCadence(open_goal_session(), tool_registered=true)
  e.record_goal_continuing()
  e.record_goal_blocked("x")
  e.record_goal_continuing()
  assert_true(e.pending_block is NoBlockTransition)
}

///|
/// goal(blocked) disarms the turn's finish check (like continuing) and
/// schedules a `[goal blocked]` marker.
test "blocked answers the finish check and schedules a block marker" {
  let cadence = GoalCadence(open_goal_session(), tool_registered=true)
  assert_true(cadence.due_finish_check() is Some(_))
  cadence.record_goal_blocked("stuck")
  assert_true(cadence.due_finish_check() is None)
  assert_true(cadence.pending_block is PendingBlock("stuck"))
}

///|
/// continue after a PRIOR-batch (durable) block schedules the unblock marker
/// that resumes auto-continuation — the case the naive design missed.
test "continue after a durable block schedules an unblock marker" {
  let cadence = GoalCadence(blocked_goal_session(), tool_registered=true)
  assert_true(cadence.durably_blocked)
  cadence.record_goal_continuing()
  assert_true(cadence.pending_block is PendingUnblock)
}

///|
/// met abandons a pending block/unblock (the goal is going away) and a new
/// goal or clear resets the durable-blocked cache.
test "met and a superseding set/clear reset the block state" {
  let cadence = GoalCadence(blocked_goal_session(), tool_registered=true)
  cadence.record_goal_continuing()
  assert_true(cadence.pending_block is PendingUnblock)
  cadence.record_goal_met()
  assert_true(cadence.pending_block is NoBlockTransition)
  assert_true(cadence.pending_tombstone)
  // A superseding set clears the durable-blocked cache for the new goal.
  let other = GoalCadence(blocked_goal_session(), tool_registered=true)
  assert_true(other.durably_blocked)
  other.observe_notice("\{@agent_session.GoalPrefix}\nnew objective")
  assert_false(other.durably_blocked)
  assert_true(other.pending_block is NoBlockTransition)
}
