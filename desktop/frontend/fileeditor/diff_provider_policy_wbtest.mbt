///|
test "diff provider forces Core outside .mbt without overwriting preference" {
  assert_true(
    effective_diff_provider_mode(ReviewDiffTree, true)
    is @moon_diff_provider.Tree,
  )
  assert_true(
    effective_diff_provider_mode(ReviewDiffTree, false)
    is @moon_diff_provider.Core,
  )
  assert_true(supports_moon_diff("SRC/MAIN.MBT"))
  assert_false(supports_moon_diff("src/main.mbti"))
}

///|
test "selecting a Moon diff algorithm enters Diff view and retains policy" {
  let initial = State::empty()
  assert_true(initial.review_diff_mode is ReviewDiffCore)
  assert_true(initial.review_diff_ignore_comments)
  assert_eq(initial.review_diff_status, None)

  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("old source"),
      view_mode: ReviewSource,
      selected,
    }),
  }
  let state = { ..owned_state(), docs, review_view_mode: ReviewSource, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, tree) = update(
    test_emit(),
    ReviewDiffModeSelected(ReviewDiffTree),
    state,
    ctx,
  )
  assert_true(tree.review_diff_mode is ReviewDiffTree)
  assert_true(tree.review_view_mode is ReviewDiff)
  assert_true(
    tree.docs.get(path)
    is Some({ review: Some({ view_mode: ReviewDiff, .. }), .. }),
  )
  assert_eq(tree.review_diff_status, None)
  let (_, include_comments) = update(
    test_emit(),
    ToggleReviewDiffIgnoreComments,
    tree,
    ctx,
  )
  assert_false(include_comments.review_diff_ignore_comments)
  let fallback : ReviewDiffStatus = {
    requested: ReviewDiffTree,
    effective: ReviewDiffToken,
    fell_back: true,
  }
  let (_, settled) = update(
    test_emit(),
    ReviewDiffStatusChanged(fallback),
    include_comments,
    ctx,
  )
  assert_eq(settled.review_diff_status, Some(fallback))
}

///|
test "non-MoonBit review parks the last Moon provider preference" {
  let path = @pathx.Relative("README.md")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("old text"),
      view_mode: ReviewDiff,
      selected,
    }),
  }
  let state = { ..owned_state(), docs, review_diff_mode: ReviewDiffTree, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, unchanged) = update(
    test_emit(),
    ReviewDiffModeSelected(ReviewDiffToken),
    state,
    ctx,
  )
  assert_true(unchanged.review_diff_mode is ReviewDiffTree)
}
