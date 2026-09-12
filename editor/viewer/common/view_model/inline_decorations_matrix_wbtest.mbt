///|
/// Branch-derived completion matrix for Monaco's
/// `src/vs/editor/common/viewModel/inlineDecorations.ts` in the checked-in
/// vscode source. The exact upstream test labels
/// remain in `inline_decorations_reference_wbtest.mbt`; these additional cases
/// close behavior-variable combinations that upstream's suite does not name.

///|
/// `InlineModelDecorationsComputer.getDecorations`
/// (`inlineDecorations.ts:78-149`).
test "matrix overlapping adjacent and same-line decorations preserve order" {
  let model = TestTextModel::create("abcdefghij")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _minimap, _margin) {
      [
        create_model_decoration(
          "overlap-a",
          Range(1, 2, 1, 6),
          ModelDecorationOptions(inline_class_name="overlap-a"),
        ),
        create_model_decoration(
          "overlap-b",
          Range(1, 4, 1, 8),
          ModelDecorationOptions(inline_class_name="overlap-b"),
        ),
        create_model_decoration(
          "adjacent",
          Range(1, 8, 1, 11),
          ModelDecorationOptions(inline_class_name="adjacent"),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 11), false, false)
  assert_inline_eq(result.inline_decorations, [
    [
      InlineDecoration(Range(1, 2, 1, 6), "overlap-a", Regular),
      InlineDecoration(Range(1, 4, 1, 8), "overlap-b", Regular),
      InlineDecoration(Range(1, 8, 1, 11), "adjacent", Regular),
    ],
  ])
}

///|
/// Whole-line conversion (`inlineDecorations.ts:163-183`).
test "matrix whole-line decorations span line minima and maxima" {
  let model = TestTextModel::create("abc\ndefgh")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _minimap, _margin) {
      [
        create_model_decoration(
          "whole",
          Range(1, 3, 2, 2),
          ModelDecorationOptions(inline_class_name="whole", is_whole_line=true),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 2, 6), false, false)
  let whole = InlineDecoration(Range(1, 1, 2, 6), "whole", Regular)
  assert_inline_eq(result.inline_decorations, [[whole], [whole]])
}

///|
/// Right-affinity wrapped conversion (`inlineDecorations.ts:163-183`).
test "matrix wrapped model decorations map exact line boundaries" {
  let source_model = TestTextModel::create("abcdefghij")
  let model = inline_reference_model(source_model)
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=4,
    wrapping_indent=Same,
  )
  let converter = lines.create_coordinates_converter()
  let first = create_model_decoration(
    "first",
    Range(1, 1, 1, 5),
    ModelDecorationOptions(inline_class_name="first"),
  )
  let second = create_model_decoration(
    "second",
    Range(1, 5, 1, 9),
    ModelDecorationOptions(inline_class_name="second"),
  )
  let references = [first, second]
  let context : InlineModelContext = {
    get_model_decorations: fn(_view_range, _minimap, _margin) {
      [first.decoration, second.decoration]
    },
  }
  let computer = InlineModelDecorationsComputer(context, model, converter)
  let viewport = converter.model_range_to_view_range(
    Range(1, 1, 1, 11),
    affinity=Right,
  )
  let result = computer.compute_decorations(
    [first.decoration, second.decoration],
    viewport,
    decoration => reference_resolved_options(references, decoration),
  )
  let first_inline = InlineDecoration(Range(1, 1, 1, 5), "first", Regular)
  let second_inline = InlineDecoration(Range(2, 1, 2, 5), "second", Regular)
  assert_inline_eq(result.inline_decorations, [
    [first_inline],
    [second_inline],
    [],
  ])
}

///|
/// Endpoint visibility and per-line font flags (`inlineDecorations.ts:105-141`).
test "matrix viewport suppresses endpoint decorations and scopes font flags" {
  let model = TestTextModel::create(
    (
      #|first
      #|middle
      #|last
    ),
  )
  let outside_context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _minimap, _margin) {
      [
        create_model_decoration(
          "outside-endpoints",
          Range(1, 2, 3, 3),
          ModelDecorationOptions(
            before_content_class_name="outside-before",
            after_content_class_name="outside-after",
            affects_font=true,
          ),
        ),
      ]
    },
  }
  let outside_computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    outside_context, model,
  )
  let outside = outside_computer.get_decorations(
    Range(2, 1, 2, 7),
    false,
    false,
  )
  assert_inline_eq(outside.inline_decorations, [[]])
  assert_bool_array_eq(outside.has_variable_fonts, [false])
  let inside_context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _minimap, _margin) {
      [
        create_model_decoration(
          "inside-endpoints",
          Range(2, 2, 2, 4),
          ModelDecorationOptions(
            before_content_class_name="inside-before",
            after_content_class_name="inside-after",
            affects_font=true,
          ),
        ),
      ]
    },
  }
  let inside_computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    inside_context, model,
  )
  let inside = inside_computer.get_decorations(Range(2, 1, 2, 7), false, false)
  assert_inline_eq(inside.inline_decorations, [
    [
      InlineDecoration(Range(2, 2, 2, 2), "inside-before", Before),
      InlineDecoration(Range(2, 4, 2, 4), "inside-after", After),
    ],
  ])
  assert_bool_array_eq(inside.has_variable_fonts, [true])
}

