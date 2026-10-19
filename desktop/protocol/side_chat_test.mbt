///|
test "a side chat id names its main conversation and ordinal" {
  assert_eq(@protocol.side_chat_id("desktop-1f2e", 3), "desktop-1f2e-sc-3")
  assert_eq(
    @protocol.split_side_chat_id("desktop-1f2e-sc-3"),
    Some(("desktop-1f2e", 3)),
  )
  assert_eq(
    @protocol.split_side_chat_id(@protocol.side_chat_id("cli-sc-7", 12)),
    Some(("cli-sc-7", 12)),
  )
}

///|
test "only a trailing well-formed suffix makes a side chat" {
  let cases = [
    "desktop-1f2e", "desktop-sc", "-sc-1", "desktop-sc-", "desktop-sc-x", "desktop-sc-1x",
    "desktop-sc-9999999999",
    // A side chat's own sub-run belongs to the side chat, not beside it.
     "desktop-sc-1-sr-2", "desktop-sr-1",
  ]
  assert_eq(cases.filter(id => @protocol.split_side_chat_id(id) is Some(_)), [])
}
