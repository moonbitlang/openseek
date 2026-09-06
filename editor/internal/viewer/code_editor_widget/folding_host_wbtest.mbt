// Headless end-to-end tests for the folding contribution: the
// `FoldingController` chain from `onModelChanged` through the hidden-range
// model into `CodeEditorWidget::set_hidden_areas` and the view axis.

///|
/// The attached folding model for `viewer`, failing the test when the
/// controller or its model is missing.
fn attached_folding_model(
  viewer : CodeEditorWidget,
) -> @folding_browser.FoldingModel raise {
  guard viewer.folding_controller() is Some(controller) else {
    fail("expected a folding controller")
  }
  guard controller.folding_model is Some(folding_model) else {
    fail("expected an attached folding model")
  }
  folding_model
}

///|
test "folding: contribution computes indent regions on model attach" {
  with_test_viewer(
    (
      #|a
      #|  b
      #|  c
      #|d
      #|  e
    ),
    viewer => {
      let folding_model = attached_folding_model(viewer)
      let regions = folding_model.regions()
      let fold_regions = folding_model.get_regions_inside(None)
      assert_eq(regions.length(), 2)
      assert_eq(fold_regions[0].start_line_number(), 1)
      assert_eq(fold_regions[0].end_line_number(), 3)
      assert_eq(fold_regions[1].start_line_number(), 4)
      assert_eq(fold_regions[1].end_line_number(), 5)
    },
  )
}

///|
test "folding: public fold_top_level collapses every outer region only" {
  with_test_viewer(
    (
      #|root
      #|  child
      #|    leaf
      #|next
      #|  item
      #|tail
    ),
    viewer => {
      let view_model = viewer.test_view_model()
      let folding_model = attached_folding_model(viewer)
      let regions = folding_model.regions()
      let fold_regions = folding_model.get_regions_inside(None)
      assert_eq(regions.length(), 3)
      viewer.set_position(Position(3, 1))
      viewer.fold_top_level()
      assert_true(fold_regions[0].is_collapsed())
      assert_false(fold_regions[1].is_collapsed())
      assert_true(fold_regions[2].is_collapsed())
      assert_eq(view_model.line_count(), 3)
      assert_eq(view_model.lines().get_view_line_content(1), "root")
      assert_eq(view_model.lines().get_view_line_content(2), "next")
      assert_eq(view_model.lines().get_view_line_content(3), "tail")
      // The API does not preserve a blocked selection: folding the containing
      // outer region snaps the caret to its header.
      guard viewer.get_selection() is Some(selection) else {
        fail("expected a selection")
      }
      assert_eq(selection.start().line_number, 1)
    },
  )
}

///|
test "folding: MoonBit outline keeps the complete signature and opening brace" {
  let text =
    #|fn f(
    #|  display_param : X,
    #|) -> ReturnType {
    #|  use(display_param)
    #|}
    #|tail
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.set_position(Position(4, 3))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  let folding_model = attached_folding_model(viewer)
  guard folding_model.get_region_at_line(3) is Some(region) else {
    fail("expected a folding region at line 3")
  }
  assert_eq(region.start_line_number(), 3)
  assert_eq(region.end_line_number(), 5)
  assert_true(region.is_collapsed())
  assert_eq(view_model.line_count(), 4)
  assert_eq(view_model.lines().get_view_line_content(1), "fn f(")
  assert_eq(view_model.lines().get_view_line_content(2), "  display_param : X,")
  assert_eq(view_model.lines().get_view_line_content(3), ") -> ReturnType {")
  assert_eq(view_model.lines().get_view_line_content(4), "tail")
  debug_inspect(
    view_model.get_hidden_areas(),
    content=(
      #|[
      #|  {
      #|    start_line_number: 4,
      #|    start_column: 1,
      #|    end_line_number: 5,
      #|    end_column: 1,
      #|  },
      #|]
    ),
  )
  guard viewer.get_position() is Some(position) else {
    fail("expected a cursor position")
  }
  assert_position(position, Position(3, 18))
  let mut saw_outline_body = false
  for
    decoration in folding_model
    .text_model()
    .get_decorations_in_range(folding_model.text_model().get_full_model_range()) {
    if decoration.options.description ==
      "folding-collapsed-outline-body-highlighted-visual-decoration" {
      saw_outline_body = true
      assert_eq(decoration.options.after_content_class_name, None)
      assert_eq(decoration.range.start_line_number, 3)
    }
  }
  assert_true(saw_outline_body)
  folding_model.toggle_collapse_state([region])
  assert_eq(view_model.line_count(), 6)
  viewer.dispose()
}

