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
    screen: Schedules,
    schedules: {
      ..SchedulePage::empty(),
      owner: Some(@interop.ChannelId::Remote("other")),
      busy: true,
      sequence: 4,
    },
  }
  let (_, refreshed) = update_schedules(test_dispatch(), Poll, model)
  assert_eq(refreshed.schedules.owner, Some(base.focused))
  assert_true(refreshed.schedules.sequence > 4)
  assert_true(refreshed.schedules.busy)
}

///|
test "reopening schedules and switching hosts preserve a pending save acknowledgement" {
  let base = test_model()
  let page = {
    ..SchedulePage::empty(),
    owner: Some(base.focused),
    busy: true,
    sequence: 7,
    form: Some(ScheduleForm::empty()),
  }
  let (_, opened) = open_schedules(test_dispatch(), { ..base, schedules: page, })
  assert_eq(opened.schedules.sequence, 7)
  assert_true(opened.schedules.busy)
  let (_, saved) = update_schedules(
    test_dispatch(),
    Loaded(base.focused, 7, true, Ok({ entries: [], runs: [], })),
    { ..opened, focused: @interop.ChannelId::Remote("other"), },
  )
  assert_false(saved.schedules.busy)
  assert_true(saved.schedules.form is None)
}

///|
test "calendar form validates only its active timing fields" {
  let form = {
    ..ScheduleForm::empty(),
    name: "Daily check",
    task: "Inspect changes",
    timing: "daily",
    time: "09:30",
    minutes: "",
  }
  guard schedule_form_spec(form) is Ok(spec) else { fail("valid daily form") }
  assert_eq(spec.timing, @protocol.Daily(hour=9, minute=30))
  guard schedule_form_spec({ ..form, timing: "weekly", weekday: "7", })
    is Ok(spec) else {
    fail("valid weekly form")
  }
  assert_eq(spec.timing, @protocol.Weekly(weekday=7, hour=9, minute=30))
  assert_true(schedule_form_spec({ ..form, time: "24:00", }) is Err(_))
  assert_true(schedule_form_spec({ ..form, time: "", }) is Err(_))
  assert_true(
    schedule_form_spec({ ..form, timing: "weekly", weekday: "0", }) is Err(_),
  )
  assert_true(schedule_form_spec({ ..form, timing: "every", }) is Err(_))
}
