///|
fn test_configuration_state(
  options~ : CodeEditorOptions = CodeEditorOptions::default(),
) -> EditorConfigurationState {
  EditorConfigurationState(
    options,
    @config.FontInfo::estimated(options.bare_font_info(pixel_ratio=1.0)),
  )
}

///|
test "configuration owner initializes one coherent empty identity" {
  let state = test_configuration_state()
  let snapshot = state.snapshot()
  assert_eq(snapshot.content_width, 0.0)
  assert_eq(snapshot.height, 0.0)
  assert_eq(snapshot.soft_wrap_column, 0)
  assert_eq(state.model_line_count, 0)
  assert_eq(state.view_line_count, 0)
  assert_false(state.consume_measure_request())
  state.request_measure()
  assert_true(state.consume_measure_request())
  assert_false(state.consume_measure_request())
}

///|
test "configuration owner replaces only changed complete option snapshots" {
  let state = test_configuration_state()
  assert_true(state.replace_options(CodeEditorOptions::default()) is None)
  let changed = CodeEditorOptions(soft_wrap=true, tab_size=7)
  assert_true(state.replace_options(changed) is Some(_))
  assert_true(state.snapshot().options == changed)
}

///|
test "measured size and font facts derive one wrap-column transition" {
  let options = CodeEditorOptions(soft_wrap=true, font_size=12, line_height=18)
  let state = test_configuration_state(options~)
  state.commit_measured_size(72.0, 180.0)
  assert_true(state.recompute_soft_wrap_column())
  let measured = state.snapshot()
  assert_eq(
    measured.soft_wrap_column,
    options.soft_wrap_column_for_content_width(
      72.0,
      measured.font_info.typical_halfwidth_character_width,
    ),
  )
  assert_false(state.recompute_soft_wrap_column())
  state.commit_measured_size(-1.0, 90.0)
  assert_true(state.recompute_soft_wrap_column())
  assert_eq(state.snapshot().content_width, 0.0)
  assert_eq(state.snapshot().soft_wrap_column, 0)
}

///|
test "digit-band transition preserves outer width and reset stays model-scoped" {
  let options = CodeEditorOptions(line_numbers_min_chars=1, folding=false)
  let state = test_configuration_state(options~)
  let initial_font = state.snapshot().font_info
  state.commit_font_info({ ..initial_font, max_digit_width: 10.0, }) |> ignore
  state.commit_measured_size(360.0, 180.0)
  state.set_line_counts(9, 9)
  state.request_measure()
  let before = state.snapshot()
  let outer_width = before.gutter_width(9) + before.content_width
  assert_true(state.adjust_content_width_for_model_line_count(10))
  let after = state.snapshot()
  assert_eq(after.gutter_width(10) + after.content_width, outer_width)
  state.set_line_counts(10, 10)
  assert_false(state.adjust_content_width_for_model_line_count(11))
  let retained = state.snapshot()
  state.reset_model_line_counts()
  assert_eq(state.model_line_count, 0)
  assert_eq(state.view_line_count, 0)
  assert_true(state.snapshot().options == retained.options)
  assert_eq(state.snapshot().width, retained.width)
  assert_eq(
    state.snapshot().content_width,
    retained.width - state.snapshot().gutter_width(0),
  )
  assert_true(state.measure_requested)
}

///|
test "default five-slot line-number band widens at 99999 to 100000" {
  let state = test_configuration_state(
    options=CodeEditorOptions(line_numbers_min_chars=5, folding=false),
  )
  let initial_font = state.snapshot().font_info
  state.commit_font_info({ ..initial_font, max_digit_width: 10.0, }) |> ignore
  state.commit_measured_size(800.0, 180.0)
  state.set_line_counts(99999, 99999)
  let before = state.snapshot()
  let outer_width = before.gutter_width(99999) + before.content_width
  assert_eq(before.line_numbers_width(99999), 50.0)

  assert_true(state.adjust_content_width_for_model_line_count(100000))
  let after = state.snapshot()
  assert_eq(after.line_numbers_width(100000), 60.0)
  assert_eq(after.gutter_width(100000) + after.content_width, outer_width)
}

///|
test "event identity observes committed layout counts" {
  let state = test_configuration_state()
  let previous = state.event_snapshot()
  state.set_line_counts(10, 10)
  let event = previous.changed_event(state.event_snapshot()).unwrap()
  assert_true(test_view_configuration_has_changed(event, LayoutInfo))
}
