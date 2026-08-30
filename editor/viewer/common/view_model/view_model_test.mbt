///|
test "no-wrap converter preserves model and view positions through identity projections" {
  let model = plain_text_model(
    (
      #|fn main {
      #|  let x = 1
      #|  let y = 2
      #|}
      #|
    ),
  )
  let converter = @view_model.ViewModel(model).coordinates_converter()
  let position = @base_common.Position(2, 7)
  assert_true(converter.model_position_to_view_position(position) == position)
  assert_true(converter.view_position_to_model_position(position) == position)
  let range = @base_common.Range::Range(2, 3, 4, 9)
  let valid_range = @base_common.Range::Range(2, 3, 4, 2)
  assert_true(converter.model_range_to_view_range(range) == valid_range)
  assert_true(converter.view_range_to_model_range(range) == valid_range)
}

///|
test "view model constructs the closed projected coordinates converter" {
  let model = plain_text_model("alpha\nbeta")
  let view_model = @view_model.ViewModel(model)
  match view_model.coordinates_converter() {
    Projected(lines) => {
      assert_eq(lines.get_view_line_count(), 2)
      assert_eq(lines.get_view_line_content(2), "beta")
    }
  }
}

///|
test "no-wrap view lines match view line rendering data" {
  let model = plain_text_model(
    (
      #|fn main {
      #|  let x = 1
      #|}
    ),
  )
  let view_model = @view_model.ViewModel(model)
  let lines = view_model.lines()
  let direct_line = lines.get_view_line_data(2)
  let data = lines.view_line_rendering_data(2)
  assert_eq(data.min_column, 1)
  assert_eq(data.max_column, direct_line.content.length() + 1)
  assert_eq(data.content, direct_line.content)
  assert_eq(data.tokens.length(), direct_line.tokens.get_count())
  for index in 0..<data.tokens.length() {
    assert_eq(
      data.tokens[index].end_index,
      direct_line.tokens.get_end_offset(index),
    )
    assert_eq(
      data.tokens[index].class_name,
      direct_line.tokens.get_class_name(index),
    )
  }
}

///|
fn test_view_model(
  text : String,
  options : @view_model.ViewModelOptions,
) -> @view_model.ViewModel {
  @view_model.ViewModel::with_options(plain_text_model(text), options)
}

///|
/// Builds a view model with `after` injected-text decorations on a backing
/// `TextModel`. The projection reads injected text from decoration storage.
fn test_injected_text_view_model(
  text : String,
  options : @view_model.ViewModelOptions,
  injections : Array[(@base_common.Position, String, String)],
) -> @view_model.ViewModel {
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/injected-text-test.mbt",
    ),
    "injected-text-test.mbt",
    "moonbit",
    1,
    "rev-1",
    text,
  )
  let decorations : Array[@model.ModelDeltaDecoration] = []
  for index in 0..<injections.length() {
    let (position, content, class_name) = injections[index]
    decorations.push({
      range: Range(
        position.line_number,
        position.column,
        position.line_number,
        position.column,
      ),
      options: ModelDecorationOptions(
        "",
        description="injected-text fixture",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          content,
          inline_class_name=class_name,
          attached_index=index,
        ),
      ),
    })
  }
  model.delta_decorations([], decorations) |> ignore
  register_plain_moonbit()
  @view_model.ViewModel::with_options(model, options)
}

///|
test "projected view lines cover one two and many wrapped segments" {
  let one = test_view_model("abc", @view_model.ViewModelOptions::soft_wrap(5))
  assert_eq(one.line_count(), 1)
  assert_eq(one.lines().get_view_line_content(1), "abc")
  let two = test_view_model(
    "abcdef",
    @view_model.ViewModelOptions::soft_wrap(5),
  )
  assert_eq(two.line_count(), 2)
  assert_eq(two.lines().get_view_line_content(1), "abcde")
  assert_eq(two.lines().get_view_line_content(2), "f")
  assert_eq(two.lines().model_line_number_of_view_line(2), 1)
  // Monaco `continuesWithWrappedLine = outputLineIndex + 1 < viewLineCount`:
  // the first view line continues into the wrap; the last does not.
  let first = two.lines().view_line_rendering_data(1)
  assert_true(first.continues_with_wrapped_line)
  let second = two.lines().view_line_rendering_data(2)
  assert_false(second.continues_with_wrapped_line)
  // View columns are segment-local (Monaco `getViewLineMinColumn`/`MaxColumn`
  // = `getMin/MaxOutputOffset + 1`): the continuation "f" spans [1, 2).
  assert_eq(second.min_column, 1)
  assert_eq(second.max_column, 2)
  let many = test_view_model(
    "abcdefghijkl",
    @view_model.ViewModelOptions::soft_wrap(5),
  )
  assert_eq(many.line_count(), 3)
  assert_eq(many.lines().get_view_line_content(1), "abcde")
  assert_eq(many.lines().get_view_line_content(2), "fghij")
  assert_eq(many.lines().get_view_line_content(3), "kl")
}

