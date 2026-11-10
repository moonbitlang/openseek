///|
test "import belongs to the project menu rather than the active conversation" {
  let workspace = @interop.ChannelId::Local.test_resource("/other")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [..dev.projects, workspace],
  })
  let expected : @session_import.HostTarget = {
    channel: Local,
    connection_generation: model.focused_connection_generation(),
    workspace: "/other",
    worktree_of: None,
  }
  let msg = OpenSessionImport(Local, workspace)
  let (_, opened) = update(test_dispatch(), msg, model)
  let (_, repeated) = update(test_dispatch(), msg, model)
  let (_, dialog) = model.session_import_dialog.open(Host(expected))
  assert_eq(opened.session_import_dialog, dialog)
  assert_eq(opened.session_import_dialog, repeated.session_import_dialog)
  assert_eq(model.session_import_target(Local, workspace), Some(expected))
  let (_, detached) = update(test_dispatch(), msg, test_model())
  assert_false(detached.session_import_dialog.is_open())
}

///|
test "import waits for the normal catalog without patching inventory and ignores stale lists" {
  let emit = test_dispatch()
  let (_, opened) = update(
    emit,
    OpenSessionImport(Local, @interop.ChannelId::Local.test_project()),
    test_model(),
  )
  let (_, typed) = update(
    emit,
    SessionImport(LinkChanged("https://example/v1/shares/sh_a")),
    opened,
  )
  let (_, pending) = update(emit, SessionImport(ImportLink), typed)
  let completed = SessionImport(Imported(2, Success("imported")))
  let (_, waiting) = update(emit, completed, pending)
  let (_, repeated) = update(emit, completed, pending)
  assert_true(waiting.navigation == repeated.navigation)
  assert_true(waiting.navigation.phase is Waiting)
  assert_true(
    waiting.navigation.location is Some({ target: Session("imported"), .. }),
  )
  assert_true(waiting.dev().sessions == pending.dev().sessions)
  assert_eq(waiting.dev().projects, pending.dev().projects)
  assert_true(waiting.dev().worktrees == pending.dev().worktrees)
  let (_, stale) = update(
    emit,
    sessions_loaded(
      [],
      request_generation=pending.dev().sessions_request_generation,
    ),
    waiting,
  )
  assert_true(stale.navigation.phase is Waiting)
  let (_, stale) = update_dev(
    emit,
    SessionsFailed(
      message="Old request failed",
      connection_generation=pending.dev().connection_generation,
      request_generation=pending.dev().sessions_request_generation,
    ),
    stale,
  )
  let (_, stale) = update_dev(
    emit,
    SessionsFailed(
      message="Old connection failed",
      connection_generation=pending.dev().connection_generation - 1,
      request_generation=waiting.dev().sessions_request_generation,
    ),
    stale,
  )
  assert_true(stale.navigation == waiting.navigation)
  assert_eq(stale.notifications.length(), waiting.notifications.length())
  let (_, stale) = update_dev(
    emit,
    ArchivedFailed(
      message="Archive unavailable",
      connection_generation=stale.dev().connection_generation,
      request_generation=stale.dev().archived_request_generation,
    ),
    stale,
  )
  assert_true(stale.navigation.phase is Waiting)
  let (_, listed) = update(
    emit,
    sessions_loaded(
      [
        {
          id: "imported",
          title: Some("Imported"),
          workspace: @interop.ChannelId::Local.test_project(),
          workspace_name: "work",
          updated_at_ms: None,
        },
      ],
      request_generation=waiting.dev().sessions_request_generation,
    ),
    stale,
  )
  assert_true(listed.navigation.phase is Active)
  assert_true(
    listed.conversation_selection() is Some({ session: "imported", .. }),
  )
}

///|
test "Cloud import belongs to the signed-in account's Chats section" {
  let model = integrated_cloud_model()
  let (_, opened) = update(test_dispatch(), OpenCloudImport, model)
  let (_, dialog) = model.session_import_dialog.open(
    Cloud(account="fixture-user"),
  )
  assert_eq(opened.session_import_dialog, dialog)
  let chats = model.sidebar_component_sections(model.dev())[0]
  assert_eq(chats.secondary_actions, [ImportConversation(disabled=false)])
  let signed_out = { ..model, account: None, }
  let (_, refused) = update(test_dispatch(), OpenCloudImport, signed_out)
  assert_false(refused.session_import_dialog.is_open())
  let chats = signed_out.sidebar_component_sections(signed_out.dev())[0]
  assert_eq(chats.secondary_actions, [ImportConversation(disabled=true)])
}

///|
test "a finished Cloud import refreshes the list and opens the new chat" {
  let emit = test_dispatch()
  let (_, opened) = update(emit, OpenCloudImport, integrated_cloud_model())
  let (_, typed) = update(
    emit,
    SessionImport(LinkChanged("https://example/v1/shares/sh_a")),
    opened,
  )
  let (_, pending) = update(emit, SessionImport(ImportLink), typed)
  let completed = SessionImport(Imported(2, Success("cloud-imported")))
  let (_, imported) = update(emit, completed, pending)
  assert_false(imported.session_import_dialog.is_open())
  assert_true(imported.screen is Chat)
  assert_true(
    imported.cloud_identity() ==
    Some(@interop.Cloud(account="fixture-user", session="cloud-imported")),
  )
  assert_true(imported.cloud.list_request > pending.cloud.list_request)
  assert_true(
    imported.navigation.location
    is Some({ target: CloudSession(session="cloud-imported", ..), .. }),
  )
  // A completion after switching accounts leaves the other account's page.
  let switched = {
    ..pending,
    cloud: { ..pending.cloud, user_id: Some("other-user"), },
  }
  let (_, stale) = update(emit, completed, switched)
  assert_false(stale.session_import_dialog.is_open())
  assert_true(stale.cloud_identity() == switched.cloud_identity())
}