///|
test "folding: MoonBit outline scan ignores bodyless functions and literal braces" {
  let text =
    #|extern "js" fn foreign() -> Int = "() => ({ value: 1 })"
    #|let callback : (Int) -> Int =
    #|  fn(value) {
    #|    value + 1
    #|  }
    #|declare pub fn declared() -> Int
    #|fn[T] real(value : T) -> T {
    #|  let quoted = "\{"}"}"
    #|  let block = /* { */ value /* } */
    #|  let raw =
    #|    #| }
    #|  let interpolated =
    #|    $| }
    #|  block
    #|}
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  let folds = source_folds.function_bodies
  assert_eq(folds.length(), 1)
  assert_eq(folds[0].declaration_start_line_number, 7)
  assert_eq(folds[0].body_start_line_number, 7)
  assert_eq(folds[0].body_end_line_number, 15)
  assert_eq(source_folds.comment_runs.length(), 0)
}

///|
test "folding: MoonBit comment-run scan finds only top-level plain runs" {
  let text =
    #|// header a
    #|// header b
    #|///|
    #|/// doc line one
    #|/// doc line two
    #|fn f() -> Int {
    #|  // inner a
    #|  // inner b
    #|  1
    #|}
    #|/* block
    #|// inside block comment
    #|// inside block comment
    #|*/
    #|// solo
    #|
    #|// tail a
    #|// tail b
  let model = test_model(text, language_id="moonbit")
  let runs = moonbit_source_folds(model.snapshot).comment_runs
  assert_eq(runs.length(), 2)
  assert_eq(runs[0].start_line_number, 1)
  assert_eq(runs[0].end_line_number, 2)
  assert_eq(runs[1].start_line_number, 17)
  assert_eq(runs[1].end_line_number, 18)
}

///|
test "folding: comments inside an in-progress declaration never form a run" {
  let text =
    #|fn f(
    #|  // keep a
    #|  // keep b
    #|) -> Int {
    #|  1
    #|}
    #|pub
    #|// prefix a
    #|// prefix b
    #|  fn g() -> Int {
    #|    2
    #|  }
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.comment_runs.length(), 0)
  let folds = source_folds.function_bodies
  assert_eq(folds.length(), 2)
  assert_eq(folds[0].declaration_start_line_number, 1)
  assert_eq(folds[0].body_start_line_number, 4)
  assert_eq(folds[0].body_end_line_number, 6)
  assert_eq(folds[1].declaration_start_line_number, 7)
  assert_eq(folds[1].body_start_line_number, 10)
  assert_eq(folds[1].body_end_line_number, 12)
}

///|
test "folding: comments inside binding continuations never form a run" {
  let text =
    #|let xs : Array[Int] = [
    #|  // element a
    #|  // element b
    #|  1, 2,
    #|]
    #|let ys : Int = make(
    #|  // argument a
    #|  // argument b
    #|  3,
    #|)
    #|pub let header : String =
    #|  // continuation a
    #|  // continuation b
    #|  "line one\n" +
    #|  "line two\n"
    #|// trailing a
    #|// trailing b
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.function_bodies.length(), 0)
  let runs = source_folds.comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 16)
  assert_eq(runs[0].end_line_number, 17)
}

