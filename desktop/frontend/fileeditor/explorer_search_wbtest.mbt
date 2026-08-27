///|
test "editor Search highlights follow the Search inventory visibility boundary" {
  let ctx = test_ctx()
  guard ctx.root() is Some(root) else { fail("test checkout root expected") }
  let path = @pathx.Relative("src/main.mbt")
  let search = @grep_search.State::empty()
  let request_id = search.request_id()
  let reply : @protocol.SearchTextReply = {
    root: root.path,
    request_id,
    matches: [
      {
        path: path.0,
        line_number: 3,
        preview: "needle needle",
        preview_start_column: 1,
        ranges: [
          { start_column: 1, end_column: 7, },
          { start_column: 8, end_column: 14, },
        ],
      },
    ],
    match_count: 2,
    file_count: 1,
    limit_hit: false,
    cancelled: false,
    error: None,
  }
  let search = search.handle(@grep_search.Loaded(reply~), ctx.search_input())
  let visible = { ..owned_state(), explorer_mode: ExplorerSearch, search }
  guard visible.editor_search_highlights(path) is Some(highlights) else {
    fail("Search inventory should expose active editor matches")
  }
  assert_eq(highlights.ranges(), [
    @common.Range(3, 1, 3, 7),
    @common.Range(3, 8, 3, 14),
  ])
  assert_true(
    { ..visible, explorer_mode: ExplorerFiles, }.editor_search_highlights(path)
    is None,
  )
}

///|
test "Explorer tab keyboard navigation wraps and honors Home and End" {
  assert_true(
    explorer_tab_key_target(ExplorerFiles, "ArrowRight") ==
    Some(ExplorerChanges),
  )
  assert_true(
    explorer_tab_key_target(ExplorerChanges, "ArrowDown") ==
    Some(ExplorerSearch),
  )
  assert_true(
    explorer_tab_key_target(ExplorerSearch, "ArrowRight") == Some(ExplorerFiles),
  )
  assert_true(
    explorer_tab_key_target(ExplorerFiles, "ArrowLeft") == Some(ExplorerSearch),
  )
  assert_true(
    explorer_tab_key_target(ExplorerSearch, "ArrowUp") == Some(ExplorerChanges),
  )
  assert_true(
    explorer_tab_key_target(ExplorerChanges, "Home") == Some(ExplorerFiles),
  )
  assert_true(
    explorer_tab_key_target(ExplorerFiles, "End") == Some(ExplorerSearch),
  )
  assert_true(explorer_tab_key_target(ExplorerFiles, "Enter") is None)
}
