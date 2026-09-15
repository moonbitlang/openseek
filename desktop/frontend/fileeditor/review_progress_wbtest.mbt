///|
fn review_progress_state() -> (State, Ctx, ChangedFile) raise {
  let path = @pathx.Relative("src/main.mbt")
  let selected = test_modified_change(path)
  let docs = owned_state().docs.copy()
  docs[path] = reviewed_doc(path, selected)
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
  file_changes : ReviewHunk,
  index : Int,
  total : Int,
) -> State {
  update(
    test_emit(),
    ReviewActiveHunkChanged(
      ready=true,
      change=selected,
      review_generation=1,
      surface_generation=state.review_hunk_surface_generation,
      hunk=Some(hunk),
      file_changes=Some(file_changes),
      position=ReviewHunkPosition::from_zero_based(Some(index), total),
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
test "hunk and file review progress stay linked in both directions" {
  let (state, ctx, selected) = review_progress_state()
  let inserted = review_test_hunk(1, 1, 3, 5)
  let deleted = review_test_hunk(8, 10, 1, 1)
  let file_changes = inserted.union(deleted)
  let inserted_active = activate_review_hunk(
    state, ctx, selected, inserted, file_changes, 0, 2,
  )
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
    inserted_viewed, ctx, selected, deleted, file_changes, 1, 2,
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
  assert_true(both_viewed.changed_file_review_state(selected) is ReviewComplete)
  assert_true(
    both_viewed.review_hunk_state(selected, inserted) is ReviewHunkViewed,
  )

  let inserted_active = activate_review_hunk(
    both_viewed, ctx, selected, inserted, file_changes, 0, 2,
  )
  let (_, one_unviewed) = update(
    test_emit(),
    ToggleActiveReviewHunk,
    inserted_active,
    ctx,
  )
  assert_true(
    one_unviewed.changed_file_review_state(selected) is ReviewInProgress,
  )
  assert_true(
    one_unviewed.review_hunk_state(selected, inserted) is ReviewHunkUnviewed,
  )
  assert_true(
    one_unviewed.review_hunk_state(selected, deleted) is ReviewHunkViewed,
  )
  let overlapping = ReviewHunk(old_ranges=[@common.LineRange(9, 12)], new_ranges=[])
  assert_true(
    one_unviewed.review_hunk_state(selected, overlapping) is ReviewHunkPartial,
  )

  let (_, file_complete) = update(
    test_emit(),
    ToggleReviewProgress,
    one_unviewed,
    ctx,
  )
  assert_true(
    file_complete.review_hunk_state(selected, inserted) is ReviewHunkViewed,
  )
  assert_true(
    file_complete.review_hunk_state(selected, deleted) is ReviewHunkViewed,
  )
  let (_, file_unviewed) = update(
    test_emit(),
    ToggleReviewProgress,
    file_complete,
    ctx,
  )
  assert_true(
    file_unviewed.changed_file_review_state(selected) is ReviewUnviewed,
  )
  assert_true(
    file_unviewed.review_hunk_state(selected, inserted) is ReviewHunkUnviewed,
  )
  assert_true(
    file_unviewed.review_hunk_state(selected, deleted) is ReviewHunkUnviewed,
  )
}

///|
test "active hunk requires exact row, diff generation, and surface generation" {
  let (state, ctx, selected) = review_progress_state()
  let hunk = review_test_hunk(2, 4, 2, 4)
  let position = ReviewHunkPosition::from_zero_based(Some(0), 1)
  let (_, stale_generation) = update(
    test_emit(),
    ReviewActiveHunkChanged(
      ready=true,
      change=selected,
      review_generation=0,
      surface_generation=state.review_hunk_surface_generation,
      hunk=Some(hunk),
      file_changes=Some(hunk),
      position~,
    ),
    state,
    ctx,
  )
  assert_true(stale_generation.review_active_hunk is None)
  assert_false(stale_generation.review_navigation_ready(ctx.active_file))
  let other = { ..selected, index_status: "M", worktree_status: " ", }
  let (_, stale_row) = update(
    test_emit(),
    ReviewActiveHunkChanged(
      ready=true,
      change=other,
      review_generation=1,
      surface_generation=state.review_hunk_surface_generation,
      hunk=Some(hunk),
      file_changes=Some(hunk),
      position~,
    ),
    state,
    ctx,
  )
  assert_true(stale_row.review_active_hunk is None)
  assert_false(stale_row.review_navigation_ready(ctx.active_file))
  let inactive_ctx = {
    ..ctx,
    active_file: Some(@pathx.Relative("src/other.mbt")),
  }
  let inactive = activate_review_hunk(
    state, inactive_ctx, selected, hunk, hunk, 0, 1,
  )
  assert_true(inactive.review_active_hunk is None)
  let current = activate_review_hunk(state, ctx, selected, hunk, hunk, 0, 1)
  let surface_generation = state.review_hunk_surface_generation
  assert_true(
    current.active_review_hunk(ctx.active_file)
    is Some(
      {
        change,
        review_generation: 1,
        surface_generation: active_surface_generation,
        hunk: current_hunk,
        file_changes: Some(current_file_changes),
        position: Some(current_position),
      }
    ) &&
    change == selected &&
    active_surface_generation == surface_generation &&
    current_hunk == hunk &&
    current_file_changes == hunk &&
    current_position.current == 1 &&
    current_position.total == 1,
  )
  let (_, token_surface) = update(
    test_emit(),
    ReviewDiffModeSelected(ReviewDiffToken),
    current,
    ctx,
  )
  let (_, line_surface) = update(
    test_emit(),
    ReviewDiffModeSelected(ReviewDiffLine),
    token_surface,
    ctx,
  )
  assert_eq(line_surface.review_hunk_surface_generation, surface_generation + 2)
  let (_, late_surface) = update(
    test_emit(),
    ReviewActiveHunkChanged(
      ready=true,
      change=selected,
      review_generation=1,
      surface_generation~,
      hunk=Some(hunk),
      file_changes=Some(hunk),
      position~,
    ),
    line_surface,
    ctx,
  )
  assert_true(late_surface.review_active_hunk is None)
}

///|
test "empty review completion reveals navigation and is invalidated with its surface" {
  let (state, ctx, selected) = review_progress_state()
  assert_false(state.review_navigation_ready(ctx.active_file))
  let ready = state.accept_active_review_hunk(
    selected,
    1,
    state.review_hunk_surface_generation,
    None,
    None,
    None,
    ctx.active_file,
    ready=true,
  )
  assert_true(ready.review_active_hunk is None)
  assert_true(ready.review_navigation_ready(ctx.active_file))
  let invalidated = ready.clear_review_active_hunk()
  assert_false(invalidated.review_navigation_ready(ctx.active_file))
  let stale = invalidated.accept_active_review_hunk(
    selected,
    1,
    state.review_hunk_surface_generation,
    None,
    None,
    None,
    ctx.active_file,
    ready=true,
  )
  assert_false(stale.review_navigation_ready(ctx.active_file))
}

///|
test "navigation retains the completed presentation until a replacement completes" {
  let (state, ctx, selected) = review_progress_state()
  let other_path = @pathx.Relative("src/other.mbt")
  let other = test_modified_change(other_path)
  let docs = state.docs.copy()
  docs[other_path] = reviewed_doc(other_path, other)
  let state = {
    ..state,
    docs,
    changes: ChangeListReady(
      repository=true,
      files=[selected, other],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let hunk = review_test_hunk(2, 4, 2, 4)
  let displayed = activate_review_hunk(state, ctx, selected, hunk, hunk, 0, 1).sync_review_navigation_display(
    ctx,
  )
  let next_ctx = { ..ctx, active_file: Some(other_path), }
  let pending = displayed
    .clear_review_active_hunk()
    .sync_review_navigation_display(next_ctx)
  assert_true(
    pending.review_navigation_display == displayed.review_navigation_display,
  )
  assert_false(review_navigation_complete(pending, next_ctx))
  let completed = activate_review_hunk(
    pending, next_ctx, other, hunk, hunk, 0, 15,
  ).sync_review_navigation_display(next_ctx)
  assert_true(
    completed.review_navigation_display
    is Some(
      {
        file_position: Some((1, 2)),
        position: Some({ current: 1, total: 15, }),
        ..
      }
    ),
  )
  // An empty result is also a complete presentation, and must retire the
  // previous file's hunk controls rather than retaining them forever.
  let empty = completed
    .accept_active_review_hunk(
      other,
      1,
      completed.review_hunk_surface_generation,
      None,
      None,
      None,
      next_ctx.active_file,
      ready=true,
    )
    .sync_review_navigation_display(next_ctx)
  assert_true(
    empty.review_navigation_display
    is Some({ position: None, hunk_toggle: None, .. }),
  )
  let inactive = empty.sync_review_navigation_display({
    ..ctx,
    active_file: None,
  })
  assert_true(inactive.review_navigation_display is None)
}
