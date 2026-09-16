///|
test "an empty successful terminal keeps a boundary without inventing an answer" {
  let items : Array[@transcript.TranscriptItem] = []
  assert_true(
    @transcript.apply_session_item(items, Terminal(Finished("  ")), sequence=7),
  )
  assert_eq(items.length(), 1)
  assert_true(items[0].kind is TurnEnd)
  assert_eq(items[0].sequence, Some(7))
  assert_eq(items[0].text(), None)
}
