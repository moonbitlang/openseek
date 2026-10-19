///|
fn cloud_rename_model() -> Model {
  let model = integrated_cloud_model()
  let id = @conversation.Id(
    source=CloudLive,
    channel="fixture-user",
    conversation="cloud-a",
  )
  let (_, model) = update_msg(
    test_dispatch(),
    ConversationRenameRequested(id~, label="Cloud conversation"),
    model,
  )
  let (_, model) = update_msg(
    test_dispatch(),
    ConversationRenameEdited(id~, edit=Typed("Manual title")),
    model,
  )
  update_msg(
    test_dispatch(),
    ConversationRenameEdited(id~, edit=Submitted),
    model,
  ).1
}

///|
test "Cloud rename reuses the root draft and closes it only for the owning save" {
  let saving = cloud_rename_model()
  assert_true(
    saving.conversation_rename
    is Some({ saving: true, draft: "Manual title", .. }),
  )
  let request = saving.cloud.metadata_saves["cloud-a"].request
  assert_eq(
    saving.cloud_chat_rows()[0].1.rename,
    Some({ draft: "Manual title", saving: true, }),
  )
  let (_, late) = update_msg(
    test_dispatch(),
    CloudAction(@cloud.Edited(2, "cloud-a", request)),
    saving,
  )
  assert_true(late.conversation_rename == saving.conversation_rename)
  let (_, saved) = update_msg(
    test_dispatch(),
    CloudAction(@cloud.Edited(3, "cloud-a", request)),
    saving,
  )
  assert_true(saved.conversation_rename is None)
  assert_eq(saved.cloud_title(), "Manual title")
  assert_true(saved.cloud_identity() == saving.cloud_identity())
  let (_, failed) = update_msg(
    test_dispatch(),
    CloudAction(@cloud.EditFailed(3, "cloud-a", request, Http(503))),
    saving,
  )
  assert_true(failed.conversation_rename is None)
  assert_eq(failed.cloud_title(), "Cloud conversation")
  assert_true(
    failed.notifications
    is [{ message: "Rename failed: Cloud answered HTTP 503. Try again.", .. }],
  )
  assert_true(failed.account is Some(_))
  let (_, signed_out) = update_msg(
    test_dispatch(),
    CloudAction(@cloud.AccountChanged(None)),
    saving,
  )
  assert_true(signed_out.conversation_rename is None)
  let (_, late) = update_msg(
    test_dispatch(),
    CloudAction(@cloud.Edited(3, "cloud-a", request)),
    signed_out,
  )
  assert_true(late.conversation_rename is None)
  assert_true(late.cloud.sessions.is_empty())
}

///|
test "Cloud archived rows join the existing archived section even without a device" {
  let model = integrated_cloud_model()
  let model = {
    ..model,
    cloud: {
      ..model.cloud,
      sessions: model.cloud.sessions.map(item => { ..item, archived: true, }),
    },
  }
  assert_true(model.cloud_chat_rows().is_empty())
  let rows = model.cloud_chat_rows(archived=true)
  assert_eq(rows.length(), 1)
  assert_true(rows[0].1.id.source() is @conversation.CloudArchived)
  assert_true(
    rows[0].1.trailing is [@conversation.Restore(..), @conversation.Delete(..)],
  )
  assert_true(rows[0].1.rename is None)
  let sections = model.sidebar_component_sections(model.dev())
  assert_true(
    sections.last()
    is Some({ entries: [@section.Conversation({ id, .. })], .. }) &&
    id.source() is @conversation.CloudArchived,
  )
  let disconnected = { ..model, devices: [], }
  let input = disconnected.sidebar_component_input()
  assert_true(
    input.sections.last()
    is Some({ entries: [@section.Conversation({ id, .. })], .. }) &&
    id.source() is @conversation.CloudArchived,
  )
}

///|
fn pending_cloud_archive(model : Model) -> Model {
  update(
    test_dispatch(),
    CloudAction(
      @cloud.Edit(account="fixture-user", session="cloud-a", edit=Archive(true)),
    ),
    model,
  ).1
}

///|
fn complete_cloud_archive(model : Model, request : Int32) -> Model {
  update(
    test_dispatch(),
    CloudAction(@cloud.Edited(3, "cloud-a", request)),
    model,
  ).1
}

///|
test "archiving the selected Cloud creates a new Cloud without retiring its archived history" {
  let pending = pending_cloud_archive(integrated_cloud_model())
  let save = pending.cloud.metadata_saves["cloud-a"]
  assert_eq(save.navigation, pending.chat_navigation_generation)
  for
    reply in [
      @cloud.Edited(2, "cloud-a", save.request),
      @cloud.Edited(3, "cloud-a", save.request + 1),
    ] {
    let (_, late) = update(test_dispatch(), CloudAction(reply), pending)
    assert_true(late.cloud.creation is None)
    assert_false(late.cloud.is_archived("cloud-a"))
  }
  let archived = complete_cloud_archive(pending, save.request)
  assert_true(archived.cloud.is_archived("cloud-a"))
  assert_true(archived.cloud.creating_at(archived.chat_navigation_generation))
  assert_true(archived.cloud_identity() is None)
  assert_true(archived.cloud.retired.is_empty())
  assert_true(archived.cloud.conversations.contains("cloud-a"))
}

///|
test "late background archives preserve navigation and archived Cloud has no send or quote entry" {
  let initial = integrated_cloud_model()
  for
    leave in [
      OpenSetup,
      OpenCloudConversation(account="fixture-user", session="cloud-b"),
    ] {
    let pending = pending_cloud_archive(initial)
    let save = pending.cloud.metadata_saves["cloud-a"]
    let (_, elsewhere) = update(test_dispatch(), leave, pending)
    let archived = complete_cloud_archive(elsewhere, save.request)
    assert_true(archived.cloud.creation is None)
    assert_true(archived.screen == elsewhere.screen)
    assert_true(
      archived.selected_conversation == elsewhere.selected_conversation,
    )
  }
  let pending = pending_cloud_archive(initial)
  let save = pending.cloud.metadata_saves["cloud-a"]
  let (_, elsewhere) = update(test_dispatch(), OpenSetup, pending)
  let (_, returned) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    elsewhere,
  )
  let archived = complete_cloud_archive(returned, save.request)
  assert_true(archived.cloud.creation is None)
  assert_true(archived.cloud_archived())
  assert_true(archived.quote_screen() is None)
  assert_true(
    archived.cloud_composer_input()
    is Some(
      {
        presentation: {
          disabled: true,
          primary_action: @composer.Send(available=false),
          ..
        },
        ..
      }
    ),
  )
}

///|
test "archiving the previous Cloud behind a new-chat page does not retry or retarget creation" {
  let (_, creating) = update(
    test_dispatch(),
    CloudAction(@cloud.Create),
    integrated_cloud_model(),
  )
  let creation = creating.cloud.creation.unwrap()
  let (_, failed) = update(
    test_dispatch(),
    CloudAction(@cloud.CreateFailed(3, creation.request, Http(503))),
    creating,
  )
  for model in [creating, failed] {
    let pending = pending_cloud_archive(model)
    let save = pending.cloud.metadata_saves["cloud-a"]
    let archived = complete_cloud_archive(pending, save.request)
    assert_true(archived.cloud.is_archived("cloud-a"))
    assert_true(archived.cloud.creation == model.cloud.creation)
    assert_eq(
      archived.chat_navigation_generation,
      model.chat_navigation_generation,
    )
    assert_true(archived.selected_conversation == model.selected_conversation)
  }
}
