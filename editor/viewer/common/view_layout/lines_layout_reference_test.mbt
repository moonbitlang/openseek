///|
/// Faithful 1:1 conformance port of Monaco's `LinesLayout` unit suite,
/// `vscode/src/vs/editor/test/common/viewLayout/linesLayout.test.ts`
/// (`suite('Editor ViewLayout - LinesLayout')`) in the checked-in submodule. Test names are preserved verbatim.
///
/// Every case constructs the layout with uniform line heights (Monaco's
/// `customLineHeightData` argument is always `[]`), matching this port's
/// uniform-height deviation recorded in `lines_layout.mbt`.

///|
/// Element-wise `Array[Double]` equality — avoids the deprecated `Show`-based
/// `assert_eq` on arrays while keeping the per-element failure detail.
fn assert_int_array_eq(
  actual : Array[Double],
  expected : Array[Double],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i], expected[i])
  }
}

///|
fn insert_whitespace(
  lines_layout : @view_layout.LinesLayout,
  after_line_number : Int32,
  ordinal : Int32,
  height_in_px : Int32,
  min_width : Int32,
) -> String {
  let id = Ref("")
  lines_layout.change_whitespace(fn(accessor) {
    id.val = accessor.insert_whitespace(
      after_line_number,
      ordinal,
      height_in_px.to_double(),
      min_width.to_double(),
    )
  })
  |> ignore
  id.val
}

///|
fn change_one_whitespace(
  lines_layout : @view_layout.LinesLayout,
  id : String,
  new_after_line_number : Int32,
  new_height : Int32,
) -> Unit {
  lines_layout.change_whitespace(fn(accessor) {
    accessor.change_one_whitespace(
      id,
      new_after_line_number,
      new_height.to_double(),
    )
  })
  |> ignore
}

///|
fn remove_whitespace(
  lines_layout : @view_layout.LinesLayout,
  id : String,
) -> Unit {
  lines_layout.change_whitespace(fn(accessor) { accessor.remove_whitespace(id) })
  |> ignore
}

///|
test "LinesLayout 1" {
  // Start off with 10 lines
  let lines_layout = @view_layout.LinesLayout(10, 10, 0, 0)

  // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  // whitespace: -
  assert_eq(lines_layout.get_lines_total_height(), 100)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 30)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 40)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 50)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 60)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 70)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 80)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 90)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(1), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(5), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(9), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(10), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(11), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(15), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(19), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(20), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(21), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(29), 3)

  // Add whitespace of height 5px after 2nd line
  insert_whitespace(lines_layout, 2, 0, 5, 0) |> ignore
  // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  // whitespace: a(2,5)
  assert_eq(lines_layout.get_lines_total_height(), 105)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 25)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 35)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 45)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(1), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(9), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(10), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(20), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(21), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(24), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(25), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(35), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(45), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(104), 10)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(105), 10)

  // Add two more whitespaces of height 5px
  insert_whitespace(lines_layout, 3, 0, 5, 0) |> ignore
  insert_whitespace(lines_layout, 4, 0, 5, 0) |> ignore
  // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  // whitespace: a(2,5), b(3, 5), c(4, 5)
  assert_eq(lines_layout.get_lines_total_height(), 115)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 25)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 40)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 55)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 65)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(1), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(9), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(10), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(19), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(20), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(34), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(35), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(49), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(50), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(64), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(65), 6)
  assert_eq(lines_layout.get_vertical_offset_for_whitespace_index(0), 20) // 20 -> 25
  assert_eq(lines_layout.get_vertical_offset_for_whitespace_index(1), 35) // 35 -> 40
  assert_eq(lines_layout.get_vertical_offset_for_whitespace_index(2), 50)
  assert_eq(lines_layout.get_whitespace_index_at_or_after_vertical_offset(0), 0)
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(19),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(20),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(21),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(22),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(23),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(24),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(25),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(26),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(34),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(35),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(36),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(39),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(40),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(41),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(49),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(50),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(51),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(54),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(55),
    -1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(1000),
    -1,
  )
}

