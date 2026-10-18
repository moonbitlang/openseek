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
