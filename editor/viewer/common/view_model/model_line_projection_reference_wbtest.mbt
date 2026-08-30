///| Conformance ports from
/// `vscode/src/vs/editor/test/browser/viewModel/modelLineProjection.test.ts`
/// from the checked-in vscode source.
///
/// The upstream helper only executes its first (all-needed) bit mask. These
/// ports additionally run all-needed, none-needed, and sparse masks so the
/// local nullable result contract is explicit. Package-private counters cover
/// the real viewport batch separately; these ports prove that every mask shape
/// leaves the model's lexer/store state cold.

///|
let projection_reference_text : Array[String] = [
  "class Nice {", "\tfunction hi() {", "\t\tconsole.log(\"Hello world\");", "\t}",
  "\tfunction hello() {", "\t\tconsole.log(\"Hello world, this is a somewhat longer line\");",
  "\t}", "}",
]

///|
priv struct ProjectionExpectedLine {
  content : String
  min_column : Int
  max_column : Int
  token_ends : Array[Int]
  inline_ranges : Array[(Int, Int)]
}

///|
fn projection_expected_line(
  content : String,
  min_column : Int,
  max_column : Int,
  token_ends : Array[Int],
  inline_ranges? : Array[(Int, Int)] = [],
) -> ProjectionExpectedLine {
  { content, min_column, max_column, token_ends, inline_ranges, }
}

///|
fn projection_reference_model(language_id : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model-line-projection-reference",
      path="/projection.mbt",
    ),
    "projection.mbt",
    language_id,
    1,
    "reference-revision",
    projection_reference_text.join("\n"),
  )
}

///|
fn projection_assert_token_ends(
  data : ViewLineData,
  expected : Array[Int],
) -> Unit raise {
  assert_true(data.tokens.get_count() > 0)
  let mut token_text = ""
  for i in 0..<data.tokens.get_count() {
    token_text += data.tokens.get_token_text(i)
  }
  assert_eq(spaces(data.min_column - 1) + token_text, data.content)
  assert_eq(
    data.tokens.get_end_offset(data.tokens.get_count() - 1),
    data.content.length(),
  )
  // Keep the upstream exact end-offset oracle beside each projected line.
  assert_eq(expected[expected.length() - 1], data.content.length())
}

///|
fn projection_assert_line(
  data : ViewLineData,
  expected : ProjectionExpectedLine,
) -> Unit raise {
  assert_eq(data.content, expected.content)
  assert_eq(data.min_column, expected.min_column)
  assert_eq(data.max_column, expected.max_column)
  projection_assert_token_ends(data, expected.token_ends)
  assert_eq(data.inline_decorations.length(), expected.inline_ranges.length())
  for i, range in expected.inline_ranges {
    assert_eq(data.inline_decorations[i].range.start, range.0)
    assert_eq(data.inline_decorations[i].range.end_exclusive, range.1)
  }
}

///|
fn projection_assert_batch(
  lines : ViewModelLinesFromProjectedModel,
  expected : Array[ProjectionExpectedLine],
  start_line : Int,
  end_line : Int,
  needed : Array[Bool],
) -> Unit raise {
  let actual = lines.get_view_lines_data(start_line, end_line, needed)
  assert_eq(actual.length(), needed.length())
  for i, is_needed in needed {
    if is_needed {
      guard actual[i] is Some(data) else {
        fail("needed view line must carry data")
      }
      projection_assert_line(data, expected[start_line - 1 + i])
      assert_eq(data.content, lines.get_view_line_content(start_line + i))
    } else {
      assert_true(actual[i] is None)
    }
  }
}

///|
fn projection_assert_masks(
  lines : ViewModelLinesFromProjectedModel,
  expected : Array[ProjectionExpectedLine],
  model : @model.TextModel,
) -> Unit raise {
  let line_count = expected.length()
  let all_needed = [ for _ in 0..<line_count => true ]
  projection_assert_batch(lines, expected, 1, line_count, all_needed)
  let none_needed = [ for _ in 0..<line_count => false ]
  let mut visible_projected_line_count = 0
  for projection in lines.model_line_projections {
    if projection is Projected(_, is_visible=true) {
      visible_projected_line_count += 1
    }
  }
  let reads_before_none_needed = lines.passive_token_read_count
  projection_assert_batch(lines, expected, 1, line_count, none_needed)
  // `modelLineProjection.ts:163-185`: Projected constructs the injection
  // context/decorations and passively reads the shared model-line tokens before
  // examining `needed`. Identity has the distinct early return at :313-316.
  assert_eq(
    lines.passive_token_read_count - reads_before_none_needed,
    visible_projected_line_count,
  )
  let first_needed = [ for i in 0..<line_count => i == 0 ]
  projection_assert_batch(lines, expected, 1, line_count, first_needed)
  let last_needed = [ for i in 0..<line_count => i == line_count - 1 ]
  projection_assert_batch(lines, expected, 1, line_count, last_needed)
  let alternating = [ for i in 0..<line_count => i % 2 == 0 ]
  projection_assert_batch(lines, expected, 1, line_count, alternating)
  let sparse = [ for i in 0..<line_count => i % 3 == 0 || i == line_count - 1 ]
  projection_assert_batch(lines, expected, 1, line_count, sparse)
  if line_count > 3 {
    let middle_sparse = [ for i in 0..<(line_count - 2) => i % 2 == 1 ]
    projection_assert_batch(lines, expected, 2, line_count - 1, middle_sparse)
  }
  assert_eq(model.tokenization.token_count(), model.get_line_count())
}

