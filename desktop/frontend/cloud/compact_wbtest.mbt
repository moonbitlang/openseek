///|
fn request_compact(state : State) -> State {
  goal_action(
    state,
    @composer.SlashCommand(identity=goal_identity(), command="compact"),
  )
}

///|
test "Cloud manual compaction survives automatic compaction and chat completion" {
  let state = request_compact(controls_fixture())
  let queued = state.conversations["session"]
  assert_true(queued.compact_queued && queued.generating)
  assert_false(queued.compacting)
  assert_true(request_compact(state) == state)
  let request = queued.compact_request.unwrap()
  let accepted = metadata_update(
    state,
    CompactFinished(1, "session", request, Accepted),
  )
  assert_true(accepted.conversations["session"].compact_queued)
  assert_true(accepted.conversations["session"].compact_request is None)
  let stream = queued.stream.unwrap()
  let automatic = native_event(
    accepted,
    stream,
    Some("task"),
    3,
    @wire.AutoCompactionStarted(from_sequence=1, to_sequence=2),
  )
  assert_true(automatic.conversations["session"].compact_queued)
  let automatic = native_event(
    automatic,
    stream,
    Some("task"),
    4,
    @wire.AutoCompactionFinished(
      from_sequence=1,
      to_sequence=2,
      summary="Automatic",
    ),
  )
  assert_true(automatic.conversations["session"].compact_queued)
  let ended = watch_event(automatic, stream, "task", 5, "task_finished", {
    "status": "completed",
  })
  assert_true(ended.conversations["session"].compact_queued)
  assert_false(ended.conversations["session"].generating)
  let started = native_event(
    ended,
    stream,
    None,
    6,
    @wire.CompactionStarted(from_sequence=1, to_sequence=2),
  )
  assert_true(started.conversations["session"].compacting)
  assert_false(started.conversations["session"].compact_queued)
  assert_true(
    metadata_update(started, CompactFinished(1, "session", request, Accepted)) ==
    started,
  )
  let finished = native_event(
    started,
    stream,
    None,
    7,
    @wire.CompactionFinished(from_sequence=1, to_sequence=2, summary="Manual"),
  )
  assert_false(finished.conversations["session"].compacting)
  assert_false(finished.conversations["session"].generating)
  assert_false(finished.conversations["session"].compact_queued)
}

///|
test "Cloud restores queued and active compaction from the session baseline" {
  for (queued, active) in [(true, false), (false, true), (false, false)] {
    let requested = request_compact(controls_fixture())
    let (state, stream) = watch_fixture(requested)
    let snapshot = {
      ..state.conversations["session"].control.unwrap(),
      active_task_id: None,
      status: Idle,
      compact_queued: queued,
      compacting: active,
    }
    let restored = watch_snapshot(state, stream, Some("task"), 1, snapshot)
    let conversation = restored.conversations["session"]
    assert_eq(conversation.compact_queued, queued)
    assert_eq(conversation.compacting, active)
    assert_true(conversation.compact_request is None)
    assert_false(conversation.generating)
    assert_eq(restored.can_send("session"), !queued && !active)
  }
}

///|
test "Cloud compaction rejection and lost response preserve their distinct outcomes" {
  let state = request_compact(controls_fixture())
  let request = state.conversations["session"].compact_request.unwrap()
  let unknown = metadata_update(
    state,
    CompactFailed(1, "session", request, Unreachable),
  )
  assert_true(unknown.conversations["session"].compact_queued)
  let rejected = metadata_update(
    state,
    CompactFinished(1, "session", request, Rejected("compaction_busy")),
  )
  assert_false(rejected.conversations["session"].compact_queued)
  assert_true(rejected.conversations["session"].notice is Some(_))
  assert_true(rejected.conversations["session"].generating)
  let stream = state.conversations["session"].stream.unwrap()
  let started = native_event(
    state,
    stream,
    Some("task"),
    3,
    @wire.CompactionStarted(from_sequence=1, to_sequence=2),
  )
  let failed = native_event(
    started,
    stream,
    Some("task"),
    4,
    @wire.CompactionFailed(error="Cannot summarize"),
  )
  assert_false(failed.conversations["session"].compacting)
  assert_true(failed.conversations["session"].generating)
  let other = metadata_update(state, AccountChanged(Some("other")))
  assert_true(
    metadata_update(other, CompactFinished(1, "session", request, Accepted)) ==
    other,
  )
}

///|
test "Cloud missing model credentials reject compact without retaining a queued command" {
  let base = controls_fixture()
  let idle = base.replace("session", {
    ..base.conversations["session"],
    generating: false,
  })
  let requested = request_compact(idle)
  let request = requested.conversations["session"].compact_request.unwrap()
  let refused = metadata_update(
    requested,
    CompactFailed(1, "session", request, ServiceNotConfigured),
  )
  assert_false(refused.conversations["session"].compact_queued)
  assert_true(refused.conversations["session"].compact_request is None)
  assert_true(refused.can_send("session"))
  assert_eq(
    refused.conversations["session"].notice,
    Some(Failure::ServiceNotConfigured.label()),
  )
  for failure in ([Unreachable, Http(503), Malformed] : Array[Failure]) {
    let unknown = metadata_update(
      requested,
      CompactFailed(1, "session", request, failure),
    )
    assert_true(unknown.conversations["session"].compact_queued)
    assert_eq(unknown.conversations["session"].compact_request, Some(request))
  }
}
