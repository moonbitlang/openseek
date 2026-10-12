///|
/// Faithful 1:1 conformance port of Monaco's inline-decoration computer suites,
/// vscode/src/vs/editor/test/common/viewModel/inlineDecorations.test.ts
/// (suite InlineModelDecorationsComputer and
/// suite InjectedTextInlineDecorationsComputer) in the checked-in submodule. Test names are preserved verbatim.

///|
/// Minimal createTextModel input retained from the source suite. Production
/// execution below converts it to the real TextModel and concrete converter.
priv struct TestTextModel {
  lines : Array[String]
}

///|
/// Splits text into logical lines on newline (the suite uses newline only).
fn TestTextModel::create(text : String) -> TestTextModel {
  let lines : Array[String] = []
  let mut buf = StringBuilder()
  for ch in text {
    if ch == '\n' {
      lines.push(buf.to_string())
      buf = StringBuilder()
    } else {
      buf.write_char(ch)
    }
  }
  lines.push(buf.to_string())
  { lines, }
}

///|
/// Source-shaped decoration options used only by this white-box suite.
/// beforeContentClassName and affectsFont are deliberately retained here to
/// exercise algorithm branches that the current product model cannot produce.
priv struct ModelDecorationOptions {
  inline_class_name : String?
  inline_class_name_affects_letter_spacing : Bool
  before_content_class_name : String?
  after_content_class_name : String?
  affects_font : Bool
  is_whole_line : Bool
}

///|
/// Builds decoration options, defaulting every optional field the way an absent
/// JavaScript property would.
fn ModelDecorationOptions::ModelDecorationOptions(
  description~ : String = "",
  class_name? : String,
  inline_class_name? : String,
  inline_class_name_affects_letter_spacing~ : Bool = false,
  before_content_class_name? : String,
  after_content_class_name? : String,
  affects_font~ : Bool = false,
  is_whole_line~ : Bool = false,
) -> ModelDecorationOptions {
  ignore(description)
  ignore(class_name)
  {
    inline_class_name,
    inline_class_name_affects_letter_spacing,
    before_content_class_name,
    after_content_class_name,
    affects_font,
    is_whole_line,
  }
}

///|
/// One canonical model decoration paired with the complete source options used
/// by the private reference adapter.
priv struct ReferenceModelDecoration {
  decoration : @model.ModelDecoration
  resolved_options : ResolvedInlineDecorationOptions
}

///|
fn create_model_decoration(
  id : String,
  range : @base_common.Range,
  options : ModelDecorationOptions,
) -> ReferenceModelDecoration {
  let model_options = @model.ModelDecorationOptions(
    "",
    inline_class_name?=options.inline_class_name,
    inline_class_name_affects_letter_spacing=options.inline_class_name_affects_letter_spacing,
    is_whole_line=options.is_whole_line,
    after_content_class_name?=options.after_content_class_name,
  )
  {
    decoration: { id, owner_id: 0, range, options: model_options, },
    resolved_options: {
      inline_class_name: options.inline_class_name,
      inline_class_name_affects_letter_spacing: options.inline_class_name_affects_letter_spacing,
      before_content_class_name: options.before_content_class_name,
      after_content_class_name: options.after_content_class_name,
      affects_font: options.affects_font,
      is_whole_line: options.is_whole_line,
    },
  }
}

///|
/// Private replacement for the package-boundary generic context. It keeps the
/// upstream suite's callback shape without widening production API.
priv struct ReferenceInlineModelContext {
  get_model_decorations : (@base_common.Range, Bool, Bool) -> Array[
    ReferenceModelDecoration,
  ]
}

///|
/// Private adapter that executes the concrete production computer. Its resolved
/// option hook exists only for source branches whose product fields are
/// terminally deferred.
priv struct ReferenceInlineModelDecorationsComputer {
  computer : InlineModelDecorationsComputer
  context : ReferenceInlineModelContext
}