///|
test "wrapping indent prefixes continuation lines and round-trips positions" {
  // Two leading spaces -> `Same` indent of 2 columns on every continuation.
  let view_model = test_view_model(
    "  abcdefghij",
    @view_model.ViewModelOptions::soft_wrap(6, tab_size=2, wrapping_indent=Same),
  )
  assert_eq(view_model.line_count(), 3)
  assert_eq(view_model.lines().get_view_line_content(1), "  abcd")
  // Continuation lines carry the two-space indent (`spaces(...) + lineContent`).
  assert_eq(view_model.lines().get_view_line_content(2), "  efgh")
  assert_eq(view_model.lines().get_view_line_content(3), "  ij")
  let second = view_model.lines().view_line_rendering_data(2)
  assert_true(second.continues_with_wrapped_line)
  assert_eq(second.content, "  efgh")

  // The indent is synthetic: view column 1 of the continuation still maps back
  // to the model column where the wrap began (offset 6 -> model column 7).
  let converter = view_model.coordinates_converter()
  let continuation_start = converter.view_position_to_model_position(
    Position(2, 1),
  )
  assert_eq(continuation_start.line_number, 1)
  assert_eq(continuation_start.column, 7)
  // Past the indent, view column 3 maps to the first real character (offset 6).
  let first_char = converter.view_position_to_model_position(Position(2, 3))
  assert_eq(first_char.line_number, 1)
  assert_eq(first_char.column, 7)
  // Round-trip: model column 7 lands at the indented continuation column 3.
  let back = converter.model_position_to_view_position(Position(1, 7))
  assert_eq(back.line_number, 2)
  assert_eq(back.column, 3)
}

///|
test "projected coordinates convert model and view positions at wrap boundaries" {
  let view_model = test_view_model(
    "abcdefghij",
    @view_model.ViewModelOptions::soft_wrap(5),
  )
  let converter = view_model.coordinates_converter()
  let before_boundary = converter.model_position_to_view_position(
    Position(1, 5),
  )
  assert_eq(before_boundary.line_number, 1)
  assert_eq(before_boundary.column, 5)
  let boundary = converter.model_position_to_view_position(Position(1, 6))
  assert_eq(boundary.line_number, 2)
  assert_eq(boundary.column, 1)
  let round_trip = converter.view_position_to_model_position(Position(2, 1))
  assert_eq(round_trip.line_number, 1)
  assert_eq(round_trip.column, 6)
  let line_end = converter.view_position_to_model_position(Position(2, 6))
  assert_eq(line_end.line_number, 1)
  assert_eq(line_end.column, 11)
  let model_input_range = @base_common.Range::Range(1, 6, 1, 10)
  let range = converter.model_range_to_view_range(model_input_range)
  assert_eq(range.start_line_number, 2)
  assert_eq(range.start_column, 1)
  assert_eq(range.end_line_number, 2)
  assert_eq(range.end_column, 5)
  let model_range = converter.view_range_to_model_range(range)
  assert_eq(model_range.start_line_number, 1)
  assert_eq(model_range.start_column, 6)
  assert_eq(model_range.end_line_number, 1)
  assert_eq(model_range.end_column, 10)
}

///|
test "projected line breaks account for tabs and full width characters" {
  let tabs = test_view_model(
    "a\tb",
    @view_model.ViewModelOptions::soft_wrap(4, tab_size=4),
  )
  assert_eq(tabs.line_count(), 2)
  let first_tab_line = tabs.lines().view_line_rendering_data(1)
  assert_eq(first_tab_line.content, "a\t")
  assert_eq(first_tab_line.start_visible_column, 0)
  assert_eq(first_tab_line.max_column, 3)
  assert_true(first_tab_line.continues_with_wrapped_line)
  let second_tab_line = tabs.lines().view_line_rendering_data(2)
  assert_eq(second_tab_line.content, "b")
  assert_eq(second_tab_line.start_visible_column, 4)
  assert_false(second_tab_line.continues_with_wrapped_line)
  let full_width = test_view_model(
    "ab中c",
    @view_model.ViewModelOptions::soft_wrap(4),
  )
  assert_eq(full_width.line_count(), 2)
  assert_eq(full_width.lines().get_view_line_content(1), "ab中")
  assert_eq(full_width.lines().get_view_line_content(2), "c")
}

///|
test "projected line breaks prefer Monaco word break points" {
  let space_break = test_view_model(
    "hello world",
    @view_model.ViewModelOptions::soft_wrap(8),
  )
  assert_eq(space_break.line_count(), 2)
  assert_eq(space_break.lines().get_view_line_content(1), "hello ")
  assert_eq(space_break.lines().get_view_line_content(2), "world")
  let before_punctuation = test_view_model(
    "call(argument)",
    @view_model.ViewModelOptions::soft_wrap(6),
  )
  assert_eq(before_punctuation.line_count(), 3)
  assert_eq(before_punctuation.lines().get_view_line_content(1), "call")
  assert_eq(before_punctuation.lines().get_view_line_content(2), "(argum")
  let cjk = test_view_model(
    "中文abc",
    @view_model.ViewModelOptions::soft_wrap(3),
  )
  assert_eq(cjk.line_count(), 3)
  assert_eq(cjk.lines().get_view_line_content(1), "中")
  assert_eq(cjk.lines().get_view_line_content(2), "文")
  assert_eq(cjk.lines().get_view_line_content(3), "abc")
}

