///|
test "native command effects do not depend on the transport" {
  let state = @engine_session.State::empty()
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

///|
test "goal delivery keeps input until confirmation and ignores superseded responses" {
  let (editing, _) = @engine_session.State::empty().act(
    EditGoal,
    "edit",
    4,
    running=false,
  )
  let command = @wire.GoalSet(text="First", auto=false)
  let (first, _) = editing.act(SetGoal("First"), "first", 4, running=false)
  let accepted = first.delivered(command, "first", Accepted)
  assert_true(accepted.pending is Some(_))
  assert_true(accepted.goal is None)
  assert_true(accepted.delivered(command, "first", Unknown) == accepted)
  let (editing, _) = accepted.act(EditGoal, "edit-again", 4, running=false)
  let (second, _) = editing.act(SetGoal("Second"), "second", 4, running=false)
  assert_true(second.delivered(command, "first", Rejected) == second)
  assert_true(second.delivered(command, "first", Accepted) == second)
  let (new_edit, _) = second.act(EditGoal, "new-edit", 4, running=false)
  let new_edit = { ..new_edit, edit: Some({ draft: "Keep editing", }), }
  let rejected = new_edit.delivered(
    @wire.GoalSet(text="Second", auto=false),
    "second",
    Rejected,
  )
  assert_true(rejected.pending is None)
  assert_eq(rejected.input().draft, Some("Keep editing"))
  let confirmed = second.restore_goal(
    Some({ text: "Second", blocked: None, }),
    [(5, @transcript.GoalSet("Second"))],
  )
  assert_true(confirmed.pending is None)
  assert_true(confirmed.delivered(command, "second", Unknown) == confirmed)
}

///|
test "compact delivery and automatic events cannot settle another manual request" {
  let compact = @wire.Compact
  let (requested, _) = @engine_session.State::empty().act(
    Send(compact),
    "first",
    0,
    running=true,
  )
  let accepted = requested.delivered(compact, "first", Accepted)
  assert_true(accepted.compaction is Queued)
  assert_true(accepted.compact_request is None)
  let automatic = accepted.event(
    @wire.AutoCompactionStarted(from_sequence=1, to_sequence=2),
  )
  assert_true(automatic.is_compacting() && automatic.is_compact_queued())
  let automatic = automatic.event(
    @wire.AutoCompactionFinished(
      from_sequence=1,
      to_sequence=2,
      summary="checkpoint",
    ),
  )
  assert_false(automatic.is_compacting())
  assert_true(automatic.compaction is Queued)
  let started = automatic.event(
    @wire.CompactionStarted(from_sequence=1, to_sequence=2),
  )
  assert_true(started.compaction is Compacting)
  assert_true(started.delivered(compact, "first", Rejected) == started)
  let finished = started.event(
    @wire.CompactionFinished(from_sequence=1, to_sequence=2, summary="manual"),
  )
  let (second, _) = finished.act(Send(compact), "second", 2, running=false)
  assert_true(second.delivered(compact, "first", Rejected) == second)
  assert_true(second.delivered(compact, "second", Unknown) == second)
  let rejected = second.delivered(compact, "second", Rejected)
  assert_true(rejected.compaction is NotCompacting)
  assert_true(rejected.compact_request is None)
}

///|
test "compaction observation distinguishes an in-flight response from a new baseline" {
  let (requested, _) = @engine_session.State::empty().act(
    Send(@wire.Compact),
    "request",
    0,
    running=false,
  )
  assert_true(
    requested.observe_compaction(queued=false, compacting=false, baseline=false) ==
    requested,
  )
  let restored = requested.observe_compaction(
    queued=false,
    compacting=false,
    baseline=true,
  )
  assert_true(
    restored.compaction is NotCompacting && restored.compact_request is None,
  )
  let overlap = requested.observe_compaction(
    queued=true,
    compacting=true,
    baseline=true,
  )
  assert_true(overlap.is_compact_queued() && overlap.is_compacting())
  assert_true(overlap.compact_request is None)
  let queued = overlap.event(
    @wire.AutoCompactionFinished(
      from_sequence=1,
      to_sequence=2,
      summary="checkpoint",
    ),
  )
  assert_true(queued.is_compact_queued())
  assert_false(queued.is_compacting())
}
