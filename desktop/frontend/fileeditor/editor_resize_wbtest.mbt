// `drag_size` is shared by three drags (editor width, tree width, tree
// height), so its rules are pinned once here rather than in any one of them.
// The DOM-driven halves of the resizers (`end_drag`, the listener install)
// need a browser. The live grid value is pure and pinned here because a browser
// silently ignores malformed CSS, which otherwise looks like a frozen drag.

///|
test "a live editor width produces a valid concrete grid track" {
  let width : EditorWidth = { pixels: 504 }
  assert_eq(width.grid_template(), "minmax(0, 1fr) 504px")
  assert_eq(width.custom_property(), "504px")
}

///|
test "a dragged size passes through inside its range and saturates outside" {
  assert_eq(drag_size(300.0, floor=100.0, max=500.0), 300)
  assert_eq(drag_size(40.0, floor=100.0, max=500.0), 100)
  assert_eq(drag_size(900.0, floor=100.0, max=500.0), 500)
}

///|
/// The bounds are exact, not exclusive.
test "a drag exactly on either bound keeps that bound" {
  assert_eq(drag_size(100.0, floor=100.0, max=500.0), 100)
  assert_eq(drag_size(500.0, floor=100.0, max=500.0), 500)
}

///|
/// On a window too narrow (or too short) to honour both bounds the ceiling
/// falls below the floor, and the floor wins: the pane keeps its minimum
/// instead of collapsing. This is the rule that was copied three times.
test "the floor outranks a ceiling that fell below it" {
  assert_eq(drag_size(900.0, floor=360.0, max=200.0), 360)
  assert_eq(drag_size(300.0, floor=360.0, max=200.0), 360)
  assert_eq(drag_size(10.0, floor=360.0, max=200.0), 360)
}

///|
/// The size becomes a whole-pixel CSS custom property; the conversion
/// truncates toward zero rather than rounding.
test "a fractional drag truncates to whole pixels" {
  assert_eq(drag_size(300.9, floor=100.0, max=500.0), 300)
  assert_eq(drag_size(99.9, floor=10.0, max=500.0), 99)
}
