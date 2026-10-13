// Source-derived ViewZones layout matrices for Monaco
// `vs/editor/common/viewLayout/{linesLayout,viewLayout}.ts` at
// checked-in source.

///|
priv suberror WhitespaceCallbackFailure {
  WhitespaceCallbackFailure
}

///|
fn insert_then_fail(
  accessor : WhitespaceChangeAccessor,
) -> Unit raise WhitespaceCallbackFailure {
  accessor.insert_whitespace(1, 0, 7.0, 0.0) |> ignore
  raise WhitespaceCallbackFailure
}

///|
test "LinesLayout applies exact JavaScript ToInt32 to raw whitespace numbers" {
  let negative_zero = -0.0
  assert_true((1.0 / negative_zero).is_neg_inf())
  let cases : Array[(Double, Int32)] = [
    (0.0, 0),
    (negative_zero, 0),
    (1.9, 1),
    (-1.9, -1),
    (@double.not_a_number, 0),
    (@double.infinity, 0),
    (@double.neg_infinity, 0),
    (2147483647.9, 2147483647),
    (2147483648.0, -2147483648),
    (4294967295.0, -1),
    (4294967296.0, 0),
    (4294967297.0, 1),
    (-2147483649.0, 2147483647),
    (-4294967297.0, -1),
  ]
  let layout = LinesLayout(3, 10, 0, 0)
  let ids : Array[String] = []
  layout.change_whitespace(accessor => {
    for index, pair in cases {
      let (raw, _) = pair
      ids.push(accessor.insert_whitespace(0, index, raw, raw))
    }
  })
  |> ignore
  let whitespaces = layout.get_whitespaces()
  assert_eq(whitespaces.length(), cases.length())
  for index, pair in cases {
    let (_, expected) = pair
    assert_eq(whitespaces[index].id, ids[index])
    assert_eq(whitespaces[index].height, expected)
    assert_eq(whitespaces[index].min_width, expected)
  }
  layout.change_whitespace(accessor => {
    accessor.change_one_whitespace(ids[0], 0, 4294967297.0)
  })
  |> ignore
  assert_eq(layout.get_height_for_whitespace_index(0), 1)
}

///|
test "LinesLayout commits and clears its pending batch when callback raises" {
  let layout = LinesLayout(3, 10, 0, 0)
  let result = Some(layout.change_whitespace(insert_then_fail)) catch {
    WhitespaceCallbackFailure => None
  }
  assert_true(result is None)
  assert_eq(layout.get_whitespaces_count(), 1)
  assert_eq(layout.get_lines_total_height(), 37)
  let second_id = Ref("")
  assert_true(
    layout.change_whitespace(accessor => {
      second_id.val = accessor.insert_whitespace(2, 0, 3.0, 0.0)
    }),
  )
  assert_eq(layout.get_whitespaces_count(), 2)
  assert_eq(layout.get_id_for_whitespace_index(1), second_id.val)
  assert_eq(layout.get_lines_total_height(), 40)
}

///|
test "LinesLayout snapshots copy the array and alias whitespace objects" {
  let layout = LinesLayout(3, 10, 0, 0)
  layout.change_whitespace(accessor => {
    accessor.insert_whitespace(1, 0, 5.0, 0.0) |> ignore
  })
  |> ignore
  let snapshot = layout.get_whitespaces()
  snapshot.push(EditorWhitespace("detached", 0, 0, 1, 0))
  assert_eq(snapshot.length(), 2)
  assert_eq(layout.get_whitespaces_count(), 1)
  snapshot[0].height = 9
  assert_eq(layout.get_height_for_whitespace_index(0), 9)
}

///|
test "LinesLayout IDs keep per-instance counters and cross-instance uniqueness" {
  let first = LinesLayout(1, 10, 0, 0)
  let first_ids : Array[String] = []
  first.change_whitespace(accessor => {
    first_ids.push(accessor.insert_whitespace(0, 0, 1.0, 0.0))
    first_ids.push(accessor.insert_whitespace(0, 0, 1.0, 0.0))
  })
  |> ignore
  let second = LinesLayout(1, 10, 0, 0)
  let second_id = Ref("")
  second.change_whitespace(accessor => {
    second_id.val = accessor.insert_whitespace(0, 0, 1.0, 0.0)
  })
  |> ignore
  assert_true(first_ids[0].has_suffix("1"))
  assert_true(first_ids[1].has_suffix("2"))
  assert_true(second_id.val.has_suffix("1"))
  // `strings.singleLetterHash(++INSTANCE_COUNT)` contributes exactly one
  // source-owned namespace character before each per-instance counter.
  assert_eq(first_ids[0].length(), 2)
  assert_eq(first_ids[1].length(), 2)
  assert_eq(second_id.val.length(), 2)
  assert_true(first_ids[0] != first_ids[1])
  assert_true(first_ids[0] != second_id.val)
  assert_true(first_ids[1] != second_id.val)
}

