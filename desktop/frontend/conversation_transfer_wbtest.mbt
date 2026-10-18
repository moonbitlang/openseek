///|
test "import follows the selected project and worktree while its transcript loads or fails" {
  let emit = test_dispatch()
  let workspace = @resource.of_path(@interop.ChannelId::Local, "/other").unwrap()
  let base = test_model().with_dev(dev => {
    ..dev,
    projects: [..dev.projects, workspace],
    sessions: [
      {
        id: "desktop-other",
        title: Some("Other conversation"),
        workspace,
        workspace_name: "other",
        updated_at_ms: None,
      },
    ],
  })
  let (_, loading) = update(emit, OpenSession(Local, "desktop-other"), base)
  let failure = SessionLoadFailed(
    session="desktop-other",
    message="unavailable",
    generation=1,
  )
  let (_, retrying) = update_dev(emit, failure, loading)
  let (_, retrying) = update_dev(emit, failure, retrying)
  let (_, failed) = update_dev(emit, failure, retrying)
  for model in [loading, failed] {
    assert_eq(model.active_session, "desktop-test")
    let (_, opened) = update(emit, OpenSessionImport, model)
    let (_, expected) = model.session_import_dialog.open({
      channel: Local,
      connection_generation: model.focused_connection_generation(),
      workspace: @session_import.Registered("/other"),
      worktree_of: Some("desktop-other"),
    })
    assert_eq(opened.session_import_dialog, expected)
  }
}

///|
test "import waits for the normal catalog without patching inventory and ignores stale lists" {
  let emit = test_dispatch()
  let (_, opened) = update(emit, OpenSessionImport, test_model())
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