///|
test "projected long moonbit lines retain source text across segments" {
  let text = "fn main { let really_long_identifier_name = 1234567890 }"
  let view_model = test_view_model(
    text,
    @view_model.ViewModelOptions::soft_wrap(12),
  )
  assert_true(view_model.line_count() > 1)
  let mut joined = ""
  for line_number in 1..<=view_model.line_count() {
    joined += view_model.lines().get_view_line_content(line_number)
  }
  assert_eq(joined, text)
}

///|
test "injected text renders without changing model offsets" {
  let view_model = test_injected_text_view_model(
    "let x = 1",
    @view_model.ViewModelOptions::no_wrap(),
    [(Position(1, 6), ": Int", "injected-text injected-text-type")],
  )
  assert_eq(view_model.line_count(), 1)
  let line = view_model.lines().get_view_line_data(1)
  assert_eq(line.content, "let x: Int = 1")
  // View positions map back to unshifted model positions through the
  // coordinates converter (Monaco's view->model boundary).
  let converter = view_model.coordinates_converter()
  assert_eq(converter.view_position_to_model_position(Position(1, 1)).column, 1)
  assert_eq(converter.view_position_to_model_position(Position(1, 6)).column, 6)
  assert_eq(
    converter.view_position_to_model_position(Position(1, 11)).column,
    6,
  )
  assert_eq(
    converter.view_position_to_model_position(
      Position(1, line.content.length() + 1),
    ).column,
    10,
  )
  // The injected span carries its source index for hit-testing lookup.
  assert_eq(view_model.injected_text_index_at(Position(1, 6)), 0)
  assert_eq(view_model.injected_text_index_at(Position(1, 11)), -1)
  let data = view_model.lines().view_line_rendering_data(1)
  assert_eq(data.content, "let x: Int = 1")
  // The injected-text class is an inline decoration (Monaco's
  // `InjectedTextInlineDecorationsComputer`), not a token class; the spliced
  // injected token carries only default syntactic metadata (`mtk1`).
  assert_false(
    data.tokens.any(part => part.class_name.contains("injected-text")),
  )
  assert_true(
    line.inline_decorations.any(decoration => {
      decoration.class_name.contains("injected-text")
    }),
  )
  // The decoration still merges onto the injected token in the rendered DOM, so
  // the injected text is styled with both token and injected-text classes.
  let html = @view_layout.render_view_line2(
      @view_model.render_line_input_from_view_line_data(line),
    ).html
  assert_true(html.contains("mtk1 injected-text injected-text-type"))
}

///|
test "injected text participates in wrapping and coordinate conversion" {
  let view_model = test_injected_text_view_model(
    "abcdef",
    @view_model.ViewModelOptions::soft_wrap(5),
    [(Position(1, 4), "XYZ", "injected-text")],
  )
  assert_eq(view_model.line_count(), 2)
  assert_eq(view_model.lines().get_view_line_content(1), "abcXY")
  assert_eq(view_model.lines().get_view_line_content(2), "Zdef")
  let converter = view_model.coordinates_converter()
  let source_position = converter.model_position_to_view_position(
    Position(1, 4),
  )
  assert_eq(source_position.line_number, 1)
  assert_eq(source_position.column, 4)
  let injected_position = converter.view_position_to_model_position(
    Position(1, 5),
  )
  assert_eq(injected_position.line_number, 1)
  assert_eq(injected_position.column, 4)
  let wrapped_source = converter.view_position_to_model_position(Position(2, 2))
  assert_eq(wrapped_source.line_number, 1)
  assert_eq(wrapped_source.column, 4)
}

///|
test "injected text can sit at line boundaries" {
  let view_model = test_injected_text_view_model(
    "ab",
    @view_model.ViewModelOptions::no_wrap(),
    [
      (Position(1, 1), "[", "injected-text-open"),
      (Position(1, 3), "]", "injected-text-close"),
    ],
  )
  let line = view_model.lines().get_view_line_data(1)
  assert_eq(line.content, "[ab]")
  let converter = view_model.coordinates_converter()
  assert_eq(converter.view_position_to_model_position(Position(1, 1)).column, 1)
  assert_eq(converter.view_position_to_model_position(Position(1, 2)).column, 1)
  assert_eq(converter.view_position_to_model_position(Position(1, 4)).column, 3)
  assert_eq(view_model.injected_text_index_at(Position(1, 1)), 0)
  assert_eq(view_model.injected_text_index_at(Position(1, 4)), 1)
}
