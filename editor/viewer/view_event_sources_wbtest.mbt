///|
fn estimated_font_info(options : ViewerOptions) -> @config.FontInfo {
  @config.FontInfo::estimated(options.bare_font_info(pixel_ratio=1.0))
}

///|
/// Builds the two immutable owner snapshots while retaining the original
/// branch tests' explicit LayoutInfo comparison input.
fn test_configuration_changed_event(
  previous_options : ViewerOptions,
  current_options : ViewerOptions,
  previous_font_info : @config.FontInfo,
  current_font_info : @config.FontInfo,
  previous_soft_wrap_column : Int,
  current_soft_wrap_column : Int,
  layout_info_changed~ : Bool,
) -> @view.ViewConfigurationChangedEvent? {
  let previous = EditorConfigurationState(previous_options, previous_font_info)
  previous.commit_soft_wrap_column(previous_soft_wrap_column) |> ignore
  let previous_snapshot = previous.event_snapshot()
  let current = EditorConfigurationState(current_options, current_font_info)
  current.commit_soft_wrap_column(current_soft_wrap_column) |> ignore
  let current_snapshot = current.event_snapshot()
  let current_snapshot = if layout_info_changed {
    {
      ..current_snapshot,
      layout: {
        ..previous_snapshot.layout,
        content_width: previous_snapshot.layout.content_width + 1.0,
      },
    }
  } else {
    { ..current_snapshot, layout: previous_snapshot.layout }
  }
  previous_snapshot.changed_event(current_snapshot)
}

///|
/// These white-box adapters keep source-fact assertions precise without
/// widening the consolidated view package's production API. The event payload
/// fields remain private; JS white-box tests inspect their emitted runtime
/// representation directly.
extern "js" fn test_view_configuration_changed_options_length(
  event : @view.ViewConfigurationChangedEvent,
) -> Int = "(event) => event.changed_options.length"

///|
extern "js" fn test_view_configuration_has_changed(
  event : @view.ViewConfigurationChangedEvent,
  option : @view.ViewConfigurationOption,
) -> Bool = "(event, option) => event.changed_options.includes(option)"

///|
extern "js" fn test_view_tokens_range_count(
  event : @view.ViewTokensChangedEvent,
) -> Int = "(event) => event.ranges.length"

///|
extern "js" fn test_view_tokens_range_from(
  event : @view.ViewTokensChangedEvent,
  index : Int,
) -> Int = "(event, index) => event.ranges[index].from_line_number"

///|
extern "js" fn test_view_tokens_range_to(
  event : @view.ViewTokensChangedEvent,
  index : Int,
) -> Int = "(event, index) => event.ranges[index].to_line_number"

///|
extern "js" fn test_view_scroll_width(
  event : @view.ViewScrollChangedEvent,
) -> Double = "(event) => event.scroll_width"

///|
extern "js" fn test_view_scroll_flags(
  event : @view.ViewScrollChangedEvent,
) -> FixedArray[Bool] =
  #| (event) => [
  #|   event.scroll_width_changed,
  #|   event.scroll_left_changed,
  #|   event.scroll_height_changed,
  #|   event.scroll_top_changed,
  #| ]

///|
extern "js" fn test_view_cursor_selections(
  event : @view.ViewCursorStateChangedEvent,
) -> FixedArray[@core.Selection] = "(event) => event.selections"

///|
test "view configuration source preserves independent paint axes and no-op" {
  let previous = ViewerOptions::default()
  let font_info = estimated_font_info(previous)
  assert_true(
    test_configuration_changed_event(
      previous,
      previous,
      font_info,
      font_info,
      0,
      0,
      layout_info_changed=false,
    )
    is None,
  )
  let current = {
    ..previous,
    render_whitespace: All,
    render_control_characters: false,
    render_line_highlight: Gutter,
    render_line_highlight_only_when_focus: true,
    render_validation_decorations: Off,
  }
  let event = test_configuration_changed_event(
    previous,
    current,
    font_info,
    font_info,
    0,
    0,
    layout_info_changed=false,
  ).unwrap()
  assert_eq(test_view_configuration_changed_options_length(event), 5)
  assert_true(test_view_configuration_has_changed(event, RenderWhitespace))
  assert_true(
    test_view_configuration_has_changed(event, RenderControlCharacters),
  )
  assert_true(test_view_configuration_has_changed(event, RenderLineHighlight))
  assert_true(
    test_view_configuration_has_changed(event, RenderLineHighlightOnlyWhenFocus),
  )
  assert_true(
    test_view_configuration_has_changed(event, RenderValidationDecorations),
  )
  assert_false(test_view_configuration_has_changed(event, LayoutInfo))
  assert_false(test_view_configuration_has_changed(event, FontInfo))
  assert_false(test_view_configuration_has_changed(event, WrappingInfo))
  let reversed = test_configuration_changed_event(
    current,
    previous,
    font_info,
    font_info,
    0,
    0,
    layout_info_changed=false,
  ).unwrap()
  assert_eq(test_view_configuration_changed_options_length(reversed), 5)
  assert_true(test_view_configuration_has_changed(reversed, RenderWhitespace))
}

