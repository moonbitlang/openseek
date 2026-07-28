// Conformance port of Monaco/VS Code's Folding Model suite.
//
// Ports: vscode/src/vs/editor/contrib/folding/test/browser/foldingModel.test.ts
// From the checked-in vscode submodule.
//
// Skipped cases: `update` and `delete` edit the backing model
// (`applyEdits`) — the viewer's `TextModel` is readonly. The suite's
// `RegExp` markers become predicates like the indent-provider suite's.

///|
let test_collapsed_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="test-collapsed",
  stickiness=NeverGrowsWhenTypingAtEdges,
  lines_decorations_class_name="folding",
)

///|
let test_expanded_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="test-expanded",
  stickiness=NeverGrowsWhenTypingAtEdges,
  lines_decorations_class_name="folding",
)

///|
let test_hidden_decoration : @model.ModelDecorationOptions = ModelDecorationOptions(
  "",
  description="test-hidden",
  stickiness=NeverGrowsWhenTypingAtEdges,
  lines_decorations_class_name="folding",
)

///|
/// The suite's `TestDecorationProvider`, distinguishing its three options by
/// description (the source compares object identity).
priv struct TestDecorationProvider {
  model : @model.TextModel
}

///|
fn TestDecorationProvider::get_decoration_option(
  _self : TestDecorationProvider,
  is_collapsed : Bool,
  is_hidden : Bool,
  _is_manual : Bool,
) -> @model.ModelDecorationOptions {
  if is_hidden {
    test_hidden_decoration
  } else if is_collapsed {
    test_collapsed_decoration
  } else {
    test_expanded_decoration
  }
}

///|
fn TestDecorationProvider::change_decorations(
  self : TestDecorationProvider,
  callback : (@model.ModelDecorationsChangeAccessor) -> Unit,
) -> Unit {
  self.model.change_decorations(callback)
}

///|
fn TestDecorationProvider::remove_decorations(
  self : TestDecorationProvider,
  decoration_ids : Array[String],
) -> Unit {
  self.model.change_decorations(accessor => {
    ignore((accessor.delta_decorations)(decoration_ids, []))
  })
}

///|
fn TestDecorationProvider::access(
  self : TestDecorationProvider,
) -> FoldingDecorationAccess {
  FoldingDecorationAccess::new(
    (is_collapsed, is_hidden, is_manual) => {
      self.get_decoration_option(is_collapsed, is_hidden, is_manual)
    },
    callback => self.change_decorations(callback),
    decoration_ids => self.remove_decorations(decoration_ids),
  )
}

///|
/// `(line, type)` pairs of the provider's live decorations, by position.
fn TestDecorationProvider::get_decorations(
  self : TestDecorationProvider,
) -> Array[(Int, String)] {
  let res : Array[(Int, String)] = []
  for decoration in self.model.get_all_decorations() {
    match decoration.options.description {
      "test-hidden" => res.push((decoration.range.start_line_number, "hidden"))
      "test-collapsed" =>
        res.push((decoration.range.start_line_number, "collapsed"))
      "test-expanded" =>
        res.push((decoration.range.start_line_number, "expanded"))
      _ => ()
    }
  }
  res.sort_by((a, b) => a.0 - b.0)
  res
}

///|
/// The suite's exact `//#region` markers (`/^\/\/#region$/`).
fn slash_region_markers() -> @languages.FoldingMarkers {
  { start: line => line == "//#region", end: line => line == "//#endregion" }
}

///|
/// `/^\s*<rest>$/`: optional leading whitespace, then exactly `rest`.
fn ws_then_exact(rest : String) -> (String) -> Bool {
  line => {
    let mut i = 0
    while i < line.length() && (line[i] == ' ' || line[i] == '\t') {
      i += 1
    }
    line.length() - i == rest.length() &&
    ({
      for j in 0..<rest.length() {
        if line[i + j] != rest[j] {
          return false
        }
      }
      true
    })
  }
}

///|
/// The suite's `assertRanges`/`assertRegion` region literal: (start, end,
/// isCollapsed).
fn assert_model_ranges(
  folding_model : FoldingModel,
  expected : Array[(Int, Int, Bool)],
  message : String,
) -> Unit raise {
  let actual_ranges : Array[(Int, Int, Bool)] = []
  let actual = folding_model.regions()
  for i in 0..<actual.length() {
    actual_ranges.push(
      (
        actual.get_start_line_number(i),
        actual.get_end_line_number(i),
        actual.is_collapsed(i),
      ),
    )
  }
  if actual_ranges != expected {
    fail("\{message}: \{Repr(actual_ranges)} != \{Repr(expected)}")
  }
}

