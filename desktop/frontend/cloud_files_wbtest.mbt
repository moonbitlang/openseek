///|
test "Cloud blank, expired and changed-account file contexts have no Host placement" {
  let model = integrated_cloud_model()
  let ctx = file_ctx(model)
  assert_true(ctx.owner is @interop.Cloud(..))
  assert_true(ctx.placement is None)
  assert_true(ctx.cloud_files is Some(_))
  assert_true(file_ctx({ ..model, screen: Settings, }).cloud_files is None)
  let unavailable = file_ctx({ ..model, account: None, })
  assert_true(unavailable.placement is None)
  assert_true(unavailable.root() is None)
  let foreign = file_ctx({
    ..model,
    account: model.account.map(account => {
      ..account,
      user: { ..account.user, user_id: "other", },
    }),
  })
  assert_true(foreign.root() is None)
  let (_, draft) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  assert_true(file_ctx(draft).root() is None)
  assert_false(draft.file_panel_visible())
  let location : @navigation_browser.Snapshot = {
    path: "/cloud",
    settings: false,
    can_back: false,
    can_forward: false,
  }
  let (_, home) = update(test_dispatch(), Navigation(Browser(location)), model)
  assert_true(home.cloud_selected())
  assert_true(file_ctx(home).placement is None)
  assert_true(file_ctx(home).root() is None)
}

///|
test "Explorer from Settings preserves Cloud files and the covered Host dock" {
  let dispatch = test_dispatch()
  let model = integrated_cloud_model()
  let cloud_owner = model.dock_owner()
  let host_owner = @interop.Host({
    channel: model.focused,
    session: model.active_session,
  })
  let host_dock = @dock.open_jobs(@dock.DockState::empty())
  let mut model = model.with_dock_state_for(host_owner, host_dock)
  let files = ["first.txt", "second.txt"].map(name => {
    @resource.join_relative(file_ctx(model).root().unwrap(), Relative(name))
  })
  for path in files {
    let (_, opened) = show_editor_resource(
      dispatch,
      model,
      path,
      None,
      file_link_generation=model.file_panel.file_link_generation,
    )
    model = opened
  }
  let (_, settings) = update(dispatch, OpenSetup, model)
  assert_true(settings.screen is Settings)
  assert_true(settings.dock_owner() == host_owner)
  let input_ctx = file_ctx(settings)
  for _ in 0..<2 {
    let (_, searched) = update(
      dispatch,
      ExplorerRequested(ExplorerSearch),
      settings,
    )
    assert_true(
      searched.dock_state_for(cloud_owner).tabs ==
      [File(path=files[0]), File(path=files[1]), FilePicker],
    )
    assert_true(searched.dock_state_for(cloud_owner).active == Some(FilePicker))
    assert_true(searched.dock_state_for(host_owner) == host_dock)
    assert_true(
      settings.dock_state_for(cloud_owner).tabs ==
      [File(path=files[0]), File(path=files[1])],
    )
    assert_true(
      settings.dock_state_for(cloud_owner).active == Some(File(path=files[1])),
    )
    assert_true(settings.dock_state_for(host_owner) == host_dock)
    assert_true(file_ctx(settings) == input_ctx)
  }
}

