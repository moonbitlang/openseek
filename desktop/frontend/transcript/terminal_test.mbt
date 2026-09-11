///|
test "an empty successful terminal keeps a boundary without inventing an answer" {
  let items : Array[@transcript.TranscriptItem] = []
  assert_true(
    @transcript.apply_session_item(
      items,
      @desktop_protocol.Terminal(@desktop_protocol.Finished("  ")),
      sequence=7,
    ),
  )
  assert_eq(items.length(), 1)
  assert_true(items[0].kind is @transcript.TurnEnd)
  assert_eq(items[0].sequence, Some(7))
  assert_eq(items[0].text(), None)
}