///|
/// The suite's `assertFoldedRanges` (collapsed regions only, as
/// (start, end)).
fn assert_folded_ranges(
  folding_model : FoldingModel,
  expected : Array[(Int, Int)],
  message : String,
) -> Unit raise {
  let actual_ranges : Array[(Int, Int)] = []
  let actual = folding_model.regions()
  for i in 0..<actual.length() {
    if actual.is_collapsed(i) {
      actual_ranges.push(
        (actual.get_start_line_number(i), actual.get_end_line_number(i)),
      )
    }
  }
  if actual_ranges != expected {
    fail("\{message}: \{Repr(actual_ranges)} != \{Repr(expected)}")
  }
}

///|
/// The suite's `assertRegions` over a region list.
fn assert_regions_list(
  actual : Array[FoldingRegion],
  expected : Array[(Int, Int, Bool)],
  message : String,
) -> Unit raise {
  let mapped = actual.map(r => {
    (r.start_line_number(), r.end_line_number(), r.is_collapsed())
  })
  if mapped != expected {
    fail("\{message}: \{Repr(mapped)} != \{Repr(expected)}")
  }
}

///|
/// The suite's `assertRegion` over an optional region.
fn assert_region_opt(
  actual : FoldingRegion?,
  expected : (Int, Int, Bool)?,
  message : String,
) -> Unit raise {
  match (actual, expected) {
    (None, None) => ()
    (Some(region), Some(expected)) => {
      let got = (
        region.start_line_number(),
        region.end_line_number(),
        region.is_collapsed(),
      )
      if got != expected {
        fail("\{message}: \{Repr(got)} != \{Repr(expected)}")
      }
    }
    _ => fail("\{message}: presence mismatch")
  }
}

///|
fn test_folding_model(
  lines : Array[String],
  markers? : @languages.FoldingMarkers,
) -> FoldingModel {
  let text_model = folding_test_model(lines)
  let folding_model = FoldingModel(
    text_model,
    TestDecorationProvider::{ model: text_model }.access(),
  )
  let ranges = compute_ranges(text_model, false, markers?)
  folding_model.update(ranges)
  folding_model
}

///|
test "getRegionAtLine" {
  let folding_model = test_folding_model([
    "/**", " * Comment", " */", "class A {", "  void foo() {", "    // comment {",
    "  }", "}",
  ])
  let r1 = (1, 3, false)
  let r2 = (4, 7, false)
  let r3 = (5, 6, false)
  assert_model_ranges(folding_model, [r1, r2, r3], "ranges")
  assert_region_opt(folding_model.get_region_at_line(1), Some(r1), "1")
  assert_region_opt(folding_model.get_region_at_line(2), Some(r1), "2")
  assert_region_opt(folding_model.get_region_at_line(3), Some(r1), "3")
  assert_region_opt(folding_model.get_region_at_line(4), Some(r2), "4")
  assert_region_opt(folding_model.get_region_at_line(5), Some(r3), "5")
  assert_region_opt(folding_model.get_region_at_line(6), Some(r3), "5")
  assert_region_opt(folding_model.get_region_at_line(7), Some(r2), "6")
  assert_region_opt(folding_model.get_region_at_line(8), None, "7")
}

///|
test "collapse" {
  let text_model = folding_test_model([
    "/**", " * Comment", " */", "class A {", "  void foo() {", "    // comment {",
    "  }", "}",
  ])
  let folding_model = FoldingModel(
    text_model,
    TestDecorationProvider::{ model: text_model }.access(),
  )
  let ranges = compute_ranges(text_model, false)
  folding_model.update(ranges)
  let r1 = (1, 3, false)
  let r2 = (4, 7, false)
  let r3 = (5, 6, false)
  assert_model_ranges(folding_model, [r1, r2, r3], "initial")
  guard folding_model.get_region_at_line(1) is Some(region1)
  folding_model.toggle_collapse_state([region1])
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [(1, 3, true), r2, r3], "1")
  guard folding_model.get_region_at_line(5) is Some(region5)
  folding_model.toggle_collapse_state([region5])
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [(1, 3, true), r2, (5, 6, true)], "2")
  guard folding_model.get_region_at_line(7) is Some(region7)
  folding_model.toggle_collapse_state([region7])
  folding_model.update(ranges)
  assert_model_ranges(
    folding_model,
    [(1, 3, true), (4, 7, true), (5, 6, true)],
    "3",
  )
}