///|
test "LinesLayout 2" {
  // Start off with 10 lines and one whitespace after line 2, of height 5
  let lines_layout = @view_layout.LinesLayout(10, 1, 0, 0)
  let a = insert_whitespace(lines_layout, 2, 0, 5, 0)

  // 10 lines
  // whitespace: - a(2,5)
  assert_eq(lines_layout.get_lines_total_height(), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 7)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 8)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 9)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 11)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 12)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 13)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 14)

  // Change whitespace height
  // 10 lines
  // whitespace: - a(2,10)
  change_one_whitespace(lines_layout, a, 2, 10)
  assert_eq(lines_layout.get_lines_total_height(), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 12)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 13)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 14)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 16)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 17)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 18)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 19)

  // Change whitespace position
  // 10 lines
  // whitespace: - a(5,10)
  change_one_whitespace(lines_layout, a, 5, 10)
  assert_eq(lines_layout.get_lines_total_height(), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 2)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 3)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 4)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 16)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 17)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 18)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 19)

  // Pretend that lines 5 and 6 were deleted
  // 8 lines
  // whitespace: - a(4,10)
  lines_layout.on_lines_deleted(5, 6)
  assert_eq(lines_layout.get_lines_total_height(), 18)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 2)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 3)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 14)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 16)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 17)

  // Insert two lines at the beginning
  // 10 lines
  // whitespace: - a(6,10)
  lines_layout.on_lines_inserted(1, 2)
  assert_eq(lines_layout.get_lines_total_height(), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 2)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 3)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 4)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 5)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 16)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 17)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 18)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 19)

  // Remove whitespace
  // 10 lines
  remove_whitespace(lines_layout, a)
  assert_eq(lines_layout.get_lines_total_height(), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 2)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 3)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 4)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 5)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 6)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 7)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 8)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 9)
}

///|
test "LinesLayout Padding" {
  // Start off with 10 lines
  let lines_layout = @view_layout.LinesLayout(10, 10, 15, 20)

  // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  // whitespace: -
  assert_eq(lines_layout.get_lines_total_height(), 135)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 25)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 35)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 45)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 55)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 65)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 75)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 85)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 95)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 105)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(10), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(15), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(24), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(25), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(34), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(35), 3)

  // Add whitespace of height 5px after 2nd line
  insert_whitespace(lines_layout, 2, 0, 5, 0) |> ignore
  // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  // whitespace: a(2,5)
  assert_eq(lines_layout.get_lines_total_height(), 140)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 25)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 40)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 50)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(10), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(25), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(34), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(35), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(39), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(40), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(41), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(49), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(50), 4)

  // Add two more whitespaces of height 5px
  insert_whitespace(lines_layout, 3, 0, 5, 0) |> ignore
  insert_whitespace(lines_layout, 4, 0, 5, 0) |> ignore
  // lines: [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
  // whitespace: a(2,5), b(3, 5), c(4, 5)
  assert_eq(lines_layout.get_lines_total_height(), 150)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 15)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 25)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 40)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 55)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 70)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 80)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(15), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(24), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(30), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(35), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(39), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(40), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(49), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(50), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(54), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(55), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(64), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(65), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(69), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(70), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(80), 6)
  assert_eq(lines_layout.get_vertical_offset_for_whitespace_index(0), 35) // 35 -> 40
  assert_eq(lines_layout.get_vertical_offset_for_whitespace_index(1), 50) // 50 -> 55
  assert_eq(lines_layout.get_vertical_offset_for_whitespace_index(2), 65)
  assert_eq(lines_layout.get_whitespace_index_at_or_after_vertical_offset(0), 0)
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(34),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(35),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(39),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(40),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(49),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(50),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(54),
    1,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(55),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(64),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(65),
    2,
  )
  assert_eq(
    lines_layout.get_whitespace_index_at_or_after_vertical_offset(70),
    -1,
  )
}

