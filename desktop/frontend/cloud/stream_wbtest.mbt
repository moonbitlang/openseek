///|
fn watch_fixture(state : State) -> (State, StreamLease) {
  let stream = StreamLease::new()
  let next = metadata_update(state, WatchOpened(state.epoch, "session", stream))
  (next, stream)
}

///|
fn watch_snapshot(
  state : State,
  stream : StreamLease,
  task : String?,
  seq : Int32,
  data : ControlState,
) -> State {
  metadata_update(
    state,
    WatchEvent(
      state.epoch,
      "session",
      stream,
      Snapshot({ session_id: "session", task_id: task, seq, data, }),
    ),
  )
}

///|
fn watch_event(
  state : State,
  stream : StreamLease,
  task : String,
  seq : Int32,
  kind : String,
  data : Json,
) -> State {
  metadata_update(
    state,
    WatchEvent(
      state.epoch,
      "session",
      stream,
      EngineEvent({ session_id: "session", task_id: task, seq, kind, data, }),
    ),
  )
}

///|
test "Cloud subscription uses its first snapshot as baseline and fences replaced observers" {
  let (state, stream) = watch_fixture(controls_fixture())
  let idle : ControlState = {
    active_task_id: None,
    status: Idle,
    paused: false,
    queue: [],
    steers: [],
  }
  let before = watch_event(state, stream, "task", 3, "assistant_delta", {
    "content": "before baseline",
  })
  assert_true(before == state)
  let ready = watch_snapshot(state, stream, None, 0, idle)
  assert_false(ready.conversations["session"].generating)
  assert_eq(ready.conversations["session"].task, None)
  let running = watch_event(ready, stream, "first", 1, "task_started", {})
  assert_true(running.conversations["session"].generating)
  let partial = watch_event(running, stream, "first", 2, "assistant_delta", {
    "content": "new",
  })
  assert_eq(partial.conversations["session"].streaming_response, Some("new"))
  assert_true(
    watch_event(partial, stream, "first", 2, "assistant_delta", {
      "content": "duplicate",
    }) ==
    partial,
  )
  let (reopened, replacement) = watch_fixture(partial)
  assert_true(
    watch_event(reopened, stream, "first", 3, "task_finished", {
      "status": "failed",
    }) ==
    reopened,
  )
  let current = watch_snapshot(reopened, replacement, Some("next"), 1, {
    ..idle,
    active_task_id: Some("next"),
    status: Running,
  })
  assert_eq(current.conversations["session"].task, Some("next"))
}

///|
test "Cloud old terminal and queue snapshots cannot end the next task" {
  let (state, stream) = watch_fixture(controls_fixture())
  let control = controls_fixture().conversations["session"].control.unwrap()
  let state = watch_snapshot(state, stream, Some("task"), 2, control)
  let completed = watch_event(state, stream, "task", 3, "task_finished", {
    "status": "completed",
  })
  let next = watch_event(completed, stream, "next", 1, "task_started", {
    "previous_task_id": "task",
    "submission_id": "queue",
  })
  let old_start = watch_event(next, stream, "old", 1, "task_started", {
    "previous_task_id": "task",
  })
  assert_true(old_start == next)
  let late = watch_event(next, stream, "task", 99, "task_finished", {
    "status": "failed",
  })
  assert_true(late == next)
  let late = watch_snapshot(late, stream, Some("task"), 100, {
    ..control,
    status: Idle,
    active_task_id: None,
  })
  assert_true(late == next)
  assert_eq(late.conversations["session"].task, Some("next"))
  assert_true(late.conversations["session"].generating)
}

///|
test "Cloud history reconciliation counts repeated messages without duplicating live records" {
  let event : Event = {
    session_id: "session",
    task_id: "task",
    seq: 2,
    kind: "user",
    data: { "content": "same input" },
  }
  let conversation = {
    ..Conversation::empty(),
    events: [event, { ..event, seq: 3, }],
  }
  let record : Record = {
    task_id: "task",
    kind: "user",
    data: event.data,
    created_at: 1,
  }
  assert_eq(conversation.events_not_in([record]).length(), 1)
  assert_true(conversation.events_not_in([record, record]).is_empty())
  let state = controls_fixture().replace("session", {
    ..conversation,
    request: 9,
    stream: Some(StreamLease::new()),
    loading: false,
    generating: true,
    control: controls_fixture().conversations["session"].control,
  })
  let loaded = metadata_update(
    state,
    Loaded(1, "session", 9, { messages: [record], generating: false, }),
  )
  assert_eq(loaded.conversations["session"].items().length(), 2)
  // A stale history generation flag cannot settle the session subscription.
  assert_true(loaded.conversations["session"].generating)
}