///|
test "getRegionsInside" {
  let folding_model = test_folding_model([
    "/**", " * Comment", " */", "class A {", "  void foo() {", "    // comment {",
    "  }", "}",
  ])
  let r1 = (1, 3, false)
  let r2 = (4, 7, false)
  let r3 = (5, 6, false)
  assert_model_ranges(folding_model, [r1, r2, r3], "ranges")
  let region1 = folding_model.get_region_at_line(1)
  let region2 = folding_model.get_region_at_line(4)
  let region3 = folding_model.get_region_at_line(5)
  assert_regions_list(folding_model.get_regions_inside(None), [r1, r2, r3], "1")
  assert_regions_list(folding_model.get_regions_inside(region1), [], "2")
  assert_regions_list(folding_model.get_regions_inside(region2), [r3], "3")
  assert_regions_list(folding_model.get_regions_inside(region3), [], "4")
}

///|
test "getRegionsInsideWithLevel" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "    if (true) {", "      return;", "    }", "  }",
      "}",
    ],
    markers=slash_region_markers(),
  )
  let r1 = (1, 2, false)
  let r2 = (3, 11, false)
  let r3 = (4, 10, false)
  let r4 = (5, 6, false)
  let r5 = (8, 9, false)
  let region1 = folding_model.get_region_at_line(1)
  let region2 = folding_model.get_region_at_line(3)
  let region3 = folding_model.get_region_at_line(4)
  assert_model_ranges(folding_model, [r1, r2, r3, r4, r5], "ranges")
  assert_regions_list(
    folding_model.get_regions_inside(
      None,
      filter=RegionFilterWithLevel((_r, level) => level == 1),
    ),
    [r1, r2],
    "1",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      None,
      filter=RegionFilterWithLevel((_r, level) => level == 2),
    ),
    [r3],
    "2",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      None,
      filter=RegionFilterWithLevel((_r, level) => level == 3),
    ),
    [r4, r5],
    "3",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      region2,
      filter=RegionFilterWithLevel((_r, level) => level == 1),
    ),
    [r3],
    "4",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      region2,
      filter=RegionFilterWithLevel((_r, level) => level == 2),
    ),
    [r4, r5],
    "5",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      region3,
      filter=RegionFilterWithLevel((_r, level) => level == 1),
    ),
    [r4, r5],
    "6",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      region2,
      filter=RegionFilterWithLevel((r, _level) => r.hides_line(9)),
    ),
    [r3, r5],
    "7",
  )
  assert_regions_list(
    folding_model.get_regions_inside(
      region1,
      filter=RegionFilterWithLevel((_r, level) => level == 1),
    ),
    [],
    "8",
  )
}

///|
test "getRegionAtLine2" {
  let folding_model = test_folding_model(
    [
      "//#region", "class A {", "  void foo() {", "    if (true) {", "      //hello",
      "    }", "", "  }", "}", "//#endregion", "",
    ],
    markers=slash_region_markers(),
  )
  let r1 = (1, 10, false)
  let r2 = (2, 8, false)
  let r3 = (3, 7, false)
  let r4 = (4, 5, false)
  assert_model_ranges(folding_model, [r1, r2, r3, r4], "ranges")
  assert_regions_list(folding_model.get_all_regions_at_line(1), [r1], "1")
  assert_regions_list(folding_model.get_all_regions_at_line(2), [r2, r1], "2")
  assert_regions_list(
    folding_model.get_all_regions_at_line(3),
    [r3, r2, r1],
    "3",
  )
  assert_regions_list(
    folding_model.get_all_regions_at_line(4),
    [r4, r3, r2, r1],
    "4",
  )
  assert_regions_list(
    folding_model.get_all_regions_at_line(5),
    [r4, r3, r2, r1],
    "5",
  )
  assert_regions_list(
    folding_model.get_all_regions_at_line(6),
    [r3, r2, r1],
    "6",
  )
  assert_regions_list(
    folding_model.get_all_regions_at_line(7),
    [r3, r2, r1],
    "7",
  )
  assert_regions_list(folding_model.get_all_regions_at_line(8), [r2, r1], "8")
  assert_regions_list(folding_model.get_all_regions_at_line(9), [r1], "9")
  assert_regions_list(folding_model.get_all_regions_at_line(10), [r1], "10")
  assert_regions_list(folding_model.get_all_regions_at_line(11), [], "10")
}