///|
test "update_options complete-snapshot no-op skips layout invalidation" {
  let viewer = Viewer::Viewer()
  assert_false(viewer.configuration.measure_requested)
  viewer.update_options(viewer.get_options())
  assert_false(viewer.configuration.measure_requested)
  viewer.dispose()
}

///|
test "view configuration source separates layout font line-height and wrapping" {
  let previous = ViewerOptions::default()
  let font_info = estimated_font_info(previous)
  let letter_spaced = {
    ..font_info,
    letter_spacing: font_info.letter_spacing + 1.0,
  }
  let font_event = test_configuration_changed_event(
    previous,
    previous,
    font_info,
    letter_spaced,
    0,
    0,
    layout_info_changed=false,
  ).unwrap()
  assert_eq(test_view_configuration_changed_options_length(font_event), 1)
  assert_true(test_view_configuration_has_changed(font_event, FontInfo))
  assert_false(test_view_configuration_has_changed(font_event, LineHeight))

  let taller = { ..font_info, line_height: font_info.line_height + 1 }
  let height_event = test_configuration_changed_event(
    previous,
    previous,
    font_info,
    taller,
    0,
    0,
    layout_info_changed=true,
  ).unwrap()
  assert_true(test_view_configuration_has_changed(height_event, LayoutInfo))
  assert_true(test_view_configuration_has_changed(height_event, FontInfo))
  assert_true(test_view_configuration_has_changed(height_event, LineHeight))

  let tabbed = { ..previous, tab_size: previous.tab_size + 1 }
  let wrapping_event = test_configuration_changed_event(
    previous,
    tabbed,
    font_info,
    font_info,
    0,
    0,
    layout_info_changed=false,
  ).unwrap()
  assert_eq(test_view_configuration_changed_options_length(wrapping_event), 1)
  assert_true(test_view_configuration_has_changed(wrapping_event, WrappingInfo))
}

///|
test "decimal digit bands and compensated layout lanes stay independently visible" {
  assert_eq(digit_count(0), 1)
  assert_eq(digit_count(1), 1)
  assert_eq(digit_count(9), 1)
  assert_eq(digit_count(10), 2)
  assert_eq(digit_count(99), 2)
  assert_eq(digit_count(100), 3)

  let initial_options = ViewerOptions(
    line_numbers_min_chars=5,
    line_decorations_width=10,
    folding=false,
  )
  let initial_font_info = estimated_font_info(initial_options)
  let configuration = EditorConfigurationState(initial_options, {
    ..initial_font_info,
    max_digit_width: 10.0,
  })
  let before = configuration.snapshot().layout_identity(3, 3)
  configuration.replace_options(
    ViewerOptions(
      line_numbers_min_chars=4,
      line_decorations_width=20,
      folding=false,
    ),
  )
  |> ignore
  let after = configuration.snapshot().layout_identity(3, 3)
  assert_eq(before.content_left, after.content_left)
  assert_true(before.line_numbers_width != after.line_numbers_width)
  assert_true(before.decorations_width != after.decorations_width)
  assert_true(before != after)
}

///|
test "set_value synchronizes a decimal line-count band into layout identity" {
  let viewer = Viewer::Viewer(
    options=ViewerOptions(line_numbers_min_chars=1, folding=false),
  )
  let nine = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/nine-lines.txt",
    ),
    "nine-lines.txt",
    "plaintext",
    1,
    "nine",
    ["1", "2", "3", "4", "5", "6", "7", "8", "9"].join("\n"),
  )
  viewer.set_model(Some(nine))
  assert_eq(viewer.configuration.model_line_count, 9)
  assert_eq(viewer.configuration.view_line_count, 9)
  let before = viewer.configuration.event_snapshot().layout
  viewer.set_value(
    ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"].join("\n"),
  )
  assert_eq(viewer.configuration.model_line_count, 10)
  assert_eq(viewer.configuration.view_line_count, 10)
  let after = viewer.configuration.event_snapshot().layout
  assert_true(after.line_numbers_width > before.line_numbers_width)
  assert_true(after != before)
  viewer.dispose()
  nine.dispose()
}

