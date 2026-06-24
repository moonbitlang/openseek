///|
test "ReadState records and recalls seen paths" {
  let state = @read_state.ReadState::ReadState()
  assert_false(state.has_seen("/ws/parser.mbt"))
  state.record("/ws/parser.mbt")
  assert_true(state.has_seen("/ws/parser.mbt"))
  // Unrelated paths stay unseen; recording is idempotent.
  assert_false(state.has_seen("/ws/types.mbt"))
  state.record("/ws/parser.mbt")
  assert_true(state.has_seen("/ws/parser.mbt"))
}