///|
test "ViewLayout incremental whitespace facade updates height and preserves IDs" {
  let layout = ViewLayout(line_height=10, line_count=3)
  assert_false(layout.change_whitespace(_ => ()))
  assert_eq(layout.get_content_height(), 30.0)
  let id = Ref("")
  assert_true(
    layout.change_whitespace(accessor => {
      id.val = accessor.insert_whitespace(1, 0, 5.0, 12.0)
    }),
  )
  assert_eq(layout.get_content_height(), 35.0)
  assert_eq(layout.get_whitespaces()[0].id, id.val)
  assert_true(
    layout.change_whitespace(accessor => {
      accessor.change_one_whitespace(id.val, 2, 7.0)
    }),
  )
  assert_eq(layout.get_content_height(), 37.0)
  let before_flush = layout.get_whitespaces()[0]
  layout.on_flushed(5)
  layout.on_height_maybe_changed() |> ignore
  let after_flush = layout.get_whitespaces()[0]
  assert_eq(after_flush.id, before_flush.id)
  assert_eq(after_flush.after_line_number, 2)
  assert_eq(after_flush.height, 7)
  assert_eq(layout.get_content_height(), 57.0)
  assert_true(
    layout.change_whitespace(accessor => accessor.remove_whitespace(id.val)),
  )
  assert_eq(layout.get_whitespaces().length(), 0)
  assert_eq(layout.get_content_height(), 50.0)
}

///|
test "retained whitespace min width updates the horizontal extent transactionally" {
  let layout = ViewLayout(line_height=10, line_count=3)
  layout.set_viewport_size(width=100.0, height=100.0) |> ignore
  layout.set_max_line_width(20.0) |> ignore
  let id = Ref("")
  layout.change_whitespace(accessor => {
    id.val = accessor.insert_whitespace(1, 0, 10.0, 0.0)
  })
  |> ignore
  assert_eq(layout.get_content_width(), 34.0)
  layout.change_whitespace(accessor => {
    accessor.change_one_whitespace(id.val, 1, 10.0, new_min_width=250.0)
  })
  |> ignore
  assert_eq(layout.get_whitespaces()[0].min_width, 250)
  assert_eq(layout.get_content_width(), 250.0)
  layout.change_whitespace(accessor => {
    accessor.change_one_whitespace(id.val, 1, 10.0, new_min_width=0.0)
  })
  |> ignore
  assert_eq(layout.get_content_width(), 34.0)
}

///|
test "ViewLayout exposes ID whitespace viewport and explicit scrollTop data" {
  let layout = ViewLayout(line_height=10, line_count=20)
  layout.set_viewport_size(width=100.0, height=25.0) |> ignore
  let ids : Array[String] = []
  layout.change_whitespace(accessor => {
    ids.push(accessor.insert_whitespace(0, 0, 5.0, 0.0))
    ids.push(accessor.insert_whitespace(2, 0, 7.0, 0.0))
    ids.push(accessor.insert_whitespace(8, 0, 11.0, 0.0))
  })
  |> ignore
  let first_band = layout.get_whitespace_viewport_data()
  assert_eq(first_band.length(), 1)
  assert_eq(first_band[0].id, ids[0])
  assert_eq(first_band[0].after_line_number, 0)
  assert_eq(first_band[0].vertical_offset, 0)
  assert_eq(first_band[0].height, 5)
  layout.set_viewport_size(width=100.0, height=26.0) |> ignore
  let wider_band = layout.get_whitespace_viewport_data()
  assert_eq(wider_band.length(), 2)
  assert_eq(wider_band[1].id, ids[1])
  assert_eq(wider_band[1].vertical_offset, 25)
  let all = layout.get_whitespaces()
  assert_eq(all.length(), 3)
  assert_eq(all[2].id, ids[2])
  layout.scroll_to(scroll_top=0.0) |> ignore
  assert_true(
    layout.get_lines_viewport_data_at_scroll_top(-100.0) ==
    layout.get_lines_viewport_data(),
  )
  layout.scroll_to(scroll_top=99999.0) |> ignore
  assert_true(
    layout.get_lines_viewport_data_at_scroll_top(99999.0) ==
    layout.get_lines_viewport_data(),
  )
}

///|
fn saved_state_with_zones(
  zone_count : Int32,
) -> (SavedScrollState, Double, Double) {
  let layout = ViewLayout(line_height=10, line_count=20, smooth_scrolling=true)
  layout.set_viewport_size(width=100.0, height=20.0) |> ignore
  if zone_count > 0 {
    layout.change_whitespace(accessor => {
      accessor.insert_whitespace(0, 0, 5.0, 0.0) |> ignore
      if zone_count > 1 {
        accessor.insert_whitespace(2, 0, 7.0, 0.0) |> ignore
        // This zone is below the first visible line and must not be subtracted.
        accessor.insert_whitespace(8, 0, 11.0, 0.0) |> ignore
      }
    })
    |> ignore
  }
  // Keep the current position at zero while the smooth-scroll target is 42.
  // `saveState` must choose `futurePosition`, not the current viewport.
  layout.scroll_to_smooth(scroll_top=42.0)
  let current_scroll_top = layout.position().scroll_top
  let future_scroll_top = layout.future_position().scroll_top
  let state = layout.save_state()
  layout.dispose()
  (state, current_scroll_top, future_scroll_top)
}

///|
test "ViewLayout saveState subtracts only whitespaces above the future viewport" {
  let (none, current, future) = saved_state_with_zones(0)
  assert_eq(current, 0.0)
  assert_eq(future, 42.0)
  assert_eq(none.scroll_top, 42.0)
  assert_eq(none.scroll_top_without_view_zones, 42.0)
  let (one, current, future) = saved_state_with_zones(1)
  assert_eq(current, 0.0)
  assert_eq(future, 42.0)
  assert_eq(one.scroll_top, 42.0)
  assert_eq(one.scroll_top_without_view_zones, 37.0)
  let (many, current, future) = saved_state_with_zones(2)
  assert_eq(current, 0.0)
  assert_eq(future, 42.0)
  assert_eq(many.scroll_top, 42.0)
  assert_eq(many.scroll_top_without_view_zones, 30.0)
}
