// White-box coverage for the package-private viewport render-input adapter.

///|
fn render_options_viewport(
  content : String,
  is_basic_ascii~ : Bool = true,
) -> @view_layout.ViewportData {
  let max_column = content.length() + 1
  {
    start_line_number: 1,
    end_line_number: 1,
    relative_vertical_offset: [0.0],
    line_height: 20,
    visible_range: Range(1, 1, 1, max_column),
    big_numbers_delta: 0,
    lines: [
      {
        min_column: 1,
        max_column,
        content,
        continues_with_wrapped_line: false,
        contains_rtl: false,
        is_basic_ascii,
        tokens: [],
        inline_decorations: [],
        tab_size: 2,
        start_visible_column: 0,
        text_direction: LTR,
        has_variable_fonts: false,
      },
    ],
    line_decorations: [[]],
    view_zones: [],
  }
}

///|
fn render_options_input(
  content : String,
  configuration : ViewLinesConfiguration,
  selection_view_range? : @base_common.Range,
  is_basic_ascii~ : Bool = true,
) -> @view_layout.RenderLineInput {
  render_line_input_for_viewport(
    render_options_viewport(content, is_basic_ascii~),
    0,
    configuration.view_line_options,
    selection_view_range~,
  )
}

///|
test "viewport line input carries each content-only whitespace mode" {
  let modes : Array[@editor_api.RenderWhitespace] = [
    None,
    Boundary,
    Trailing,
    All,
  ]
  for mode in modes {
    let input = render_options_input(
      "  abc  ",
      ViewLinesConfiguration(render_whitespace=mode),
    )
    assert_true(input.render_whitespace == mode)
  }
}

///|
test "viewport line input carries render-control and ascii facts" {
  let input = render_options_input(
    "café\u{202E}",
    ViewLinesConfiguration(render_control_characters=true),
    is_basic_ascii=false,
  )
  assert_true(input.render_control_characters)
  assert_false(input.is_basic_ascii)
}

///|
test "Selection mode is inert without a threaded selection" {
  let input = render_options_input(
    "  abc  ",
    ViewLinesConfiguration(render_whitespace=Selection),
  )
  assert_true(input.render_whitespace == Selection)
  assert_eq(input.selections_on_line.length(), 0)
}

///|
test "view-line options carry font axes into render input" {
  let input = render_options_input(
    " a ",
    ViewLinesConfiguration(
      line_height=23,
      space_width=7.0,
      middot_width=8.0,
      wsmiddot_width=9.0,
      use_monospace_optimizations=false,
      can_use_halfwidth_rightwards_arrow=true,
      stop_rendering_line_after=17,
      render_whitespace=All,
      render_control_characters=true,
      font_ligatures=true,
      vertical_scrollbar_size=19.0,
    ),
  )
  assert_eq(input.space_width, 7.0)
  assert_eq(input.render_space_width, 8.0)
  assert_eq(input.render_space_char_code, 0x00B7)
  assert_false(input.use_monospace_optimizations)
  assert_eq(input.stop_rendering_line_after, 17)
  assert_true(input.render_whitespace == All)
  assert_true(input.render_control_characters)
  assert_true(input.font_ligatures)
  assert_eq(input.vertical_scrollbar_size, 19.0)
}
