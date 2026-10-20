///|
fn submit_blank_cloud(model : Model) -> Model {
  let (_, next) = update(
    test_dispatch(),
    ComposerAction(
      @composer.DraftSubmitted(identity=model.composer_input().identity, draft={
        task: "First Cloud message",
        images: [],
        mentions: [],
      }),
    ),
    model,
  )
  next
}

///|
test "new Cloud is an editable empty composer without a remote session" {
  let initial = integrated_cloud_model()
  let (_, settings) = update(test_dispatch(), OpenSetup, initial)
  let (_, blank) = update(test_dispatch(), CloudAction(@cloud.Create), settings)
  assert_true(blank.screen is Chat)
  assert_true(blank.cloud_selected())
  assert_true(blank.cloud_identity() is None)
  assert_eq(blank.cloud_title(), "New chat")
  assert_true(blank.cloud_chat_section("local").activation is None)
  assert_true(blank.cloud.creation is Some({ submission: None, .. }))
  assert_true(blank.cloud.sessions == initial.cloud.sessions)
  assert_true(blank.chat_column() is CloudTranscript(..))
  assert_true(blank.cloud_conversation() is None)
  assert_false(blank.composer_input().presentation.disabled)
  assert_true(
    blank.composer_input().presentation.primary_action
    is @composer.Send(available=true),
  )
  let (_, repeated) = update(test_dispatch(), CloudAction(@cloud.Create), blank)
  assert_true(
    repeated.cloud.creation.unwrap().id == blank.cloud.creation.unwrap().id,
  )
  assert_true(repeated.cloud.sessions == initial.cloud.sessions)
}

///|
test "first Cloud submit creates once and sends its snapshot after creation" {
  let (_, blank) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let sending = submit_blank_cloud(blank)
  let request = sending.cloud.creation.unwrap().request
  assert_true(sending.composer_input().presentation.disabled)
  assert_true(sending.cloud.creation is Some({ submission: Some(_), .. }))
  assert_true(submit_blank_cloud(sending).cloud == sending.cloud)
  let (_, repeated) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    sending,
  )
  assert_eq(repeated.cloud.creation.unwrap().request, request)
  let (_, created) = update(
    test_dispatch(),
    CloudAction(@cloud.Created(3, request, "new-cloud")),
    repeated,
  )
  assert_true(
    created.cloud_identity()
    is Some(@interop.Cloud(account="fixture-user", session="new-cloud")),
  )
  let conversation = created.cloud.conversations["new-cloud"]
  assert_true(conversation.sending)
  assert_false(conversation.loading)
  assert_eq(conversation.pending.unwrap().content.text(), "First Cloud message")
  assert_eq(created.composer_input().draft.task, "First Cloud message")
  assert_true(
    created.composer_entry_retirements.contains(
      blank.composer_input().identity.owner,
    ),
  )
  let (_, late) = update(
    test_dispatch(),
    CloudAction(@cloud.Created(3, request, "duplicate")),
    created,
  )
  assert_false(late.cloud.sessions.any(item => item.id == "duplicate"))
  let (_, back) = update(test_dispatch(), Navigation(Back), created)
  assert_true(
    back.cloud_identity() is Some(@interop.Cloud(session="cloud-a", ..)),
  )
}

///|
test "failed Cloud creation retains the composer owner and retries only on submit" {
  let (_, blank) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let pending = submit_blank_cloud(blank)
  let request = pending.cloud.creation.unwrap().request
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(@cloud.CreateFailed(3, request, Http(503))),
    pending,
  )
  assert_true(failed.cloud.creation is Some({ submission: None, .. }))
  assert_true(failed.cloud.notice is Some(_))
  assert_true(
    failed.composer_input().identity == blank.composer_input().identity,
  )
  assert_false(failed.composer_input().presentation.disabled)
  assert_true(failed.chat_column() is CloudTranscript(..))
  assert_true(failed.cloud.sessions == blank.cloud.sessions)
  let retried = submit_blank_cloud(failed)
  assert_true(retried.cloud.creation.unwrap().request > request)
  assert_true(
    retried.composer_input().identity == blank.composer_input().identity,
  )
  let (_, stale) = update(
    test_dispatch(),
    CloudAction(@cloud.Created(3, request, "stale")),
    retried,
  )
  assert_true(stale.cloud == retried.cloud)
}

