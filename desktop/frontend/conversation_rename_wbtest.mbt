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
test "a failed save closes the field and reports through a toast" {
  let id = test_conversation_id()
  let model = rename_edit(renaming_model(), Typed("Renamed"))
  let (_, failed) = update_msg(
    test_dispatch(),
    ConversationRenameFailed(id~, message="offline"),
    rename_edit(model, Submitted),
  )
  assert_true(failed.conversation_rename is None)
  assert_true(
    failed.notifications is [{ message: "Rename failed: offline", .. }],
  )
}

///|
test "a pending save keeps its draft and notes that focus moved on" {
  let model = rename_edit(renaming_model(), Typed("Renamed"))
  let saving = rename_edit(model, Submitted)
  let typed = rename_edit(saving, Typed("Too late"))
  assert_true(typed.conversation_rename == saving.conversation_rename)
  guard rename_edit(saving, Left).conversation_rename is Some(rename) else {
    fail("leaving the field ended a pending save")
  }
  assert_true(rename.saving)
  assert_true(rename.focus_left)
  assert_eq(rename.draft, "Renamed")
}

///|
test "another rename cannot replace one whose save is pending" {
  let model = rename_edit(renaming_model(), Typed("Renamed"))
  let saving = rename_edit(model, Submitted)
  let other = @conversation.Id(
    source=@conversation.OpenSeekLive,
    channel=@interop.ChannelId::Local.uri_authority(),
    conversation="chat-2",
    root="/work/project",
  )
  let (_, requested) = update_msg(
    test_dispatch(),
    ConversationRenameRequested(id=other, label="Other"),
    saving,
  )
  assert_true(requested.conversation_rename == saving.conversation_rename)
}
