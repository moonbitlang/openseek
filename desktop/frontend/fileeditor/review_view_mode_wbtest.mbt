///|
/// One open changed-file review document: `path` loaded from the fixture
/// workspace with `baseline` as its HEAD side, in the given presentation.
fn reviewed_doc(
  path : @pathx.Relative,
  selected : ChangedFile,
  baseline? : String = "old source",
  view_mode? : ReviewViewMode = ReviewDiff,
  generation? : Int = 1,
) -> Doc raise {
  {
    ..loaded_doc(path.0),
    review: Some({
      generation,
      working_generation: generation,
      baseline: ReviewContent(baseline),
      view_mode,
      selected,
    }),
  }
}

///|
test "new reviews default to the full diff" {
  let path = @pathx.Relative("src/main.mbt")
  let change = test_modified_change(path)
  let state = owned_state()
  assert_true(state.review_view_mode is ReviewDiff)
  assert_true(state.review_diff_layout is ReviewSideBySide)
  assert_false(state.review_diff_navigation_available)
  let (_, opened) = open_changed_document(
    test_emit(),
    state,
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
    change,
    had_active=false,
  )
  assert_true(
    opened.docs.get(path)
    is Some({ review: Some({ view_mode: ReviewDiff, .. }), .. }),
  )
}

///|
test "full diff change navigation is enabled only after a nonempty diff" {
  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = reviewed_doc(path, selected)
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let state = { ..owned_state(), docs, }
  let (_, available) = update(
    test_emit(),
    ReviewDiffNavigationAvailabilityChanged(true),
    state,
    ctx,
  )
  assert_true(available.review_diff_navigation_available)

  // Commands are opaque Rabbita effects, so reducer tests assert that each
  // accepted direction preserves all business state. The command bridge maps
  // these two messages to DiffEditor's previous/next APIs respectively.
  let (_, after_previous) = update(
    test_emit(),
    RevealPreviousReviewDiffChange,
    available,
    ctx,
  )
  assert_true(after_previous == available)
  let (_, after_next) = update(
    test_emit(),
    RevealNextReviewDiffChange,
    available,
    ctx,
  )
  assert_true(after_next == available)

  let unavailable = { ..available, review_diff_navigation_available: false, }
  let (_, previous_rejected) = update(
    test_emit(),
    RevealPreviousReviewDiffChange,
    unavailable,
    ctx,
  )
  let (_, next_rejected) = update(
    test_emit(),
    RevealNextReviewDiffChange,
    unavailable,
    ctx,
  )
  assert_true(previous_rejected == unavailable)
  assert_true(next_rejected == unavailable)

  let source_docs = docs.copy()
  source_docs[path] = {
    ..source_docs.get(path).unwrap(),
    review: source_docs.get(path).unwrap().review.map(review => {
      ..review,
      view_mode: ReviewSource,
    }),
  }
  let (_, parked) = update(
    test_emit(),
    ReviewDiffNavigationAvailabilityChanged(true),
    { ..state, docs: source_docs, },
    ctx,
  )
  // Source mode parks the completed DiffEditor pair. Retain its availability
  // so returning to the same full diff does not require a provider rerun;
  // full_diff_ready still hides the controls and rejects clicks meanwhile.
  assert_true(parked.review_diff_navigation_available)
  let (_, hidden_previous_rejected) = update(
    test_emit(),
    RevealPreviousReviewDiffChange,
    parked,
    ctx,
  )
  let (_, hidden_next_rejected) = update(
    test_emit(),
    RevealNextReviewDiffChange,
    parked,
    ctx,
  )
  assert_true(hidden_previous_rejected == parked)
  assert_true(hidden_next_rejected == parked)
}

///|
test "full diff layout toggles independently and source mode preserves it" {
  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = reviewed_doc(path, selected)
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, inline) = update(
    test_emit(),
    ToggleReviewDiffLayout,
    { ..owned_state(), docs, },
    ctx,
  )
  assert_true(inline.review_diff_layout is ReviewInline)
  let source_docs = inline.docs.copy()
  source_docs[path] = {
    ..source_docs.get(path).unwrap(),
    review: source_docs.get(path).unwrap().review.map(review => {
      ..review,
      view_mode: ReviewSource,
    }),
  }
  let (_, unchanged) = update(
    test_emit(),
    ToggleReviewDiffLayout,
    { ..inline, docs: source_docs, },
    ctx,
  )
  assert_true(unchanged.review_diff_layout is ReviewInline)
}

///|
test "full diff remains selected when opening another changed file" {
  let first_path = @pathx.Relative("src/first.mbt")
  let second_path = @pathx.Relative("src/second.mbt")
  let first_change = test_modified_change(first_path)
  let second_change = test_modified_change(second_path)
  let docs = owned_state().docs.copy()
  docs[first_path] = reviewed_doc(
    first_path,
    first_change,
    view_mode=ReviewSource,
  )
  let first_ctx = {
    ..test_ctx(),
    open_files: [first_path],
    active_file: Some(first_path),
  }
  let (_, full_diff) = update(
    test_emit(),
    ToggleReviewDiff,
    { ..owned_state(), docs, review_view_mode: ReviewSource, },
    first_ctx,
  )
  assert_true(full_diff.review_view_mode is ReviewDiff)
  assert_true(
    full_diff.docs.get(first_path)
    is Some({ review: Some({ view_mode: ReviewDiff, .. }), .. }),
  )

  let second_ctx = {
    ..first_ctx,
    open_files: [first_path, second_path],
    active_file: Some(second_path),
  }
  let (_, switched) = open_changed_document(
    test_emit(),
    full_diff,
    second_ctx,
    second_change,
    had_active=true,
  )
  assert_true(
    switched.docs.get(second_path)
    is Some({ review: Some({ view_mode: ReviewDiff, .. }), .. }),
  )

  let loaded_docs = switched.docs.copy()
  loaded_docs[second_path] = reviewed_doc(
    second_path,
    second_change,
    baseline="second old source",
    generation=switched.review_generation,
  )
  let (_, source_again) = update(
    test_emit(),
    ToggleReviewDiff,
    { ..switched, docs: loaded_docs, },
    second_ctx,
  )
  assert_true(source_again.review_view_mode is ReviewSource)
  for path in [first_path, second_path] {
    assert_true(
      source_again.docs.get(path)
      is Some({ review: Some({ view_mode: ReviewSource, .. }), .. }),
    )
  }
}
