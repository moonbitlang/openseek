///|
fn cloud_notification_event(
  model : Model,
  seq : Int32,
  kind : String,
  data : Json,
) -> (Msg, Model) {
  let message = CloudAction(
    @cloud.StreamEvent(
      model.cloud.epoch,
      "cloud-a",
      model.cloud.conversations["cloud-a"].request,
      { session_id: "cloud-a", task_id: "cloud-run", seq, kind, data, },
    ),
  )
  let (_, next) = update(test_dispatch(), message, model)
  (message, next)
}

///|
fn cloud_notification_model() -> Model {
  let model = { ..integrated_cloud_model(), window_focused: true, }
  let (_, running) = cloud_notification_event(model, 1, "task_started", {})
  cloud_notification_event(running, 2, "assistant_message", {
    "content": "Cloud final answer",
  }).1
}

///|
fn cloud_notification_finish(model : Model) -> (Msg, Model) {
  cloud_notification_event(model, 3, "task_finished", {
    "status": "completed",
    "result": { "status": "completed" },
  })
}

///|
test "Cloud completion reuses notification text and foreground read semantics" {
  let model = cloud_notification_model()
  let (message, next) = cloud_notification_finish(model)
  guard message is CloudAction(message) &&
    cloud_finished_notification(model.cloud, next.cloud, message)
    is Some((id, notification)) else {
    fail("expected one accepted Cloud completion")
  }
  assert_eq(id, "cloud-a")
  assert_eq(notification.title(), Some("Task finished"))
  assert_eq(notification.body(), "Cloud final answer")
  assert_eq(notification.payload, model.cloud_identity().unwrap().key())
  assert_false(next.cloud.conversations["cloud-a"].unseen_finish)
  assert_eq(next.notification_badge_count(), 0)
}

///|
test "Cloud unread completion uses the shared focus and panel read receipts" {
  let (_, settings) = update(
    test_dispatch(),
    OpenSetup,
    cloud_notification_model(),
  )
  for
    index, hidden in [
      { ..cloud_notification_model(), window_focused: false, },
      settings,
      {
        ..cloud_notification_model(),
        right_panel_open: true,
        right_panel_expanded: true,
      },
    ] {
    assert_false(hidden.transcript_is_visible(), msg="hidden layout \{index}")
    let (_, finished) = cloud_notification_finish(hidden)
    assert_true(
      finished.cloud.conversations["cloud-a"].unseen_finish,
      msg="completion layout \{index}",
    )
    assert_eq(finished.notification_badge_count(), 1)
    let (_, opened) = update(
      test_dispatch(),
      NotificationClicked(run_id=hidden.cloud_identity().unwrap().key()),
      {
        ..finished,
        window_focused: true,
        right_panel_open: false,
        terminal: @terminal.State::empty(),
      },
    )
    assert_true(opened.cloud_identity() == hidden.cloud_identity())
    assert_false(opened.cloud.conversations["cloud-a"].unseen_finish)
    assert_eq(opened.notification_badge_count(), 0)
  }
}

///|
test "Cloud completion notifications ignore duplicate terminals and history replay" {
  let model = cloud_notification_model()
  let (_, finished) = cloud_notification_finish(model)
  let (duplicate, next) = cloud_notification_event(
    { ..finished, screen: Settings, },
    99,
    "task_finished",
    { "status": "completed", "result": { "status": "completed" } },
  )
  guard duplicate is CloudAction(message) else {
    fail("expected a Cloud event")
  }
  assert_true(
    cloud_finished_notification(finished.cloud, next.cloud, message) is None,
  )
  assert_eq(next.notification_badge_count(), 0)
  let replay = @cloud.Loaded(
    model.cloud.epoch,
    "cloud-a",
    model.cloud.conversations["cloud-a"].request,
    {
      generating: false,
      messages: [
        {
          task_id: "cloud-run",
          kind: "task_finished",
          data: { "status": "completed" },
          created_at: 100,
        },
      ],
    },
  )
  let (_, recovered) = update(test_dispatch(), CloudAction(replay), {
    ..model,
    screen: Settings,
  })
  assert_true(
    cloud_finished_notification(model.cloud, recovered.cloud, replay) is None,
  )
  assert_eq(recovered.notification_badge_count(), 0)
}

///|
test "Cloud live completion is notified when its history reply arrives first" {
  let (_, model) = update(
    test_dispatch(),
    OpenSetup,
    cloud_notification_model(),
  )
  let (_, loaded) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(
        model.cloud.epoch,
        "cloud-a",
        model.cloud.conversations["cloud-a"].request,
        {
          generating: false,
          messages: [
            {
              task_id: "cloud-run",
              kind: "task_finished",
              data: { "status": "completed" },
              created_at: 100,
            },
          ],
        },
      ),
    ),
    model,
  )
  assert_eq(loaded.notification_badge_count(), 0)
  let (message, finished) = cloud_notification_finish(loaded)
  guard message is CloudAction(message) else { fail("expected a Cloud event") }
  assert_true(
    cloud_finished_notification(loaded.cloud, finished.cloud, message)
    is Some(_),
  )
  assert_eq(finished.notification_badge_count(), 1)
}

