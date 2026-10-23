///|
fn native_event(
  state : State,
  stream : StreamLease,
  task : String?,
  seq : Int32,
  event : @wire.Event,
) -> State {
  metadata_update(
    state,
    WatchEvent(
      state.epoch,
      "session",
      stream,
      NativeEvent({
        session_id: "session",
        task_id: task,
        seq,
        data: event.to_json(),
      }),
    ),
  )
}

///|
test "Cloud native event envelopes allow idle context without relaxing task events" {
  let payload = @wire.GoalUpdated(goal=Some("Ship the change")).to_json()
  let frame : Json = {
    "kind": "engine_event",
    "session_id": "session",
    "task_id": null,
    "seq": 21,
    "data": payload,
  }
  guard decode_control_event("engine_event", frame) is NativeEvent(decoded) else {
    fail("expected a native event")
  }
  assert_eq(decoded.task_id, None)
  assert_eq(decoded.data, payload)
  assert_true(
    @wire.parse(decoded.data)
    is Some(@wire.GoalUpdated(goal=Some("Ship the change"))),
  )
  for
    invalid in [
      (
        {
          "kind": "engine_event",
          "session_id": "session",
          "seq": 1,
          "data": payload,
        } : Json),
      {
        "kind": "engine_event",
        "session_id": "session",
        "task_id": null,
        "seq": 0,
        "data": payload,
      },
      {
        "kind": "engine_event",
        "session_id": "session",
        "task_id": null,
        "seq": 1,
        "data": null,
      },
      {
        "kind": "task_finished",
        "session_id": "session",
        "task_id": null,
        "seq": 1,
        "data": {},
      },
    ] {
    let malformed = try {
      ignore(decode_control_event("message", invalid))
      false
    } catch {
      @cloud_client.RequestError(Malformed) => true
      _ => false
    }
    assert_true(malformed)
  }
}

///|
test "Cloud native idle events and new tasks share the snapshot sequence" {
  let (state, stream) = watch_fixture(controls_fixture())
  let control = state.conversations["session"].control.unwrap()
  let state = watch_snapshot(state, stream, Some("task"), 19, control)
  let ended = watch_event(state, stream, "task", 20, "task_finished", {
    "status": "completed",
  })
  let goal = native_event(
    ended,
    stream,
    None,
    21,
    @wire.GoalUpdated(goal=Some("Ship")),
  )
  assert_false(goal.conversations["session"].generating)
  assert_eq(goal.conversations["session"].last_seq, Some(21))
  let compacting = native_event(
    goal,
    stream,
    None,
    22,
    @wire.CompactionStarted(from_sequence=1, to_sequence=4),
  )
  assert_true(compacting.conversations["session"].controls.is_compacting())
  assert_false(compacting.conversations["session"].generating)
  let snapshot = watch_snapshot(compacting, stream, Some("task"), 23, {
    ..control,
    active_task_id: None,
    status: Idle,
    compact_queued: false,
    compacting: true,
  })
  let finished = native_event(
    snapshot,
    stream,
    None,
    24,
    @wire.CompactionFinished(
      from_sequence=1,
      to_sequence=4,
      summary="Earlier work",
    ),
  )
  assert_false(finished.conversations["session"].controls.is_compacting())
  assert_true(
    native_event(
      finished,
      stream,
      None,
      22,
      @wire.CompactionStarted(from_sequence=1, to_sequence=4),
    ) ==
    finished,
  )
  let next = watch_event(finished, stream, "next", 26, "task_started", {
    "previous_task_id": "task",
  })
  assert_true(next.conversations["session"].generating)
  assert_eq(next.conversations["session"].task, Some("next"))
  assert_true(watch_event(next, stream, "reset", 1, "task_started", {}) == next)
}

///|
test "Cloud native command errors report context without ending or attributing a command" {
  let (state, stream) = watch_fixture(controls_fixture())
  let state = watch_snapshot(
    state,
    stream,
    Some("task"),
    10,
    state.conversations["session"].control.unwrap(),
  )
  let failed = native_event(
    state,
    stream,
    Some("task"),
    11,
    @wire.CommandError(error="Cannot compact now"),
  )
  assert_true(failed.conversations["session"].generating)
  assert_eq(failed.conversations["session"].task, Some("task"))
  assert_true(failed.conversations["session"].notice is None)
  assert_true(
    failed.conversations["session"].document.events.unwrap_or([]).is_empty(),
  )
  let ended = watch_event(failed, stream, "task", 12, "task_finished", {
    "status": "completed",
  })
  let idle = native_event(
    ended,
    stream,
    None,
    13,
    @wire.CommandError(error="Goal is empty"),
  )
  assert_false(idle.conversations["session"].generating)
  assert_true(idle.conversations["session"].notice is None)
}

