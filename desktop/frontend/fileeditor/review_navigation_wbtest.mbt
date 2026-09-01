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
      refreshing=None,
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
      refreshing=None,
      refresh_again=false,
    ),
  }
  assert_true(review_neighbor(state, deleted, 1) == Some(untracked))
  assert_true(review_neighbor(state, untracked, -1) == Some(deleted))
}
