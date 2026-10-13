// Phase 4 of `monaco-hover-logic-chain-port.md`: whitebox coverage for
// `compute_hover_positions`. One case per behavior-switching branch.

///|
fn pos_part(
  start_line : Int32,
  start_column : Int32,
  end_line : Int32,
  end_column : Int32,
  force~ : Bool = false,
) -> HoverPositionPart {
  {
    range: Range(start_line, start_column, end_line, end_column),
    force_show_at_range: force,
  }
}

///|
test "computeHoverPositions: secondary column is the leftmost part start on the anchor line" {
  let anchor = @base_common.Range(2, 10, 2, 14)
  let (show_at, show_at_secondary) = compute_hover_positions(
    anchor,
    [
      // On the anchor line, starting left of the anchor: pulls the secondary left.
      pos_part(2, 6, 2, 9),
      // Starts on the anchor line but spans onto the next line: not "on the
      // anchor line", so it is ignored even though it starts further left.
      pos_part(2, 3, 3, 1),
      // Entirely on a different line: ignored.
      pos_part(5, 1, 5, 4),
    ],
    1,
  )
  // The primary anchor is the anchor range start.
  assert_eq(show_at.line_number, 2)
  assert_eq(show_at.column, 10)
  // The secondary anchor moved left to the leftmost on-anchor-line part.
  assert_eq(show_at_secondary.line_number, 2)
  assert_eq(show_at_secondary.column, 6)
}

///|
test "computeHoverPositions: secondary column is clamped up to the start-column boundary" {
  let anchor = @base_common.Range(2, 10, 2, 14)
  // The part starts at column 3, but the view line's minimum model column is 8.
  let (_, show_at_secondary) = compute_hover_positions(
    anchor,
    [pos_part(2, 3, 2, 5)],
    8,
  )
  assert_eq(show_at_secondary.column, 8)
}

///|
test "computeHoverPositions: no on-anchor-line parts leaves the secondary at the anchor start" {
  let anchor = @base_common.Range(4, 7, 4, 9)
  // Empty parts, and a part off the anchor line: secondary stays the anchor start column.
  let (_, empty_secondary) = compute_hover_positions(anchor, [], 1)
  assert_eq(empty_secondary.line_number, 4)
  assert_eq(empty_secondary.column, 7)
  let (_, off_line_secondary) = compute_hover_positions(
    anchor,
    [pos_part(9, 1, 9, 2)],
    1,
  )
  assert_eq(off_line_secondary.column, 7)
}

///|
test "computeHoverPositions: forceShowAtRange overrides both positions, last one wins" {
  let anchor = @base_common.Range(2, 10, 2, 14)
  let (show_at, show_at_secondary) = compute_hover_positions(
    anchor,
    [pos_part(6, 3, 6, 8, force=true), pos_part(7, 2, 7, 5, force=true)],
    1,
  )
  // Both the primary and secondary collapse to the last forced part's start.
  assert_eq(show_at.line_number, 7)
  assert_eq(show_at.column, 2)
  assert_eq(show_at_secondary.line_number, 7)
  assert_eq(show_at_secondary.column, 2)
}

///|
test "computeDistanceFromPointToRectangle: inside, beside, and off a corner" {
  // Rectangle at (100,100) sized 50x50 -> spans x[100,150], y[100,150].
  // Inside the rectangle: distance 0.
  assert_eq(
    compute_distance_from_point_to_rectangle(
      125.0, 125.0, 100.0, 100.0, 50.0, 50.0,
    ),
    0.0,
  )
  // Directly to the left: the horizontal gap only.
  assert_eq(
    compute_distance_from_point_to_rectangle(
      80.0, 125.0, 100.0, 100.0, 50.0, 50.0,
    ),
    20.0,
  )
  // Off the bottom-right corner by (50,50): the diagonal gap.
  let corner = compute_distance_from_point_to_rectangle(
    200.0, 200.0, 100.0, 100.0, 50.0, 50.0,
  )
  assert_true((corner - 70.71067811865476).abs() < 0.0001)
}

///|
test "isMouseGettingCloser: first call seeds the reference then tracks the running minimum" {
  // Rectangle x[100,150], y[100,150].
  let state = MouseCloserState()
  // First move seeds the reference point and reports false (no closeness yet).
  assert_false(
    state.is_mouse_getting_closer(200.0, 125.0, 100.0, 100.0, 50.0, 50.0),
  )
  // Reference distance from (200,125) is 50. Moving to (160,125) is distance 10:
  // well within the closest-so-far + 4, so it is getting closer.
  assert_true(
    state.is_mouse_getting_closer(160.0, 125.0, 100.0, 100.0, 50.0, 50.0),
  )
  // Back out to (200,125), distance 50 > 10 + 4: getting farther.
  assert_false(
    state.is_mouse_getting_closer(200.0, 125.0, 100.0, 100.0, 50.0, 50.0),
  )
  // (162,125) is distance 12, within 10 + 4: still counts as getting closer.
  assert_true(
    state.is_mouse_getting_closer(162.0, 125.0, 100.0, 100.0, 50.0, 50.0),
  )
  // After a reset the next move re-seeds (returns false again).
  state.reset()
  assert_false(
    state.is_mouse_getting_closer(160.0, 125.0, 100.0, 100.0, 50.0, 50.0),
  )
}
