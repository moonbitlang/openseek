///|
test "import belongs to the project menu rather than the active conversation" {
  let workspace = @interop.ChannelId::Local.test_resource("/other")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [..dev.projects, workspace],
  })
  let expected : @session_import.Target = {
    channel: Local,
    connection_generation: model.focused_connection_generation(),
    workspace: "/other",
    worktree_of: None,
  }
  let msg = OpenSessionImport(Local, workspace)
  let (_, opened) = update(test_dispatch(), msg, model)
  let (_, repeated) = update(test_dispatch(), msg, model)
  let (_, dialog) = model.session_import_dialog.open(expected)
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
