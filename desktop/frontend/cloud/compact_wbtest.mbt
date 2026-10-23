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
  assert_true(queued.controls.is_compact_queued() && queued.generating)
  assert_false(queued.controls.is_compacting())
  assert_true(request_compact(state) == state)
  let request = queued.controls.compact_request.unwrap()
  let accepted = metadata_update(
    state,
    CommandFinished(1, "session", request, @wire.Compact, Accepted),
  )
  assert_true(accepted.conversations["session"].controls.is_compact_queued())
  assert_true(
    accepted.conversations["session"].controls.compact_request is None,
  )
  let stream = queued.stream.unwrap()
  let automatic = native_event(
    accepted,
    stream,
    Some("task"),
    3,
    @wire.AutoCompactionStarted(from_sequence=1, to_sequence=2),
  )
  assert_true(automatic.conversations["session"].controls.is_compact_queued())
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
  assert_true(automatic.conversations["session"].controls.is_compact_queued())
  let ended = watch_event(automatic, stream, "task", 5, "task_finished", {
    "status": "completed",
  })
  assert_true(ended.conversations["session"].controls.is_compact_queued())
  assert_false(ended.conversations["session"].generating)
  let started = native_event(
    ended,
    stream,
    None,
    6,
    @wire.CompactionStarted(from_sequence=1, to_sequence=2),
  )
  assert_true(started.conversations["session"].controls.is_compacting())
  assert_false(started.conversations["session"].controls.is_compact_queued())
  assert_true(
    metadata_update(
      started,
      CommandFinished(1, "session", request, @wire.Compact, Accepted),
    ) ==
    started,
  )
  let finished = native_event(
    started,
    stream,
    None,
    7,
    @wire.CompactionFinished(from_sequence=1, to_sequence=2, summary="Manual"),
  )
  assert_false(finished.conversations["session"].controls.is_compacting())
  assert_false(finished.conversations["session"].generating)
  assert_false(finished.conversations["session"].controls.is_compact_queued())
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
    assert_eq(conversation.controls.is_compact_queued(), queued)
    assert_eq(conversation.controls.is_compacting(), active)
    assert_true(conversation.controls.compact_request is None)
    assert_false(conversation.generating)
    assert_eq(restored.can_send("session"), !queued && !active)
  }
}

///|
test "Cloud compaction rejection and lost response preserve their distinct outcomes" {
  let state = request_compact(controls_fixture())
  let request = state.conversations["session"].controls.compact_request.unwrap()
  let unknown = metadata_update(
    state,
    CommandFailed(1, "session", request, @wire.Compact, Unreachable),
  )
  assert_true(unknown.conversations["session"].controls.is_compact_queued())
  let rejected = metadata_update(
    state,
    CommandFinished(
      1,
      "session",
      request,
      @wire.Compact,
      Rejected("compaction_busy"),
    ),
  )
  assert_false(rejected.conversations["session"].controls.is_compact_queued())
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
  assert_false(failed.conversations["session"].controls.is_compacting())
  assert_true(failed.conversations["session"].generating)
  let other = metadata_update(state, AccountChanged(Some("other")))
  assert_true(
    metadata_update(
      other,
      CommandFinished(1, "session", request, @wire.Compact, Accepted),
    ) ==
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
  let request = requested.conversations["session"].controls.compact_request.unwrap()
  let refused = metadata_update(
    requested,
    CommandFailed(1, "session", request, @wire.Compact, ServiceNotConfigured),
  )
  assert_false(refused.conversations["session"].controls.is_compact_queued())
  assert_true(refused.conversations["session"].controls.compact_request is None)
  assert_true(refused.can_send("session"))
  assert_eq(
    refused.conversations["session"].notice,
    Some(Failure::ServiceNotConfigured.label()),
  )
  for failure in ([Unreachable, Http(503), Malformed] : Array[Failure]) {
    let unknown = metadata_update(
      requested,
      CommandFailed(1, "session", request, @wire.Compact, failure),
    )
    assert_true(unknown.conversations["session"].controls.is_compact_queued())
    assert_eq(
      unknown.conversations["session"].controls.compact_request,
      Some(request),
    )
  }
}
