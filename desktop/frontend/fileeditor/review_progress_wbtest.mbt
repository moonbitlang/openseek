///|
fn review_progress_state() -> (State, Ctx, ChangedFile) raise {
  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 1,
      working_generation: 1,
      baseline: ReviewContent("old source"),
      view_mode: ReviewDiff,
      selected,
    }),
  }
  let state = {
    ..owned_state(),
    docs,
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[selected],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  (state, ctx, selected)
}

///|
fn review_test_hunk(
  old_start : Int,
  old_end : Int,
  new_start : Int,
  new_end : Int,
) -> ReviewHunk {
  ReviewHunk(
    old_ranges=if old_start < old_end {
      [@common.LineRange(old_start, old_end)]
    } else {
      []
    },
    new_ranges=if new_start < new_end {
      [@common.LineRange(new_start, new_end)]
    } else {
      []
    },
  )
}

///|
fn activate_review_hunk(
  state : State,
  ctx : Ctx,
  selected : ChangedFile,
  hunk : ReviewHunk,
) -> State {
  update(
    test_emit(),
    ReviewActiveHunkChanged(
      change=selected,
      review_generation=1,
      hunk=Some(hunk),
    ),
    state,
    ctx,
  ).1
}

///|
test "review hunk normalizes unions and subtraction" {
  let coverage = ReviewHunk(
    old_ranges=[
      @common.LineRange(4, 7),
      @common.LineRange(1, 3),
      @common.LineRange(3, 5),
      @common.LineRange(8, 8),
    ],
    new_ranges=[@common.LineRange(10, 13)],
  )
  assert_eq(coverage.old_ranges, [@common.LineRange(1, 7)])
  let removed = ReviewHunk(old_ranges=[@common.LineRange(2, 4)], new_ranges=[
    @common.LineRange(11, 12),
  ])
  let retained = coverage.subtract(removed)
  assert_eq(retained.old_ranges, [
    @common.LineRange(1, 2),
    @common.LineRange(4, 7),
  ])
  assert_eq(retained.new_ranges, [
    @common.LineRange(10, 11),
    @common.LineRange(12, 13),
  ])
  assert_true(retained.union(removed) == coverage)
}

///|
test "hunk toggles keep partial and one-sided coverage without completing file" {
  let (state, ctx, selected) = review_progress_state()
  let inserted = review_test_hunk(1, 1, 3, 5)
  let deleted = review_test_hunk(8, 10, 1, 1)
  let inserted_active = activate_review_hunk(state, ctx, selected, inserted)
  let (_, inserted_viewed) = update(
    test_emit(),
    ToggleActiveReviewHunk,
    inserted_active,
    ctx,
  )
  assert_true(
    inserted_viewed.review_hunk_state(selected, inserted) is ReviewHunkViewed,
  )
  let deleted_active = activate_review_hunk(
    inserted_viewed, ctx, selected, deleted,
  )
  let (_, both_viewed) = update(
    test_emit(),
    ToggleActiveReviewHunk,
    deleted_active,
    ctx,
  )
  assert_true(
    both_viewed.review_hunk_state(selected, deleted) is ReviewHunkViewed,
  )
  assert_true(
    both_viewed.changed_file_review_state(selected) is ReviewInProgress,
  )
  let overlapping = ReviewHunk(old_ranges=[@common.LineRange(9, 12)], new_ranges=[])
  assert_true(
    both_viewed.review_hunk_state(selected, overlapping) is ReviewHunkPartial,
  )

  let (_, complete) = update(
    test_emit(),
    ToggleReviewProgress,
    both_viewed,
    ctx,
  )
  let (_, unchanged) = update(
    test_emit(),
    ToggleActiveReviewHunk,
    complete,
    ctx,
  )
  assert_true(unchanged == complete)
}

///|
test "active hunk requires the exact changed row and review generation" {
  let (state, ctx, selected) = review_progress_state()
  let hunk = review_test_hunk(2, 4, 2, 4)
  let (_, stale_generation) = update(
    test_emit(),
    ReviewActiveHunkChanged(
      change=selected,
      review_generation=0,
      hunk=Some(hunk),
    ),
    state,
    ctx,
  )
  assert_true(stale_generation.review_active_hunk is None)
  let other = { ..selected, index_status: "M", worktree_status: " ", }
  let (_, stale_row) = update(
    test_emit(),
    ReviewActiveHunkChanged(change=other, review_generation=1, hunk=Some(hunk)),
    state,
    ctx,
  )
  assert_true(stale_row.review_active_hunk is None)
  let inactive_ctx = {
    ..ctx,
    active_file: Some(@pathx.Relative("src/other.mbt")),
  }
  let inactive = activate_review_hunk(state, inactive_ctx, selected, hunk)
  assert_true(inactive.review_active_hunk is None)
  let current = activate_review_hunk(state, ctx, selected, hunk)
  assert_true(
    current.active_review_hunk(ctx.active_file)
    is Some({ change, review_generation: 1, hunk: current_hunk, }) &&
    change == selected &&
    current_hunk == hunk,
  )
}