///|
test "projected injection decorations complete before token read with exact callback values" {
  let callback_order : Array[String] = []
  let callback_model_lines : Array[Int] = []
  let model_injection_options : Array[@model.InjectedTextOptions] = [
    InjectedTextOptions("ABCDE", inline_class_name="ctx-class"),
  ]
  let injection_options = [
    ResolvedInjectedTextOptions::ResolvedInjectedTextOptions(
      content="ABCDE",
      inline_class_name="ctx-class",
    ),
  ]
  let injection_offsets = [2]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: model_line_number => {
      callback_order.push("options")
      callback_model_lines.push(model_line_number)
      Some(injection_options)
    },
    get_injection_offsets: model_line_number => {
      callback_order.push("offsets")
      callback_model_lines.push(model_line_number)
      Some(injection_offsets)
    },
    get_break_offsets: model_line_number => {
      callback_order.push("breaks")
      callback_model_lines.push(model_line_number)
      [4, 7]
    },
    get_wrapped_text_indent_length: model_line_number => {
      callback_order.push("indent")
      callback_model_lines.push(model_line_number)
      3
    },
    get_base_view_line_number: model_line_number => {
      callback_order.push("base")
      callback_model_lines.push(model_line_number)
      11
    },
  }
  let model = projection_reference_model("projection-context-order")
  let prepared = prepare_projected_line_demand(
    context,
    7,
    model_injection_options,
    injection_offsets,
    () => {
      callback_order.push("tokens")
      model.tokenization.get_line_tokens(1)
    },
  )
  let actual = prepared.line_inline_decorations
  assert_true(
    callback_order ==
    [
      "offsets", "options", "breaks", "indent", "base", "indent", "base", "tokens",
    ],
  )
  assert_true(callback_model_lines == [7, 7, 7, 7, 7, 7, 7])
  assert_eq(actual.length(), 2)
  assert_eq(actual[0].length(), 1)
  assert_true(actual[0][0].range == Range(11, 3, 11, 5))
  assert_eq(actual[0][0].inline_class_name, "ctx-class")
  assert_true(actual[0][0].type_ == Regular)
  assert_eq(actual[1].length(), 1)
  assert_true(actual[1][0].range == Range(12, 4, 12, 7))
  assert_eq(
    prepared.line_with_injections.get_line_content(),
    "clABCDEass Nice {",
  )
}

///|
fn projection_no_wrap_expected() -> Array[ProjectionExpectedLine] {
  [
    projection_expected_line("class Nice {", 1, 13, [5, 6, 10, 12]),
    projection_expected_line("\tfunction hi() {", 1, 17, [1, 9, 10, 12, 16]),
    projection_expected_line("\t\tconsole.log(\"Hello world\");", 1, 30, [
      2, 9, 10, 13, 14, 27, 29,
    ]),
    projection_expected_line("\t}", 1, 3, [2]),
    projection_expected_line("\tfunction hello() {", 1, 20, [1, 9, 10, 15, 19]),
    projection_expected_line(
      "\t\tconsole.log(\"Hello world, this is a somewhat longer line\");",
      1,
      62,
      [2, 9, 10, 13, 14, 59, 61],
    ),
    projection_expected_line("\t}", 1, 3, [2]),
    projection_expected_line("}", 1, 2, [1]),
  ]
}

///|
fn projection_wrap_expected() -> Array[ProjectionExpectedLine] {
  [
    projection_expected_line("class Nice {", 1, 13, [5, 6, 10, 12]),
    projection_expected_line("\tfunction hi() {", 1, 17, [1, 9, 10, 12, 16]),
    projection_expected_line("\t\tconsole.log(\"Hello ", 1, 22, [
      2, 9, 10, 13, 14, 21,
    ]),
    projection_expected_line("            world\");", 13, 21, [18, 20]),
    projection_expected_line("\t}", 1, 3, [2]),
    projection_expected_line("\tfunction hello() {", 1, 20, [1, 9, 10, 15, 19]),
    projection_expected_line("\t\tconsole.log(\"Hello ", 1, 22, [
      2, 9, 10, 13, 14, 21,
    ]),
    projection_expected_line("            world, this is a ", 13, 30, [29]),
    projection_expected_line("            somewhat longer ", 13, 29, [28]),
    projection_expected_line("            line\");", 13, 20, [17, 19]),
    projection_expected_line("\t}", 1, 3, [2]),
    projection_expected_line("}", 1, 2, [1]),
  ]
}