///|
test "folding: bodyless declarations and raw literals release comment runs" {
  let text =
    #|declare
    #|// pending a
    #|// pending b
    #|pub fn declared() -> Int
    #|let raw : String =
    #|  #| body one
    #|  #| body two
    #|// after raw a
    #|// after raw b
    #|declare fn lookup() -> Item?
    #|// optional a
    #|// optional b
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.function_bodies.length(), 0)
  let runs = source_folds.comment_runs
  assert_eq(runs.length(), 2)
  assert_eq(runs[0].start_line_number, 8)
  assert_eq(runs[0].end_line_number, 9)
  assert_eq(runs[1].start_line_number, 11)
  assert_eq(runs[1].end_line_number, 12)
}

///|
test "folding: split bindings and declare signatures keep their comments" {
  let text =
    #|let x
    #|// binding a
    #|// binding b
    #|= 1
    #|declare pub fn
    #|// name a
    #|// name b
    #|lookup() -> Int
    #|// tail a
    #|// tail b
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.function_bodies.length(), 0)
  let runs = source_folds.comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 9)
  assert_eq(runs[0].end_line_number, 10)
}

///|
test "folding: aliases release runs while split constructs keep theirs" {
  let text =
    #|pub typealias Int as Id
    #|// alias a
    #|// alias b
    #|let value = /* explanation
    #|*/
    #|// note a
    #|// note b
    #|1 + 1
    #|declare fn lookup()
    #|// ret a
    #|// ret b
    #|-> Int
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.function_bodies.length(), 0)
  let runs = source_folds.comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 2)
  assert_eq(runs[0].end_line_number, 3)
}

///|
test "folding: keyword-led continuations swallow their comment runs" {
  let text =
    #|let v : Int = if c { 1 }
    #|// branch a
    #|// branch b
    #|else { 2 }
    #|let w : Unit = f
    #|// call a
    #|// call b
    #|(1)
    #|// tail a
    #|// tail b
  let model = test_model(text, language_id="moonbit")
  let runs = moonbit_source_folds(model.snapshot).comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 9)
  assert_eq(runs[0].end_line_number, 10)
}

///|
test "folding: trivia gaps defer run decisions until the continuation" {
  let text =
    #|let v : Int = if c { 1 }
    #|// gap a
    #|// gap b
    #|
    #|else { 2 }
    #|// first a
    #|// first b
    #|
    #|noraise { 3 }
    #|// second a
    #|// second b
    #|/* spacer */
    #|is Some(_)
    #|// third a
    #|// third b
    #|
    #|// fourth a
    #|// fourth b
  let model = test_model(text, language_id="moonbit")
  let runs = moonbit_source_folds(model.snapshot).comment_runs
  assert_eq(runs.length(), 2)
  assert_eq(runs[0].start_line_number, 14)
  assert_eq(runs[0].end_line_number, 15)
  assert_eq(runs[1].start_line_number, 17)
  assert_eq(runs[1].end_line_number, 18)
}

///|
test "folding: queued gap runs and keyword tails stay with their construct" {
  let text =
    #|let v : Int = if c { 1 }
    #|// gap one a
    #|// gap one b
    #|
    #|// gap two a
    #|// gap two b
    #|else { 2 }
    #|let b : Bool = value is
    #|// tail a
    #|// tail b
    #|Some(_)
    #|// final a
    #|// final b
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.function_bodies.length(), 0)
  let runs = source_folds.comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 12)
  assert_eq(runs[0].end_line_number, 13)
}

///|
test "folding: prefixed continuations and split declarations keep comments" {
  let text =
    #|let v : Int = if c { 1 }
    #|// gap a
    #|// gap b
    #|/* rationale */ else { 2 }
    #|declare pub fn[T]
    #|// generic a
    #|// generic b
    #|lookup(value : T) -> T
    #|extern "js"
    #|// abi a
    #|// abi b
    #|fn foreign() -> Int = "() => 1"
    #|let d : Bool = !
    #|// not a
    #|// not b
    #|false
    #|// tail a
    #|// tail b
  let model = test_model(text, language_id="moonbit")
  let source_folds = moonbit_source_folds(model.snapshot)
  assert_eq(source_folds.function_bodies.length(), 0)
  let runs = source_folds.comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 17)
  assert_eq(runs[0].end_line_number, 18)
}

