///|
test "review navigation skips unavailable rows and stops at queue edges" {
  let first = test_modified_change(@pathx.Relative("first.mbt"))
  let unavailable = {
    ..test_modified_change(@pathx.Relative("link.mbt")),
    kind: ChangeSymlink,
  }
  let last = test_modified_change(@pathx.Relative("last.mbt"))
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[first, unavailable, last],
      refreshing=false,
      refresh_again=false,
    ),
  }
  assert_true(review_neighbor(state, first, -1) is None)
  assert_true(review_neighbor(state, first, 1) == Some(last))
  assert_true(review_neighbor(state, last, -1) == Some(first))
  assert_true(review_neighbor(state, last, 1) is None)
  assert_true(review_edge(state, first, first=true) is None)
  assert_true(review_edge(state, first, first=false) == Some(last))
  assert_true(review_edge(state, last, first=true) == Some(first))
  assert_true(review_edge(state, last, first=false) is None)
  assert_true(change_row_index(state, first) == Some(0))
  assert_true(change_row_index(state, last) == Some(2))
}

///|
test "review navigation distinguishes duplicate same-path Git rows" {
  let path = @pathx.Relative("same.mbt")
  let deleted = {
    ..test_modified_change(path),
    index_status: "D",
    worktree_status: " ",
    kind: ChangeDeleted,
  }
  let untracked = {
    ..test_modified_change(path),
    index_status: "?",
    worktree_status: "?",
    kind: ChangeUntracked,
  }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[deleted, untracked],
      refreshing=false,
      refresh_again=false,
    ),
  }
  assert_true(review_neighbor(state, deleted, 1) == Some(untracked))
  assert_true(review_neighbor(state, untracked, -1) == Some(deleted))
  let marked = state.set_review_file_progress(deleted, Some(ReviewFileComplete))
  assert_true(review_neighbor(marked, deleted, 1) == Some(untracked))
  assert_true(review_neighbor(marked, untracked, -1) is None)
}

///|
test "review navigation skips reviewed files while retaining visible row positions" {
  let first = test_modified_change(@pathx.Relative("first.mbt"))
  let middle = test_modified_change(@pathx.Relative("middle.mbt"))
  let last = test_modified_change(@pathx.Relative("last.mbt"))
  let docs = owned_state().docs.copy()
  docs[test_file(first.path.0)] = reviewed_doc(first.path, first)
  let ctx = { ..test_ctx(), active_file: Some(test_file(first.path.0)), }
  let state = {
    ..owned_state(),
    docs,
    changes: ChangeListReady(
      repository=true,
      files=[first, middle, last],
      refreshing=false,
      refresh_again=false,
    ),
  }.set_review_file_progress(middle, Some(ReviewFileComplete))
  assert_true(review_neighbor(state, first, 1) == Some(last))
  assert_true(review_neighbor(state, last, -1) == Some(first))
  assert_true(review_navigation_neighbor(state, ctx, true) == Some(last))
  assert_eq(change_row_index(state, middle), Some(1))
  assert_true(active_review_position(state, ctx) is Some((_, 0, 3)))
  let filtered = { ..state, change_path_filter: "middle", }
  assert_true(active_review_position(filtered, ctx) is None)
  assert_true(active_review_change(filtered, ctx) == Some(first))
  let only_first = state.set_review_file_progress(
    last,
    Some(ReviewFileComplete),
  )
  assert_true(review_navigation_neighbor(only_first, ctx, false) is None)
  let complete = only_first.set_review_file_progress(
    first,
    Some(ReviewFileComplete),
  )
  assert_false(review_diff_navigation_enabled(complete, ctx))
  let reopened = complete.set_review_file_progress(middle, None)
  assert_true(review_navigation_neighbor(reopened, ctx, false) == Some(middle))
}

///|
test "hunk navigation skips viewed coverage in both directions and retains partial hunks" {
  let (state, _, change) = review_progress_state()
  let hunks = [
    review_test_hunk(1, 2, 1, 2),
    review_test_hunk(10, 12, 10, 12),
    review_test_hunk(20, 21, 20, 21),
  ]
  let marked = state.set_review_file_progress(
    change,
    Some(ReviewFileInProgress(hunks[1])),
  )
  assert_eq(
    review_hunk_navigation_index(marked, Some(change), hunks, Some(0), false),
    Some(2),
  )
  assert_eq(
    review_hunk_navigation_index(marked, Some(change), hunks, Some(2), true),
    Some(0),
  )
  assert_eq(
    review_hunk_navigation_index(marked, Some(change), hunks, None, false),
    Some(0),
  )
  assert_eq(
    review_hunk_navigation_index(marked, Some(change), hunks, None, true),
    Some(2),
  )
  let partial = state.set_review_file_progress(
    change,
    Some(ReviewFileInProgress(review_test_hunk(10, 11, 10, 11))),
  )
  assert_eq(
    review_hunk_navigation_index(partial, Some(change), hunks, Some(0), false),
    Some(1),
  )
  assert_eq(
    review_hunk_navigation_index(partial, Some(change), hunks, Some(2), true),
    Some(1),
  )
  let complete = state.set_review_file_progress(
    change,
    Some(ReviewFileComplete),
  )
  assert_eq(
    review_hunk_navigation_index(complete, Some(change), hunks, None, false),
    None,
  )
  assert_eq(
    review_hunk_navigation_index(complete, Some(change), hunks, None, true),
    None,
  )
  // Historical comparisons have no working-tree review identity or coverage.
  assert_eq(
    review_hunk_navigation_index(complete, None, hunks, Some(0), false),
    Some(1),
  )
}

