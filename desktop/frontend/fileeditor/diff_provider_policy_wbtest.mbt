///|
test "semantic review is available only for MoonBit source files" {
  assert_true(supports_moon_diff("SRC/MAIN.MBT"))
  assert_false(supports_moon_diff("src/main.mbti"))
}

///|
test "selecting a Moon semantic algorithm enters Diff view and retains policy" {
  let initial = State::empty()
  assert_true(initial.review_diff_mode is ReviewDiffLine)
  assert_true(initial.review_diff_ignore_comments)
  assert_true(initial.review_diff_ignore_tests)

  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = reviewed_doc(path, selected, view_mode=ReviewSource)
  let state = { ..owned_state(), docs, review_view_mode: ReviewSource, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, line_unchanged) = update(
    test_emit(),
    ToggleReviewDiffIgnoreTests,
    state,
    ctx,
  )
  assert_true(line_unchanged == state)
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
  let (_, include_comments) = update(
    test_emit(),
    ToggleReviewDiffIgnoreComments,
    tree,
    ctx,
  )
  assert_false(include_comments.review_diff_ignore_comments)
  let (_, include_tests) = update(
    test_emit(),
    ToggleReviewDiffIgnoreTests,
    include_comments,
    ctx,
  )
  assert_false(include_tests.review_diff_ignore_tests)
}

///|
test "semantic review preferences survive owner replacement" {
  let configured = {
    ..owned_state(),
    review_diff_mode: ReviewDiffTree,
    review_diff_ignore_comments: false,
    review_diff_ignore_tests: false,
  }
  let next_owner : @interop.ConversationKey = {
    ..test_ctx().owner,
    session: "next-session",
  }
  let prepared = configured.prepare_owner(next_owner, [])
  assert_true(prepared.review_diff_mode is ReviewDiffTree)
  assert_false(prepared.review_diff_ignore_comments)
  assert_false(prepared.review_diff_ignore_tests)
}

///|
test "non-MoonBit review parks the last semantic review preference" {
  let path = @pathx.Relative("README.md")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = reviewed_doc(path, selected, baseline="old text")
  let state = { ..owned_state(), docs, review_diff_mode: ReviewDiffTree, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, unchanged) = update(
    test_emit(),
    ReviewDiffModeSelected(ReviewDiffToken),
    state,
    ctx,
  )
  assert_true(unchanged.review_diff_mode is ReviewDiffTree)
  let (_, filters_unchanged) = update(
    test_emit(),
    ToggleReviewDiffIgnoreTests,
    state,
    ctx,
  )
  assert_true(filters_unchanged == state)
}