///|
test "setCollapseStateRecursivly" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "", "    if (true) {", "      return;", "    }",
      "  }", "}",
    ],
    markers=slash_region_markers(),
  )
  let r1 = (1, 2)
  let r2 = (3, 12)
  let r3 = (4, 11)
  let r4 = (5, 6)
  let r5 = (9, 10)
  assert_model_ranges(
    folding_model,
    [
      (1, 2, false),
      (3, 12, false),
      (4, 11, false),
      (5, 6, false),
      (9, 10, false),
    ],
    "ranges",
  )
  set_collapse_state_levels_down(folding_model, true, line_numbers=[4])
  assert_folded_ranges(folding_model, [r3, r4, r5], "1")
  set_collapse_state_levels_down(folding_model, false, line_numbers=[8])
  assert_folded_ranges(folding_model, [], "2")
  set_collapse_state_levels_down(folding_model, true, line_numbers=[12])
  assert_folded_ranges(folding_model, [r2, r3, r4, r5], "1")
  set_collapse_state_levels_down(folding_model, false, line_numbers=[7])
  assert_folded_ranges(folding_model, [r2], "1")
  set_collapse_state_levels_down(folding_model, false)
  assert_folded_ranges(folding_model, [], "1")
  set_collapse_state_levels_down(folding_model, true)
  assert_folded_ranges(folding_model, [r1, r2, r3, r4, r5], "1")
}

///|
test "setCollapseStateAtLevel" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "", "    if (true) {", "      return;", "    }",
      "  }", "  //#region", "  const bar = 9;", "  //#endregion", "}",
    ],
    markers={
      start: ws_then_exact("//#region"),
      end: ws_then_exact("//#endregion"),
    },
  )
  let r1 = (1, 2)
  let r2 = (3, 15)
  let r3 = (4, 11)
  let r4 = (5, 6)
  let r6 = (13, 15)
  assert_model_ranges(
    folding_model,
    [
      (1, 2, false),
      (3, 15, false),
      (4, 11, false),
      (5, 6, false),
      (9, 10, false),
      (13, 15, false),
    ],
    "ranges",
  )
  set_collapse_state_at_level(folding_model, 1, true, [])
  assert_folded_ranges(folding_model, [r1, r2], "1")
  set_collapse_state_at_level(folding_model, 1, false, [5])
  assert_folded_ranges(folding_model, [r2], "2")
  set_collapse_state_at_level(folding_model, 1, false, [1])
  assert_folded_ranges(folding_model, [], "3")
  set_collapse_state_at_level(folding_model, 2, true, [])
  assert_folded_ranges(folding_model, [r3, r6], "4")
  set_collapse_state_at_level(folding_model, 2, false, [5, 6])
  assert_folded_ranges(folding_model, [r3], "5")
  set_collapse_state_at_level(folding_model, 3, true, [4, 9])
  assert_folded_ranges(folding_model, [r3, r4], "6")
  set_collapse_state_at_level(folding_model, 3, false, [4, 9])
  assert_folded_ranges(folding_model, [r3], "7")
}

///|
test "setCollapseStateLevelsDown" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "", "    if (true) {", "      return;", "    }",
      "  }", "}",
    ],
    markers=slash_region_markers(),
  )
  let r1 = (1, 2)
  let r3 = (4, 11)
  let r4 = (5, 6)
  let r5 = (9, 10)
  set_collapse_state_levels_down(folding_model, true, levels=1, line_numbers=[4])
  assert_folded_ranges(folding_model, [r3], "1")
  set_collapse_state_levels_down(folding_model, true, levels=2, line_numbers=[4])
  assert_folded_ranges(folding_model, [r3, r4, r5], "2")
  set_collapse_state_levels_down(folding_model, false, levels=2, line_numbers=[
    3,
  ])
  assert_folded_ranges(folding_model, [r4, r5], "3")
  set_collapse_state_levels_down(folding_model, false, levels=2, line_numbers=[
    2,
  ])
  assert_folded_ranges(folding_model, [r4, r5], "4")
  set_collapse_state_levels_down(folding_model, true, levels=4, line_numbers=[2])
  assert_folded_ranges(folding_model, [r1, r4, r5], "5")
  set_collapse_state_levels_down(folding_model, false, levels=4, line_numbers=[
    2, 3,
  ])
  assert_folded_ranges(folding_model, [], "6")
}

