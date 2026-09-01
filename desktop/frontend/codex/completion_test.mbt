///|
test "Codex composer reports selected task run status" {
  let context : @codex.ComposerContext = {
    channel: @interop.ChannelId::Local,
    model_control: {
      id: "codex-model-picker",
      groups: [],
      selected: "",
      disabled: true,
      open: false,
      title: "Model",
    },
    reasoning_control: None,
    file_candidates: [],
    open_files: [],
    active_file: None,
    file_index: @composer.FileIndexReady(epoch=1, truncated=false),
  }

  // A loaded in-progress turn is enough even when a lifecycle notification
  // was missed before this page attached.
  let turn_running = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-turn-running",
      "turns": [
        {
          "id": "turn-1",
          "status": "inProgress",
          "startedAt": 1000,
          "items": [],
        },
      ],
    },
  })
  let turn_input = turn_running.composer_input(context)
  guard turn_input.run is Some(turn_run) else {
    fail("an in-progress Codex turn should produce a composer heartbeat")
  }
  assert_true(turn_run.stage is @composer.Working)
  assert_eq(turn_run.started_ms, Some(1_000_000.0))
  assert_eq(turn_run.tokens, None)
  assert_true(
    turn_input.presentation.primary_action
    is @composer.Running(can_stop=true, ..),
  )

  // The task-level status also covers an adopted run whose turns have not
  // been loaded yet, such as immediately after reconnect.
  let task_running = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-task-running",
      "status": { "type": "active", "activeFlags": [] },
      "turns": [],
    },
  })
  let task_input = task_running.composer_input(context)
  guard task_input.run is Some(task_run) else {
    fail("an active Codex task should produce a composer heartbeat")
  }
  assert_true(task_run.stage is @composer.Working)
  assert_eq(task_run.tokens, None)
  guard task_input.presentation.primary_action
    is @composer.Running(steer_available~, can_stop~, ..) else {
    fail("an active Codex task without a turn id must keep running controls")
  }
  assert_false(steer_available)
  assert_false(can_stop)

  let idle = @codex.State::from_thread_snapshot({
    "thread": {
      "id": "thread-idle",
      "status": { "type": "idle" },
      "turns": [{ "id": "turn-1", "status": "completed", "items": [] }],
    },
  })
  assert_eq(idle.composer_input(context).run, None)

  // Live lifecycle notifications drive the same projection used by the
  // mounted composer, then remove the row when the turn completes.
  let emit : @cmd.Emit[@codex.Msg] = @cmd.Emit(_ => @cmd.none)
  let open_external = (_ : String) => @cmd.none
  let (_, started) = @codex.update(
    emit,
    @codex.Msg::notification(
      "turn/started",
      {
        "threadId": "thread-idle",
        "turn": {
          "id": "turn-2",
          "status": "inProgress",
          "startedAt": 2000,
          "items": [],
        },
      },
      1,
    ),
    idle,
    @interop.ChannelId::Local,
    open_external,
  )
  guard started.composer_input(context).run is Some(live_run) else {
    fail("a live Codex turn should produce a composer heartbeat")
  }
  assert_true(live_run.stage is @composer.Working)
  assert_eq(live_run.started_ms, Some(2_000_000.0))
  assert_eq(live_run.tokens, None)

  let usage = @codex.Msg::notification(
    "thread/tokenUsage/updated",
    {
      "threadId": "thread-idle",
      "turnId": "turn-2",
      "tokenUsage": {
        "total": { "totalTokens": 50000 },
        "last": { "totalTokens": 12345 },
        "modelContextWindow": 200000,
      },
    },
    2,
  )
  let (_, with_usage) = @codex.update(
    emit,
    usage,
    started,
    @interop.ChannelId::Local,
    open_external,
  )
  let (_, with_usage_again) = @codex.update(
    emit,
    usage,
    started,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_true(with_usage == with_usage_again)
  guard with_usage.composer_input(context).run is Some(usage_run) else {
    fail("Codex token usage should update the active composer heartbeat")
  }
  assert_eq(usage_run.tokens, Some(12345))

  let (_, replaced_usage) = @codex.update(
    emit,
    @codex.Msg::notification(
      "thread/tokenUsage/updated",
      {
        "threadId": "thread-idle",
        "turnId": "turn-2",
        "tokenUsage": {
          "total": { "totalTokens": 50000 },
          "last": { "totalTokens": 0 },
          "modelContextWindow": 200000,
        },
      },
      3,
    ),
    with_usage,
    @interop.ChannelId::Local,
    open_external,
  )
  guard replaced_usage.composer_input(context).run is Some(replaced_run) else {
    fail("replacement token usage should keep the composer heartbeat")
  }
  assert_eq(replaced_run.tokens, Some(0))

  let (_, completed) = @codex.update(
    emit,
    @codex.Msg::notification(
      "turn/completed",
      {
        "threadId": "thread-idle",
        "turn": { "id": "turn-2", "status": "completed", "items": [] },
      },
      4,
    ),
    replaced_usage,
    @interop.ChannelId::Local,
    open_external,
  )
  assert_eq(completed.composer_input(context).run, None)
}