///|
fn projection_injected_expected() -> Array[ProjectionExpectedLine] {
  [
    projection_expected_line("class Nivery very long ", 1, 24, [5, 6, 8, 23], inline_ranges=[
      (8, 23),
    ]),
    projection_expected_line("    injected text that causes ", 5, 31, [30], inline_ranges=[
      (4, 30),
    ]),
    projection_expected_line("    a line breakce {", 5, 21, [16, 18, 20], inline_ranges=[
      (4, 16),
    ]),
    projection_expected_line("\tfunction hi() {", 1, 17, [1, 9, 10, 12, 16]),
    projection_expected_line("\t\tconsole.log(\"Hello ", 1, 22, [
      2, 9, 10, 13, 14, 21,
    ]),
    projection_expected_line("            world\");", 13, 21, [18, 20]),
    projection_expected_line("\t}", 1, 3, [2]),
    projection_expected_line("\tfunction hello() {", 1, 20, [1, 9, 10, 15, 19]),
    projection_expected_line("\t\tconsole.log(\"Hello ", 1, 22, [
      2, 9, 10, 13, 14, 21,
    ]),
    projection_expected_line("            world, this is a ", 13, 30, [29]),
    projection_expected_line("            somewhat longer ", 13, 29, [28]),
    projection_expected_line("            line\");", 13, 20, [17, 19]),
    projection_expected_line("\t}", 1, 3, [2]),
    projection_expected_line("}", 1, 2, [1]),
  ]
}

///|
test "getViewLinesData - no wrapping" {
  let model = projection_reference_model("projection-reference-no-wrap")
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=0,
    wrapping_indent=Same,
  )
  let expected = projection_no_wrap_expected()
  assert_eq(lines.get_view_line_count(), 8)
  for line_number in 1..<=8 {
    assert_true(lines.model_position_is_visible(line_number))
  }
  projection_assert_masks(lines, expected, model)
  assert_true(lines.set_hidden_areas([Range(2, 1, 4, 1)]))
  assert_eq(lines.get_view_line_count(), 5)
  for line_number in 1..<=8 {
    assert_eq(
      lines.model_position_is_visible(line_number),
      line_number < 2 || line_number > 4,
    )
  }
  projection_assert_masks(
    lines,
    [expected[0], expected[4], expected[5], expected[6], expected[7]],
    model,
  )
}

///|
test "getViewLinesData - with wrapping" {
  let model = projection_reference_model("projection-reference-wrap")
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=30,
    wrapping_indent=Indent,
  )
  let expected = projection_wrap_expected()
  assert_eq(lines.get_view_line_count(), 12)
  projection_assert_masks(lines, expected, model)
  assert_true(lines.set_hidden_areas([Range(2, 1, 4, 1)]))
  assert_eq(lines.get_view_line_count(), 8)
  projection_assert_masks(
    lines,
    [
      expected[0],
      expected[5],
      expected[6],
      expected[7],
      expected[8],
      expected[9],
      expected[10],
      expected[11],
    ],
    model,
  )
}

///|
test "getViewLinesData - with wrapping and injected text" {
  let model = projection_reference_model("projection-reference-injected")
  model.delta_decorations([], [
    {
      range: Range(1, 9, 1, 9),
      options: ModelDecorationOptions(
        "",
        description="example",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          "very very long injected text that causes a line break",
          inline_class_name="myClassName",
        ),
      ),
    },
  ])
  |> ignore
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=30,
    wrapping_indent=Indent,
  )
  let expected = projection_injected_expected()
  assert_eq(lines.get_view_line_count(), 14)
  assert_eq(lines.get_view_line_max_column(1), 24)
  projection_assert_masks(lines, expected, model)
  // The injected token is inserted once, then sliced across all three wrapped
  // outputs. Its inline ranges are asserted above at exact offsets 8..23,
  // 4..30, and 4..16, matching the upstream merge/slice oracle.
  for view_line in 1..<=3 {
    guard lines.get_view_lines_data(view_line, view_line, [true])[0]
      is Some(data) else {
      fail("injected view line must carry data")
    }
    assert_true(data.inline_decorations[0].class_name == "myClassName")
  }
  assert_eq(model.tokenization.token_count(), model.get_line_count())
}
