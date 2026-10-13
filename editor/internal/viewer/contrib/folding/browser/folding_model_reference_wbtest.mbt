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
  _is_outline_body : Bool,
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
  FoldingDecorationAccess(
    (is_collapsed, is_hidden, is_manual, is_outline_body) => {
      self.get_decoration_option(
        is_collapsed, is_hidden, is_manual, is_outline_body,
      )
    },
    callback => self.change_decorations(callback),
    decoration_ids => self.remove_decorations(decoration_ids),
  )
}

///|
/// `(line, type)` pairs of the provider's live decorations, by position.
fn TestDecorationProvider::get_decorations(
  self : TestDecorationProvider,
) -> Array[(Int32, String)] {
  let res : Array[(Int32, String)] = []
  for
    decoration in self.model.get_decorations_in_range(
      self.model.get_full_model_range(),
    ) {
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
  { start: line => line == "//#region", end: line => line == "//#endregion", }
}

///|
/// `/^\s*<rest>$/`: optional leading whitespace, then exactly `rest`.
fn ws_then_exact(rest : String) -> (String) -> Bool {
  line => {
    let i = for i = 0; i < line.length() && (line[i] == ' ' || line[i] == '\t'); {
      continue i + 1
    } nobreak {
      i
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
  expected : Array[(Int32, Int32, Bool)],
  message : String,
) -> Unit raise {
  let actual_ranges : Array[(Int32, Int32, Bool)] = []
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
  expected : Array[(Int32, Int32)],
  message : String,
) -> Unit raise {
  let actual_ranges : Array[(Int32, Int32)] = []
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
  expected : Array[(Int32, Int32, Bool)],
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
  expected : (Int32, Int32, Bool)?,
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
    TestDecorationProvider::{ model: text_model, }.access(),
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
    TestDecorationProvider::{ model: text_model, }.access(),
  )
  let ranges = compute_ranges(text_model, false)
  folding_model.update(ranges)
  let r1 = (1, 3, false)
  let r2 = (4, 7, false)
  let r3 = (5, 6, false)
  assert_model_ranges(folding_model, [r1, r2, r3], "initial")
  guard folding_model.get_region_at_line(1) is Some(region1) else {
    fail("expected a folding region at line 1")
  }
  folding_model.toggle_collapse_state([region1])
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [(1, 3, true), r2, r3], "1")
  guard folding_model.get_region_at_line(5) is Some(region5) else {
    fail("expected a folding region at line 5")
  }
  folding_model.toggle_collapse_state([region5])
  folding_model.update(ranges)
  assert_model_ranges(folding_model, [(1, 3, true), r2, (5, 6, true)], "2")
  guard folding_model.get_region_at_line(7) is Some(region7) else {
    fail("expected a folding region at line 7")
  }
  folding_model.toggle_collapse_state([region7])
  folding_model.update(ranges)
  assert_model_ranges(
    folding_model,
    [(1, 3, true), (4, 7, true), (5, 6, true)],
    "3",
  )
}

///|
/// Persistence port of `FoldingModel.getMemento`/`applyMemento` at the pinned
/// VS Code revision. Expanded provider ranges are represented by absence;
/// collapsed siblings are restored after a fresh folding model is computed.
test "folding memento restores only collapsed provider ranges" {
  let lines = [
    "class A {", "  first();", "}", "class B {", "  second();", "}", "tail",
  ]
  let before = test_folding_model(lines)
  set_collapse_state_at_level(before, 1, true, [])
  guard before.get_region_at_line(1) is Some(first) else {
    fail("expected first top-level region")
  }
  before.toggle_collapse_state([first])
  assert_folded_ranges(before, [(4, 5)], "saved state")
  guard before.get_memento() is Some(memento) else {
    fail("expected collapsed range memento")
  }

  let after = test_folding_model(lines)
  after.apply_memento(memento)
  assert_model_ranges(after, [(1, 2, false), (4, 5, true)], "restored state")
}

///|
/// The persisted checksum rejects a range whose body boundary changed instead
/// of applying stale line coordinates to a different fold.
test "folding memento rejects a stale range checksum" {
  let before = test_folding_model([
    "class A {", "  first();", "}", "class B {", "  second();", "}", "tail",
  ])
  set_collapse_state_at_level(before, 1, true, [])
  guard before.get_memento() is Some(memento) else {
    fail("expected collapsed range memento")
  }

  let after = test_folding_model([
    "class A {", "  changed();", "}", "class B {", "  second();", "}", "tail",
  ])
  after.apply_memento(memento)
  assert_model_ranges(
    after,
    [(1, 2, false), (4, 5, true)],
    "only checksum-compatible range restored",
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
test "folding decoration" {
  let text_model = folding_test_model([
    "class A {", "  void foo() {", "    if (true) {", "      hoo();", "    }", "  }",
    "}",
  ])
  let provider = TestDecorationProvider::{ model: text_model, }
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
  guard folding_model.get_region_at_line(2) is Some(region2) else {
    fail("expected a folding region at line 2")
  }
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
  guard folding_model.get_region_at_line(1) is Some(region1) else {
    fail("expected a folding region at line 1")
  }
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
  guard folding_model.get_region_at_line(1) is Some(region1b) else {
    fail("expected a folding region at line 1")
  }
  guard folding_model.get_region_at_line(3) is Some(region3) else {
    fail("expected a folding region at line 3")
  }
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
