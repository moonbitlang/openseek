///|
fn semantic_test_section(
  key : String,
  identity : Int?,
  kind : @moon_diff_provider.SemanticReviewSectionKind,
  original_source : String,
  modified_source : String,
) -> @moon_diff_provider.SemanticReviewSection {
  {
    key,
    identity,
    kind,
    old_range: Some({ start_line_number: 10, line_count: 2, }),
    new_range: Some({ start_line_number: 30, line_count: 2, }),
    old_context: Some("fn old_context"),
    new_context: Some("fn new_context"),
    fallbacks: [],
    original_source,
    modified_source,
    diff: @moon_diff_provider.SemanticReviewDiff::Line,
  }
}

///|
test "semantic input follows active MoonBit review and ignores layout" {
  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..reviewed_doc(path, selected, baseline="fn value() { 1 }"),
    state: TabLoaded(
      content="fn value() { 2 }",
      absolute=test_ctx().test_resource("/work/src/main.mbt"),
      sig="working",
    ),
  }
  let state = {
    ..owned_state(),
    docs,
    review_diff_mode: ReviewDiffToken,
    review_diff_layout: ReviewInline,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  guard semantic_review_input(state, ctx) is Some(input) else {
    fail("expected semantic review input")
  }
  assert_eq(input.old_source, "fn value() { 1 }")
  assert_eq(input.new_source, "fn value() { 2 }")
  assert_true(input.mode is @moon_diff_provider.Token)
  assert_eq(input.feedback_file, Some(path))
  assert_true(
    input.live_modified is Some({ resource, path: live_path, }) &&
    resource.path == "/work/src/main.mbt" &&
    live_path == path,
  )
  let deleted_docs = docs.copy()
  deleted_docs[path] = { ..docs[path], state: TabDeleted, }
  guard semantic_review_input({ ..state, docs: deleted_docs, }, ctx)
    is Some(deleted_input) else {
    fail("expected deleted semantic review input")
  }
  assert_eq(deleted_input.feedback_file, Some(path))
  assert_eq(deleted_input.live_modified, None)
  assert_eq(
    semantic_review_input({ ..state, review_diff_mode: ReviewDiffLine, }, ctx),
    None,
  )
}

///|
test "semantic model identity enables IDE only on Modified" {
  guard semantic_model_uri(SemanticReviewOriginal, "section-3")
    is Some(original) &&
    semantic_model_uri(SemanticReviewModified, "section-3") is Some(modified) else {
    fail("expected semantic model URIs")
  }
  assert_eq(original.scheme, SemanticReviewOriginalScheme)
  assert_eq(modified.scheme, SemanticReviewModifiedScheme)
  assert_eq(original.path, "/section-3.mbt")
  assert_eq(modified.path, "/section-3.mbt")
}

///|
test "semantic feedback enables only physical sides of working-tree sections" {
  let file = @pathx.Relative("src/main.mbt")
  let matched = semantic_test_section(
    "section-1",
    Some(1),
    @moon_diff_provider.SemanticReviewSectionKind::Matched,
    "old",
    "new",
  )
  assert_true(
    semantic_feedback_side_enabled(Some(file), matched, SemanticReviewOriginal),
  )
  assert_true(
    semantic_feedback_side_enabled(Some(file), matched, SemanticReviewModified),
  )
  assert_false(
    semantic_feedback_side_enabled(None, matched, SemanticReviewOriginal),
  )
  let deleted = {
    ..matched,
    kind: @moon_diff_provider.SemanticReviewSectionKind::Deleted,
    new_range: None,
    modified_source: "",
  }
  assert_true(
    semantic_feedback_side_enabled(Some(file), deleted, SemanticReviewOriginal),
  )
  assert_false(
    semantic_feedback_side_enabled(Some(file), deleted, SemanticReviewModified),
  )
  let inserted = {
    ..matched,
    kind: @moon_diff_provider.SemanticReviewSectionKind::Inserted,
    old_range: None,
    original_source: "",
  }
  assert_false(
    semantic_feedback_side_enabled(Some(file), inserted, SemanticReviewOriginal),
  )
  assert_true(
    semantic_feedback_side_enabled(Some(file), inserted, SemanticReviewModified),
  )
}

