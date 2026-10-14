///|
test "terminal attach codecs distinguish missing sessions from malformed replies" {
  let request : @protocol.TerminalAttachPayload = @json.from_json({
    "id": "pty",
    "sequence": 0,
    "future": true,
  })
  @debug.assert_eq(request.to_json(), { "id": "pty", "sequence": 0 })
  for
    raw in (
      [
        {},
        null,
        { "id": "pty" },
        { "id": "", "sequence": 0 },
        { "id": "pty", "sequence": -1 },
        { "id": "pty", "sequence": null },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.TerminalAttachPayload = @json.from_json(raw)
      }),
    )
  }
  let missing : @protocol.TerminalAttachReply = @json.from_json({
    "attached": false,
  })
  assert_false(missing.attached)
  @debug.assert_eq(missing.to_json(), { "attached": false })
  for
    raw in (
      [{}, null, { "attached": null }, { "attached": "true" }] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.TerminalAttachReply = @json.from_json(raw)
      }),
    )
  }
}