///|
test "folding: same-start provider ranges yield to the comment run" {
  let text =
    #|// zero
    #|  // one
    #|  two
    #|tail
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let folding_model = attached_folding_model(viewer)
  let regions = folding_model.regions()
  let fold_regions = folding_model.get_regions_inside(None)
  assert_eq(regions.length(), 1)
  assert_eq(fold_regions[0].start_line_number(), 1)
  assert_eq(fold_regions[0].end_line_number(), 2)
  assert_eq(regions.get_type(0), Some(COMMENT_RUN_FOLDING_RANGE_TYPE))
  assert_true(fold_regions[0].is_collapsed())
  viewer.dispose()
}

///|
test "folding: provider ranges containing a comment run are retained" {
  let text =
    #|zero
    #|  // indent a
    #|  // indent b
    #|tail
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let folding_model = attached_folding_model(viewer)
  let regions = folding_model.regions()
  let fold_regions = folding_model.get_regions_inside(None)
  assert_eq(regions.length(), 2)
  assert_eq(fold_regions[0].start_line_number(), 1)
  assert_eq(fold_regions[0].end_line_number(), 3)
  assert_eq(regions.get_type(0), None)
  assert_true(fold_regions[0].is_collapsed())
  assert_eq(fold_regions[1].start_line_number(), 2)
  assert_eq(fold_regions[1].end_line_number(), 3)
  assert_eq(regions.get_type(1), Some(COMMENT_RUN_FOLDING_RANGE_TYPE))
  assert_false(fold_regions[1].is_collapsed())
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 2)
  assert_eq(view_model.lines().get_view_line_content(1), "zero")
  assert_eq(view_model.lines().get_view_line_content(2), "tail")
  viewer.dispose()
}

///|
test "folding: a BOM-prefixed header folds from its first line" {
  let model = test_model(
    "\u{FEFF}// bom a\n// bom b\n// bom c",
    language_id="moonbit",
  )
  let runs = moonbit_source_folds(model.snapshot).comment_runs
  assert_eq(runs.length(), 1)
  assert_eq(runs[0].start_line_number, 1)
  assert_eq(runs[0].end_line_number, 3)
}

///|
test "folding: MoonBit outline collapses a copyright header to its first line" {
  let text =
    #|// Copyright 2026 Example Authors.
    #|// Licensed under Apache-2.0.
    #|// See LICENSE for details.
    #|
    #|fn f() -> Int {
    #|  1
    #|}
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 3)
  assert_eq(
    view_model.lines().get_view_line_content(1),
    "// Copyright 2026 Example Authors.",
  )
  assert_eq(view_model.lines().get_view_line_content(2), "")
  assert_eq(view_model.lines().get_view_line_content(3), "fn f() -> Int {")
  let folding_model = attached_folding_model(viewer)
  let regions = folding_model.regions()
  let fold_regions = folding_model.get_regions_inside(None)
  assert_eq(regions.length(), 2)
  assert_eq(fold_regions[0].start_line_number(), 1)
  assert_eq(fold_regions[0].end_line_number(), 3)
  assert_eq(regions.get_type(0), Some(COMMENT_RUN_FOLDING_RANGE_TYPE))
  assert_true(fold_regions[0].is_collapsed())
  // Unlike outline bodies, the collapsed comment run keeps the ordinary
  // trailing ellipsis after its visible first line.
  let mut saw_comment_header = false
  for
    decoration in folding_model
    .text_model()
    .get_decorations_in_range(folding_model.text_model().get_full_model_range()) {
    if decoration.range.start_line_number == 1 &&
      decoration.options.first_line_decoration_class_name
      is Some("codicon codicon-folding-collapsed") {
      saw_comment_header = true
      assert_true(
        decoration.options.after_content_class_name is Some("inline-folded"),
      )
    }
  }
  assert_true(saw_comment_header)
  viewer.dispose()
}

