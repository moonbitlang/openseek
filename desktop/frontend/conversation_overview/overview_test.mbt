///|
test "the environment starts unfolded and the connectors as their summary" {
  let state = @conversation_overview.State::initial()
  assert_true(state.is_open(Environment))
  assert_false(state.is_open(Connectors))
}

///|
test "a card's title folds and unfolds only that card" {
  let state = @conversation_overview.State::initial()
  let unfolded = @conversation_overview.update(Toggled(Connectors), state)
  assert_true(unfolded.is_open(Connectors))
  assert_true(unfolded.is_open(Environment))
  let folded = @conversation_overview.update(Toggled(Environment), unfolded)
  assert_false(folded.is_open(Environment))
  assert_true(folded.is_open(Connectors))
  assert_true(
    @conversation_overview.update(Toggled(Environment), folded) == unfolded,
  )
}
