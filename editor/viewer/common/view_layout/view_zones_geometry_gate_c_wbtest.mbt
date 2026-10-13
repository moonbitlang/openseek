///|
fn view_layout_with_min_width(min_width : Double) -> ViewLayout {
  let layout = ViewLayout(
    line_height=10,
    line_count=5,
    vertical_scrollbar_width=14.0,
    horizontal_scrollbar_height=12.0,
  )
  layout.set_viewport_size(width=100.0, height=50.0) |> ignore
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(1, 0, 10.0, min_width) |> ignore
  })
  |> ignore
  // `setMaxLineWidth` is the source-owned width recomputation trigger.
  layout.set_max_line_width(86.0) |> ignore
  layout
}

///|
test "ViewLayout whitespace min width covers below equal above content and scroll width" {
  let below = view_layout_with_min_width(99.0)
  assert_eq(below.get_content_width(), 100.0)
  assert_eq(below.get_scroll_width(), 100.0)

  let equal = view_layout_with_min_width(100.0)
  assert_eq(equal.get_content_width(), 100.0)
  assert_eq(equal.get_scroll_width(), 100.0)

  let above = view_layout_with_min_width(101.0)
  assert_eq(above.get_content_width(), 101.0)
  assert_eq(above.get_scroll_width(), 101.0)
}

///|
fn rail_layout(offset : Int32) -> ViewLayout {
  let layout = ViewLayout(line_height=18, line_count=3)
  layout.set_viewport_size(width=100.0, height=1.0) |> ignore
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(0, 0, offset.to_double(), 0.0) |> ignore
  })
  |> ignore
  layout
}

///|
test "ViewLayout big-number rail is exact at 499999 500000 500001" {
  let cases : Array[(Int32, Int32, Double)] = [
    (499999, 0, 499999.0),
    (500000, 499986, 14.0),
    (500001, 499986, 15.0),
  ]
  for case in cases {
    let (offset, expected_delta, expected_relative) = case
    let layout = rail_layout(offset)
    let window : LineWindow = { start: 1, end: 2, }
    assert_eq(layout.big_numbers_delta_for_window(window), expected_delta)
    assert_eq(
      layout.relative_vertical_offset_for_line(window, 1),
      expected_relative,
    )
    let data = layout.get_lines_viewport_data_at_scroll_top(offset.to_double())
    assert_eq(data.start_line_number, 1)
    assert_eq(data.big_numbers_delta, expected_delta)
    assert_eq(data.relative_vertical_offset[0], expected_relative)
  }
  assert_eq(499986 % 18, 0)
}
