///|
test "transfer menu visibility updates are pure and repeated dismissal stays closed" {
  let base = test_model()
  let emit = test_dispatch()
  let (_, first) = update(emit, ConversationTransferMenuChanged(true), base)
  let (_, second) = update(emit, ConversationTransferMenuChanged(true), base)
  assert_true(first.conversation_transfer_menu_open)
  assert_eq(
    first.conversation_transfer_menu_open,
    second.conversation_transfer_menu_open,
  )
  assert_false(base.conversation_transfer_menu_open)
  let (_, closed) = update(emit, ConversationTransferMenuChanged(false), first)
  let (_, closed_again) = update(
    emit,
    ConversationTransferMenuChanged(false),
    closed,
  )
  assert_false(closed.conversation_transfer_menu_open)
  assert_false(closed_again.conversation_transfer_menu_open)
}

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
