///|
test "navigation errors preserve multiline diagnostics instead of empty locations" {
  let message = "moon ide peek-def exited with code 1\nCannot find module for unicode/basic.mbt"
  let failure : @protocol.MoonIdeNavigationReply = NavigationError(message)
  let decoded : @protocol.MoonIdeNavigationReply = @json.from_json(
    failure.to_json(),
  )
  assert_eq(decoded, failure)
  let empty : @protocol.MoonIdeNavigationReply = @json.from_json({
    "kind": "locations",
    "locations": [],
  })
  assert_true(empty is NavigationLocations({ locations: [], }))
  assert_true(empty != failure)
}

///|
test "navigation rejects missing or malformed failure details" {
  let invalid : Array[Json] = [
    { "kind": "error" },
    { "kind": "error", "message": null },
    { "kind": "error", "message": 1 },
    { "kind": "unknown", "locations": [] },
    { "locations": [] },
  ]
  for json in invalid {
    try {
      let reply : @protocol.MoonIdeNavigationReply = @json.from_json(json)
      ignore(reply)
    } catch {
      JsonDecodeError(_) => ()
    } noraise {
      _ => fail("invalid navigation reply was accepted")
    }
  }
}
