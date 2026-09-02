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
test "WebView menu request enters controlled rename and blank cannot submit" {
  let dispatch = test_dispatch()
  let id = test_conversation_id()
  let (_, model) = update_msg(
    dispatch,
    ConversationRenameRequested(id~, label="Original"),
    initial_model(),
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
