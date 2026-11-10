///|
test "scheduled session blocks direct send until the host reports completion" {
  let base = test_model()
  let conv = { ..base.active(), task: "Are you there?", }
  let run : @protocol.ScheduleRun = {
    id: "run",
    schedule_id: "plan",
    name: "task",
    workspace: "/workspace",
    session: conv.session_id,
    started_at: 1,
    finished_at: None,
    status: Running,
    log_path: "/run.log",
  }
  let model = {
    ..base.replace_conversation(conv),
    screen: Chat,
    schedules: {
      ..SchedulePage::empty(),
      owner: Some(base.focused),
      snapshot: { entries: [], runs: [run], },
    },
  }
  assert_true(model.scheduled_session_read_only(conv))
  assert_true(model.wants_schedule_updates())
  let (_, sent) = update(test_dispatch(), Send, model)
  assert_true(sent.active().run == conv.run)
  assert_eq(sent.active().task, conv.task)
  let (_, steered) = update(
    test_dispatch(),
    SendFollowup(@composer.SteerNow),
    model,
  )
  assert_true(steered.active().run == conv.run)
  let completed = {
    ..model,
    schedules: {
      ..model.schedules,
      snapshot: {
        entries: [],
        runs: [{ ..run, status: Succeeded, finished_at: Some(2), }],
      },
    },
  }
  assert_false(completed.scheduled_session_read_only(conv))
  assert_false(completed.wants_schedule_updates())
  let unknown = { ..conv, session_id: "scheduled-unknown", }
  assert_true(base.scheduled_session_read_only(unknown))
  assert_false(base.scheduled_session_read_only(conv))
}

///|
test "scheduled status refresh cannot remain busy on a previous host" {
  let base = test_model()
  let model = {
    ..base,
    management_dialog: Some(Schedules),
    schedules: {
      ..SchedulePage::empty(),
      owner: Some(@interop.ChannelId::Remote("other")),
      pending: Some(Change),
      sequence: 4,
    },
  }
  let (_, refreshed) = update_schedules(test_dispatch(), Poll, model)
  assert_eq(refreshed.schedules.owner, Some(base.focused))
  assert_true(refreshed.schedules.sequence > 4)
  assert_true(refreshed.schedules.pending is Some(Refresh))
}

///|
test "reopening schedules and switching hosts preserve a pending save acknowledgement" {
  let base = test_model()
  let page = {
    ..SchedulePage::empty(),
    owner: Some(base.focused),
    pending: Some(Change),
    sequence: 7,
    form: Some(ScheduleForm::empty()),
  }
  let (_, opened) = open_schedules(test_dispatch(), { ..base, schedules: page, })
  assert_eq(opened.schedules.sequence, 7)
  assert_true(opened.schedules.pending is Some(Change))
  let (_, saved) = update_schedules(
    test_dispatch(),
    Loaded(base.focused, 7, true, Ok({ entries: [], runs: [], })),
    { ..opened, focused: @interop.ChannelId::Remote("other"), },
  )
  assert_true(saved.schedules.pending is None)
  assert_true(saved.schedules.form is None)
}

///|
test "a schedule action during a background refresh is sent, not dropped" {
  let base = test_model()
  let model = {
    ..base,
    management_dialog: Some(Schedules),
    schedules: { ..SchedulePage::empty(), owner: Some(base.focused), },
  }
  let (_, refreshing) = update_schedules(test_dispatch(), Poll, model)
  assert_true(refreshing.schedules.pending is Some(Refresh))
  assert_false(refreshing.schedules.changing())
  let refresh = refreshing.schedules.sequence
  let (_, pausing) = update_schedules(
    test_dispatch(),
    Action("plan", "pause"),
    refreshing,
  )
  assert_true(pausing.schedules.pending is Some(Change))
  assert_true(pausing.schedules.sequence > refresh)
  // While the change is in flight, a poll and a second change wait for it.
  let (_, polled) = update_schedules(test_dispatch(), Poll, pausing)
  assert_eq(polled.schedules.sequence, pausing.schedules.sequence)
  let (_, again) = update_schedules(
    test_dispatch(),
    Action("plan", "resume"),
    polled,
  )
  assert_eq(again.schedules.sequence, pausing.schedules.sequence)
  // The superseded refresh reply cannot overwrite the change's snapshot.
  let entry : @protocol.ScheduleEntry = {
    id: "plan",
    spec: {
      name: "task",
      workspace: None,
      task: "work",
      model: None,
      timing: Every(30),
      timeout_minutes: 30,
    },
    enabled: true,
    run_requested: false,
    notice: None,
    next_at: Some(1),
  }
  let (_, stale) = update_schedules(
    test_dispatch(),
    Loaded(base.focused, refresh, false, Ok({ entries: [entry], runs: [], })),
    again,
  )
  assert_true(stale.schedules.pending is Some(Change))
  let paused = { ..entry, enabled: false, next_at: None, }
  let (_, settled) = update_schedules(
    test_dispatch(),
    Loaded(
      base.focused,
      pausing.schedules.sequence,
      false,
      Ok({ entries: [paused], runs: [], }),
    ),
    stale,
  )
  assert_true(settled.schedules.pending is None)
  assert_eq(settled.schedules.snapshot.entries, [paused])
}
