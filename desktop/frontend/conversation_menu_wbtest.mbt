///|
fn test_conversation_id() -> @conversation.Id {
  @conversation.Id(
    source="openseek.live",
    channel=@interop.ChannelId::Local.uri_authority(),
    conversation="chat-1",
    root="/work/project",
  )
}

///|
test "native menu selection enters controlled rename and blank cannot submit" {
  let dispatch = test_dispatch()
  let id = test_conversation_id()
  let model = { ..initial_model(), is_desktop: true, }
  let (_, model) = update_msg(
    dispatch,
    ShowConversationMenu(
      id~,
      label="Original",
      kind=LiveConversationMenu,
      archive_enabled=true,
      delete_enabled=false,
      x=10,
      y=20,
    ),
    model,
  )
  guard model.sidebar_menu_target
    is Some(ConversationTarget(id=target_id, label~)) else {
    fail("native menu target was not retained")
  }
  assert_eq(target_id, id)
  assert_eq(label, "Original")
  let (_, model) = update_msg(
    dispatch,
    ConversationMenuSelected(RenameConversation),
    model,
  )
  guard model.conversation_rename is Some(rename) else {
    fail("rename editor did not open")
  }
  assert_eq(rename.draft, "Original")
  assert_false(rename.saving)
  let (_, model) = update_msg(
    dispatch,
    ConversationRenameChanged(id~, value="   "),
    model,
  )
  let (_, model) = update_msg(dispatch, ConversationRenameSubmitted(id), model)
  guard model.conversation_rename is Some(rename) else {
    fail("blank submit closed rename editor")
  }
  assert_false(rename.saving)
  let (_, model) = update_msg(dispatch, ConversationRenameCancelled(id), model)
  assert_true(model.conversation_rename is None)
}
