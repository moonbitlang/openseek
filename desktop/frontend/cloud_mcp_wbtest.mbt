///|
test "Cloud client browser opens and displays only in its owning account and session" {
  let model = integrated_cloud_model()
  let requested = CloudBrowserOpenRequested(
    account="fixture-user",
    request="open-a",
    session="cloud-a",
    url="https://example.test/",
  )
  let (_, opened) = update(test_dispatch(), requested, model)
  let id = @dock.active_browser(opened.dock_state()).unwrap()
  assert_eq(desired_browser_view(opened), Some(id))
  assert_eq(
    @preview.page(opened.preview, id).unwrap().url,
    Some("https://example.test/"),
  )
  let (_, elsewhere) = update(
    test_dispatch(),
    CloudBrowserOpenRequested(
      account="fixture-user",
      request="open-b",
      session="cloud-b",
      url="https://other.test/",
    ),
    opened,
  )
  assert_eq(@dock.active_browser(elsewhere.dock_state()), Some(id))
  assert_eq(
    @dock.active_browser(
      elsewhere.dock_state_for(
        @interop.Cloud(account="fixture-user", session="cloud-b"),
      ),
    ),
    Some(id + 1),
  )
  let (_, retired) = update(test_dispatch(), requested, {
    ..model,
    account: None,
  })
  assert_true(retired.preview == model.preview)
  let closed = { ..opened, preview: @preview.close_page(opened.preview, id), }
  assert_eq(desired_browser_view(closed), None)
}

///|
test "Cloud question drafts and snapshots are isolated from Local and stale accounts" {
  let model = integrated_cloud_model()
  let notification = CloudMcpNotification(
    @protocol.CloudMcpEvent::Questions(account="fixture-user", snapshot={
      generation: 1,
      requests: [
        {
          id: "question",
          session: "cloud-a",
          questions: [{ id: "plan", title: "Which plan?", options: None, }],
        },
      ],
    }),
  )
  let (_, shown) = update(test_dispatch(), notification, model)
  assert_false(shown.cloud_questions == model.cloud_questions)
  assert_true(shown.devices == model.devices)
  let (_, stale) = update(test_dispatch(), notification, {
    ..model,
    account: None,
  })
  assert_true(stale.cloud_questions == model.cloud_questions)
}