///|
test "Cloud subscription closure is not a server Stop and old callbacks cannot revive another account" {
  let (state, stream) = watch_fixture(controls_fixture())
  let state = watch_snapshot(
    state,
    stream,
    Some("task"),
    2,
    controls_fixture().conversations["session"].control.unwrap(),
  )
  stream.close()
  assert_true(
    watch_event(state, stream, "task", 3, "task_finished", {
      "status": "failed",
    }) ==
    state,
  )
  assert_true(state.conversations["session"].generating)
  assert_true(state.conversations["session"].control_inputs.is_empty())
  let changed = metadata_update(state, AccountChanged(Some("other")))
  assert_true(
    metadata_update(changed, WatchOpened(1, "session", StreamLease::new())) ==
    changed,
  )
}

///|
test "Cloud observer failure retains the confirmed queue as read-only" {
  let (state, stream) = watch_fixture(controls_fixture())
  let control : ControlState = {
    active_task_id: Some("task"),
    status: Running,
    paused: false,
    queue: [{ id: "queued", content: Content([Text("Keep this input")]), }],
    steers: [],
  }
  let state = watch_snapshot(state, stream, Some("task"), 2, control)
  let disconnected = metadata_update(
    state,
    WatchEnded(1, "session", stream, Some(Unreachable)),
  )
  let conversation = disconnected.conversations["session"]
  assert_true(conversation.control == Some(control))
  assert_true(
    conversation.control_context()
    is [@composer.QueuedInputPanel(enabled=false, ..)],
  )
  let recovered = metadata_update(
    disconnected,
    Loaded(1, "session", conversation.request, {
      messages: [],
      generating: true,
    }),
  )
  assert_eq(
    recovered.conversations["session"].notice,
    Some(Failure::Unreachable.label()),
  )
  assert_true(
    recovered.conversations["session"].control.unwrap().queue == control.queue,
  )
}

///|
test "Cloud current terminal settles after the idle control snapshot" {
  for
    terminal in [
      ({ "status": "completed", "result": { "status": "ok" } } : Json),
      (
        {
          "status": "failed",
          "result": { "status": "aborted", "reason": "interrupted" },
        } : Json),
    ] {
    let (state, stream) = watch_fixture(controls_fixture())
    let control = controls_fixture().conversations["session"].control.unwrap()
    let state = watch_snapshot(state, stream, Some("task"), 2, control)
    let partial = watch_event(state, stream, "task", 3, "assistant_delta", {
      "content": "unfinished",
    })
    let idle = watch_snapshot(partial, stream, Some("task"), 4, {
      ..control,
      active_task_id: None,
      status: Idle,
    })
    let before = idle.conversations["session"]
    assert_false(before.generating)
    let finished = watch_event(
      idle, stream, "task", 5, "task_finished", terminal,
    )
    let after = finished.conversations["session"]
    assert_true(after.streaming_response is None)
    assert_true(after.heartbeat is None)
    assert_true(
      after.events.any(event => {
        event.kind == "task_finished" && event.data == terminal
      }),
    )
    assert_true(after.request > before.request)
    assert_eq(after.last_seq, Some(5))
    assert_true(
      watch_event(finished, stream, "task", 5, "task_finished", terminal) ==
      finished,
    )
    let next = watch_event(finished, stream, "next", 1, "task_started", {
      "previous_task_id": "task",
    })
    assert_true(
      watch_event(next, stream, "task", 6, "task_finished", terminal) == next,
    )
  }
}

///|
test "Cloud steer receipts settle input without duplicating the durable user message" {
  let pending = controls_submit(controls_fixture(), @composer.SteerNow)
  let input = pending.conversations["session"].control_inputs[0]
  let (state, stream) = watch_fixture(pending)
  let state = watch_snapshot(
    state,
    stream,
    Some("task"),
    2,
    controls_fixture().conversations["session"].control.unwrap(),
  )
  let content : Json = { "content": "Follow up", "submission_id": input.key }
  let user = watch_event(state, stream, "task", 3, "user", content)
  let applied = watch_event(user, stream, "task", 4, "steer_applied", {
    "content": "Follow up",
    "submission_id": input.key,
    "kind": "prompt",
  })
  assert_true(applied.conversations["session"].control_inputs.is_empty())
  assert_eq(
    applied.conversations["session"].events
    .filter(event => event.kind == "user")
    .length(),
    1,
  )
  let history : History = {
    generating: true,
    messages: [
      { task_id: "task", kind: "user", data: content, created_at: 10, },
    ],
  }
  let loaded = metadata_update(
    applied,
    Loaded(1, "session", applied.conversations["session"].request, history),
  )
  assert_eq(loaded.conversations["session"].items().length(), 1)
}