///|
fn inline_reference_model(model : TestTextModel) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="inline-decoration-reference",
      path="/inline.txt",
    ),
    "inline.txt",
    "inline-decoration-reference",
    1,
    "reference-revision",
    model.lines.join("\n"),
  )
}

///|
fn reference_model_decorations(
  context : ReferenceInlineModelContext,
  view_range : @base_common.Range,
  only_minimap_decorations : Bool,
  only_margin_decorations : Bool,
) -> Array[@model.ModelDecoration] {
  let result : Array[@model.ModelDecoration] = []
  for
    reference in (context.get_model_decorations)(
      view_range, only_minimap_decorations, only_margin_decorations,
    ) {
    result.push(reference.decoration)
  }
  result
}

///|
fn reference_resolved_options(
  references : Array[ReferenceModelDecoration],
  decoration : @model.ModelDecoration,
) -> ResolvedInlineDecorationOptions {
  for reference in references {
    if reference.decoration.id == decoration.id {
      return reference.resolved_options
    }
  }
  abort("missing resolved inline-decoration options for \{decoration.id}")
}

///|
fn ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
  context : ReferenceInlineModelContext,
  source_model : TestTextModel,
) -> ReferenceInlineModelDecorationsComputer {
  let model = inline_reference_model(source_model)
  let lines = ViewModelLinesFromProjectedModel(
    model,
    font_info=@config.FontInfo::default(),
    tab_size=4,
    wrapping_column=0,
    wrapping_indent=Same,
  )
  let coordinates_converter = lines.create_coordinates_converter()
  let production_context : InlineModelContext = {
    get_model_decorations: (view_range, only_minimap, only_margin) => {
      reference_model_decorations(
        context, view_range, only_minimap, only_margin,
      )
    },
  }
  {
    computer: InlineModelDecorationsComputer(
      production_context, model, coordinates_converter,
    ),
    context,
  }
}

///|
fn ReferenceInlineModelDecorationsComputer::get_decorations(
  self : ReferenceInlineModelDecorationsComputer,
  view_range : @base_common.Range,
  only_minimap_decorations : Bool,
  only_margin_decorations : Bool,
) -> ViewDecorationsCollection {
  let references = (self.context.get_model_decorations)(
    view_range, only_minimap_decorations, only_margin_decorations,
  )
  let model_decorations : Array[@model.ModelDecoration] = []
  for reference in references {
    model_decorations.push(reference.decoration)
  }
  self.computer.compute_decorations(model_decorations, view_range, decoration => {
    reference_resolved_options(references, decoration)
  })
}

///|
fn ReferenceInlineModelDecorationsComputer::get_inline_decorations(
  self : ReferenceInlineModelDecorationsComputer,
  model_line_number : Int32,
) -> Array[Array[InlineDecoration]] {
  self.computer.get_inline_decorations(model_line_number)
}

///|
fn ReferenceInlineModelDecorationsComputer::reset(
  self : ReferenceInlineModelDecorationsComputer,
) -> Unit {
  self.computer.reset()
}

///|
/// Per-line, per-decoration `InlineDecoration` equality (avoids the deprecated
/// `Show`-based `assert_eq` on nested arrays while keeping per-element detail).
fn assert_inline_eq(
  actual : Array[Array[InlineDecoration]],
  expected : Array[Array[InlineDecoration]],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i].length(), expected[i].length())
    for j in 0..<expected[i].length() {
      assert_true(actual[i][j] == expected[i][j])
    }
  }
}

///|
fn assert_bool_array_eq(
  actual : Array[Bool],
  expected : Array[Bool],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i], expected[i])
  }
}

// ---- suite('InlineModelDecorationsComputer') ----

///|
test "no decorations" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) { [] },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_eq(result.decorations.length(), 0)
  assert_inline_eq(result.inline_decorations, [[]])
  assert_bool_array_eq(result.has_variable_fonts, [false])
}