///|
test "LinesLayout getLineNumberAtOrAfterVerticalOffset" {
  let lines_layout = @view_layout.LinesLayout(10, 1, 0, 0)
  insert_whitespace(lines_layout, 6, 0, 10, 0) |> ignore

  // 10 lines
  // whitespace: - a(6,10)
  assert_eq(lines_layout.get_lines_total_height(), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 2)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 3)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 4)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 5)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 16)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 17)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 18)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 19)

  // Do some hit testing
  // line      [1, 2, 3, 4, 5, 6,  7,  8,  9, 10]
  // vertical: [0, 1, 2, 3, 4, 5, 16, 17, 18, 19]
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(-100), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(-1), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(0), 1)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(1), 2)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(2), 3)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(3), 4)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(4), 5)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(5), 6)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(6), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(7), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(8), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(9), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(10), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(11), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(12), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(13), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(14), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(15), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(16), 7)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(17), 8)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(18), 9)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(19), 10)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(20), 10)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(21), 10)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(22), 10)
  assert_eq(lines_layout.get_line_number_at_or_after_vertical_offset(23), 10)
}

///|
test "LinesLayout getCenteredLineInViewport" {
  let lines_layout = @view_layout.LinesLayout(10, 1, 0, 0)
  insert_whitespace(lines_layout, 6, 0, 10, 0) |> ignore

  // 10 lines
  // whitespace: - a(6,10)
  assert_eq(lines_layout.get_lines_total_height(), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 1)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 2)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 3)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 4)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 5)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 16)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 17)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 18)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 19)

  // Find centered line in viewport 1
  // line      [1, 2, 3, 4, 5, 6,  7,  8,  9, 10]
  // vertical: [0, 1, 2, 3, 4, 5, 16, 17, 18, 19]
  assert_eq(lines_layout.get_lines_viewport_data(0, 1).centered_line_number, 1)
  assert_eq(lines_layout.get_lines_viewport_data(0, 2).centered_line_number, 2)
  assert_eq(lines_layout.get_lines_viewport_data(0, 3).centered_line_number, 2)
  assert_eq(lines_layout.get_lines_viewport_data(0, 4).centered_line_number, 3)
  assert_eq(lines_layout.get_lines_viewport_data(0, 5).centered_line_number, 3)
  assert_eq(lines_layout.get_lines_viewport_data(0, 6).centered_line_number, 4)
  assert_eq(lines_layout.get_lines_viewport_data(0, 7).centered_line_number, 4)
  assert_eq(lines_layout.get_lines_viewport_data(0, 8).centered_line_number, 5)
  assert_eq(lines_layout.get_lines_viewport_data(0, 9).centered_line_number, 5)
  assert_eq(lines_layout.get_lines_viewport_data(0, 10).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 11).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 12).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 13).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 14).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 15).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 16).centered_line_number, 6)
  assert_eq(lines_layout.get_lines_viewport_data(0, 17).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 18).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 19).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 21).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 22).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 23).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 24).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 25).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 26).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 27).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 28).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 29).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 30).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 31).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 32).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(0, 33).centered_line_number, 7)

  // Find centered line in viewport 2
  // line      [1, 2, 3, 4, 5, 6,  7,  8,  9, 10]
  // vertical: [0, 1, 2, 3, 4, 5, 16, 17, 18, 19]
  assert_eq(lines_layout.get_lines_viewport_data(0, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(1, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(2, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(3, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(4, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(5, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(6, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(7, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(8, 20).centered_line_number, 7)
  assert_eq(lines_layout.get_lines_viewport_data(9, 20).centered_line_number, 7)
  assert_eq(
    lines_layout.get_lines_viewport_data(10, 20).centered_line_number,
    7,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(11, 20).centered_line_number,
    7,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(12, 20).centered_line_number,
    7,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(13, 20).centered_line_number,
    7,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(14, 20).centered_line_number,
    8,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(15, 20).centered_line_number,
    8,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(16, 20).centered_line_number,
    9,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(17, 20).centered_line_number,
    9,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(18, 20).centered_line_number,
    10,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(19, 20).centered_line_number,
    10,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(20, 23).centered_line_number,
    10,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(21, 23).centered_line_number,
    10,
  )
  assert_eq(
    lines_layout.get_lines_viewport_data(22, 23).centered_line_number,
    10,
  )
}

///|
test "LinesLayout getLinesViewportData 1" {
  let lines_layout = @view_layout.LinesLayout(10, 10, 0, 0)
  insert_whitespace(lines_layout, 6, 0, 100, 0) |> ignore

  // 10 lines
  // whitespace: - a(6,100)
  assert_eq(lines_layout.get_lines_total_height(), 200)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 30)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 40)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 50)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 160)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 170)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 180)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 190)

  // viewport 0->50
  let viewport_data = lines_layout.get_lines_viewport_data(0, 50)
  assert_eq(viewport_data.start_line_number, 1)
  assert_eq(viewport_data.end_line_number, 5)
  assert_eq(viewport_data.completely_visible_start_line_number, 1)
  assert_eq(viewport_data.completely_visible_end_line_number, 5)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [
    0, 10, 20, 30, 40,
  ])

  // viewport 1->51
  let viewport_data = lines_layout.get_lines_viewport_data(1, 51)
  assert_eq(viewport_data.start_line_number, 1)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 2)
  assert_eq(viewport_data.completely_visible_end_line_number, 5)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [
    0, 10, 20, 30, 40, 50,
  ])

  // viewport 5->55
  let viewport_data = lines_layout.get_lines_viewport_data(5, 55)
  assert_eq(viewport_data.start_line_number, 1)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 2)
  assert_eq(viewport_data.completely_visible_end_line_number, 5)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [
    0, 10, 20, 30, 40, 50,
  ])

  // viewport 10->60
  let viewport_data = lines_layout.get_lines_viewport_data(10, 60)
  assert_eq(viewport_data.start_line_number, 2)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 2)
  assert_eq(viewport_data.completely_visible_end_line_number, 6)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [
    10, 20, 30, 40, 50,
  ])

  // viewport 50->100
  let viewport_data = lines_layout.get_lines_viewport_data(50, 100)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 6)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50])

  // viewport 60->110
  let viewport_data = lines_layout.get_lines_viewport_data(60, 110)
  assert_eq(viewport_data.start_line_number, 7)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [160])

  // viewport 65->115
  let viewport_data = lines_layout.get_lines_viewport_data(65, 115)
  assert_eq(viewport_data.start_line_number, 7)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [160])

  // viewport 50->159
  let viewport_data = lines_layout.get_lines_viewport_data(50, 159)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 6)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50])

  // viewport 50->160
  let viewport_data = lines_layout.get_lines_viewport_data(50, 160)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 6)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50])

  // viewport 51->161
  let viewport_data = lines_layout.get_lines_viewport_data(51, 161)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50, 160])

  // viewport 150->169
  let viewport_data = lines_layout.get_lines_viewport_data(150, 169)
  assert_eq(viewport_data.start_line_number, 7)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [160])

  // viewport 159->169
  let viewport_data = lines_layout.get_lines_viewport_data(159, 169)
  assert_eq(viewport_data.start_line_number, 7)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [160])

  // viewport 160->169
  let viewport_data = lines_layout.get_lines_viewport_data(160, 169)
  assert_eq(viewport_data.start_line_number, 7)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [160])

  // viewport 160->1000
  let viewport_data = lines_layout.get_lines_viewport_data(160, 1000)
  assert_eq(viewport_data.start_line_number, 7)
  assert_eq(viewport_data.end_line_number, 10)
  assert_eq(viewport_data.completely_visible_start_line_number, 7)
  assert_eq(viewport_data.completely_visible_end_line_number, 10)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [
    160, 170, 180, 190,
  ])
}