///|
test "account changes retire Cloud file strips and fence old reads after same-account sign-in" {
  let model = integrated_cloud_model()
  let ctx = file_ctx(model)
  let path = @resource.join_relative(
    ctx.root().unwrap(),
    Relative("private.txt"),
  )
  let (_, model) = show_editor_resource(
    test_dispatch(),
    model,
    path,
    None,
    file_link_generation=model.file_panel.file_link_generation,
  )
  let (model, _) = sync_file_panel(test_dispatch(), model)
  let epoch = model.file_panel.request_epoch
  let old_reply = FileEditor(
    @fileeditor.FileLoaded(
      owner=ctx.owner,
      epoch~,
      path~,
      name="private.txt",
      file=Content(content="old account content", sig="old"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
  )
  let (_, model) = update(test_dispatch(), old_reply, model)
  assert_true(model.file_panel.docs.contains(path))
  let model = {
    ..model,
    file_panel: {
      ..model.file_panel,
      cloud_documents: Map([
        (
          @interop.Cloud(account="fixture-user", session="parked"),
          model.file_panel.docs,
        ),
      ]),
    },
  }
  let (_, signed_out) = update(
    test_dispatch(),
    AccountLoaded(model.account_epoch, Ok(None)),
    model,
  )
  assert_true(signed_out.file_panel.docs.is_empty())
  assert_true(signed_out.file_panel.cloud_documents.is_empty())
  assert_true(signed_out.dock_state().tabs.is_empty())
  assert_false(signed_out.docks.contains(ctx.owner))
  for account in ["other-user", "fixture-user"] {
    let credentials = model.account.unwrap()
    let (_, signed_in) = update(
      test_dispatch(),
      AccountLoaded(
        signed_out.account_epoch,
        Ok(
          Some({
            ..credentials,
            user: { ..credentials.user, user_id: account, },
          }),
        ),
      ),
      signed_out,
    )
    let (_, reopened) = update(
      test_dispatch(),
      OpenCloudConversation(account~, session="cloud-a"),
      signed_in,
    )
    let (_, ignored) = update(test_dispatch(), old_reply, reopened)
    assert_false(ignored.file_panel.docs.contains(path))
    assert_true(ignored.dock_state().tabs.is_empty())
  }
}

///|
test "deleting an inactive Cloud session clears its documents and dock bookmarks" {
  let model = integrated_cloud_model()
  let owner = @interop.Cloud(account="fixture-user", session="cloud-b")
  let path = @resource.join_relative(
    @resource.cloud_root(@cloud.CloudOrigin, "fixture-user", "cloud-b").unwrap(),
    Relative("private.txt"),
  )
  let tab = @dock.File(path~)
  let model = {
    ..model.with_dock_state_for(owner, { tabs: [tab], active: Some(tab), }),
    cloud: {
      ..model.cloud,
      sessions: [
        ..model.cloud.sessions,
        {
          id: "cloud-b",
          title: None,
          updated_at: None,
          generating: false,
          archived: false,
        },
      ],
    },
    file_panel: {
      ..model.file_panel,
      cloud_documents: Map([
        (
          owner,
          Map([
            (
              path,
              {
                name: "private.txt",
                state: @fileeditor.TabLoaded(content="private", sig="sig"),
                review: None,
                stale: false,
              },
            ),
          ]),
        ),
      ]),
    },
  }
  let (_, pending) = update(
    test_dispatch(),
    CloudAction(@cloud.Delete("cloud-b")),
    model,
  )
  let (_, deleted) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Deleted(
        pending.cloud.epoch,
        "cloud-b",
        pending.cloud.deletions["cloud-b"],
      ),
    ),
    pending,
  )
  assert_false(deleted.file_panel.cloud_documents.contains(owner))
  assert_false(deleted.docks.contains(owner))
  assert_true(deleted.cloud_identity() == model.cloud_identity())
}

///|
test "a web link in a Cloud conversation reveals its tab in the Cloud dock" {
  let model = {
    ..integrated_cloud_model(),
    right_panel_open: false,
    right_panel_menu_open: true,
  }
  let cloud = model.dock_owner()
  guard cloud is @interop.Cloud(..) else {
    fail("the Cloud conversation owns the dock on screen")
  }
  let (_, opened) = update(
    test_dispatch(),
    ExternalLinkClicked("https://example.com/"),
    model,
  )
  assert_true(opened.right_panel_open)
  assert_false(opened.right_panel_menu_open)
  assert_true(opened.dock_owner() == cloud)
  guard @dock.active_browser(opened.dock_state()) is Some(id) else {
    fail("the link opens a browser tab")
  }
  assert_true(opened.dock_state().tabs.contains(Browser(id~)))
  assert_true(
    @preview.page(opened.preview, id).unwrap().url ==
    Some("https://example.com/"),
  )
  // A Host conversation's agent page opens in that conversation's own
  // dock and leaves the Cloud screen as it is.
  let (_, background) = update(
    test_dispatch(),
    BrowserOpenRequested(
      request="r-1",
      session="host-away",
      url="https://example.org/",
    ),
    model,
  )
  assert_false(background.right_panel_open)
  assert_true(background.right_panel_menu_open)
  assert_true(background.dock_state() == model.dock_state())
  let away = @interop.Host({ channel: Local, session: "host-away", })
  assert_true(background.dock_state_for(away).tabs is [Browser(..)])
}
