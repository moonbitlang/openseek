///|
fn test_conversation_id() -> @conversation.Id {
  @conversation.Id(
    source=@conversation.OpenSeekLive,
    channel=@interop.ChannelId::Local.uri_authority(),
    conversation="chat-1",
    root="/work/project",
  )
}

///|
fn rename_edit(model : Model, edit : @conversation.RenameEdit) -> Model {
  update_msg(
    test_dispatch(),
    ConversationRenameEdited(id=test_conversation_id(), edit~),
    model,
  ).1
}

///|
fn renaming_model() -> Model {
  update_msg(
    test_dispatch(),
    ConversationRenameRequested(id=test_conversation_id(), label="Original"),
    initial_model(desktop=false),
  ).1
}

///|
test "a rename request edits the row's title in place" {
  guard renaming_model().conversation_rename is Some(rename) else {
    fail("rename did not start")
  }
  assert_eq(rename.draft, "Original")
  assert_false(rename.saving)
}

///|
test "a blank or unchanged title closes the field without saving" {
  for draft in ["   ", " Original "] {
    for edit in [@conversation.Submitted, @conversation.Left] {
      let model = rename_edit(renaming_model(), Typed(draft))
      assert_true(rename_edit(model, edit).conversation_rename is None)
    }
  }
}

///|
test "Enter and leaving the field both save a changed title" {
  for edit in [@conversation.Submitted, @conversation.Left] {
    let model = rename_edit(renaming_model(), Typed("Renamed"))
    guard rename_edit(model, edit).conversation_rename is Some(rename) else {
      fail("the changed title was dropped")
    }
    assert_true(rename.saving)
    assert_eq(rename.draft, "Renamed")
  }
}

///|
test "Escape discards the draft" {
  let model = rename_edit(renaming_model(), Typed("Renamed"))
  assert_true(rename_edit(model, Cancelled).conversation_rename is None)
}

///|
test "a failed save retries on Enter and gives up when focus leaves" {
  let id = test_conversation_id()
  let model = rename_edit(renaming_model(), Typed("Renamed"))
  let model = rename_edit(model, Submitted)
  let (_, failed) = update_msg(
    test_dispatch(),
    ConversationRenameFailed(id~, message="offline"),
    model,
  )
  guard failed.conversation_rename is Some(rename) else {
    fail("the failed rename closed")
  }
  assert_false(rename.saving)
  assert_eq(rename.error, Some("Rename failed: offline"))
  guard rename_edit(failed, Submitted).conversation_rename is Some(retry) else {
    fail("Enter did not retry")
  }
  assert_true(retry.saving)
  assert_true(rename_edit(failed, Left).conversation_rename is None)
}