///|
test "LinesLayout getLinesViewportData 2 & getWhitespaceViewportData" {
  let lines_layout = @view_layout.LinesLayout(10, 10, 0, 0)
  let a = insert_whitespace(lines_layout, 6, 0, 100, 0)
  let b = insert_whitespace(lines_layout, 7, 0, 50, 0)

  // 10 lines
  // whitespace: - a(6,100), b(7, 50)
  assert_eq(lines_layout.get_lines_total_height(), 250)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(1), 0)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(2), 10)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(3), 20)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(4), 30)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(5), 40)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(6), 50)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(7), 160)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(8), 220)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(9), 230)
  assert_eq(lines_layout.get_vertical_offset_for_line_number(10), 240)

  // viewport 50->160
  let viewport_data = lines_layout.get_lines_viewport_data(50, 160)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 6)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 6)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50])
  let whitespace_data = lines_layout.get_whitespace_viewport_data(50, 160)
  assert_eq(whitespace_data.length(), 1)
  assert_eq(whitespace_data[0].id, a)
  assert_eq(whitespace_data[0].after_line_number, 6)
  assert_eq(whitespace_data[0].vertical_offset, 60)
  assert_eq(whitespace_data[0].height, 100)

  // viewport 50->219
  let viewport_data = lines_layout.get_lines_viewport_data(50, 219)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50, 160])
  let whitespace_data = lines_layout.get_whitespace_viewport_data(50, 219)
  assert_eq(whitespace_data.length(), 2)
  assert_eq(whitespace_data[0].id, a)
  assert_eq(whitespace_data[0].after_line_number, 6)
  assert_eq(whitespace_data[0].vertical_offset, 60)
  assert_eq(whitespace_data[0].height, 100)
  assert_eq(whitespace_data[1].id, b)
  assert_eq(whitespace_data[1].after_line_number, 7)
  assert_eq(whitespace_data[1].vertical_offset, 170)
  assert_eq(whitespace_data[1].height, 50)

  // viewport 50->220
  let viewport_data = lines_layout.get_lines_viewport_data(50, 220)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 7)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 7)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [50, 160])

  // viewport 50->250
  let viewport_data = lines_layout.get_lines_viewport_data(50, 250)
  assert_eq(viewport_data.start_line_number, 6)
  assert_eq(viewport_data.end_line_number, 10)
  assert_eq(viewport_data.completely_visible_start_line_number, 6)
  assert_eq(viewport_data.completely_visible_end_line_number, 10)
  assert_int_array_eq(viewport_data.relative_vertical_offset, [
    50, 160, 220, 230, 240,
  ])
}

