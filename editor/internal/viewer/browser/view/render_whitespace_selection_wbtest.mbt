// Stage-2 white-box for the `RenderWhitespace::Selection` per-line offset
// derivation (plan: monaco-render-whitespace-control-options-port.md), the port
// of `viewLine.ts:122-149`. Drives `selections_on_line_for` over the four
// Selection shapes — miss, partial single-line, multi-line clamp, empty-drop —
// asserting the `-1` zero-based conversion, the `min/maxColumn` clamp on
// non-anchor lines, and the `startColumn < endColumn` empty-drop.

///|
/// Minimal view-line data for the derivation: only `min_column`/`max_column`
/// (the non-anchor clamp bounds) feed `selections_on_line_for`.
fn selection_line_data(
  min_column : Int32,
  max_column : Int32,
) -> @view_layout.ViewLineRenderingData {
  {
    min_column,
    max_column,
    content: "",
    continues_with_wrapped_line: false,
    contains_rtl: false,
    is_basic_ascii: true,
    tokens: [],
    inline_decorations: [],
    tab_size: 2,
    start_visible_column: 0,
    text_direction: LTR,
    has_variable_fonts: false,
  }
}

///|
fn view_range(
  start_line : Int32,
  start_column : Int32,
  end_line : Int32,
  end_column : Int32,
) -> @base_common.Range {
  Range(start_line, start_column, end_line, end_column)
}

///|
test "selection derivation: a selection that misses the line yields no offsets" {
  let line_data = selection_line_data(1, 11)
  // Selection on lines 2..3; the line under test is 5 — no intersection.
  let result = selections_on_line_for(
    5,
    line_data,
    Selection,
    Some(view_range(2, 1, 3, 4)),
  )
  assert_eq(result.length(), 0)
}

///|
test "selection derivation: a partial single-line selection clips to its columns" {
  let line_data = selection_line_data(1, 11)
  // Columns 3..6 on line 5 → zero-based OffsetRange(2, 5).
  let result = selections_on_line_for(
    5,
    line_data,
    Selection,
    Some(view_range(5, 3, 5, 6)),
  )
  assert_eq(result.length(), 1)
  assert_eq(result[0].start, 2)
  assert_eq(result[0].end_exclusive, 5)
}

///|
test "selection derivation: a non-anchor line clamps to min/max column" {
  let line_data = selection_line_data(1, 11)
  // Line 5 is interior to a 4→6 multi-line selection (neither start nor end
  // line), so it spans [min_column, max_column] = [1, 11] → OffsetRange(0, 10).
  // The selection's own start/end columns (8 and 2) are ignored off-anchor.
  let result = selections_on_line_for(
    5,
    line_data,
    Selection,
    Some(view_range(4, 8, 6, 2)),
  )
  assert_eq(result.length(), 1)
  assert_eq(result[0].start, 0)
  assert_eq(result[0].end_exclusive, 10)
}

///|
test "selection derivation: an empty per-line range is dropped" {
  let line_data = selection_line_data(1, 11)
  // start_column == end_column (4) on the line → `start < end` is false → drop.
  let result = selections_on_line_for(
    5,
    line_data,
    Selection,
    Some(view_range(5, 4, 5, 4)),
  )
  assert_eq(result.length(), 0)
}

///|
test "selection derivation: only Selection mode gathers offsets" {
  let line_data = selection_line_data(1, 11)
  let sel = Some(view_range(5, 3, 5, 6))
  // A real selection on the line, but non-Selection modes ignore it.
  assert_eq(selections_on_line_for(5, line_data, All, sel).length(), 0)
  assert_eq(selections_on_line_for(5, line_data, Boundary, sel).length(), 0)
  assert_eq(selections_on_line_for(5, line_data, Trailing, sel).length(), 0)
  assert_eq(selections_on_line_for(5, line_data, None, sel).length(), 0)
  // Selection mode with no selection threaded is also empty.
  assert_eq(selections_on_line_for(5, line_data, Selection, None).length(), 0)
}
