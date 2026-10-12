///|
fn insert_max_height_whitespaces(
  layout : LinesLayout,
  after_line_number : Int32,
) -> Unit {
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(after_line_number, 0, 2147483647.0, 0.0)
    |> ignore
    accessor.insert_whitespace(after_line_number, 1, 2147483647.0, 0.0)
    |> ignore
  })
  |> ignore
}

///|
test "LinesLayout accumulates ToInt32 whitespace heights as JavaScript numbers" {
  let layout = LinesLayout(1, 10, 3, 4)
  insert_max_height_whitespaces(layout, 0)

  assert_eq(layout.get_height_for_whitespace_index(0), 2147483647)
  assert_eq(layout.get_height_for_whitespace_index(1), 2147483647)
  assert_eq(layout.get_whitespaces_accumulated_height(0), 2147483647.0)
  assert_eq(layout.get_whitespaces_accumulated_height(1), 4294967294.0)
  assert_eq(layout.get_whitespaces_total_height(), 4294967294.0)
  assert_eq(layout.get_lines_total_height(), 4294967311.0)

  let rows = layout.get_whitespaces()
  assert_eq(rows[0].prefix_sum, 2147483647.0)
  assert_eq(rows[1].prefix_sum, 4294967294.0)
  assert_eq(layout.get_vertical_offset_for_line_number(1), 4294967297.0)
  assert_eq(layout.get_vertical_offset_after_line_number(1), 4294967307.0)
  assert_eq(layout.get_vertical_offset_for_whitespace_index(0), 3.0)
  assert_eq(layout.get_vertical_offset_for_whitespace_index(1), 2147483650.0)
}

///|
test "ViewLayout exposes uncoerced large line totals and offsets" {
  let layout = ViewLayout(line_height=10, line_count=1)
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(0, 0, 2147483647.0, 0.0) |> ignore
    accessor.insert_whitespace(0, 1, 2147483647.0, 0.0) |> ignore
  })
  |> ignore

  assert_eq(layout.get_vertical_offset_for_line_number(1), 4294967294.0)
  assert_eq(layout.get_vertical_offset_after_line_number(1), 4294967304.0)
  // `EditorScrollDimensions(...)` is a separate source-owned ToInt32 boundary.
  assert_eq(layout.get_content_height(), 8.0)
  assert_false(layout.is_after_lines(4294967304.0))
  assert_true(layout.is_after_lines(4294967304.5))
}

///|
test "LinesLayout preserves source ToInt32 points in search and viewport setup" {
  let search_layout = LinesLayout(3, 10, 0, 0)
  insert_max_height_whitespaces(search_layout, 0)

  // The line-2 top is 4294967304 before the source's `| 0`, and 8 after it.
  assert_eq(search_layout.get_vertical_offset_for_line_number(2), 4294967304.0)
  assert_eq(
    search_layout.get_line_number_at_or_after_vertical_offset(4294967305.0),
    2,
  )
  let coerced_viewport = search_layout.get_lines_viewport_data(
    4294967305.0, 4294967306.0,
  )
  assert_eq(coerced_viewport.start_line_number, 2)
  assert_eq(coerced_viewport.end_line_number, 2)
  assert_eq(coerced_viewport.relative_vertical_offset.length(), 1)
  assert_eq(coerced_viewport.relative_vertical_offset[0], 8.0)
  assert_eq(coerced_viewport.big_numbers_delta, 0)

  // Once viewport setup has applied its explicit coercions, loop accumulation
  // is ordinary JS-number addition and must not wrap back into the viewport.
  let accumulation_layout = LinesLayout(2, 10, 0, 0)
  insert_max_height_whitespaces(accumulation_layout, 1)
  let accumulated_viewport = accumulation_layout.get_lines_viewport_data(0, 100)
  assert_eq(accumulated_viewport.start_line_number, 1)
  assert_eq(accumulated_viewport.end_line_number, 1)
  assert_eq(accumulated_viewport.relative_vertical_offset.length(), 1)
  assert_eq(accumulated_viewport.relative_vertical_offset[0], 0.0)
}
