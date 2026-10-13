// Source-derived retained-line invalidator matrix for pinned
// `viewLine.ts:55-100,109-114`.

///|
fn retained_line_test_input(
  render_whitespace : @editor_api.RenderWhitespace,
  space_width~ : Double = 7.2,
  middot_width~ : Double = 7.2,
  wsmiddot_width~ : Double = 7.2,
) -> @view_layout.RenderLineInput {
  @view_layout.RenderLineInput::from_view_line(
    {
      min_column: 1,
      max_column: 6,
      content: "alpha",
      continues_with_wrapped_line: false,
      contains_rtl: false,
      is_basic_ascii: true,
      tokens: [],
      inline_decorations: [],
      tab_size: 2,
      start_visible_column: 0,
      text_direction: LTR,
      has_variable_fonts: false,
    },
    space_width~,
    middot_width~,
    wsmiddot_width~,
    render_whitespace~,
  )
}

///|
test "retained ViewLine consumes sticky content token decoration and option invalidators" {
  let line = ViewLine::ViewLine()
  let input = retained_line_test_input(None)
  let builder = StringBuilder()
  assert_true(line.is_maybe_invalid)
  assert_true(line.get_dom_node() is None)
  assert_true(line.render_line(1, input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)
  builder.reset()
  assert_false(line.render_line(1, input, 0, 20, builder))

  line.on_tokens_changed()
  assert_true(line.is_maybe_invalid)
  assert_false(line.render_line(1, input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)

  line.on_tokens_changed()
  assert_true(line.is_maybe_invalid)
  assert_false(line.render_line(1, input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)

  line.on_decorations_changed()
  assert_true(line.is_maybe_invalid)
  assert_false(line.render_line(1, input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)

  line.on_options_changed(ViewLineOptions(render_whitespace=All))
  assert_true(line.is_maybe_invalid)
  assert_false(line.render_line(1, input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)
}

///|
test "retained ViewLine selection invalidates only last-rendered Selection whitespace" {
  let line = ViewLine::ViewLine()
  let none_input = retained_line_test_input(None)
  let selection_input = retained_line_test_input(Selection)
  let builder = StringBuilder()
  assert_true(line.render_line(1, none_input, 0, 20, builder))
  assert_false(line.on_selection_changed())
  assert_false(line.is_maybe_invalid)

  line.on_options_changed(ViewLineOptions(render_whitespace=Selection))
  builder.reset()
  assert_true(line.render_line(1, selection_input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)
  assert_true(line.on_selection_changed())
  assert_true(line.is_maybe_invalid)
  builder.reset()
  assert_false(line.render_line(1, selection_input, 0, 20, builder))
  assert_false(line.is_maybe_invalid)
}

///|
test "retained ViewLine skips writes for distinct raw whitespace widths with equal normalized identity" {
  let line = ViewLine::ViewLine()
  let first = retained_line_test_input(
    None,
    space_width=7.2,
    middot_width=6.0,
    wsmiddot_width=9.0,
  )
  let same_normalized = retained_line_test_input(
    None,
    space_width=7.2,
    middot_width=6.0,
    wsmiddot_width=20.0,
  )
  assert_true(first == same_normalized)
  assert_eq(first.render_space_width, 6.0)
  assert_eq(first.render_space_char_code, 0xB7)
  let builder = StringBuilder()
  assert_true(line.render_line(1, first, 0, 20, builder))
  builder.reset()
  line.on_tokens_changed()
  assert_false(line.render_line(1, same_normalized, 0, 20, builder))
  assert_eq(builder.to_string(), "")
}

///|
test "retained line factory reads the current option snapshot on every creation" {
  let options = Ref(ViewLineOptions::ViewLineOptions(render_whitespace=None))
  let factory = retained_view_line_factory(options)
  let first = factory()
  assert_true(first.option_snapshot().render_whitespace == None)
  options.val = ViewLineOptions(render_whitespace=All)
  let second = factory()
  assert_true(second.option_snapshot().render_whitespace == All)
  assert_true(first.option_snapshot().render_whitespace == None)
}

///|
test "ViewLineOptions equality covers every applicable source render axis" {
  let base = ViewLineOptions::ViewLineOptions()
  let variants : Array[ViewLineOptions] = [
    { ..base, line_height: base.line_height + 1, },
    { ..base, space_width: base.space_width + 1.0, },
    { ..base, middot_width: base.middot_width + 1.0, },
    { ..base, wsmiddot_width: base.wsmiddot_width + 1.0, },
    { ..base, use_monospace_optimizations: !base.use_monospace_optimizations, },
    {
      ..base,
      can_use_halfwidth_rightwards_arrow: !base.can_use_halfwidth_rightwards_arrow,
    },
    { ..base, stop_rendering_line_after: base.stop_rendering_line_after + 1, },
    { ..base, render_whitespace: All, },
    { ..base, render_control_characters: !base.render_control_characters, },
    { ..base, font_ligatures: !base.font_ligatures, },
    { ..base, vertical_scrollbar_size: base.vertical_scrollbar_size + 1.0, },
  ]
  assert_true(base.equals(base))
  for variant in variants {
    assert_false(base.equals(variant))
  }
}
