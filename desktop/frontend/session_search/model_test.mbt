///|
test "keyboard selection uses current results and preserves the query after opening" {
  let first = @conversation.Id(
    source=OpenSeekLive,
    channel="local",
    conversation="first",
  )
  let second = @conversation.Id(
    source=CloudLive,
    channel="account",
    conversation="second",
  )
  let (_, typed, _) = @session_search.Model().update(Changed("title"), [])
  let (_, moved, _) = typed.update(Move(1), [first, second])
  let (_, opened, selection) = moved.update(Pick, [first, second])
  assert_eq(selection, Some(second))
  assert_eq(opened.query(), "title")
  // A refreshed or signed-out list cannot open a cached account's result.
  let (_, _, selection) = opened.update(Pick, [first])
  assert_eq(selection, Some(first))
  let (_, _, selection) = opened.update(Pick, [])
  assert_eq(selection, None)
}

///|
test "clearing or changing a query resets selection" {
  let id = @conversation.Id(
    source=OpenSeekLive,
    channel="local",
    conversation="first",
  )
  let (_, typed, _) = @session_search.Model().update(Changed("title"), [])
  let (_, cleared, _) = typed.update(Clear, [id])
  assert_eq(cleared.query(), "")
  let (_, _, selection) = cleared.update(Pick, [id])
  assert_eq(selection, None)
  let (_, changed, _) = typed.update(Changed("next"), [id])
  assert_eq(changed.selected(1), 0)
}