///|
test "LinesLayout getWhitespaceAtVerticalOffset" {
  let lines_layout = @view_layout.LinesLayout(10, 10, 0, 0)
  let a = insert_whitespace(lines_layout, 6, 0, 100, 0)
  let b = insert_whitespace(lines_layout, 7, 0, 50, 0)
  assert_true(lines_layout.get_whitespace_at_vertical_offset(0) is None)
  assert_true(lines_layout.get_whitespace_at_vertical_offset(59) is None)
  assert_eq(lines_layout.get_whitespace_at_vertical_offset(60).unwrap().id, a)
  assert_eq(lines_layout.get_whitespace_at_vertical_offset(61).unwrap().id, a)
  assert_eq(lines_layout.get_whitespace_at_vertical_offset(159).unwrap().id, a)
  assert_true(lines_layout.get_whitespace_at_vertical_offset(160) is None)
  assert_true(lines_layout.get_whitespace_at_vertical_offset(161) is None)
  assert_true(lines_layout.get_whitespace_at_vertical_offset(169) is None)
  assert_eq(lines_layout.get_whitespace_at_vertical_offset(170).unwrap().id, b)
  assert_eq(lines_layout.get_whitespace_at_vertical_offset(171).unwrap().id, b)
  assert_eq(lines_layout.get_whitespace_at_vertical_offset(219).unwrap().id, b)
  assert_true(lines_layout.get_whitespace_at_vertical_offset(220) is None)
}

