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
test "review progress toggles only the active exact change" {
  let (state, ctx, selected) = review_progress_state()
  let (_, reviewed) = update(test_emit(), ToggleReviewProgress, state, ctx)
  assert_true(reviewed.reviewed_changes == [selected])
  let (_, unreviewed) = update(test_emit(), ToggleReviewProgress, reviewed, ctx)
  assert_true(unreviewed.reviewed_changes.is_empty())

  let ordinary_docs = state.docs.copy()
  ordinary_docs[selected.path] = {
    ..ordinary_docs.get(selected.path).unwrap(),
    review: None,
  }
  let ordinary = { ..state, docs: ordinary_docs, }
  let (_, unchanged) = update(test_emit(), ToggleReviewProgress, ordinary, ctx)
  assert_true(unchanged == ordinary)
}

///|
test "a final changes refresh invalidates progress when the row changes" {
  let (state, ctx, selected) = review_progress_state()
  let (_, reviewed) = update(test_emit(), ToggleReviewProgress, state, ctx)
  let changed_again = { ..selected, index_status: "M", worktree_status: " ", }
  let refreshing = {
    ..reviewed,
    changes: ChangeListReady(
      repository=true,
      files=[selected],
      refreshing=true,
      refresh_again=false,
    ),
  }
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=ctx.owner,
      generation=refreshing.changes_generation,
      repository=true,
      head=None,
      files=[changed_again],
    ),
    refreshing,
    ctx,
  )
  assert_true(settled.reviewed_changes.is_empty())

  let same_row_refresh = {
    ..reviewed,
    changes: ChangeListReady(
      repository=true,
      files=[selected],
      refreshing=true,
      refresh_again=false,
    ),
    changes_head: Some("old-head"),
    changes_head_known: true,
  }
  let (_, moved_head) = update(
    test_emit(),
    ChangesLoaded(
      owner=ctx.owner,
      generation=same_row_refresh.changes_generation,
      repository=true,
      head=Some("new-head"),
      files=[selected],
    ),
    same_row_refresh,
    ctx,
  )
  assert_true(moved_head.reviewed_changes.is_empty())
}

///|
test "file events and run completion invalidate stale review progress" {
  let (state, ctx, selected) = review_progress_state()
  let (_, reviewed) = update(test_emit(), ToggleReviewProgress, state, ctx)
  let (_, unrelated) = update(
    test_emit(),
    FsChanged(
      root=ctx.test_root(),
      generation=ctx.watch_identity(state.watch_generation),
      changes=Some([Modified(@pathx.Relative("README.md"))]),
    ),
    reviewed,
    ctx,
  )
  assert_true(unrelated.reviewed_changes == [selected])

  let (_, touched) = update(
    test_emit(),
    FsChanged(
      root=ctx.test_root(),
      generation=ctx.watch_identity(state.watch_generation),
      changes=Some([Modified(selected.path)]),
    ),
    unrelated,
    ctx,
  )
  assert_true(touched.reviewed_changes.is_empty())

  let (_, remarked) = update(test_emit(), ToggleReviewProgress, touched, ctx)
  let (_, settled) = update(
    test_emit(),
    RunSettled(owner=ctx.owner),
    remarked,
    ctx,
  )
  assert_true(settled.reviewed_changes.is_empty())
}