///|
test "wrapped view-line growth does not widen the model line-number band" {
  let text = [
    "abcdefghij", "abcdefghij", "abcdefghij", "abcdefghij", "abcdefghij", "abcdefghij",
    "abcdefghij", "abcdefghij", "abcdefghij",
  ].join("\n")
  with_test_viewer(
    text,
    viewer => {
      let configuration = viewer.configuration
      let before = configuration
        .snapshot()
        .gutter_width(configuration.model_line_count)
      assert_eq(configuration.model_line_count, 9)
      assert_eq(configuration.view_line_count, 9)
      viewer.test_set_soft_wrap_column(4)
      assert_eq(configuration.model_line_count, 9)
      assert_true(configuration.view_line_count >= 18)
      let snapshot = configuration.snapshot()
      assert_true(
        snapshot.gutter_width(configuration.model_line_count) == before,
      )
      assert_true(
        snapshot.line_numbers_width(configuration.view_line_count) >
        snapshot.line_numbers_width(configuration.model_line_count),
      )
    },
    options=ViewerOptions(
      soft_wrap=true,
      line_numbers_min_chars=1,
      folding=false,
      font_size=12,
      line_height=18,
    ),
  )
}

///|
test "token source preserves inclusive ranges in producer order" {
  let event = view_tokens_changed_event([(2, 4), (9, 9)])
  assert_eq(test_view_tokens_range_count(event), 2)
  assert_eq(test_view_tokens_range_from(event, 0), 2)
  assert_eq(test_view_tokens_range_to(event, 0), 4)
  assert_eq(test_view_tokens_range_from(event, 1), 9)
  assert_eq(test_view_tokens_range_to(event, 1), 9)
}

///|
test "scroll source copies consumed width and independent flags" {
  let previous = @view_layout.ScrollState(
    force_integer_values=false,
    100.0,
    500.0,
    10.0,
    200.0,
    800.0,
    20.0,
  )
  let current = @view_layout.ScrollState(
    force_integer_values=false,
    100.0,
    550.0,
    30.0,
    200.0,
    900.0,
    40.0,
  )
  let event = view_scroll_changed_event(
    current.create_scroll_event(previous, false),
  )
  assert_eq(test_view_scroll_width(event), 550.0)
  let event_flags = test_view_scroll_flags(event)
  assert_true(event_flags[0])
  assert_true(event_flags[1])
  assert_true(event_flags[2])
  assert_true(event_flags[3])

  let left_only = @view_layout.ScrollState(
    force_integer_values=false,
    100.0,
    500.0,
    30.0,
    200.0,
    800.0,
    20.0,
  )
  let left_event = view_scroll_changed_event(
    left_only.create_scroll_event(previous, false),
  )
  let left_flags = test_view_scroll_flags(left_event)
  assert_true(left_flags[1])
  assert_false(left_flags[0])
  assert_false(left_flags[2])
  assert_false(left_flags[3])
}

///|
test "cursor source carries the committed view selection" {
  with_test_viewer("alpha", viewer => {
    let position = @base_common.Position::Position(1, 3)
    viewer.set_position(position, source="source-fact-test")
    let view_model = viewer.test_view_model()
    let event = view_cursor_state_changed_event(view_model)
    let selections = test_view_cursor_selections(event)
    assert_eq(selections.length(), 1)
    assert_true(selections[0] == view_model.cursor.get_view_selection())
  })
}

///|
test "validation option rotates the headless decoration provider" {
  with_test_viewer("alpha", viewer => {
    let model = viewer.get_model().unwrap()
    let _ = model.delta_decorations([], [
      {
        range: Range(1, 1, 1, 3),
        options: ModelDecorationOptions("squiggly-error"),
      },
    ])
    let view_model = viewer.test_view_model()
    let view_range = @base_common.Range::Range(1, 1, 1, 6)
    assert_eq(
      view_model.decorations().get_decorations_viewport_data(view_range).decorations.length(),
      1,
    )
    viewer.update_options({
      ..viewer.get_options(),
      render_validation_decorations: Off,
    })
    assert_eq(
      view_model.decorations().get_decorations_viewport_data(view_range).decorations.length(),
      0,
    )
  })
}

///|
test "view-zone callback is skipped without a real model view" {
  let viewer = Viewer::Viewer()
  let called = Ref(false)
  viewer.change_view_zones(_ => called.val = true)
  assert_false(viewer.configuration.measure_requested)
  assert_false(called.val)
  viewer.dispose()
  with_test_viewer("alpha", headless => {
    let measure_requested_before = headless.configuration.measure_requested
    headless.change_view_zones(_ => called.val = true)
    assert_false(called.val)
    assert_eq(
      headless.configuration.measure_requested,
      measure_requested_before,
    )
  })
}
