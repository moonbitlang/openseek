///|
test "the environment starts unfolded and the other cards as their summaries" {
  let state = @conversation_overview.State::initial()
  assert_true(state.is_open(Environment))
  assert_false(state.is_open(Connectors))
  assert_false(state.is_open(BackgroundTasks))
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
  let tasks = @conversation_overview.update(Toggled(BackgroundTasks), folded)
  assert_true(tasks.is_open(BackgroundTasks))
  assert_true(tasks.is_open(Connectors))
  assert_false(tasks.is_open(Environment))
}

///|
test "the changes card starts unfolded and folds on its own" {
  let state = @conversation_overview.State::initial()
  assert_true(state.is_open(Changes))
  let folded = @conversation_overview.update(Toggled(Changes), state)
  assert_false(folded.is_open(Changes))
  assert_true(folded.is_open(Environment))
  assert_false(folded.is_open(Connectors))
}
