// Tests for the hidden-areas (folding) machinery: the projected line
// collection's `setHiddenAreas` (`viewModelLines.ts:174`) and the view
// model's per-source merge (`viewModelImpl.ts:592`).

///|
fn hidden_test_model() -> @view_model.ViewModel {
  ViewModel(
    // 8 lines, distinct content so view-line assertions read clearly.
    plain_text_model(
      (
        #|line1
        #|line2
        #|line3
        #|line4
        #|line5
        #|line6
        #|line7
        #|line8
      ),
    ),
  )
}

///|
test "hidden-area mapping phase precedes layout flush and recovery scroll" {
  let view_model = hidden_test_model()
  let layout = view_model.view_layout
  layout.set_viewport_size(width=400.0, height=18.0) |> ignore
  let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
  layout.scroll_to(scroll_top=old_top) |> ignore

  let order : Array[String] = []
  let scroll_listener = layout.on_did_scroll(_change => order.push("scroll"))
  defer scroll_listener.dispose()
  assert_true(
    view_model.set_hidden_areas([Range(2, 1, 3, 1)], on_line_mapping_changed=reproject_cursor => {
      order.push("mapping")
      reproject_cursor()
      order.push("cursor")
    }),
  )
  // `onFlushed` first clamps the old scroll position to the shorter layout;
  // stable-viewport recovery then restores the same model line/delta. Both
  // Scroll changes must follow the mapping/cursor phase in the collector.
  assert_true(order == ["mapping", "cursor", "scroll", "scroll"])
  assert_eq(
    layout.get_current_scroll_top(),
    layout.get_vertical_offset_for_line_number(2) + 7.0,
  )

  // The unchanged contribution returns before the owner is asked to open an
  // event batch, matching the source's VI-008 → VI-010 control flow.
  let mut batch_calls = 0
  assert_false(
    view_model.set_hidden_areas([Range(2, 1, 3, 1)], with_event_batch=mutation => {
      batch_calls += 1
      mutation()
    }),
  )
  assert_eq(batch_calls, 0)
}

///|
test "set_hidden_areas removes lines from the view axis" {
  let view_model = hidden_test_model()
  assert_eq(view_model.line_count(), 8)
  let changed = view_model.set_hidden_areas([Range(3, 1, 5, 1)])
  assert_true(changed)
  assert_eq(view_model.line_count(), 5)
  let lines = view_model.lines()
  assert_eq(lines.get_view_line_content(2), "line2")
  assert_eq(lines.get_view_line_content(3), "line6")
  assert_eq(lines.get_view_line_content(5), "line8")
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 3,
      #|    start_column: 1,
      #|    end_line_number: 5,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
}

///|
test "set_hidden_areas is idempotent and unhides on empty" {
  let view_model = hidden_test_model()
  assert_true(view_model.set_hidden_areas([Range(2, 1, 3, 1)]))
  // Same ranges again: no change.
  assert_false(view_model.set_hidden_areas([Range(2, 1, 3, 1)]))
  assert_eq(view_model.line_count(), 6)
  // Clearing restores every line.
  assert_true(view_model.set_hidden_areas([]))
  assert_eq(view_model.line_count(), 8)
  assert_eq(view_model.get_hidden_areas().length(), 0)
}

///|
test "overlapping and touching ranges normalize into one hidden area" {
  let view_model = hidden_test_model()
  // [2..3] and [4..5] touch; [5..6] overlaps — all merge to [2..6].
  assert_true(
    view_model.set_hidden_areas([
      Range(4, 1, 5, 1),
      Range(2, 1, 3, 1),
      Range(5, 1, 6, 1),
    ]),
  )
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 2,
      #|    start_column: 1,
      #|    end_line_number: 6,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  assert_eq(view_model.line_count(), 3)
}

