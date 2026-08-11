///|
test "new reviews default to the full diff" {
  let path = @pathx.Relative("src/main.mbt")
  let change = test_modified_change(path)
  let state = owned_state()
  assert_true(state.review_view_mode is ReviewUnifiedDiff)
  let (_, opened) = open_changed_document(
    test_emit(),
    state,
    { ..test_ctx(), open_files: [path], active_file: Some(path) },
    change,
    had_active=false,
  )
  assert_true(
    opened.docs.get(path)
    is Some({ review: Some({ view_mode: ReviewUnifiedDiff, .. }), .. }),
  )
}

///|
test "full diff remains selected when opening another changed file" {
  let first_path = @pathx.Relative("src/first.mbt")
  let second_path = @pathx.Relative("src/second.mbt")
  let first_change = test_modified_change(first_path)
  let second_change = test_modified_change(second_path)
  let docs = owned_state().docs.copy()
  docs[first_path] = {
    ..loaded_doc(first_path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("old source"),
      view_mode: ReviewSource,
      selected: first_change,
    }),
  }
  let first_ctx = {
    ..test_ctx(),
    open_files: [first_path],
    active_file: Some(first_path),
  }
  let (_, full_diff) = update(
    test_emit(),
    ToggleReviewDiff,
    { ..owned_state(), docs, review_view_mode: ReviewSource },
    first_ctx,
  )
  assert_true(full_diff.review_view_mode is ReviewUnifiedDiff)
  assert_true(
    full_diff.docs.get(first_path)
    is Some({ review: Some({ view_mode: ReviewUnifiedDiff, .. }), .. }),
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
    is Some({ review: Some({ view_mode: ReviewUnifiedDiff, .. }), .. }),
  )

  let loaded_docs = switched.docs.copy()
  loaded_docs[second_path] = {
    ..loaded_doc(second_path.0),
    review: Some({
      generation: switched.review_generation,
      working_generation: switched.review_generation,
      baseline: ReviewContent("second old source"),
      view_mode: ReviewUnifiedDiff,
      selected: second_change,
    }),
  }
  let (_, source_again) = update(
    test_emit(),
    ToggleReviewDiff,
    { ..switched, docs: loaded_docs },
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
