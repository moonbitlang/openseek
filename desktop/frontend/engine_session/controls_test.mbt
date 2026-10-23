///|
test "native command effects do not depend on the transport" {
  let state : @engine_session.State = {
    goal: None,
    edit: None,
    pending: None,
    compaction: NotCompacting,
  }
  let (editing, command) = state.act(EditGoal, "edit", 3, running=false)
  assert_true(command is None)
  let (pending, command) = editing.act(
    SetGoal("  Ship it  "),
    "goal",
    3,
    running=false,
  )
  assert_true(command == Some(@wire.GoalSet(text="Ship it", auto=false)))
  assert_true(pending.input().pending is Some(@composer.GoalSetting("Ship it")))
  assert_true(
    pending.restore_goal(None, [(3, @transcript.GoalSet("Ship it"))]).pending
    is Some(_),
  )
  assert_true(
    pending.restore_goal(Some({ text: "Ship it", blocked: None, }), [
      (4, @transcript.GoalSet("Ship it")),
    ]).pending
    is None,
  )
  let request : @wire.Command = @wire.JobsSnapshot(request_id="native-request")
  let (unchanged, effect) = state.act(
    Send(request),
    "request",
    3,
    running=false,
  )
  assert_true(unchanged == state && effect == Some(request))
  let (queued, command) = state.act(
    @engine_session.slash_action("compact").unwrap(),
    "compact",
    3,
    running=true,
  )
  assert_true(command == Some(@wire.Compact) && queued.compaction is Queued)
  let (still_queued, duplicate) = queued.act(
    Send(@wire.Compact),
    "again",
    3,
    running=true,
  )
  assert_true(duplicate is None && still_queued == queued)
}