///|
test "LinesLayout" {
  let lines_layout = @view_layout.LinesLayout(100, 20, 0, 0)

  // Insert a whitespace after line number 2, of height 10
  let a = insert_whitespace(lines_layout, 2, 0, 10, 0)
  // whitespaces: a(2, 10)
  assert_eq(lines_layout.get_whitespaces_count(), 1)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 10)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 10)
  assert_eq(lines_layout.get_whitespaces_total_height(), 10)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    10,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    10,
  )

  // Insert a whitespace again after line number 2, of height 20
  let b = insert_whitespace(lines_layout, 2, 0, 20, 0)
  // whitespaces: a(2, 10), b(2, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 10)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 10)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 30)
  assert_eq(lines_layout.get_whitespaces_total_height(), 30)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    30,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    30,
  )

  // Change last inserted whitespace height to 30
  change_one_whitespace(lines_layout, b, 2, 30)
  // whitespaces: a(2, 10), b(2, 30)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 10)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 30)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 10)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 40)
  assert_eq(lines_layout.get_whitespaces_total_height(), 40)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    40,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    40,
  )

  // Remove last inserted whitespace
  remove_whitespace(lines_layout, b)
  // whitespaces: a(2, 10)
  assert_eq(lines_layout.get_whitespaces_count(), 1)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 10)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 10)
  assert_eq(lines_layout.get_whitespaces_total_height(), 10)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    10,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    10,
  )

  // Add a whitespace before the first line of height 50
  let b = insert_whitespace(lines_layout, 0, 0, 50, 0)
  // whitespaces: b(0, 50), a(2, 10)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 0)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 50)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 10)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 50)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 60)
  assert_eq(lines_layout.get_whitespaces_total_height(), 60)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    60,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    60,
  )

  // Add a whitespace after line 4 of height 20
  insert_whitespace(lines_layout, 4, 0, 20, 0) |> ignore
  // whitespaces: b(0, 50), a(2, 10), c(4, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 3)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 0)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 50)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 10)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 4)
  assert_eq(lines_layout.get_height_for_whitespace_index(2), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 50)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 60)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(2), 80)
  assert_eq(lines_layout.get_whitespaces_total_height(), 80)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    60,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    60,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    80,
  )

  // Add a whitespace after line 3 of height 30
  insert_whitespace(lines_layout, 3, 0, 30, 0) |> ignore
  // whitespaces: b(0, 50), a(2, 10), d(3, 30), c(4, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 4)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 0)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 50)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 10)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(2), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(3), 4)
  assert_eq(lines_layout.get_height_for_whitespace_index(3), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 50)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 60)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(2), 90)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(3), 110)
  assert_eq(lines_layout.get_whitespaces_total_height(), 110)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    60,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    90,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    110,
  )

  // Change whitespace after line 2 to height of 100
  change_one_whitespace(lines_layout, a, 2, 100)
  // whitespaces: b(0, 50), a(2, 100), d(3, 30), c(4, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 4)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 0)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 50)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 100)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(2), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(3), 4)
  assert_eq(lines_layout.get_height_for_whitespace_index(3), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 50)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 150)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(2), 180)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(3), 200)
  assert_eq(lines_layout.get_whitespaces_total_height(), 200)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    150,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    180,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    200,
  )

  // Remove whitespace after line 2
  remove_whitespace(lines_layout, a)
  // whitespaces: b(0, 50), d(3, 30), c(4, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 3)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 0)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 50)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 4)
  assert_eq(lines_layout.get_height_for_whitespace_index(2), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 50)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 80)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(2), 100)
  assert_eq(lines_layout.get_whitespaces_total_height(), 100)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    80,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    100,
  )

  // Remove whitespace before line 1
  remove_whitespace(lines_layout, b)
  // whitespaces: d(3, 30), c(4, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 4)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 30)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 50)
  assert_eq(lines_layout.get_whitespaces_total_height(), 50)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    30,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    50,
  )

  // Delete line 1
  lines_layout.on_lines_deleted(1, 1)
  // whitespaces: d(2, 30), c(3, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 2)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 30)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 50)
  assert_eq(lines_layout.get_whitespaces_total_height(), 50)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    30,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    50,
  )

  // Insert a line before line 1
  lines_layout.on_lines_inserted(1, 1)
  // whitespaces: d(3, 30), c(4, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 4)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 30)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 50)
  assert_eq(lines_layout.get_whitespaces_total_height(), 50)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    30,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    50,
  )

  // Delete line 4
  lines_layout.on_lines_deleted(4, 4)
  // whitespaces: d(3, 30), c(3, 20)
  assert_eq(lines_layout.get_whitespaces_count(), 2)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(0), 30)
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_height_for_whitespace_index(1), 20)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(0), 30)
  assert_eq(lines_layout.get_whitespaces_accumulated_height(1), 50)
  assert_eq(lines_layout.get_whitespaces_total_height(), 50)
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(1),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(2),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(3),
    0,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(4),
    50,
  )
  assert_eq(
    lines_layout.get_whitespace_accumulated_height_before_line_number(5),
    50,
  )
}

