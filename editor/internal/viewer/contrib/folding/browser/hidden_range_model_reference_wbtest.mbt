// Conformance port of Monaco/VS Code's Hidden Range Model suite.
//
// Ports: vscode/src/vs/editor/contrib/folding/test/browser/hiddenRangeModel.test.ts
// From the checked-in vscode submodule.

///|
fn assert_hidden_ranges(
  actual : Array[@base_common.Range],
  expected : Array[(Int, Int)],
  message : String,
) -> Unit raise {
  let mapped = actual.map(r => (r.start_line_number, r.end_line_number))
  if mapped != expected {
    fail("\{message}: \{Repr(mapped)} != \{Repr(expected)}")
  }
}

///|
test "hasRanges" {
  let text_model = folding_test_model([
    "/**", " * Comment", " */", "class A {", "  void foo() {", "    if (true) {",
    "      //hello", "    }", "  }", "}",
  ])
  let folding_model = FoldingModel(
    text_model,
    TestDecorationProvider::{ model: text_model }.access(),
  )
  let hidden_range_model = HiddenRangeModel(folding_model)
  assert_false(hidden_range_model.has_ranges())
  let ranges = compute_ranges(text_model, false)
  folding_model.update(ranges)
  guard folding_model.get_region_at_line(1) is Some(region1)
  guard folding_model.get_region_at_line(6) is Some(region6)
  folding_model.toggle_collapse_state([region1, region6])
  assert_hidden_ranges(
    hidden_range_model.hidden_ranges(),
    [(2, 3), (7, 7)],
    "1",
  )
  assert_true(hidden_range_model.has_ranges())
  assert_false(hidden_range_model.is_hidden(1))
  assert_true(hidden_range_model.is_hidden(2))
  assert_true(hidden_range_model.is_hidden(3))
  assert_false(hidden_range_model.is_hidden(4))
  assert_false(hidden_range_model.is_hidden(5))
  assert_false(hidden_range_model.is_hidden(6))
  assert_true(hidden_range_model.is_hidden(7))
  assert_false(hidden_range_model.is_hidden(8))
  assert_false(hidden_range_model.is_hidden(9))
  assert_false(hidden_range_model.is_hidden(10))
  guard folding_model.get_region_at_line(4) is Some(region4)
  folding_model.toggle_collapse_state([region4])
  assert_hidden_ranges(
    hidden_range_model.hidden_ranges(),
    [(2, 3), (5, 9)],
    "2",
  )
  assert_true(hidden_range_model.has_ranges())
  assert_false(hidden_range_model.is_hidden(1))
  assert_true(hidden_range_model.is_hidden(2))
  assert_true(hidden_range_model.is_hidden(3))
  assert_false(hidden_range_model.is_hidden(4))
  assert_true(hidden_range_model.is_hidden(5))
  assert_true(hidden_range_model.is_hidden(6))
  assert_true(hidden_range_model.is_hidden(7))
  assert_true(hidden_range_model.is_hidden(8))
  assert_true(hidden_range_model.is_hidden(9))
  assert_false(hidden_range_model.is_hidden(10))
  guard folding_model.get_region_at_line(1) is Some(region1b)
  guard folding_model.get_region_at_line(6) is Some(region6b)
  guard folding_model.get_region_at_line(4) is Some(region4b)
  folding_model.toggle_collapse_state([region1b, region6b, region4b])
  assert_hidden_ranges(hidden_range_model.hidden_ranges(), [], "3")
  assert_false(hidden_range_model.has_ranges())
  for line in 1..<=10 {
    assert_false(hidden_range_model.is_hidden(line))
  }
  hidden_range_model.dispose()
}

///|
test "adjustSelections moves endpoints out of hidden ranges" {
  let text_model = folding_test_model([
    "/**", " * Comment", " */", "class A {", "  void foo() {", "    if (true) {",
    "      //hello", "    }", "  }", "}",
  ])
  let folding_model = FoldingModel(
    text_model,
    TestDecorationProvider::{ model: text_model }.access(),
  )
  let hidden_range_model = HiddenRangeModel(folding_model)
  folding_model.update(compute_ranges(text_model, false))
  guard folding_model.get_region_at_line(1) is Some(region1)
  folding_model.toggle_collapse_state([region1])
  assert_hidden_ranges(hidden_range_model.hidden_ranges(), [(2, 3)], "hidden")
  // A caret on hidden line 2 snaps to the fold header's end (line 1).
  let selections = [
    @core.Selection::from_positions(Position(2, 4), Position(2, 4)),
    @core.Selection::from_positions(Position(5, 1), Position(5, 1)),
  ]
  assert_true(hidden_range_model.adjust_selections(selections))
  debug_inspect(
    selections[0],
    content=(
      #|{
      #|  selection_start: { line_number: 1, column: 4 },
      #|  position: { line_number: 1, column: 4 },
      #|}
    ),
  )
  // The visible selection is untouched.
  debug_inspect(
    selections[1],
    content=(
      #|{
      #|  selection_start: { line_number: 5, column: 1 },
      #|  position: { line_number: 5, column: 1 },
      #|}
    ),
  )
}
