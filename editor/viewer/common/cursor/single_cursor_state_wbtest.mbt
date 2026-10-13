///|
/// White-box cursor-state coverage.
fn pos(line : Int32, column : Int32) -> @base_common.Position {
  Position(line, column)
}

///|
test "collapsed cursor selects nothing" {
  let state = SingleCursorState::collapsed(pos(1, 2))
  assert_true(state.selection().is_empty())
  assert_false(state.has_selection())
  assert_true(state.selection().start() == pos(1, 2))
}

///|
test "simple drag keeps the anchor and moves the active end" {
  let start = SingleCursorState::collapsed(pos(0, 3))
  let dragged = start.moved(true, pos(0, 7))
  assert_false(dragged.selection().is_empty())
  assert_true(dragged.selection().start() == pos(0, 3))
  assert_true(dragged.selection().end() == pos(0, 7))
  assert_true(dragged.selection().get_selection_start() == pos(0, 3))
  assert_true(dragged.selection().get_position() == pos(0, 7))
}

///|
test "out of selection mode collapses the whole state" {
  let dragged = SingleCursorState::collapsed(pos(0, 3)).moved(true, pos(0, 7))
  let collapsed = dragged.moved(false, pos(1, 1))
  assert_true(collapsed.selection().is_empty())
  assert_true(collapsed.selection().start() == pos(1, 1))
  assert_true(collapsed.selection_start_kind == Simple)
}

///|
test "dragging backward across a word anchor keeps the far edge" {
  // A word anchor spanning columns [4, 8); the active end starts at 8.
  let word = SingleCursorState(pos(0, 4), pos(0, 8), Word, pos(0, 8))
  // Drag the active end before the anchor's start: the anchor flips to the end.
  let backward = word.moved(true, pos(0, 2))
  assert_true(backward.selection().start() == pos(0, 2))
  assert_true(backward.selection().end() == pos(0, 8))
  // The kind is preserved while extending.
  assert_true(backward.selection_start_kind == Word)
}

///|
test "selection movement preserves anchor residue and replaces active residue" {
  let state = SingleCursorState(
    pos(1, 3),
    pos(1, 3),
    Simple,
    pos(1, 5),
    selection_start_leftover_visible_columns=4,
    leftover_visible_columns=7,
  )
  let moved = state.moved(true, pos(2, 2), leftover_visible_columns=9)
  assert_eq(moved.selection_start_leftover_visible_columns, 4)
  assert_eq(moved.leftover_visible_columns, 9)
}

///|
test "collapsing movement applies one residue to both cursor ends" {
  let state = SingleCursorState::collapsed(pos(1, 3)).moved(
    false,
    pos(2, 2),
    leftover_visible_columns=6,
  )
  assert_eq(state.selection_start_leftover_visible_columns, 6)
  assert_eq(state.leftover_visible_columns, 6)
}