///|
test "folding: comment-only MoonBit file folds and survives option updates" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(
    Some(
      test_model(
        (
          #|// a
          #|// b
          #|// c
        ),
        language_id="moonbit",
      ),
    ),
  )
  viewer.fold_top_level()
  assert_eq(viewer.test_view_model().line_count(), 1)
  // Reapplying the policy is a no-op...
  viewer.fold_top_level()
  assert_eq(viewer.test_view_model().line_count(), 1)
  // ...and provider recomputation (an option change) retains the host fold
  // even though the file contributes no outline function bodies.
  viewer.update_options(CodeEditorOptions(show_folding_controls=Never))
  let folding_model = attached_folding_model(viewer)
  let regions = folding_model.regions()
  let fold_regions = folding_model.get_regions_inside(None)
  assert_eq(regions.length(), 1)
  assert_eq(fold_regions[0].start_line_number(), 1)
  assert_eq(fold_regions[0].end_line_number(), 3)
  assert_eq(regions.get_type(0), Some(COMMENT_RUN_FOLDING_RANGE_TYPE))
  assert_true(fold_regions[0].is_collapsed())
  assert_eq(viewer.test_view_model().line_count(), 1)
  viewer.dispose()
}

///|
test "folding: formatted modifiers and impl headers remain visible" {
  let text =
    #|pub
    #|  fn first() -> Int {
    #|    1
    #|  }
    #|impl Eq for X with
    #|  fn equal(self, other) {
    #|    true
    #|  }
    #|tail
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 5)
  assert_eq(view_model.lines().get_view_line_content(1), "pub")
  assert_eq(
    view_model.lines().get_view_line_content(2),
    "  fn first() -> Int {",
  )
  assert_eq(view_model.lines().get_view_line_content(3), "impl Eq for X with")
  assert_eq(
    view_model.lines().get_view_line_content(4),
    "  fn equal(self, other) {",
  )
  assert_eq(view_model.lines().get_view_line_content(5), "tail")
  viewer.dispose()
}

///|
test "folding: repeated MoonBit outline fold is idempotent" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(
    Some(
      test_model(
        (
          #|fn f() -> Int {
          #|  1
          #|}
          #|tail
        ),
        language_id="moonbit",
      ),
    ),
  )
  let mut hidden_area_changes = 0
  viewer.on_did_change_hidden_areas(() => hidden_area_changes += 1) |> ignore
  viewer.fold_top_level()
  let changes_after_first_fold = hidden_area_changes
  viewer.fold_top_level()
  assert_eq(hidden_area_changes, changes_after_first_fold)
  viewer.dispose()
}

///|
test "folding: MoonBit outline survives folding decoration option updates" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(
    Some(
      test_model(
        (
          #|fn f() -> Int {
          #|  1
          #|}
          #|tail
        ),
        language_id="moonbit",
      ),
    ),
  )
  viewer.fold_top_level()
  let folding_model = attached_folding_model(viewer)
  viewer.update_options(CodeEditorOptions(show_folding_controls=Never))
  let regions = folding_model.regions()
  let fold_regions = folding_model.get_regions_inside(None)
  assert_eq(regions.length(), 1)
  assert_eq(fold_regions[0].start_line_number(), 1)
  assert_eq(fold_regions[0].end_line_number(), 3)
  assert_eq(
    regions.get_type(0),
    Some(@folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE),
  )
  assert_true(fold_regions[0].is_collapsed())
  assert_eq(viewer.test_view_model().line_count(), 2)
  let mut saw_outline_body = false
  for
    decoration in folding_model
    .text_model()
    .get_decorations_in_range(folding_model.text_model().get_full_model_range()) {
    if decoration.options.description ==
      "folding-no-controls-outline-body-range-decoration" {
      saw_outline_body = true
      assert_eq(decoration.options.after_content_class_name, None)
    }
  }
  assert_true(saw_outline_body)
  viewer.dispose()
}