///|
test "setCollapseStateLevelsUp" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "", "    if (true) {", "      return;", "    }",
      "  }", "}",
    ],
    markers=slash_region_markers(),
  )
  let r2 = (3, 12)
  let r3 = (4, 11)
  let r5 = (9, 10)
  set_collapse_state_levels_up(folding_model, true, 1, [4])
  assert_folded_ranges(folding_model, [r3], "1")
  set_collapse_state_levels_up(folding_model, true, 2, [4])
  assert_folded_ranges(folding_model, [r2, r3], "2")
  set_collapse_state_levels_up(folding_model, false, 4, [1, 3, 4])
  assert_folded_ranges(folding_model, [], "3")
  set_collapse_state_levels_up(folding_model, true, 2, [10])
  assert_folded_ranges(folding_model, [r3, r5], "4")
}

///|
test "setCollapseStateUp" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "", "    if (true) {", "      return;", "    }",
      "  }", "}",
    ],
    markers=slash_region_markers(),
  )
  let r2 = (3, 12)
  let r3 = (4, 11)
  let r4 = (5, 6)
  set_collapse_state_up(folding_model, true, [5])
  assert_folded_ranges(folding_model, [r4], "1")
  set_collapse_state_up(folding_model, true, [5])
  assert_folded_ranges(folding_model, [r3, r4], "2")
  set_collapse_state_up(folding_model, true, [4])
  assert_folded_ranges(folding_model, [r2, r3, r4], "2")
}

///|
test "setCollapseStateForMatchingLines" {
  let folding_model = test_folding_model(
    [
      "/**", " * the class", " */", "class A {", "  /**", "   * the foo", "   */",
      "  void foo() {", "    /*", "     * the comment", "     */", "  }", "}",
    ],
    markers=slash_region_markers(),
  )
  let r1 = (1, 3)
  let r3 = (5, 7)
  let r5 = (9, 11)
  assert_model_ranges(
    folding_model,
    [
      (1, 3, false),
      (4, 12, false),
      (5, 7, false),
      (8, 11, false),
      (9, 11, false),
    ],
    "ranges",
  )
  // `new RegExp('^\\s*' + escapeRegExpCharacters('/*'))`
  let reg_exp = (line : String) => {
    let mut i = 0
    while i < line.length() && (line[i] == ' ' || line[i] == '\t') {
      i += 1
    }
    i + 1 < line.length() && line[i] == '/' && line[i + 1] == '*'
  }
  set_collapse_state_for_matching_lines(folding_model, reg_exp, true)
  assert_folded_ranges(folding_model, [r1, r3, r5], "1")
}

///|
test "setCollapseStateForRest" {
  let folding_model = test_folding_model(
    [
      "//#region", "//#endregion", "class A {", "  void foo() {", "    if (true) {",
      "        return;", "    }", "", "    if (true) {", "      return;", "    }",
      "  }", "}",
    ],
    markers=slash_region_markers(),
  )
  let r1 = (1, 2)
  let r2 = (3, 12)
  let r3 = (4, 11)
  let r4 = (5, 6)
  let r5 = (9, 10)
  set_collapse_state_for_rest(folding_model, true, [5])
  assert_folded_ranges(folding_model, [r1, r5], "1")
  set_collapse_state_for_rest(folding_model, false, [5])
  assert_folded_ranges(folding_model, [], "2")
  set_collapse_state_for_rest(folding_model, true, [1])
  assert_folded_ranges(folding_model, [r2, r3, r4, r5], "3")
  set_collapse_state_for_rest(folding_model, true, [3])
  assert_folded_ranges(folding_model, [r1, r2, r3, r4, r5], "3")
}

