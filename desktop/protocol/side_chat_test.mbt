///|
test "a side chat id names its main conversation" {
  assert_eq(
    @protocol.side_chat_id("desktop-1f2e", "0a1b2c3d"),
    "desktop-1f2e-sc-0a1b2c3d",
  )
  assert_eq(
    @protocol.split_side_chat_id("desktop-1f2e-sc-0a1b2c3d"),
    Some("desktop-1f2e"),
  )
  assert_eq(
    @protocol.split_side_chat_id(
      @protocol.side_chat_id("cli-sc-0a1b2c3d", "ffffffff"),
    ),
    Some("cli-sc-0a1b2c3d"),
  )
}

///|
test "only a trailing well-formed suffix makes a side chat" {
  let cases = [
    "desktop-1f2e", "desktop-sc", "-sc-0a1b2c3d", "desktop-sc-", "desktop-sc-1",
    "desktop-sc-0a1b2c3", "desktop-sc-0a1b2c3d4", "desktop-sc-0A1B2C3D", "desktop-sc-0a1b2c3g",
    // A side chat's own sub-run belongs to the side chat, not beside it.
     "desktop-sc-0a1b2c3d-sr-2", "desktop-sr-1",
  ]
  assert_eq(cases.filter(id => @protocol.split_side_chat_id(id) is Some(_)), [])
}

///|
test "a side chat and its sub-runs sit beside the conversation" {
  assert_eq(@protocol.side_chat_parent("chat-sc-0a1b2c3d"), Some("chat"))
  assert_eq(@protocol.side_chat_parent("chat-sc-0a1b2c3d-sr-2"), Some("chat"))
  assert_eq(
    @protocol.side_chat_parent("chat-sr-1-sc-0a1b2c3d"),
    Some("chat-sr-1"),
  )
  assert_eq(@protocol.side_chat_parent("chat"), None)
  assert_eq(@protocol.side_chat_parent("chat-sr-1"), None)
}
