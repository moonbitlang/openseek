///|
test "changed tree compacts directory chains but retains branches and exact Git rows" {
  let host = test_modified_change(
    Relative("desktop/backend/internal/host/open.mbt"),
  )
  let view = test_modified_change(Relative("desktop/frontend/view.mbt"))
  let deleted = { ..view, kind: ChangeDeleted, index_status: "D", }
  let readme = test_modified_change(Relative("README.md"))
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[host, view, deleted, readme],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let rows = change_tree_rows(state)
  assert_eq(rows.map(row => row.node.label), [
    "desktop", "backend/internal/host", "open.mbt", "frontend", "view.mbt", "view.mbt",
    "README.md",
  ])
  assert_eq(rows.map(row => row.depth), [0, 1, 2, 1, 2, 2, 0])
  assert_true(rows[4].node.item == ChangeFile(view))
  assert_true(rows[5].node.item == ChangeFile(deleted))
  let folded = {
    ..state,
    change_tree_collapsed: [Relative("desktop/backend/internal/host")],
    change_tree_focus: Some(ChangeFile(host)),
  }
  let visible = change_tree_rows(folded)
  assert_eq(visible.map(row => row.node.label), [
    "desktop", "backend/internal/host", "frontend", "view.mbt", "view.mbt", "README.md",
  ])
  assert_true(
    change_tree_focus_target(folded, visible) ==
    Some(ChangeDirectory(Relative("desktop/backend/internal/host"))),
  )
}

///|
test "directory review aggregates partial progress and only marks matching reviewable descendants" {
  let source = test_modified_change(Relative("src/main.mbt"))
  let doc = test_modified_change(Relative("src/readme.md"))
  let link = { ..source, path: Relative("src/link.mbt"), kind: ChangeSymlink, }
  let outside = test_modified_change(Relative("src-other/other.mbt"))
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[source, doc, link, outside],
      refreshing=false,
      refresh_again=false,
    ),
  }.set_review_file_progress(
    source,
    Some(ReviewFileInProgress(review_test_hunk(1, 2, 1, 2))),
  )
  assert_true(
    change_tree_review_state(state, [source, doc, link]) is ReviewInProgress,
  )
  let filtered = { ..state, change_extensions: Some([Some(".mbt")]), }.toggle_change_tree_review(
    ChangeDirectory(Relative("src")),
  )
  assert_true(filtered.is_change_reviewed(source))
  assert_true(!filtered.is_change_reviewed(doc))
  assert_true(!filtered.is_change_reviewed(link))
  assert_true(!filtered.is_change_reviewed(outside))
  let complete = { ..filtered, change_extensions: None, }.toggle_change_tree_review(
    ChangeDirectory(Relative("src")),
  )
  assert_true(
    change_tree_review_state(complete, [source, doc, link]) is ReviewComplete,
  )
  let cleared = complete.toggle_change_tree_review(
    ChangeDirectory(Relative("src")),
  )
  assert_true(cleared.review_progress.is_empty())
}

///|
test "tree checkboxes distinguish same-path reviews and ignore vanished rows" {
  let deleted = {
    ..test_modified_change(Relative("same.mbt")),
    kind: ChangeDeleted,
  }
  let untracked = { ..deleted, kind: ChangeUntracked, }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[deleted, untracked],
      refreshing=false,
      refresh_again=false,
    ),
  }.toggle_change_tree_review(ChangeFile(deleted))
  assert_true(state.is_change_reviewed(deleted))
  assert_true(!state.is_change_reviewed(untracked))
  let stale = state.toggle_change_tree_review(
    ChangeFile({ ..deleted, kind: ChangeModified, }),
  )
  assert_true(stale.review_progress == state.review_progress)
  let (_, filtered) = update(
    test_emit(),
    ChangePathFilterChanged("same"),
    { ..state, change_tree_collapsed: [Relative("src")], },
    test_ctx(),
  )
  assert_true(filtered.change_tree_collapsed.is_empty())
}