///|
test "sources merge independently and clear independently" {
  let view_model = hidden_test_model()
  assert_true(
    view_model.set_hidden_areas([Range(2, 1, 3, 1)], source="folding"),
  )
  assert_true(view_model.set_hidden_areas([Range(6, 1, 7, 1)], source="other"))
  assert_eq(view_model.line_count(), 4)
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 2,
      #|    start_column: 1,
      #|    end_line_number: 3,
      #|    end_column: 1,
      #|  },
      #|  {
      #|    start_line_number: 6,
      #|    start_column: 1,
      #|    end_line_number: 7,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  // Clearing one source keeps the other's lines hidden.
  assert_true(view_model.set_hidden_areas([], source="folding"))
  assert_eq(view_model.line_count(), 6)
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 6,
      #|    start_column: 1,
      #|    end_line_number: 7,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
}

///|
test "same String hidden source replaces its prior contribution" {
  let view_model = hidden_test_model()
  assert_true(
    view_model.set_hidden_areas([Range(2, 1, 3, 1)], source="folding"),
  )
  assert_true(
    view_model.set_hidden_areas([Range(6, 1, 6, 1)], source="folding"),
  )
  assert_true(view_model.get_hidden_areas() == [Range(6, 1, 6, 1)])
  assert_eq(view_model.line_count(), 7)
  // The source contribution and merged-array caches both short-circuit.
  assert_false(
    view_model.set_hidden_areas([Range(6, 1, 6, 1)], source="folding"),
  )
  assert_false(
    view_model.set_hidden_areas(
      [Range(6, 1, 6, 1)],
      source="folding",
      force_update=true,
    ),
  )
}

///|
test "hiding every line reveals everything" {
  let view_model = hidden_test_model()
  assert_true(view_model.set_hidden_areas([Range(1, 1, 8, 1)]))
  // Cannot have everything be hidden => reveal everything!
  assert_eq(view_model.line_count(), 8)
  assert_eq(view_model.get_hidden_areas().length(), 0)
}

///|
test "model positions inside a hidden area convert to the nearest visible view line" {
  let view_model = hidden_test_model()
  assert_true(view_model.set_hidden_areas([Range(3, 1, 5, 1)]))
  let lines = view_model.lines()
  // A position on hidden line 4 walks up to visible line 2's end.
  let up = lines.convert_model_position_to_view_position(4, 1)
  debug_inspect(
    up,
    content=(
      #|{ line_number: 2, column: 6 }
    ),
  )
  // ... or down to line 6's start with `below_hidden_ranges`.
  let down = lines.convert_model_position_to_view_position(
    4,
    1,
    below_hidden_ranges=true,
  )
  debug_inspect(
    down,
    content=(
      #|{ line_number: 3, column: 1 }
    ),
  )
  // Visible lines stay bijective: model line 6 is view line 3.
  let visible = lines.convert_model_position_to_view_position(6, 2)
  debug_inspect(
    visible,
    content=(
      #|{ line_number: 3, column: 2 }
    ),
  )
  assert_eq(lines.convert_view_position_to_model_position(3, 2).line_number, 6)
  // Visibility probes.
  assert_false(lines.model_position_is_visible(4))
  assert_true(lines.model_position_is_visible(6))
  assert_false(view_model.model_position_is_visible(Position(4, 1)))
  let converter = view_model.coordinates_converter()
  assert_false(converter.model_position_is_visible(Position(0, 1)))
  assert_false(converter.model_position_is_visible(Position(4, 999)))
  assert_true(converter.model_position_is_visible(Position(6, 999)))
  assert_false(converter.model_position_is_visible(Position(9, 1)))
}

///|
test "model position conversion validates bounds and forwards allow-zero" {
  let view_model = hidden_test_model()
  assert_true(
    view_model.validate_model_position(Position(-5, 999)) == Position(1, 1),
  )
  assert_true(
    view_model.validate_model_position(Position(99, 999)) == Position(8, 6),
  )
  assert_true(
    view_model.model_position_to_view_position(Position(99, 999)) ==
    Position(8, 6),
  )

  assert_true(view_model.set_hidden_areas([Range(1, 1, 2, 1)]))
  assert_true(
    view_model.model_position_to_view_position(
      Position(1, 999),
      allow_zero_line_number=true,
    ) ==
    Position(0, 1),
  )
  assert_true(
    view_model.model_position_to_view_position(Position(1, 999)) ==
    Position(1, 1),
  )
}