///|
test "sending failure after creation keeps the initial input and reuses its remote session" {
  let (_, blank) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let pending = submit_blank_cloud(blank)
  let (_, created) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Created(3, pending.cloud.creation.unwrap().request, "new-cloud"),
    ),
    pending,
  )
  let request = created.cloud.conversations["new-cloud"].request
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(
      @cloud.SendFailed(3, "new-cloud", request, ServiceNotConfigured),
    ),
    created,
  )
  assert_eq(failed.composer_input().draft.task, "First Cloud message")
  assert_true(failed.cloud.can_send("new-cloud"))
  let sending = submit_blank_cloud(failed)
  assert_true(sending.cloud.creation is None)
  assert_true(sending.cloud.conversations["new-cloud"].sending)
  let request = sending.cloud.conversations["new-cloud"].request
  let (_, admitted) = update(
    test_dispatch(),
    CloudAction(
      @cloud.StreamEvent(3, "new-cloud", request, {
        session_id: "new-cloud",
        task_id: "task",
        seq: 1,
        kind: "task_started",
        data: {},
      }),
    ),
    sending,
  )
  assert_eq(admitted.composer_input().draft.task, "")
  assert_eq(admitted.composer_input().submission_sequence, 1)
}

///|
test "signing in for new Cloud returns to an empty page without creating a session" {
  let initial = integrated_cloud_model()
  let model = { ..initial, account: None, cloud: @cloud.State::empty(), }
  let (_, login) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  assert_true(login.remote_connecting)
  let (_, blank) = update(
    test_dispatch(),
    AccountLoaded(login.account_epoch, Ok(initial.account)),
    login,
  )
  assert_true(blank.screen is Chat && blank.cloud_selected())
  assert_true(blank.cloud.creation is Some({ submission: None, .. }))
  assert_true(blank.cloud.sessions.is_empty())
  assert_true(blank.navigation.location == blank.navigation_location())
  assert_true(blank.cloud_identity() is None)
  assert_false(blank.composer_input().presentation.disabled)
}

///|
test "Cloud blank selection survives sidebar browsing and Settings over a Work project" {
  let initial = integrated_cloud_model().with_active_project(
    Some(@interop.ChannelId::Local.test_project()),
  )
  let (_, blank) = update(test_dispatch(), CloudAction(@cloud.Create), initial)
  assert_true(blank.sidebar_mode is ChatMode)
  let identity = blank.composer_input().identity.owner
  let (_, browsed) = update(
    test_dispatch(),
    SidebarModeSelected(WorkMode),
    blank,
  )
  assert_true(browsed.cloud_selected())
  assert_true(browsed.active_conversation() is None)
  assert_eq(browsed.composer_input().identity.owner, identity)
  let (_, repeated) = update(test_dispatch(), NewChatRequested, browsed)
  assert_true(repeated.cloud_selected())
  assert_eq(repeated.composer_input().identity.owner, identity)
  let (_, settings) = update(test_dispatch(), OpenSetup, browsed)
  let (_, back) = update(test_dispatch(), Navigation(Back), settings)
  assert_true(back.screen is Chat && back.cloud_selected())
  assert_eq(back.composer_input().identity.owner, identity)
  let (_, repeated) = update(test_dispatch(), NewChatRequested, settings)
  assert_true(repeated.screen is Chat && repeated.cloud_selected())
  assert_eq(repeated.composer_input().identity.owner, identity)
  assert_true(repeated.cloud.creation is Some({ submission: None, .. }))
}

///|
test "Cloud creation behind Settings promotes its navigation without leaving Settings" {
  let (_, blank) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let (_, browsed) = update(
    test_dispatch(),
    SidebarModeSelected(WorkMode),
    blank,
  )
  let pending = submit_blank_cloud(browsed)
  assert_true(pending.cloud.creation is Some({ submission: Some(_), .. }))
  let (_, settings) = update(test_dispatch(), OpenSetup, pending)
  let (_, created) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Created(3, pending.cloud.creation.unwrap().request, "new-cloud"),
    ),
    settings,
  )
  assert_true(created.screen is Settings)
  let (_, back) = update(test_dispatch(), Navigation(Back), created)
  assert_true(
    back.cloud_identity() is Some(@interop.Cloud(session="new-cloud", ..)),
  )
  assert_true(back.cloud_conversation() is Some({ sending: true, .. }))
}

///|
test "account changes retire the Cloud blank selection and its composer" {
  let (_, blank) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  for account in [None, Some("other-user")] {
    let (_, changed) = update(
      test_dispatch(),
      CloudAction(@cloud.AccountChanged(account)),
      blank,
    )
    assert_true(changed.selected_conversation is None)
    assert_true(changed.cloud.creation is None)
    assert_true(
      changed.composer_entry_retirements.contains(
        blank.composer_input().identity.owner,
      ),
    )
    assert_false(
      changed.accepts_composer_action(blank.composer_input().identity),
    )
  }
}
