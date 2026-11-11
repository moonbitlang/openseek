///|
test "preview requests reuse the foreground Local and Cloud file viewers" {
  for model in [desktop_model(), integrated_cloud_model()] {
    for
      path in [
        "report.pdf", "image.png", "report.docx", "src/main.mbt", "notes.txt",
      ] {
      let ctx = file_ctx(model)
      let request : @protocol.PreviewOpenRequest = if model.cloud_selected() {
        Cloud(account="fixture-user", session="cloud-a", path~)
      } else {
        Local(session=model.active_session, workspace="/work", path~)
      }
      let (_, opened) = update(
        test_dispatch(),
        PreviewOpenRequested(request),
        model,
      )
      let expected = @resource.join_relative(
        ctx.root().unwrap(),
        Relative(path),
      )
      assert_eq(@dock.active_file(opened.dock_state()), Some(expected))
      assert_eq(opened.file_panel.owner, Some(ctx.owner))
      assert_true(opened.file_panel.docs.contains(expected))
      assert_true(opened.right_panel_open)
      assert_true(opened.pending_previews.is_empty())
    }
  }
  let (_, html) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Local(session="desktop-test", workspace="/work", path="index.htm"),
    ),
    desktop_model(),
  )
  assert_true(@dock.active_browser(html.dock_state()) is Some(_))
  assert_true(html.right_panel_open)
}

///|
test "background previews retain their owner and drain only after returning" {
  let original = integrated_cloud_model()
  let (_, background) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Local(session="desktop-test", workspace="/work", path="host.txt"),
    ),
    original,
  )
  assert_true(
    background.selected_conversation == original.selected_conversation,
  )
  assert_true(background.docks == original.docks)
  assert_eq(background.file_panel.owner, original.file_panel.owner)
  let (_, host) = update(
    test_dispatch(),
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    background,
  )
  assert_eq(
    @dock.active_file(host.dock_state()),
    @resource.of_path(Local, "/work/host.txt"),
  )
  assert_true(host.pending_previews.is_empty())
  let (_, parked) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Cloud(account="fixture-user", session="cloud-a", path="cloud.txt"),
    ),
    host,
  )
  let (_, parked) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Cloud(account="fixture-user", session="cloud-a", path="second.txt"),
    ),
    parked,
  )
  assert_true(parked.selected_conversation == host.selected_conversation)
  assert_true(parked.docks == host.docks)
  let (_, returned) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    parked,
  )
  let root = file_ctx(returned).root().unwrap()
  assert_eq(
    @dock.active_file(returned.dock_state()),
    Some(@resource.join_relative(root, Relative("cloud.txt"))),
  )
  let (_, drained) = update(test_dispatch(), OpenNextPreview, returned)
  assert_eq(
    @dock.active_file(drained.dock_state()),
    Some(@resource.join_relative(root, Relative("second.txt"))),
  )
  assert_true(drained.pending_previews.is_empty())
}

///|
test "preview requests cannot redirect a stale workspace or retired account" {
  let host = desktop_model()
  let (_, stale) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Local(
        session="desktop-test",
        workspace="/replaced-worktree",
        path="index.html",
      ),
    ),
    host,
  )
  assert_true(stale.docks == host.docks)
  assert_true(stale.pending_previews.is_empty())
  let cloud = integrated_cloud_model()
  let (_, stale) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Cloud(account="retired", session="cloud-a", path="index.html"),
    ),
    cloud,
  )
  assert_true(stale.docks == cloud.docks)
  assert_true(stale.pending_previews.is_empty())
}

///|
test "Cloud sign-out clears parked previews and remote notifications cannot open Local files" {
  let model = integrated_cloud_model()
  let (_, parked) = update(
    test_dispatch(),
    PreviewOpenRequested(
      Cloud(account="fixture-user", session="cloud-b", path="report.pdf"),
    ),
    model,
  )
  assert_eq(parked.pending_previews.length(), 1)
  let (_, signed_out) = update(
    test_dispatch(),
    CloudAction(@cloud.AccountChanged(None)),
    parked,
  )
  assert_true(signed_out.pending_previews.is_empty())
  let host = desktop_model()
  let (_, ignored) = update(
    test_dispatch(),
    FromDevice(
      Remote("other-device"),
      PreviewRequested(
        Local(session="desktop-test", workspace="/work", path="report.pdf"),
      ),
    ),
    host,
  )
  assert_true(ignored.docks == host.docks)
  assert_true(ignored.pending_previews.is_empty())
}