///|
test "folding: MoonBit outline respects the configured folding limit" {
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(folding_maximum_regions=1),
  )
  viewer.set_model(
    Some(
      test_model(
        (
          #|fn f() -> Int {
          #|  1
          #|}
          #|fn g() -> Int {
          #|  2
          #|}
          #|tail
        ),
        language_id="moonbit",
      ),
    ),
  )
  viewer.fold_top_level()
  let folding_model = attached_folding_model(viewer)
  let regions = folding_model.regions()
  let fold_regions = folding_model.get_regions_inside(None)
  assert_eq(regions.length(), 1)
  assert_eq(
    regions.get_type(0),
    Some(@folding_browser.OUTLINE_BODY_FOLDING_RANGE_TYPE),
  )
  assert_true(fold_regions[0].is_collapsed())
  viewer.dispose()
}

///|
test "folding: MoonBit outline preserves signatures with same-line bodies" {
  let text =
    #|fn f(
    #|  display_param : X,
    #|) -> ReturnType { display_param }
    #|tail
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(text, language_id="moonbit")))
  viewer.fold_top_level()
  let folding_model = attached_folding_model(viewer)
  assert_eq(folding_model.regions().length(), 0)
  let view_model = viewer.test_view_model()
  assert_eq(view_model.line_count(), 4)
  assert_eq(view_model.lines().get_view_line_content(1), "fn f(")
  assert_eq(view_model.lines().get_view_line_content(2), "  display_param : X,")
  assert_eq(
    view_model.lines().get_view_line_content(3),
    ") -> ReturnType { display_param }",
  )
  assert_eq(view_model.lines().get_view_line_content(4), "tail")
  viewer.dispose()
}

///|
test "folding: toggling a region folds its lines out of the view axis" {
  with_test_viewer(
    (
      #|a
      #|  b
      #|  c
      #|d
      #|  e
    ),
    viewer => {
      let view_model = viewer.test_view_model()
      assert_eq(view_model.line_count(), 5)
      let folding_model = attached_folding_model(viewer)
      guard folding_model.get_region_at_line(1) is Some(region) else {
        fail("expected a folding region at line 1")
      }
      folding_model.toggle_collapse_state([region])
      // Lines 2-3 fold away; the header and the second block stay.
      assert_eq(view_model.line_count(), 3)
      assert_eq(view_model.lines().get_view_line_content(1), "a")
      assert_eq(view_model.lines().get_view_line_content(2), "d")
      debug_inspect(
        view_model.get_hidden_areas(),
        content=(
          #|[
          #|  {
          #|    start_line_number: 2,
          #|    start_column: 1,
          #|    end_line_number: 3,
          #|    end_column: 1,
          #|  },
          #|]
        ),
      )
      // The folded header carries the collapsed chevron + `⋯` + highlight
      // decoration on the model.
      let mut saw_collapsed = false
      for
        decoration in folding_model
        .text_model()
        .get_decorations_in_range(
          folding_model.text_model().get_full_model_range(),
        ) {
        if decoration.options.first_line_decoration_class_name
          is Some("codicon codicon-folding-collapsed") {
          saw_collapsed = true
          assert_true(
            decoration.options.after_content_class_name is Some("inline-folded"),
          )
          assert_eq(decoration.options.class_name, "folded-background")
        }
      }
      assert_true(saw_collapsed)
      // Toggling back restores every line.
      guard folding_model.get_region_at_line(1) is Some(region_again) else {
        fail("expected a folding region at line 1")
      }
      folding_model.toggle_collapse_state([region_again])
      assert_eq(view_model.line_count(), 5)
      assert_eq(view_model.get_hidden_areas().length(), 0)
    },
  )
}

///|
test "folding: fold and unfold actions work off the selection" {
  with_test_viewer(
    (
      #|a
      #|  b
      #|  c
      #|d
    ),
    viewer => {
      let view_model = viewer.test_view_model()
      viewer.set_position(Position(2, 1))
      assert_true(viewer.folding_enabled())
      viewer.folding_fold_action()
      assert_eq(view_model.line_count(), 2)
      // The caret was inside the fold; `onHiddenRangesChanges` snapped it to
      // the header line.
      guard viewer.get_selection() is Some(selection) else {
        fail("expected a selection")
      }
      assert_eq(selection.start().line_number, 1)
      viewer.set_position(Position(1, 1))
      viewer.folding_unfold_action()
      assert_eq(view_model.line_count(), 4)
    },
  )
}