///|
test "folding decoration" {
  let text_model = folding_test_model([
    "class A {", "  void foo() {", "    if (true) {", "      hoo();", "    }", "  }",
    "}",
  ])
  let provider = TestDecorationProvider::{ model: text_model }
  let folding_model = FoldingModel(text_model, provider.access())
  let ranges = compute_ranges(text_model, false)
  folding_model.update(ranges)
  let r1 = (1, 6, false)
  let r2 = (2, 5, false)
  let r3 = (3, 4, false)
  assert_model_ranges(folding_model, [r1, r2, r3], "initial")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "expanded"), (2, "expanded"), (3, "expanded")]
    ),
  )
  guard folding_model.get_region_at_line(2) is Some(region2)
  folding_model.toggle_collapse_state([region2])
  assert_model_ranges(folding_model, [r1, (2, 5, true), r3], "1")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "expanded"), (2, "collapsed"), (3, "hidden")]
    ),
  )
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [r1, (2, 5, true), r3], "2")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "expanded"), (2, "collapsed"), (3, "hidden")]
    ),
  )
  guard folding_model.get_region_at_line(1) is Some(region1)
  folding_model.toggle_collapse_state([region1])
  assert_model_ranges(folding_model, [(1, 6, true), (2, 5, true), r3], "3")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "collapsed"), (2, "hidden"), (3, "hidden")]
    ),
  )
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [(1, 6, true), (2, 5, true), r3], "4")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "collapsed"), (2, "hidden"), (3, "hidden")]
    ),
  )
  guard folding_model.get_region_at_line(1) is Some(region1b)
  guard folding_model.get_region_at_line(3) is Some(region3)
  folding_model.toggle_collapse_state([region1b, region3])
  assert_model_ranges(folding_model, [r1, (2, 5, true), (3, 4, true)], "5")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "expanded"), (2, "collapsed"), (3, "hidden")]
    ),
  )
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [r1, (2, 5, true), (3, 4, true)], "6")
  debug_inspect(
    provider.get_decorations(),
    content=(
      #|[(1, "expanded"), (2, "collapsed"), (3, "hidden")]
    ),
  )
}

///|
test "fold jumping" {
  let folding_model = test_folding_model([
    "class A {", "  void foo() {", "    if (1) {", "      a();", "    } else if (2) {",
    "      if (true) {", "        b();", "      }", "    } else {", "      c();",
    "    }", "  }", "}",
  ])
  assert_model_ranges(
    folding_model,
    [
      (1, 12, false),
      (2, 11, false),
      (3, 4, false),
      (5, 8, false),
      (6, 7, false),
      (9, 10, false),
    ],
    "ranges",
  )
  // Test jump to parent.
  assert_true(get_parent_fold_line(7, folding_model) is Some(6))
  assert_true(get_parent_fold_line(6, folding_model) is Some(5))
  assert_true(get_parent_fold_line(5, folding_model) is Some(2))
  assert_true(get_parent_fold_line(2, folding_model) is Some(1))
  assert_true(get_parent_fold_line(1, folding_model) is None)
  // Test jump to previous.
  assert_true(get_previous_fold_line(10, folding_model) is Some(9))
  assert_true(get_previous_fold_line(9, folding_model) is Some(5))
  assert_true(get_previous_fold_line(5, folding_model) is Some(3))
  assert_true(get_previous_fold_line(3, folding_model) is None)
  // Test when not on a folding region start line.
  assert_true(get_previous_fold_line(4, folding_model) is Some(3))
  assert_true(get_previous_fold_line(7, folding_model) is Some(6))
  assert_true(get_previous_fold_line(8, folding_model) is Some(6))
  // Test jump to next.
  assert_true(get_next_fold_line(3, folding_model) is Some(5))
  assert_true(get_next_fold_line(5, folding_model) is Some(9))
  assert_true(get_next_fold_line(9, folding_model) is None)
  // Test when not on a folding region start line.
  assert_true(get_next_fold_line(4, folding_model) is Some(5))
  assert_true(get_next_fold_line(7, folding_model) is Some(9))
  assert_true(get_next_fold_line(8, folding_model) is Some(9))
}

///|
test "fold jumping issue #129503" {
  let folding_model = test_folding_model([
    "", "if True:", "  print(1)", "if True:", "  print(1)", "",
  ])
  assert_model_ranges(folding_model, [(2, 3, false), (4, 6, false)], "ranges")
  // Test jump to next.
  assert_true(get_next_fold_line(1, folding_model) is Some(2))
  assert_true(get_next_fold_line(2, folding_model) is Some(4))
  assert_true(get_next_fold_line(3, folding_model) is Some(4))
  assert_true(get_next_fold_line(4, folding_model) is None)
  assert_true(get_next_fold_line(5, folding_model) is None)
  assert_true(get_next_fold_line(6, folding_model) is None)
  // Test jump to previous.
  assert_true(get_previous_fold_line(1, folding_model) is None)
  assert_true(get_previous_fold_line(2, folding_model) is None)
  assert_true(get_previous_fold_line(3, folding_model) is Some(2))
  assert_true(get_previous_fold_line(4, folding_model) is Some(2))
  assert_true(get_previous_fold_line(5, folding_model) is Some(4))
  assert_true(get_previous_fold_line(6, folding_model) is Some(4))
}
