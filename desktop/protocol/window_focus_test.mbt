///|
test "focused Browser replies encode absence as an omitted field" {
  let focused : @protocol.AppFocusedBrowserReply = { id: Some(7), }
  let unfocused : @protocol.AppFocusedBrowserReply = { id: None, }
  json_inspect(focused, content={ "id": 7 })
  json_inspect(unfocused, content={})
  assert_eq(@json.from_json(focused.to_json()), focused)
  assert_eq(@json.from_json(unfocused.to_json()), unfocused)
  assert_eq(@json.from_json(@json.parse("{\"id\":null}")), unfocused)
  try {
    let _ : @protocol.AppFocusedBrowserReply = @json.from_json({ "id": "7" })
  } catch {
    _ => ()
  } noraise {
    _ => fail("malformed Browser id must not decode as no focus")
  }
}