///|
test "inline class name decoration on a single line" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 1, 1, 6),
          ModelDecorationOptions(
            description="test",
            inline_class_name="test-class",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_eq(result.decorations.length(), 1)
  assert_inline_eq(result.inline_decorations, [
    [InlineDecoration(Range(1, 1, 1, 6), "test-class", Regular)],
  ])
  assert_bool_array_eq(result.has_variable_fonts, [false])
}

///|
test "inlineClassName with affectsLetterSpacing" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 1, 1, 6),
          ModelDecorationOptions(
            description="test",
            inline_class_name="test-class",
            inline_class_name_affects_letter_spacing=true,
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_inline_eq(result.inline_decorations, [
    [
      InlineDecoration(
        Range(1, 1, 1, 6),
        "test-class",
        RegularAffectingLetterSpacing,
      ),
    ],
  ])
}

///|
test "beforeContentClassName decoration" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 3, 1, 8),
          ModelDecorationOptions(
            description="test",
            before_content_class_name="before-class",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_inline_eq(result.inline_decorations, [
    [InlineDecoration(Range(1, 3, 1, 3), "before-class", Before)],
  ])
}

///|
test "afterContentClassName decoration" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 3, 1, 8),
          ModelDecorationOptions(
            description="test",
            after_content_class_name="after-class",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_inline_eq(result.inline_decorations, [
    [InlineDecoration(Range(1, 8, 1, 8), "after-class", After)],
  ])
}

///|
test "all decoration types combined" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 2, 1, 6),
          ModelDecorationOptions(
            description="test",
            inline_class_name="inline-class",
            before_content_class_name="before-class",
            after_content_class_name="after-class",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_inline_eq(result.inline_decorations, [
    [
      InlineDecoration(Range(1, 2, 1, 6), "inline-class", Regular),
      InlineDecoration(Range(1, 2, 1, 2), "before-class", Before),
      InlineDecoration(Range(1, 6, 1, 6), "after-class", After),
    ],
  ])
}

///|
test "decoration spanning multiple lines" {
  let model = TestTextModel::create(
    (
      #|line one
      #|line two
      #|line three
    ),
  )
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 3, 3, 5),
          ModelDecorationOptions(
            description="test",
            inline_class_name="multi-line",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 3, 11), false, false)
  let expected = InlineDecoration(Range(1, 3, 3, 5), "multi-line", Regular)
  assert_inline_eq(result.inline_decorations, [
    [expected],
    [expected],
    [expected],
  ])
}

///|
test "decoration with affectsFont sets hasVariableFonts" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 1, 1, 6),
          ModelDecorationOptions(
            description="test",
            inline_class_name="font-class",
            affects_font=true,
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_bool_array_eq(result.has_variable_fonts, [true])
}

///|
test "multiple decorations on different lines" {
  let model = TestTextModel::create("line one\nline two")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 1, 1, 5),
          ModelDecorationOptions(
            description="test",
            inline_class_name="class-a",
          ),
        ),
        create_model_decoration(
          "dec2",
          Range(2, 1, 2, 5),
          ModelDecorationOptions(
            description="test",
            inline_class_name="class-b",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_decorations(Range(1, 1, 2, 9), false, false)
  assert_inline_eq(result.inline_decorations, [
    [InlineDecoration(Range(1, 1, 1, 5), "class-a", Regular)],
    [InlineDecoration(Range(2, 1, 2, 5), "class-b", Regular)],
  ])
}

///|
test "decoration cache is used for same decoration id" {
  let model = TestTextModel::create("hello world")
  let dec = create_model_decoration(
    "dec1",
    Range(1, 1, 1, 6),
    ModelDecorationOptions(description="test", inline_class_name="test-class"),
  )
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) { [dec] },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result1 = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  let result2 = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_true(physical_equal(result1.decorations[0], result2.decorations[0]))
}