///|
/// Query-flag forwarding (`inlineDecorations.ts:78-80`).
test "matrix minimap and margin query flags reach source context" {
  let mut seen_minimap = false
  let mut seen_margin = false
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, minimap, margin) {
      seen_minimap = minimap
      seen_margin = margin
      []
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context,
    TestTextModel::create("abc"),
  )
  ignore(computer.computer.get_decorations(Range(1, 1, 1, 4), true, false))
  assert_true(seen_minimap)
  assert_false(seen_margin)
  ignore(computer.computer.get_decorations(Range(1, 1, 1, 4), false, true))
  assert_false(seen_minimap)
  assert_true(seen_margin)
}

///|
/// Reachable `onlyMarginDecorations` model query
/// (`viewModelLines.ts:923-975`).
test "matrix margin-only query filters glyph-margin decorations" {
  let model = inline_reference_model(TestTextModel::create("abc"))
  let ids = model.delta_decorations([], [
    {
      range: Range(1, 1, 1, 3),
      options: ModelDecorationOptions("", inline_class_name="regular"),
    },
    {
      range: Range(1, 1, 1, 3),
      options: ModelDecorationOptions("", glyph_margin_class_name="margin"),
    },
  ])
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=0,
    wrapping_indent=Same,
  )
  let converter = lines.create_coordinates_converter()
  let margin_only = view_model_lines_get_decorations_in_range(
    lines,
    model,
    converter,
    Range(1, 1, 1, 4),
    0,
    false,
    false,
    true,
  )
  assert_eq(margin_only.length(), 1)
  assert_eq(margin_only[0].id, ids[1])
  assert_true(margin_only[0].options.glyph_margin_class_name is Some("margin"))
}

///|
/// Both named cache-reset hooks (`inlineDecorations.ts:151-161`).
test "matrix model and line mapping changes invalidate decoration cache" {
  let decoration = create_model_decoration(
    "cached",
    Range(1, 1, 1, 3),
    ModelDecorationOptions(inline_class_name="cached"),
  )
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _minimap, _margin) { [decoration] },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context,
    TestTextModel::create("abc"),
  )
  let first = computer.get_decorations(Range(1, 1, 1, 4), false, false)
  let cached = computer.get_decorations(Range(1, 1, 1, 4), false, false)
  assert_true(physical_equal(first.decorations[0], cached.decorations[0]))
  computer.computer.on_model_decorations_changed()
  let after_model_change = computer.get_decorations(
    Range(1, 1, 1, 4),
    false,
    false,
  )
  assert_false(
    physical_equal(cached.decorations[0], after_model_change.decorations[0]),
  )
  computer.computer.on_line_mapping_changed()
  let after_mapping_change = computer.get_decorations(
    Range(1, 1, 1, 4),
    false,
    false,
  )
  assert_false(
    physical_equal(
      after_model_change.decorations[0],
      after_mapping_change.decorations[0],
    ),
  )
}

///|
/// Before/after construction and ordering (`textModelEvents.ts:257-288`).
test "matrix model before and after injections keep source order" {
  let model = inline_reference_model(TestTextModel::create("ab"))
  model.delta_decorations([], [
    {
      range: Range(1, 2, 1, 2),
      options: ModelDecorationOptions(
        "",
        description="matrix before/after",
        show_if_collapsed=true,
        before=InjectedTextOptions("[", inline_class_name="before"),
        after=InjectedTextOptions("]", inline_class_name="after"),
      ),
    },
  ])
  |> ignore
  let stored = model.get_injected_text_decorations()
  assert_eq(stored.length(), 1)
  assert_true(stored[0].options.before is Some(_))
  assert_true(stored[0].options.after is Some(_))
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=0,
    wrapping_indent=Same,
  )
  let data = lines.get_view_line_data(1)
  assert_eq(data.content, "a[]b")
  assert_eq(data.inline_decorations.length(), 2)
  assert_eq(data.inline_decorations[0].class_name, "before")
  assert_eq(data.inline_decorations[1].class_name, "after")
}