///|
test "continuous review navigation wraps the selectable queue even with an empty diff" {
  let first = test_modified_change(@pathx.Relative("first.mbt"))
  let last = test_modified_change(@pathx.Relative("last.mbt"))
  let unavailable = {
    ..first,
    path: @pathx.Relative("link.mbt"),
    kind: ChangeSymlink,
  }
  let docs = owned_state().docs.copy()
  docs[test_file(first.path.0)] = reviewed_doc(first.path, first)
  docs[test_file(last.path.0)] = reviewed_doc(last.path, last)
  let state = {
    ..owned_state(),
    docs,
    changes: ChangeListReady(
      repository=true,
      files=[first, unavailable, last],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let first_ctx = { ..test_ctx(), active_file: Some(test_file(first.path.0)), }
  let last_ctx = { ..test_ctx(), active_file: Some(test_file(last.path.0)), }
  assert_true(review_diff_navigation_enabled(state, first_ctx))
  assert_true(review_navigation_neighbor(state, first_ctx, true) == Some(last))
  assert_true(review_navigation_neighbor(state, first_ctx, false) == Some(last))
  assert_true(review_navigation_neighbor(state, last_ctx, false) == Some(first))
  assert_true(review_navigation_neighbor(state, last_ctx, true) == Some(first))
}

///|
test "cross-file navigation stops after one cycle when filters hide all outstanding changes" {
  let (initial, first_ctx, first) = review_progress_state()
  let last = test_modified_change(@pathx.Relative("src/last.mbt"))
  let docs = initial.docs.copy()
  docs[test_file(last.path.0)] = reviewed_doc(last.path, last)
  let state = {
    ..initial,
    docs,
    changes: ChangeListReady(
      repository=true,
      files=[first, last],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let last_ctx = { ..first_ctx, active_file: Some(test_file(last.path.0)), }
  for previous in [false, true] {
    let messages : Array[Msg] = []
    let emit = @cmd.Emit(message => {
      messages.push(message)
      @cmd.none
    })
    let (_, first_step) = update(
      emit,
      ReviewDiffFileBoundary(previous),
      state,
      first_ctx,
    )
    assert_true(
      messages is [ChangedFileNavigated(change, direction)] &&
      change == last &&
      direction == previous,
    )
    assert_eq(first_step.review_navigation_remaining, Some(1))
    messages.clear()
    let (_, last_step) = update(
      emit,
      ReviewDiffFileBoundary(previous),
      first_step,
      last_ctx,
    )
    assert_true(
      messages is [ChangedFileNavigated(change, direction)] &&
      change == first &&
      direction == previous,
    )
    assert_eq(last_step.review_navigation_remaining, Some(0))
    messages.clear()
    let (_, stopped) = update(
      emit,
      ReviewDiffFileBoundary(previous),
      last_step,
      first_ctx,
    )
    assert_true(messages.is_empty())
    assert_true(stopped == state)
  }
}

///|
test "cross-file reveal waits for content and cancels when its review is superseded" {
  let path = @pathx.Relative("last.mbt")
  let file = test_file(path.0)
  let change = test_modified_change(path)
  let doc = reviewed_doc(path, change)
  let docs = owned_state().docs.copy()
  docs[file] = {
    ..doc,
    review: doc.review.map(review => { ..review, baseline: ReviewLoading, }),
  }
  let ctx = { ..test_ctx(), active_file: Some(file), }
  let state = {
    ..owned_state(),
    docs,
    changes: ChangeListReady(
      repository=true,
      files=[change],
      refreshing=false,
      refresh_again=false,
    ),
  }.with_review_navigation_destination(ctx, change, true)
  let (_, waiting) = sync_review_navigation_destination(test_emit(), state, ctx)
  assert_true(waiting.review_navigation_destination is Some((_, 1, true)))
  let (_, cancelled) = sync_review_navigation_destination(
    test_emit(),
    waiting,
    { ..ctx, active_file: None, },
  )
  assert_true(cancelled.review_navigation_destination is None)
  let replaced_docs = docs.copy()
  replaced_docs[file] = {
    ..doc,
    review: doc.review.map(review => { ..review, generation: 2, }),
  }
  let (_, replaced) = sync_review_navigation_destination(
    test_emit(),
    { ..waiting, docs: replaced_docs, },
    ctx,
  )
  assert_true(replaced.review_navigation_destination is None)
  let ready_docs = docs.copy()
  ready_docs[file] = doc
  let (_, awaiting_diff) = sync_review_navigation_destination(
    test_emit(),
    { ..waiting, docs: ready_docs, },
    ctx,
  )
  assert_true(awaiting_diff.review_navigation_destination is Some(_))
  let (_, completed) = sync_review_navigation_destination(
    test_emit(),
    {
      ..awaiting_diff,
      review_hunk_ready: Some(
        (change, 1, awaiting_diff.review_hunk_surface_generation),
      ),
    },
    ctx,
  )
  assert_true(completed.review_navigation_destination is None)
}

///|
test "path-filtered navigation and row indexes use the visible list" {
  let first = test_modified_change(Relative("src/first.mbt"))
  let hidden = test_modified_change(Relative("docs/readme.md"))
  let last = test_modified_change(Relative("src/last.mbt"))
  let state = {
    ..owned_state(),
    change_path_filter: "SRC/",
    changes: ChangeListReady(
      repository=true,
      files=[first, hidden, last],
      refreshing=false,
      refresh_again=false,
    ),
  }
  assert_true(filtered_changes(state) == [first, last])
  assert_true(review_neighbor(state, first, 1) == Some(last))
  assert_eq(change_row_index(state, last), Some(1))
  assert_eq(change_row_index(state, hidden), None)
  assert_true(review_neighbor(state, hidden, 1) is None)
}

///|
test "extension filters intersect paths and keep full-list counts" {
  let source = test_modified_change(Relative("src/main.mbt"))
  let doc = test_modified_change(Relative("src/guide.md"))
  let other = test_modified_change(Relative("docs/guide.md"))
  let plain = test_modified_change(Relative("LICENSE"))
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[source, doc, other, plain],
      refreshing=false,
      refresh_again=false,
    ),
    change_path_filter: "src/",
    change_extensions: Some([Some(".md")]),
  }
  assert_true(filtered_changes(state) == [doc])
  assert_eq(change_extension_options(state), [
    (Some(".mbt"), 1),
    (Some(".md"), 2),
    (None, 1),
  ])
  assert_true(
    filtered_changes({ ..state, change_extensions: Some([]), }).is_empty(),
  )
  assert_true(
    filtered_changes({ ..state, change_extensions: None, }) == [source, doc],
  )
  assert_true(
    filtered_changes({
      ..state,
      change_path_filter: "",
      change_extensions: Some([None]),
    }) ==
    [plain],
  )
}

///|
test "history filtering shares matching but owns its inventory and counts" {
  let workspace = test_modified_change(Relative("workspace.mbt"))
  let renamed : @protocol.GitHistoricalChange = {
    path: "docs/new.md",
    original_path: Some("old/readme.md"),
    status: "renamed",
    kind: "file",
  }
  let plain : @protocol.GitHistoricalChange = {
    path: "LICENSE",
    original_path: None,
    status: "added",
    kind: "file",
  }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[workspace],
      refreshing=false,
      refresh_again=false,
    ),
    git_graph_selected: Some("commit-a"),
    git_commit_files: GitCommitFilesReady(commit="commit-a", parent=None, files=[
      renamed, plain,
    ]),
    change_path_filter: "OLD/",
    change_extensions: Some([Some(".md")]),
  }
  assert_eq(filtered_history_changes(state, [renamed, plain]), [renamed])
  assert_true(filtered_changes(state) == [workspace])
  assert_eq(change_extension_options(state), [(Some(".md"), 1), (None, 1)])
  assert_true(
    review_filter_inventory({ ..state, git_graph_selected: Some("commit-b"), })
    is None,
  )
  assert_true(
    review_filter_inventory({
      ..state,
      git_commit_files: GitCommitFilesLoading(commit="commit-a"),
    })
    is None,
  )
  assert_true(
    review_filter_inventory({
      ..state,
      git_commit_files: GitCommitFilesFailed(
        commit="commit-a",
        message="failed",
      ),
    })
    is None,
  )
  let working = {
    ..state,
    git_graph_selected: None,
    change_path_filter: "",
    change_extensions: None,
  }
  assert_eq(change_extension_options(working), [(Some(".mbt"), 1)])
  assert_true(filtered_changes(working) == [workspace])
}