///|
test "semantic feedback projects local ranges into each physical source side" {
  let section = semantic_test_section(
    "section-2",
    Some(2),
    @moon_diff_provider.SemanticReviewSectionKind::Matched,
    "old one\nold two",
    "new one\nnew two",
  )
  assert_eq(
    semantic_feedback_line_offset(section, SemanticReviewOriginal),
    Some(9),
  )
  assert_eq(
    semantic_feedback_line_offset(section, SemanticReviewModified),
    Some(29),
  )
  let local_range = @common.Range(1, 2, 2, 5)
  assert_eq(
    project_semantic_feedback_range(local_range, 9),
    @common.Range(10, 2, 11, 5),
  )
  assert_eq(
    project_semantic_feedback_range(local_range, 29),
    @common.Range(30, 2, 31, 5),
  )
  let whole = {
    ..section,
    key: "whole",
    identity: None,
    kind: @moon_diff_provider.SemanticReviewSectionKind::Whole,
    old_range: None,
    new_range: None,
  }
  assert_eq(
    semantic_feedback_line_offset(whole, SemanticReviewOriginal),
    Some(0),
  )
  assert_eq(
    semantic_feedback_line_offset(whole, SemanticReviewModified),
    Some(0),
  )
}

///|
test "semantic feedback messages preserve projected side and range identity" {
  let file = @pathx.Relative("src/main.mbt")
  let resource = ModelUri("openseek-semantic-diff-modified:/section-2.mbt")
  let modified = semantic_feedback_message(
    file,
    SemanticReviewModified,
    @common.Range(30, 2, 31, 5),
    "new one\nnew two",
    "keep this",
    resource,
    "feedback-modified",
  )
  assert_true(
    modified
    is EditorCommentAdded(
      file=@pathx.Relative("src/main.mbt"),
      range=modified_range,
      quote="new one\nnew two",
      comment="keep this",
      ..
    ) &&
    modified_range == @common.Range(30, 2, 31, 5),
  )
  let original = semantic_feedback_message(
    file,
    SemanticReviewOriginal,
    @common.Range(10, 2, 11, 5),
    "old one\nold two",
    "restore this",
    ModelUri("openseek-semantic-diff-original:/section-2.mbt"),
    "feedback-original",
  )
  assert_true(
    original
    is DiffCommentAdded(
      file=@pathx.Relative("src/main.mbt"),
      original_line_number=Some(10),
      modified_line_number=None,
      quote="old one\nold two",
      comment="restore this",
      ..
    ),
  )
}

///|
test "semantic diagnostics retain only and relocate the section overlap" {
  let model = @model.TextModel(
    @common.Uri::parse("\{SemanticReviewModifiedScheme}:/section-4.mbt"),
    "main.mbt",
    "moonbit",
    1,
    "semantic-new",
    "fn value() -> Int {\n  2\n}",
  )
  defer model.dispose()
  let diagnostics : Array[@language.Diagnostic] = [
    {
      range: @common.Range(2, 1, 2, 4),
      severity: Error,
      message: "outside",
      tags: None,
    },
    {
      range: @common.Range(30, 4, 30, 9),
      severity: Warning,
      message: "inside",
      tags: None,
    },
    {
      range: @common.Range(28, 8, 32, 8),
      severity: Info,
      message: "crossing",
      tags: None,
    },
  ]
  let projected = project_semantic_modified_diagnostics(diagnostics, model, 29)
  assert_eq(projected.length(), 2)
  assert_eq(projected[0].message, "inside")
  assert_eq(projected[0].range, @common.Range(1, 4, 1, 9))
  assert_eq(projected[1].message, "crossing")
  assert_eq(projected[1].range, @common.Range(1, 1, 3, 2))
}