///|
test "Cloud notifications preserve cancellation and engine result semantics" {
  for
    (outer, status, title) in [
      ("completed", "ok", Some("Task finished")),
      ("failed", "aborted", None),
      ("failed", "failed", Some("Task failed")),
      ("failed", "max_steps_exhausted", Some("Task stopped at the step limit")),
    ] {
    let model = cloud_notification_model()
    let (message, next) = cloud_notification_event(model, 3, "task_finished", {
      "status": Json(outer),
      "result": { "status": Json(status) },
    })
    guard message is CloudAction(message) &&
      cloud_finished_notification(model.cloud, next.cloud, message)
      is Some((_, notification)) else {
      fail("expected an accepted terminal")
    }
    assert_eq(notification.title(), title)
  }
}

///|
test "Cloud notification targets are isolated by account and retired conversations" {
  let model = cloud_notification_model()
  let payload = model.cloud_identity().unwrap().key()
  let (_, finished) = cloud_notification_finish({ ..model, screen: Settings, })
  let (_, signed_out) = update(
    test_dispatch(),
    CloudAction(@cloud.AccountChanged(None)),
    { ..finished, account: None, },
  )
  let (_, ignored) = update(
    test_dispatch(),
    NotificationClicked(run_id=payload),
    signed_out,
  )
  assert_true(ignored.cloud_identity() == signed_out.cloud_identity())
  assert_true(ignored.screen == signed_out.screen)
  assert_eq(ignored.notification_badge_count(), 0)
  let account = finished.account.unwrap()
  let (_, switched) = update(
    test_dispatch(),
    CloudAction(@cloud.AccountChanged(Some("other-account"))),
    {
      ..finished,
      account: Some({
        ..account,
        user: { ..account.user, user_id: "other-account", },
      }),
    },
  )
  let (_, ignored) = update(
    test_dispatch(),
    NotificationClicked(run_id=payload),
    switched,
  )
  assert_true(ignored.cloud_identity() == switched.cloud_identity())
  assert_eq(ignored.notification_badge_count(), 0)
  let cloud = {
    ..finished.cloud,
    sessions: [],
    conversations: Map([]),
    retired: ["cloud-a"],
  }
  let deleted = { ..finished, cloud, }
  let (_, ignored) = update(
    test_dispatch(),
    NotificationClicked(run_id=payload),
    deleted,
  )
  assert_true(ignored.cloud_identity() == deleted.cloud_identity())
  assert_true(ignored.screen == deleted.screen)
  let archived = {
    ..finished,
    cloud: {
      ..finished.cloud,
      sessions: finished.cloud.sessions.map(session => {
        ..session,
        archived: true,
      }),
    },
  }
  let (_, ignored) = update(
    test_dispatch(),
    NotificationClicked(run_id=payload),
    archived,
  )
  assert_true(ignored.cloud_identity() == archived.cloud_identity())
  assert_eq(ignored.notification_badge_count(), 0)
}

///|
test "a Cloud draft does not read the remembered Local conversation" {
  let cloud = cloud_notification_model()
  let model = {
    ..running_model(),
    cloud: cloud.cloud,
    account: cloud.account,
    selected_conversation: cloud.selected_conversation,
    window_focused: true,
  }
  let (_, draft) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  assert_true(draft.cloud_draft_identity() is Some(_))
  let (_, finished) = update_dev(
    test_dispatch(),
    Finished(run_id="r7", status="finished", answer=None),
    draft,
  )
  assert_true(
    finished.find_conversation(Local, "desktop-test").unwrap().unseen_finish,
  )
  assert_eq(finished.notification_badge_count(), 1)
}

///|
test "Local and Cloud unread completions share one badge without reading each other" {
  let cloud = cloud_notification_model()
  let model = {
    ..running_model(),
    cloud: cloud.cloud,
    account: cloud.account,
    selected_conversation: cloud.selected_conversation,
    window_focused: true,
  }
  let (_, local_finished) = update_dev(
    test_dispatch(),
    Finished(run_id="r7", status="finished", answer=None),
    model,
  )
  assert_true(
    local_finished.find_conversation(Local, "desktop-test").unwrap().unseen_finish,
  )
  assert_eq(local_finished.notification_badge_count(), 1)
  let (_, both) = cloud_notification_finish({
    ..local_finished,
    screen: Settings,
  })
  assert_eq(both.notification_badge_count(), 2)
  let (_, cloud_read) = update(
    test_dispatch(),
    NotificationClicked(run_id=cloud.cloud_identity().unwrap().key()),
    both,
  )
  assert_eq(cloud_read.notification_badge_count(), 1)
  let (_, local_read) = update(
    test_dispatch(),
    NotificationClicked(run_id="r7"),
    cloud_read,
  )
  assert_eq(local_read.notification_badge_count(), 0)
}
