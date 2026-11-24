///|
test "changes starts unfolded and the background tasks card starts folded" {
  let state = @conversation_overview.State::initial()
  assert_true(state.is_open(Changes))
  assert_false(state.is_open(BackgroundTasks))
}

///|
test "a card's title folds and unfolds only that card" {
  let state = @conversation_overview.State::initial()
  let folded = @conversation_overview.update(Toggled(Changes), state)
  assert_false(folded.is_open(Changes))
  assert_false(folded.is_open(BackgroundTasks))
  assert_true(@conversation_overview.update(Toggled(Changes), folded) == state)
  let tasks = @conversation_overview.update(Toggled(BackgroundTasks), folded)
  assert_true(tasks.is_open(BackgroundTasks))
  assert_false(tasks.is_open(Changes))
}
