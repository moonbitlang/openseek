///|
test "viewport data exposes one-based inclusive line data" {
  let doc = @model.TextSnapshot(
    (
      #|a
      #|bb
      #|ccc
    ),
  )
  let view_model = view_model_for(doc)
  let viewport = @view_model.viewport_data_from_view_model(
    view_model,
    { start: 2, end: 4, },
    line_height=18,
  )
  assert_eq(viewport.start_line_number, 2)
  assert_eq(viewport.end_line_number, 3)
  debug_inspect(
    viewport.relative_vertical_offset,
    content=(
      #|[0, 18]
    ),
  )
  match viewport.line_data(2) {
    Some(line) => {
      assert_eq(line.min_column, 1)
      assert_eq(line.max_column, 3)
      assert_eq(line.content, "bb")
      assert_eq(
        line.tokens.length(),
        view_model.lines().get_view_line_data(2).tokens.get_count(),
      )
    }
    None => fail("expected line 2 data")
  }
  assert_true(viewport.line_data(1) is None)
}

///|
test "render line input carries readonly defaults and equality" {
  let doc = @model.TextSnapshot("let x = 1")
  let line = view_model_for(doc).lines().get_view_line_data(1)
  let input = @view_model.render_line_input_from_view_line_data(line)
  let same = @view_model.render_line_input_from_view_line_data(line)
  assert_true(input == same)
  assert_true(input.use_monospace_optimizations)
  assert_true(input.can_use_halfwidth_rightwards_arrow)
  assert_eq(input.tab_size, 2)
  assert_eq(input.start_visible_column, 0)
  assert_eq(input.stop_rendering_line_after, -1)
  assert_false(input.render_control_characters)
  let changed = @view_layout.RenderLineInput::from_view_line(
    @view_model.view_line_rendering_data_from_view_line_data(line),
    render_whitespace=All,
  )
  assert_false(input == changed)
}

///|
test "line decorations normalizer splits overlapping segments" {
  let normalized = @view_layout.LineDecorationsNormalizer::normalize("abcdef", [
    LineDecoration(1, 4, "first"),
    LineDecoration(3, 6, "second"),
  ])
  debug_inspect(
    normalized,
    content=(
      #|[
      #|  { start_offset: 0, end_offset: 1, class_name: "first", metadata: 0 },
      #|  {
      #|    start_offset: 2,
      #|    end_offset: 2,
      #|    class_name: "first second",
      #|    metadata: 0,
      #|  },
      #|  { start_offset: 3, end_offset: 4, class_name: "second", metadata: 0 },
      #|]
    ),
  )
}

///|
test "render view line escapes text and returns character mapping" {
  let input = simple_render_input("a<b", [LinePart(3, "tok-test")])
  let output = @view_layout.render_view_line2(input)
  assert_eq(
    output.html,
    "<span class=\"view-line-content\"><span class=\"tok-test\">a&lt;b</span></span>",
  )
  let position = output.character_mapping.get_dom_position(2)
  assert_eq(position.part_index, 0)
  assert_eq(position.char_index, 1)
  assert_eq(output.character_mapping.get_column(position, 3), 2)
  assert_eq(output.character_mapping.get_horizontal_offset(3), 2)
  let end_position = output.character_mapping.get_dom_position(4)
  assert_eq(end_position.part_index, 0)
  assert_eq(end_position.char_index, 3)
}

///|
test "render view line supports pseudo decorations and large token splitting" {
  let mut long = ""
  for _ in 0..<121 {
    long = "\{long}a"
  }
  let input = @view_layout.RenderLineInput::from_view_line(
    simple_view_line(long, [LinePart(long.length(), "tok-long")]),
    line_decorations=[
      LineDecoration(1, 1, "before-content", decoration_type=Before),
      LineDecoration(
        long.length() + 1,
        long.length() + 1,
        "after-content",
        decoration_type=After,
      ),
    ],
  )
  let output = @view_layout.render_view_line2(input)
  assert_true(output.html.contains("before-content"))
  assert_true(output.html.contains("after-content"))
  assert_true(output.contains_foreign_elements == BeforeAndAfter)
  assert_true(count_occurrences(output.html, "tok-long") >= 3)
  assert_eq(output.character_mapping.length, long.length() + 1)
  let end_position = output.character_mapping.get_dom_position(
    long.length() + 1,
  )
  assert_true(end_position.part_index > 0)
  assert_eq(end_position.char_index, 0)
}

///|
test "empty line preserves compatibility wrapper" {
  let doc = @model.TextSnapshot(
    (
      #|a
      #|
      #|b
    ),
  )
  // Monaco emits an empty inner `<span></span>` for a blank line.
  assert_eq(
    @common.render_line_html(
      view_model_for(doc).lines().get_view_line_data(2),
      [],
    ),
    "<span class=\"view-line-content\"><span></span></span>",
  )
}

///|
fn simple_render_input(
  content : String,
  tokens : Array[@view_layout.LinePart],
) -> @view_layout.RenderLineInput {
  @view_layout.RenderLineInput::from_view_line(
    simple_view_line(content, tokens),
  )
}

///|
fn simple_view_line(
  content : String,
  tokens : Array[@view_layout.LinePart],
) -> @view_layout.ViewLineRenderingData {
  {
    min_column: 1,
    max_column: content.length() + 1,
    content,
    continues_with_wrapped_line: false,
    contains_rtl: false,
    is_basic_ascii: true,
    tokens,
    inline_decorations: [],
    tab_size: 2,
    start_visible_column: 0,
    text_direction: LTR,
    has_variable_fonts: false,
  }
}

///|
fn count_occurrences(haystack : String, needle : String) -> Int {
  let mut count = 0
  let needle_len = needle.length()
  if needle_len == 0 {
    return 0
  }
  for index in 0..<=(haystack.length() - needle_len) {
    if haystack[index:index + needle_len].to_owned() == needle {
      count += 1
    }
  }
  count
}