///|
test "LinesLayout findInsertionIndex" {
  let make_internal_whitespace = fn(
    after_line_numbers : Array[Int32],
    ordinal : Int32,
  ) -> Array[@view_layout.EditorWhitespace] {
    after_line_numbers.map(fn(after_line_number) {
      EditorWhitespace("", after_line_number, ordinal, 0, 0)
    })
  }
  let arr = make_internal_whitespace([], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 0)
  let arr = make_internal_whitespace([1], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  let arr = make_internal_whitespace([1, 3], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  let arr = make_internal_whitespace([1, 3, 5], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  let arr = make_internal_whitespace([1, 3, 5], 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  let arr = make_internal_whitespace([1, 3, 5, 7], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 7, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 8, 0), 4)
  let arr = make_internal_whitespace([1, 3, 5, 7, 9], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 7, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 8, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 9, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 10, 0), 5)
  let arr = make_internal_whitespace([1, 3, 5, 7, 9, 11], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 7, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 8, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 9, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 10, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 11, 0), 6)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 12, 0), 6)
  let arr = make_internal_whitespace([1, 3, 5, 7, 9, 11, 13], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 7, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 8, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 9, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 10, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 11, 0), 6)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 12, 0), 6)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 13, 0), 7)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 14, 0), 7)
  let arr = make_internal_whitespace([1, 3, 5, 7, 9, 11, 13, 15], 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 0, 0), 0)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 1, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 2, 0), 1)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 3, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 4, 0), 2)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 5, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 6, 0), 3)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 7, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 8, 0), 4)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 9, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 10, 0), 5)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 11, 0), 6)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 12, 0), 6)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 13, 0), 7)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 14, 0), 7)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 15, 0), 8)
  assert_eq(@view_layout.LinesLayout::find_insertion_index(arr, 16, 0), 8)
}