///|
test "reset clears decoration cache" {
  let model = TestTextModel::create("hello world")
  let dec = create_model_decoration(
    "dec1",
    Range(1, 1, 1, 6),
    ModelDecorationOptions(description="test", inline_class_name="test-class"),
  )
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) { [dec] },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result1 = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  computer.reset()
  let result2 = computer.get_decorations(Range(1, 1, 1, 12), false, false)
  assert_false(physical_equal(result1.decorations[0], result2.decorations[0]))
}

///|
test "getInlineDecorations returns inline decorations for a model line" {
  let model = TestTextModel::create("hello world")
  let context : ReferenceInlineModelContext = {
    get_model_decorations: fn(_view_range, _a, _b) {
      [
        create_model_decoration(
          "dec1",
          Range(1, 1, 1, 6),
          ModelDecorationOptions(
            description="test",
            inline_class_name="test-class",
          ),
        ),
      ]
    },
  }
  let computer = ReferenceInlineModelDecorationsComputer::ReferenceInlineModelDecorationsComputer(
    context, model,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [
    [InlineDecoration(Range(1, 1, 1, 6), "test-class", Regular)],
  ])
}

// ---- suite('InjectedTextInlineDecorationsComputer') ----

///|
test "no injections returns empty" {
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) -> Array[ResolvedInjectedTextOptions]? {
      None
    },
    get_injection_offsets: fn(_l) -> Array[Int32]? { None },
    get_break_offsets: fn(_l) { [10] },
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [])
}

///|
test "single injection with inlineClassName on a single output line" {
  let injection_options = [
    ResolvedInjectedTextOptions(
      content="injected",
      inline_class_name="injected-class",
    ),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([5]) },
    get_break_offsets: fn(_l) { [18] }, // 10 (original) + 8 (injected)
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [
    [InlineDecoration(Range(1, 6, 1, 14), "injected-class", Regular)],
  ])
}

///|
test "injection without inlineClassName produces no inline decorations" {
  let injection_options = [ResolvedInjectedTextOptions(content="injected")]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([5]) },
    get_break_offsets: fn(_l) { [18] },
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [[]]) // empty - no inlineClassName
}

///|
test "injection with inlineClassNameAffectsLetterSpacing" {
  let injection_options = [
    ResolvedInjectedTextOptions(
      content="abc",
      inline_class_name="ls-class",
      inline_class_name_affects_letter_spacing=true,
    ),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([0]) },
    get_break_offsets: fn(_l) { [13] }, // 10 + 3
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [
    [
      InlineDecoration(
        Range(1, 1, 1, 4),
        "ls-class",
        RegularAffectingLetterSpacing,
      ),
    ],
  ])
}

///|
test "multiple injections on a single output line" {
  let injection_options = [
    ResolvedInjectedTextOptions(content="AA", inline_class_name="class-a"),
    ResolvedInjectedTextOptions(content="BBB", inline_class_name="class-b"),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([2, 5]) },
    get_break_offsets: fn(_l) { [15] }, // 10 + 2 + 3
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [
    [
      InlineDecoration(Range(1, 3, 1, 5), "class-a", Regular),
      InlineDecoration(Range(1, 8, 1, 11), "class-b", Regular),
    ],
  ])
}

///|
test "injection spanning across wrapped lines" {
  // Original text is 20 chars, injection of 10 chars at offset 8.
  // Break offsets split at 15 and 30 (two wrapped lines).
  let injection_options = [
    ResolvedInjectedTextOptions(
      content="1234567890",
      inline_class_name="injected",
    ),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([8]) },
    get_break_offsets: fn(_l) { [15, 30] },
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 5 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  // Injected text starts at offset 8 in the input with injections.
  // Line 0: [0, 15), injected text occupies [8, 18) -> clipped to [8, 15)
  // Line 1: [15, 30), injected text occupies [8, 18) -> clipped to [15, 18) -> [0, 3)
  assert_inline_eq(result, [
    [InlineDecoration(Range(5, 9, 5, 16), "injected", Regular)],
    [InlineDecoration(Range(6, 1, 6, 4), "injected", Regular)],
  ])
}