///|
test "stable viewport preserves the first model line and intra-line delta" {
  let view_model = hidden_test_model()
  let layout = view_model.view_layout
  layout.set_viewport_size(width=400.0, height=18.0) |> ignore
  let line_height = layout.line_height().to_double()
  let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
  layout.scroll_to(scroll_top=old_top) |> ignore

  assert_true(view_model.set_hidden_areas([Range(2, 1, 3, 1)]))
  let expected = layout.get_vertical_offset_for_line_number(2) + 7.0
  assert_eq(layout.get_current_scroll_top(), expected)
  let top_view_line = layout.line_at_vertical_offset(
    layout.get_current_scroll_top(),
  )
  assert_eq(
    view_model.lines().convert_view_position_to_model_position(top_view_line, 1).line_number,
    4,
  )
  assert_true(line_height > 0.0)
}

///|
test "stable viewport skips recovery at top or when its first line is hidden" {
  let at_top = hidden_test_model()
  at_top.view_layout.set_viewport_size(width=400.0, height=18.0) |> ignore
  assert_eq(at_top.view_layout.get_current_scroll_top(), 0.0)
  assert_true(at_top.set_hidden_areas([Range(2, 1, 2, 1)]))
  assert_eq(at_top.view_layout.get_current_scroll_top(), 0.0)

  let first_hidden = hidden_test_model()
  let layout = first_hidden.view_layout
  layout.set_viewport_size(width=400.0, height=18.0) |> ignore
  let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
  layout.scroll_to(scroll_top=old_top) |> ignore
  assert_true(first_hidden.set_hidden_areas([Range(4, 1, 4, 1)]))
  assert_eq(layout.get_current_scroll_top(), old_top)
}

///|
test "to_model_visible_ranges splits the viewport around hidden areas" {
  let view_model = hidden_test_model()
  assert_true(view_model.set_hidden_areas([Range(3, 1, 5, 1)]))
  // All 5 remaining view lines: model lines 1-2 and 6-8.
  let ranges = view_model.to_model_visible_ranges(Range(1, 1, 5, 6))
  debug_inspect(
    ranges,
    content=(
      #|[
      #|  {
      #|    start_line_number: 1,
      #|    start_column: 1,
      #|    end_line_number: 2,
      #|    end_column: 6,
      #|  },
      #|  {
      #|    start_line_number: 6,
      #|    start_column: 1,
      #|    end_line_number: 8,
      #|    end_column: 6,
      #|  },
      #|]
    ),
  )
}

///|
test "hidden areas survive a wrapping reflow" {
  let model = plain_text_model(
    (
      #|line1
      #|line2
      #|line3 is much longer than the wrap column
      #|line4
    ),
  )
  let view_model = @view_model.ViewModel::with_options(
    model,
    @view_model.ViewModelOptions::no_wrap(),
  )
  assert_true(view_model.set_hidden_areas([Range(2, 1, 2, 1)]))
  assert_eq(view_model.line_count(), 3)
  // Reflow to a narrow wrap column: line 3 wraps, line 2 stays hidden.
  assert_true(
    view_model.on_configuration_changed(
      @view_model.ViewModelOptions::soft_wrap(10),
    ),
  )
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 2,
      #|    start_column: 1,
      #|    end_line_number: 2,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  let lines = view_model.lines()
  assert_eq(lines.get_view_line_content(1), "line1")
  // View line 2 is the first segment of wrapped model line 3.
  assert_eq(lines.convert_view_position_to_model_position(2, 1).line_number, 3)
  assert_false(lines.model_position_is_visible(2))
}