///|
test "LinesLayout changeWhitespaceAfterLineNumber & getFirstWhitespaceIndexAfterLineNumber" {
  let lines_layout = @view_layout.LinesLayout(100, 20, 0, 0)
  let a = insert_whitespace(lines_layout, 0, 0, 1, 0)
  let b = insert_whitespace(lines_layout, 7, 0, 1, 0)
  let c = insert_whitespace(lines_layout, 3, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(1), c) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(2), b) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 7)
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(1), 1) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(2), 1) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(3), 1) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(4), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(5), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(6), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(7), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(8), -1) // --

  // Do not really move a
  change_one_whitespace(lines_layout, a, 1, 1)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 1
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 1)
  assert_eq(lines_layout.get_id_for_whitespace_index(1), c) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(2), b) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 7)
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(1), 0) // a
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(2), 1) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(3), 1) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(4), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(5), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(6), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(7), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(8), -1) // --

  // Do not really move a
  change_one_whitespace(lines_layout, a, 2, 1)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 2
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 2)
  assert_eq(lines_layout.get_id_for_whitespace_index(1), c) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(2), b) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 7)
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(1), 0) // a
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(2), 0) // a
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(3), 1) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(4), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(5), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(6), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(7), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(8), -1) // --

  // Change a to conflict with c => a gets placed after c
  change_one_whitespace(lines_layout, a, 3, 1)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), c) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(1), a) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(2), b) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 7)
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(1), 0) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(2), 0) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(3), 0) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(4), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(5), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(6), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(7), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(8), -1) // --

  // Make a no-op
  change_one_whitespace(lines_layout, c, 3, 1)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), c) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(1), a) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(2), b) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 7)
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(1), 0) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(2), 0) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(3), 0) // c
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(4), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(5), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(6), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(7), 2) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(8), -1) // --

  // Conflict c with b => c gets placed after b
  change_one_whitespace(lines_layout, c, 7, 1)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 3
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(0), 3)
  assert_eq(lines_layout.get_id_for_whitespace_index(1), b) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(1), 7)
  assert_eq(lines_layout.get_id_for_whitespace_index(2), c) // 7
  assert_eq(lines_layout.get_after_line_number_for_whitespace_index(2), 7)
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(1), 0) // a
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(2), 0) // a
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(3), 0) // a
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(4), 1) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(5), 1) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(6), 1) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(7), 1) // b
  assert_eq(lines_layout.get_first_whitespace_index_after_line_number(8), -1) // --
}

///|
test "LinesLayout Bug" {
  let lines_layout = @view_layout.LinesLayout(100, 20, 0, 0)
  let a = insert_whitespace(lines_layout, 0, 0, 1, 0)
  let b = insert_whitespace(lines_layout, 7, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), b) // 7
  let c = insert_whitespace(lines_layout, 3, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), c) // 3
  assert_eq(lines_layout.get_id_for_whitespace_index(2), b) // 7
  let d = insert_whitespace(lines_layout, 2, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), d) // 2
  assert_eq(lines_layout.get_id_for_whitespace_index(2), c) // 3
  assert_eq(lines_layout.get_id_for_whitespace_index(3), b) // 7
  let e = insert_whitespace(lines_layout, 8, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), d) // 2
  assert_eq(lines_layout.get_id_for_whitespace_index(2), c) // 3
  assert_eq(lines_layout.get_id_for_whitespace_index(3), b) // 7
  assert_eq(lines_layout.get_id_for_whitespace_index(4), e) // 8
  let f = insert_whitespace(lines_layout, 11, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), d) // 2
  assert_eq(lines_layout.get_id_for_whitespace_index(2), c) // 3
  assert_eq(lines_layout.get_id_for_whitespace_index(3), b) // 7
  assert_eq(lines_layout.get_id_for_whitespace_index(4), e) // 8
  assert_eq(lines_layout.get_id_for_whitespace_index(5), f) // 11
  let g = insert_whitespace(lines_layout, 10, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), d) // 2
  assert_eq(lines_layout.get_id_for_whitespace_index(2), c) // 3
  assert_eq(lines_layout.get_id_for_whitespace_index(3), b) // 7
  assert_eq(lines_layout.get_id_for_whitespace_index(4), e) // 8
  assert_eq(lines_layout.get_id_for_whitespace_index(5), g) // 10
  assert_eq(lines_layout.get_id_for_whitespace_index(6), f) // 11
  let h = insert_whitespace(lines_layout, 0, 0, 1, 0)
  assert_eq(lines_layout.get_id_for_whitespace_index(0), a) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(1), h) // 0
  assert_eq(lines_layout.get_id_for_whitespace_index(2), d) // 2
  assert_eq(lines_layout.get_id_for_whitespace_index(3), c) // 3
  assert_eq(lines_layout.get_id_for_whitespace_index(4), b) // 7
  assert_eq(lines_layout.get_id_for_whitespace_index(5), e) // 8
  assert_eq(lines_layout.get_id_for_whitespace_index(6), g) // 10
  assert_eq(lines_layout.get_id_for_whitespace_index(7), f) // 11
}