///|
test "injection with wrappedTextIndentLength on wrapped lines" {
  let injection_options = [
    ResolvedInjectedTextOptions(
      content="12345678901234567890",
      inline_class_name="injected",
    ),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([0]) },
    get_break_offsets: fn(_l) { [15, 30] },
    get_wrapped_text_indent_length: fn(_l) { 4 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  // Line 0 (outputLineIndex 0): no offset, start=0, end=15 -> columns 1 to 16
  // Line 1 (outputLineIndex 1): wrappedTextIndentLength=4, start=4, end=9 -> columns 5 to 10
  assert_inline_eq(result, [
    [InlineDecoration(Range(1, 1, 1, 16), "injected", Regular)],
    [InlineDecoration(Range(2, 5, 2, 10), "injected", Regular)],
  ])
}

///|
test "injection starting in later wrapped line" {
  // Injection at offset 20 which is past the first line break.
  let injection_options = [
    ResolvedInjectedTextOptions(content="ab", inline_class_name="late-class"),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([20]) },
    get_break_offsets: fn(_l) { [15, 32] }, // 30 + 2
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 1 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  // Line 0: [0, 15) -> injection at offset 20 is past this line -> empty
  // Line 1: [15, 32) -> injection at offset 20 -> start=5, end=7 -> columns 6 to 8
  assert_inline_eq(result, [
    [],
    [InlineDecoration(Range(2, 6, 2, 8), "late-class", Regular)],
  ])
}

///|
test "base view line number offsets correctly" {
  let injection_options = [
    ResolvedInjectedTextOptions(content="test", inline_class_name="test-class"),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([0]) },
    get_break_offsets: fn(_l) { [14] },
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { 10 },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(1)
  assert_inline_eq(result, [
    [InlineDecoration(Range(10, 1, 10, 5), "test-class", Regular)],
  ])
}

///|
test "range uses view line number, not model line number" {
  // Model line 3 maps to view line 7 (e.g. due to previous lines wrapping).
  // The range in the resulting InlineDecoration must use the view line number.
  let model_line_number = 3
  let base_view_line_number = 7
  let injection_options = [
    ResolvedInjectedTextOptions(
      content="ghost",
      inline_class_name="ghost-class",
    ),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([0]) },
    get_break_offsets: fn(_l) { [15] }, // 10 (original) + 5 (injected)
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { base_view_line_number },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(model_line_number)
  // The range must reference view line 7, not model line 3.
  assert_inline_eq(result, [
    [InlineDecoration(Range(7, 1, 7, 6), "ghost-class", Regular)],
  ])
}

///|
test "range uses view line number on wrapped lines, not model line number" {
  // Model line 2 wraps into view lines 5 and 6.
  let model_line_number = 2
  let base_view_line_number = 5
  let injection_options = [
    ResolvedInjectedTextOptions(
      content="1234567890",
      inline_class_name="wrap-class",
    ),
  ]
  let context : InjectedTextInlineDecorationsComputerContext = {
    get_injection_options: fn(_l) { Some(injection_options) },
    get_injection_offsets: fn(_l) { Some([0]) },
    get_break_offsets: fn(_l) { [8, 20] },
    get_wrapped_text_indent_length: fn(_l) { 0 },
    get_base_view_line_number: fn(_l) { base_view_line_number },
  }
  let computer = InjectedTextInlineDecorationsComputer::InjectedTextInlineDecorationsComputer(
    context,
  )
  let result = computer.get_inline_decorations(model_line_number)
  // First wrapped line uses view line 5, second uses view line 6.
  assert_inline_eq(result, [
    [InlineDecoration(Range(5, 1, 5, 9), "wrap-class", Regular)],
    [InlineDecoration(Range(6, 1, 6, 3), "wrap-class", Regular)],
  ])
}
