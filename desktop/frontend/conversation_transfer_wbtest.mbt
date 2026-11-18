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
  assert_true(opened.session_import_dialog == dialog)
  assert_true(opened.session_import_dialog == repeated.session_import_dialog)
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
  let completed = SessionImport(Imported(2, Ok("imported")))
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
          model_settings: None,
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
  assert_true(opened.session_import_dialog == dialog)
  let chats = model.sidebar_component_input().chat_sections[0]
  assert_eq(chats.secondary_actions, [ImportConversation(disabled=false)])
  let signed_out = { ..model, account: None, }
  let (_, refused) = update(test_dispatch(), OpenCloudImport, signed_out)
  assert_false(refused.session_import_dialog.is_open())
  let chats = signed_out.sidebar_component_input().chat_sections[0]
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
  let completed = SessionImport(Imported(2, Ok("cloud-imported")))
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

///|
test "account changes retire pending host shares before late replies can expire the new account" {
  let emit = test_dispatch()
  let first = account_error_test_account("account-a")
  let second = account_error_test_account("account-b")
  let initial = { ..test_model(), is_desktop: true, account: Some(first), }
  let (_, opened) = update(
    emit,
    OpenExport(Local, {
      session: "session",
      workspace: "/workspace",
      title: "Conversation",
      archived: false,
    }),
    initial,
  )
  let (_, pending) = update(emit, ExportDialog(Share), opened)
  // Opening and sharing each advance the dialog generation.
  let expired = @export_dialog.Published(
    generation=2,
    Ok(@protocol.SignInRequired),
  )
  assert_true(pending.export_dialog.account_expired(expired))
  // A current rejection must still expire its own account.
  let (_, rejected) = update(emit, ExportDialog(expired), pending)
  assert_true(rejected.account is None)
  for dismissed in [false, true] {
    let previous = if dismissed {
      update(emit, ExportDialog(Close), pending).1
    } else {
      pending
    }
    let (_, signed_out) = update(
      emit,
      AccountLoaded(previous.account_epoch, Ok(None)),
      previous,
    )
    let (_, switched) = update(
      emit,
      AccountLoaded(signed_out.account_epoch, Ok(Some(second))),
      signed_out,
    )
    assert_true(switched.account == Some(second))
    assert_false(switched.export_dialog.is_open())
    let (_, reopened) = update(
      emit,
      OpenExport(Local, {
        session: "other-session",
        workspace: "/workspace",
        title: "Other conversation",
        archived: false,
      }),
      switched,
    )
    let (_, new_pending) = update(emit, ExportDialog(Share), reopened)
    for current in [switched, new_pending] {
      for
        reply in [
          expired,
          @export_dialog.Published(
            generation=2,
            Ok(@protocol.Shared(url="https://shares.test/old")),
          ),
        ] {
        let (_, late) = update(emit, ExportDialog(reply), current)
        let (_, repeated) = update(emit, ExportDialog(reply), current)
        assert_true(late.account == Some(second))
        assert_eq(late.account_epoch, current.account_epoch)
        assert_eq(late.remote_connecting, current.remote_connecting)
        assert_true(late.export_dialog == current.export_dialog)
        assert_true(late.export_dialog == repeated.export_dialog)
      }
    }
  }
}
