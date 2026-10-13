// PositionAffinity conformance matrix (deviations-closeout Track B):
// boundary behavior of `translateToOutputPosition`,
// `normalizeOutputPosition`, and `convertModelRangeToViewRange`
// (`modelLineProjectionData.ts:111-192`, `viewModelLines.ts:892-901`) at
// injected-text anchors and soft-wrap breaks.

///|
/// Injections are written as `after` decorations on a backing model;
/// `(column, content)` pairs use 1-based model columns.
fn affinity_view_model(
  text : String,
  injections : Array[(Int32, String)],
  soft_wrap_column~ : Int32,
) -> @view_model.ViewModel {
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/affinity-test.mbt",
    ),
    "affinity-test.mbt",
    "moonbit",
    1,
    "rev-1",
    text,
  )
  let decorations : Array[@model.ModelDeltaDecoration] = []
  for index in 0..<injections.length() {
    let (column, content) = injections[index]
    decorations.push({
      range: Range(1, column, 1, column),
      options: ModelDecorationOptions(
        "",
        description="position-affinity injection",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          content,
          inline_class_name="position-affinity-injection",
          attached_index=index,
        ),
      ),
    })
  }
  model.delta_decorations([], decorations) |> ignore
  register_plain_moonbit()
  @view_model.ViewModel::with_options(
    model,
    ViewModelOptions(soft_wrap_column~),
  )
}

///|
fn view_of(
  vm : @view_model.ViewModel,
  line : Int32,
  column : Int32,
  affinity? : @model.PositionAffinity,
) -> String {
  let converter = vm.coordinates_converter()
  let position = converter.model_position_to_view_position(
    Position(line, column),
    affinity?,
  )
  "\{position.line_number}:\{position.column}"
}

///|
fn normalized(
  vm : @view_model.ViewModel,
  line : Int32,
  column : Int32,
  affinity : @model.PositionAffinity,
) -> String {
  let position = vm.normalize_position(Position(line, column), affinity)
  "\{position.line_number}:\{position.column}"
}

///|
/// Two injections share the anchor at offset 2 of `abcdef` (positions are
/// 1-based; `bucket_injected_text` converts), projecting to `abXXYYcdef` —
/// the `Right` walks must cross both touching injections.
fn injected_view_model() -> @view_model.ViewModel {
  affinity_view_model("abcdef", [(3, "XX"), (3, "YY")], soft_wrap_column=0)
}

///|
test "translate at an injected-text anchor: only Right crosses the injections" {
  let vm = injected_view_model()
  // Model column 3 (offset 2) is the anchor of both injections.
  inspect(view_of(vm, 1, 3), content="1:3")
  inspect(view_of(vm, 1, 3, affinity=Left), content="1:3")
  inspect(view_of(vm, 1, 3, affinity=LeftOfInjectedText), content="1:3")
  inspect(view_of(vm, 1, 3, affinity=RightOfInjectedText), content="1:3")
  inspect(view_of(vm, 1, 3, affinity=Right), content="1:7")
}

///|
test "translate mid-token ignores affinity" {
  let vm = injected_view_model()
  inspect(view_of(vm, 1, 2), content="1:2")
  inspect(view_of(vm, 1, 2, affinity=Left), content="1:2")
  inspect(view_of(vm, 1, 2, affinity=Right), content="1:2")
  inspect(view_of(vm, 1, 2, affinity=LeftOfInjectedText), content="1:2")
  inspect(view_of(vm, 1, 2, affinity=RightOfInjectedText), content="1:2")
}

///|
test "normalize snaps positions inside injected text per affinity" {
  let vm = injected_view_model()
  // View column 4 sits strictly inside the first injection (`abXX…`).
  inspect(normalized(vm, 1, 4, None), content="1:3")
  inspect(normalized(vm, 1, 4, Left), content="1:3")
  inspect(normalized(vm, 1, 4, LeftOfInjectedText), content="1:3")
  inspect(normalized(vm, 1, 4, Right), content="1:7")
  inspect(normalized(vm, 1, 4, RightOfInjectedText), content="1:7")
  // View column 5 is the boundary between the two touching injections: a cursor
  // stop for `None` (`InjectedTextCursorStops.Both`), still crossed by
  // Left/Right.
  inspect(normalized(vm, 1, 5, None), content="1:5")
  inspect(normalized(vm, 1, 5, Left), content="1:3")
  inspect(normalized(vm, 1, 5, Right), content="1:7")
  // Mid-token positions never move.
  inspect(normalized(vm, 1, 2, None), content="1:2")
  inspect(normalized(vm, 1, 2, Left), content="1:2")
  inspect(normalized(vm, 1, 2, Right), content="1:2")
}

///|
test "translate at a soft-wrap break: only Left stays on the earlier line" {
  let vm = affinity_view_model("abcdefgh", [], soft_wrap_column=4)
  // Model column 5 (offset 4) is the break between `abcd` and `efgh`.
  inspect(view_of(vm, 1, 5), content="2:1")
  inspect(view_of(vm, 1, 5, affinity=Right), content="2:1")
  inspect(view_of(vm, 1, 5, affinity=LeftOfInjectedText), content="2:1")
  inspect(view_of(vm, 1, 5, affinity=RightOfInjectedText), content="2:1")
  inspect(view_of(vm, 1, 5, affinity=Left), content="1:5")
}

///|
test "normalize snaps wrap boundaries per affinity" {
  let vm = affinity_view_model("abcdefgh", [], soft_wrap_column=4)
  inspect(normalized(vm, 2, 1, Left), content="1:5")
  inspect(normalized(vm, 2, 1, None), content="2:1")
  inspect(normalized(vm, 2, 1, Right), content="2:1")
  inspect(normalized(vm, 1, 5, Right), content="2:1")
  inspect(normalized(vm, 1, 5, None), content="1:5")
  inspect(normalized(vm, 1, 5, Left), content="1:5")
}

///|
test "range conversion: non-empty ranges exclude injected text at the edges" {
  let vm = injected_view_model()
  let converter = vm.coordinates_converter()
  // Start at the injection anchor converts with `Right` (past both), end
  // mid-source with `Left` (`viewModelLines.ts:897-899`).
  let view_range = converter.model_range_to_view_range(Range(1, 3, 1, 7))
  inspect(
    "\{view_range.start_line_number}:\{view_range.start_column}-\{view_range.end_line_number}:\{view_range.end_column}",
    content="1:7-1:11",
  )
}

///|
test "range conversion: empty ranges default to Left at a wrap break" {
  let vm = affinity_view_model("abcdefgh", [], soft_wrap_column=4)
  let converter = vm.coordinates_converter()
  let view_range = converter.model_range_to_view_range(Range(1, 5, 1, 5))
  inspect(
    "\{view_range.start_line_number}:\{view_range.start_column}-\{view_range.end_line_number}:\{view_range.end_column}",
    content="1:5-1:5",
  )
  let right = converter.model_range_to_view_range(
    Range(1, 5, 1, 5),
    affinity=Right,
  )
  inspect(
    "\{right.start_line_number}:\{right.start_column}-\{right.end_line_number}:\{right.end_column}",
    content="2:1-2:1",
  )
}