///|
/// Injected-text accumulation and clipping (`inlineDecorations.ts:213-267`).
test "matrix same-position injections preserve accumulated order" {
  let options = [
    ResolvedInjectedTextOptions(content="AA", inline_class_name="first"),
    ResolvedInjectedTextOptions(content="BBB", inline_class_name="second"),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_line) { Some(options) },
    get_injection_offsets: fn(_line) { Some([3, 3]) },
    get_break_offsets: fn(_line) { [10] },
    get_wrapped_text_indent_length: fn(_line) { 0 },
    get_base_view_line_number: fn(_line) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer(context)
  assert_inline_eq(computer.get_inline_decorations(1), [
    [
      InlineDecoration(Range(1, 4, 1, 6), "first", Regular),
      InlineDecoration(Range(1, 6, 1, 9), "second", Regular),
    ],
  ])
}

///|
/// The projected-line producer supplies the paired arrays consumed at
/// `modelLineProjection.ts:165-178` and `textModel.ts:2135-2163`.
test "matrix projected injections keep option-offset pairs aligned" {
  let projected = ProjectedTextLine::from_injected_text("abcd", [
    InjectedText(Position(0, 3), "YY", "second", source_index=2),
    InjectedText(Position(0, 1), "X", "first", source_index=1),
  ])
  let options = injection_options_for_projected_line(projected)
  let offsets = injection_offsets_for_projected_line(projected)
  assert_eq(options.length(), 2)
  assert_eq(offsets.length(), options.length())
  assert_eq(options[0].content(), "X")
  assert_eq(offsets[0], 1)
  assert_eq(options[1].content(), "YY")
  assert_eq(offsets[1], 3)
}

///|
test "matrix empty injected text is suppressed" {
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_line) {
      Some([ResolvedInjectedTextOptions(content="", inline_class_name="empty")])
    },
    get_injection_offsets: fn(_line) { Some([2]) },
    get_break_offsets: fn(_line) { [5] },
    get_wrapped_text_indent_length: fn(_line) { 0 },
    get_base_view_line_number: fn(_line) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer(context)
  assert_inline_eq(computer.get_inline_decorations(1), [[]])
}

///|
test "matrix empty break offsets return no buckets" {
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_line) {
      Some([ResolvedInjectedTextOptions(content="x", inline_class_name="x")])
    },
    get_injection_offsets: fn(_line) { Some([0]) },
    get_break_offsets: fn(_line) { [] },
    get_wrapped_text_indent_length: fn(_line) { 0 },
    get_base_view_line_number: fn(_line) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer(context)
  assert_inline_eq(computer.get_inline_decorations(1), [])
}

///|
test "matrix line-end injection suppresses zero-width clip and resumes next line" {
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_line) {
      Some([ResolvedInjectedTextOptions(content="xx", inline_class_name="edge")])
    },
    get_injection_offsets: fn(_line) { Some([5]) },
    get_break_offsets: fn(_line) { [5, 10] },
    get_wrapped_text_indent_length: fn(_line) { 0 },
    get_base_view_line_number: fn(_line) { 4 },
  }
  let computer = InjectedTextInlineDecorationsComputer(context)
  assert_inline_eq(computer.get_inline_decorations(1), [
    [],
    [InlineDecoration(Range(5, 1, 5, 3), "edge", Regular)],
  ])
}

///|
test "panic matrix injected offsets require options" {
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_line) { None },
    get_injection_offsets: fn(_line) { Some([0]) },
    get_break_offsets: fn(_line) { [1] },
    get_wrapped_text_indent_length: fn(_line) { 0 },
    get_base_view_line_number: fn(_line) { 1 },
  }
  ignore(
    InjectedTextInlineDecorationsComputer(context).get_inline_decorations(1),
  )
}

///|
test "panic matrix injected offsets cannot outnumber options" {
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_line) {
      Some([ResolvedInjectedTextOptions(content="x", inline_class_name="x")])
    },
    get_injection_offsets: fn(_line) { Some([0, 1]) },
    get_break_offsets: fn(_line) { [5] },
    get_wrapped_text_indent_length: fn(_line) { 0 },
    get_base_view_line_number: fn(_line) { 1 },
  }
  ignore(
    InjectedTextInlineDecorationsComputer(context).get_inline_decorations(1),
  )
}
