///|
test "review navigation skips unavailable rows and stops at queue edges" {
  let first = test_modified_change(Relative("first.mbt"))
  let unavailable = {
    ..test_modified_change(Relative("link.mbt")),
    kind: ChangeSymlink,
  }
  let last = test_modified_change(Relative("last.mbt"))
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
}

///|
test "continuous review navigation wraps the selectable queue even with an empty diff" {
  let first = test_modified_change(Relative("first.mbt"))
  let last = test_modified_change(Relative("last.mbt"))
  let unavailable = {
    ..first,
    path: Relative("link.mbt"),
    kind: ChangeSymlink,
  }
  let docs = owned_state().docs.copy()
  docs[first.path] = reviewed_doc(first.path, first)
  docs[last.path] = reviewed_doc(last.path, last)
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
  let first_ctx = { ..test_ctx(), active_file: Some(first.path), }
  let last_ctx = { ..test_ctx(), active_file: Some(last.path), }
  assert_true(review_diff_navigation_enabled(state, first_ctx))
  assert_true(review_navigation_neighbor(state, first_ctx, true) == Some(last))
  assert_true(review_navigation_neighbor(state, first_ctx, false) == Some(last))
  assert_true(review_navigation_neighbor(state, last_ctx, false) == Some(first))
  assert_true(review_navigation_neighbor(state, last_ctx, true) == Some(first))
}

///|
test "cross-file reveal waits for content and cancels when its review is superseded" {
  let path = @pathx.Relative("last.mbt")
  let change = test_modified_change(path)
  let doc = reviewed_doc(path, change)
  let docs = owned_state().docs.copy()
  docs[path] = {
    ..doc,
    review: doc.review.map(review => { ..review, baseline: ReviewLoading, }),
  }
  let state = { ..owned_state(), docs, }.with_review_navigation_destination(
    change, true,
  )
  let ctx = { ..test_ctx(), active_file: Some(path), }
  let (_, waiting) = sync_review_navigation_destination(test_emit(), state, ctx)
  assert_true(waiting.review_navigation_destination is Some((_, 1, true)))
  let (_, cancelled) = sync_review_navigation_destination(
    test_emit(),
    waiting,
    { ..ctx, active_file: None, },
  )
  assert_true(cancelled.review_navigation_destination is None)
  let replaced_docs = docs.copy()
  replaced_docs[path] = {
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
  ready_docs[path] = doc
  let (_, completed) = sync_review_navigation_destination(
    test_emit(),
    { ..waiting, docs: ready_docs, },
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