///|
test "folding: disabling the option clears folds and detaches the model state" {
  with_test_viewer(
    (
      #|a
      #|  b
      #|  c
      #|d
    ),
    viewer => {
      let view_model = viewer.test_view_model()
      guard viewer.folding_controller() is Some(controller) else {
        fail("expected a folding controller")
      }
      guard controller.folding_model is Some(folding_model) else {
        fail("expected an attached folding model")
      }
      guard folding_model.get_region_at_line(1) is Some(region) else {
        fail("expected a folding region at line 1")
      }
      folding_model.toggle_collapse_state([region])
      assert_eq(view_model.line_count(), 2)
      viewer.update_options(CodeEditorOptions(folding=false))
      // `onModelChanged` with folding off: the hidden-range model's dispose
      // fired an empty set through the still-live listener.
      assert_eq(view_model.line_count(), 4)
      assert_true(controller.folding_model is None)
      assert_false(viewer.folding_enabled())
      viewer.fold_top_level()
      assert_eq(view_model.line_count(), 4)
    },
  )
}

///|
test "folding: model swap rebuilds state on the same central controller" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let first = test_model(
    (
      #|a
      #|  b
      #|  c
      #|d
    ),
  )
  let second = test_model(
    (
      #|root
      #|  child
      #|  leaf
      #|tail
      #|  end
    ),
  )
  viewer.set_model(Some(first))
  let controller = viewer.folding_controller().unwrap()
  let first_folding_model = controller.folding_model.unwrap()
  let first_view_model = viewer.test_view_model()
  let first_region = first_folding_model.get_region_at_line(1).unwrap()
  first_folding_model.toggle_collapse_state([first_region])
  assert_eq(first_view_model.line_count(), 2)
  viewer.set_model(Some(second))
  assert_true(physical_equal(controller, viewer.folding_controller().unwrap()))
  let second_folding_model = controller.folding_model.unwrap()
  assert_false(physical_equal(first_folding_model, second_folding_model))
  assert_true(physical_equal(second, second_folding_model.text_model()))
  assert_eq(second_folding_model.regions().length(), 2)
  assert_eq(viewer.test_view_model().line_count(), 5)
  assert_eq(viewer.test_view_model().get_hidden_areas().length(), 0)
  viewer.dispose()
}

///|
test "folding: contribution disposal clears folds before silencing listeners" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(
    Some(
      test_model(
        (
          #|a
          #|  b
          #|  c
          #|d
        ),
      ),
    ),
  )
  let controller = viewer.folding_controller().unwrap()
  let folding_model = controller.folding_model.unwrap()
  let region = folding_model.get_region_at_line(1).unwrap()
  folding_model.toggle_collapse_state([region])
  assert_eq(viewer.test_view_model().line_count(), 2)
  let entry = viewer.contributions.instances[@folding_browser.FOLDING_CONTROLLER_ID]
  assert_eq(entry.listeners.length(), 5)
  entry.dispose(viewer)
  // `clear_local` runs while the hidden-range listener is still live, so its
  // empty range publication restores the view before the root listeners go.
  assert_eq(viewer.test_view_model().line_count(), 4)
  assert_eq(entry.listeners.length(), 0)
  assert_true(controller.folding_model is None)
  assert_true(controller.hidden_range_model is None)
  assert_true(viewer.folding_controller() is None)
  viewer.set_model(
    Some(
      test_model(
        (
          #|x
          #|  y
          #|z
        ),
      ),
    ),
  )
  // Model-change/content listeners cannot recreate state after contribution
  // disposal; the retained concrete controller stays silent.
  assert_true(controller.folding_model is None)
  assert_true(controller.hidden_range_model is None)
  viewer.dispose()
}