///|
test "Cloud compacting snapshots default absent state and recover actual compression" {
  let fixture = control_snapshot_fixture()
  let snapshot : ControlSnapshot = @json.from_json(fixture)
  assert_false(snapshot.data.compacting)
  guard fixture is Object(fields) && fields["data"] is Object(data) else {
    fail("snapshot fixture")
  }
  let fields = fields.copy()
  let data = data.copy()
  data["compacting"] = true
  fields["data"] = Json(data)
  let snapshot : ControlSnapshot = @json.from_json(Json(fields))
  let (state, stream) = watch_fixture(controls_fixture())
  let recovered = watch_snapshot(state, stream, Some("task"), 50, {
    ..snapshot.data,
    active_task_id: None,
    status: Idle,
  })
  assert_true(recovered.conversations["session"].controls.is_compacting())
  assert_false(recovered.conversations["session"].generating)
  data["compacting"] = null
  fields["data"] = Json(data)
  let invalid = try {
    let _ : ControlSnapshot = @json.from_json(Json(fields))
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
}

///|
test "Cloud host failure settles idle commands without closing observation" {
  let initial = request_compact(
    goal_action(
      controls_fixture(),
      @composer.GoalEditStarted(identity=goal_identity()),
    ),
  )
  let pending = goal_action(
    initial,
    @composer.GoalSubmitted(
      identity=goal_identity(),
      draft="Keep this goal",
      prompt_present=false,
    ),
  )
  let conversation = pending.conversations["session"]
  let stream = conversation.stream.unwrap()
  let failure = decode_control_event("engine_failed", {
    "kind": "engine_failed",
    "session_id": "session",
    "task_id": null,
    "seq": 3,
    "data": { "error": "Engine could not start" },
  })
  let failed = metadata_update(
    pending,
    WatchEvent(1, "session", stream, failure),
  )
  let restored = failed.conversations["session"]
  assert_eq(restored.controls.input().draft, Some("Keep this goal"))
  assert_true(restored.controls.input().pending is None)
  assert_false(
    restored.controls.is_compacting() || restored.controls.is_compact_queued(),
  )
  assert_true(restored.controls.compact_request is None)
  assert_eq(restored.notice, Some("Engine could not start"))
  assert_true(stream.active && restored.watch_status == Watching)
  assert_eq(restored.generating, conversation.generating)
  let settled = watch_snapshot(failed, stream, Some("task"), 4, {
    ..conversation.control.unwrap(),
    active_task_id: None,
    status: Idle,
    compacting: false,
    compact_queued: false,
    paused: true,
  })
  assert_eq(settled.conversations["session"].last_seq, Some(4))
  assert_true(settled.can_send("session"))
  assert_true(
    metadata_update(settled, WatchEvent(1, "session", stream, failure)) ==
    settled,
  )
}

///|
test "Cloud retains native notification text until completion and fences it by task" {
  let (state, stream) = watch_fixture(controls_fixture())
  let state = watch_snapshot(
    state,
    stream,
    Some("task"),
    1,
    state.conversations["session"].control.unwrap(),
  )
  let replied = native_event(
    state,
    stream,
    Some("task"),
    2,
    @wire.AssistantMessage(content="Native answer"),
  )
  assert_eq(
    replied.conversations["session"].notification_answer,
    Some("Native answer"),
  )
  assert_true(replied.conversations["session"].records.is_empty())
  let finished = watch_event(replied, stream, "task", 3, "task_finished", {
    "status": "completed",
  })
  assert_eq(
    finished.conversations["session"].notification_answer,
    Some("Native answer"),
  )
  let next = watch_event(finished, stream, "next", 4, "task_started", {
    "previous_task_id": "task",
  })
  let late = native_event(
    next,
    stream,
    Some("task"),
    5,
    @wire.AssistantMessage(content="Late answer"),
  )
  assert_true(late.conversations["session"].notification_answer is None)
}
