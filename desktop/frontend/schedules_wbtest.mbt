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