///|
test "semantic multi-diff entry collapse is tab-local retained state" {
  let section = semantic_test_section(
    "section-4",
    Some(4),
    @moon_diff_provider.SemanticReviewSectionKind::Matched,
    "old",
    "new",
  )
  let state = {
    ..State::empty(),
    semantic_review_plan: Some({
      requested: @moon_diff_provider.Token,
      status: @moon_diff_provider.SemanticReviewStatus::Changed,
      reordered: false,
      main_sections: [section],
      deleted_sections: [],
    }),
  }
  let (_, collapsed) = update(
    test_emit(),
    SemanticReviewSectionToggled("section-4"),
    state,
    test_ctx(),
  )
  assert_eq(collapsed.semantic_review_collapsed, ["section-4"])
  let (_, expanded) = update(
    test_emit(),
    SemanticReviewSectionToggled("section-4"),
    collapsed,
    test_ctx(),
  )
  assert_true(expanded.semantic_review_collapsed.is_empty())
  let (_, unknown) = update(
    test_emit(),
    SemanticReviewSectionToggled("missing"),
    expanded,
    test_ctx(),
  )
  assert_true(unknown == expanded)
}

///|
test "semantic hunk reveal projects the VS Code child scroll delta" {
  // The active item has 40px of sticky chrome, leaving a 360px editor
  // viewport. Its child target is 430; starting at child scroll 0 moves the
  // outer viewport from 500 to 930.
  assert_eq(
    semantic_review_scroll_top_after_child_reveal(
      500.0, 400.0, 500.0, 1040.0, 540.0, 40.0, 600.0, 620.0,
    ),
    930.0,
  )
  // Repeating the same reveal from a child scroll of 200 lands at the same
  // absolute target by applying only the remaining delta.
  assert_eq(
    semantic_review_scroll_top_after_child_reveal(
      700.0, 400.0, 500.0, 1040.0, 540.0, 40.0, 600.0, 620.0,
    ),
    930.0,
  )
  // An oversized line range aligns immediately below the 40px sticky chrome,
  // matching the child editor's top reveal rather than hiding it underneath.
  assert_eq(
    semantic_review_scroll_top_after_child_reveal(
      240.0, 300.0, 240.0, 700.0, 280.0, 40.0, 80.0, 480.0,
    ),
    320.0,
  )
  // A short item has no child scroll range. Same-item navigation therefore
  // preserves the parent position, as VS Code's zero scroll delta does.
  assert_eq(
    semantic_review_scroll_top_after_child_reveal(
      0.0, 400.0, 20.0, 200.0, 60.0, 40.0, 10.0, 30.0,
    ),
    0.0,
  )
  // A non-sticky notice before the editor shifts the target through the
  // child's scrolling content; it does not shrink the viewport like chrome.
  assert_eq(
    semantic_review_scroll_top_after_child_reveal(
      500.0, 400.0, 500.0, 1080.0, 580.0, 40.0, 600.0, 620.0,
    ),
    970.0,
  )
  // If a long active item only clips the viewport edge, its clamped child
  // offset is not a valid delta origin. Re-origin at the item before applying
  // the target so the hunk still lands below the sticky header.
  assert_eq(
    semantic_review_scroll_top_after_child_reveal(
      100.0, 400.0, 450.0, 1040.0, 490.0, 40.0, 600.0, 620.0,
    ),
    880.0,
  )
}

///|
test "semantic navigation restores an active item that left the viewport" {
  // A short item must be entirely visible because its child has no scroll
  // range. Partial visibility therefore restores the item origin.
  assert_true(
    semantic_review_item_needs_navigation_origin(100.0, 400.0, 450.0, 100.0),
  )
  assert_true(
    !semantic_review_item_needs_navigation_origin(100.0, 400.0, 200.0, 100.0),
  )
  // A long item keeps its current child offset while it fully contains the
  // viewport. Partial overlap at either edge is outside the child's valid
  // scroll band and must be re-established too.
  assert_true(
    !semantic_review_item_needs_navigation_origin(300.0, 400.0, 100.0, 800.0),
  )
  assert_true(
    semantic_review_item_needs_navigation_origin(900.0, 400.0, 100.0, 800.0),
  )
  assert_true(
    semantic_review_item_needs_navigation_origin(100.0, 400.0, 500.0, 800.0),
  )
  assert_true(
    semantic_review_item_needs_navigation_origin(100.0, 400.0, 450.0, 800.0),
  )
  assert_true(
    semantic_review_item_needs_navigation_origin(450.0, 400.0, 100.0, 700.0),
  )
}
