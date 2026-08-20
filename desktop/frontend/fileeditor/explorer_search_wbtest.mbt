///|
#warnings("-alert_unstable")
fn render_explorer_for_test(state : State) -> String {
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(body_view(test_emit(), state, test_ctx()))
  })
}

///|
test "Explorer renders Files Changes Search as a roving tablist" {
  let ctx = test_ctx()
  let search = @grep_search.State::empty().handle(
    @grep_search.QueryChanged("needle"),
    ctx.search_input(),
  )
  let html = render_explorer_for_test({
    ..owned_state(),
    explorer_mode: ExplorerSearch,
    search,
  })
  let files = html.find(">Files</span>").unwrap()
  let changes = html.find(">Changes</span>").unwrap()
  let search = html.find(">Search</span>").unwrap()
  assert_true(files < changes && changes < search)
  assert_true(html.contains("role=\"tablist\""))
  assert_true(
    html.contains("id=\"explorer-search-tab\" role=\"tab\" tabindex=\"0\""),
  )
  assert_true(html.contains("aria-selected=\"true\""))
  assert_true(
    html.contains(
      "id=\"explorer-inventory\" role=\"tabpanel\" aria-labelledby=\"explorer-search-tab\"",
    ),
  )
  assert_true(html.contains("class=\"file-tree search-inventory\""))
  assert_true(html.contains("class=\"workspace-search\""))
  assert_true(html.contains("value=\"needle\""))
}

///|
test "Search inventory hides unrelated file watcher errors" {
  let html = render_explorer_for_test({
    ..owned_state(),
    explorer_mode: ExplorerSearch,
    error: Some("directory failure"),
    watch_error: Some("watcher failure"),
  })
  assert_false(html.contains("directory failure"))
  assert_false(html.contains("watcher failure"))
  assert_true(html.contains("file-panel-error empty"))
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
