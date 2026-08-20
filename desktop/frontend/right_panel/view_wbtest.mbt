///|
fn test_actions() -> Actions {
  {
    dock: @cmd.Emit(_ => @cmd.none),
    file_editor: @cmd.Emit(_ => @cmd.none),
    browser_tab: @cmd.none,
    search: @cmd.none,
    files: @cmd.none,
    review: @cmd.none,
    browser_input: @cmd.Emit(_ => @cmd.none),
    browser_submit: @cmd.none,
    browser_back: @cmd.none,
    browser_forward: @cmd.none,
    browser_reload: @cmd.none,
    browser_open_external: @cmd.none,
    toggle_panel: @cmd.none,
    toggle_menu: @cmd.none,
    toggle_expanded: @cmd.none,
    close_menu: @cmd.none,
  }
}

///|
fn test_ctx() -> @fileeditor.Ctx {
  {
    owner: { channel: @interop.ChannelId::Local, session: "panel-test" },
    request_epoch: 0,
    watch_namespace: "panel-test-watch",
    placement: None,
    dark_mode: false,
    tree_layout: @fileeditor.RightSidebar,
    narrow: false,
    panel_open: true,
    open_files: [],
    active_file: None,
    open_history_diffs: [],
    active_history_diff: None,
  }
}

///|
#warnings("-alert_unstable")
fn render_picker(mode : @fileeditor.ExplorerMode) -> String {
  let input = Input::Input(
    dock=@dock.open_picker(@dock.State::empty()),
    file_panel={ ..@fileeditor.State::empty(), explorer_mode: mode },
    preview=@preview.State::empty(),
    file_ctx=test_ctx(),
    is_desktop=true,
    menu_open=false,
    expanded=false,
  )
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(panel_view(input, test_actions()))
  })
}

///|
test "Search picker uses the Explorer Search label and body mode" {
  let html = render_picker(@fileeditor.ExplorerSearch)
  assert_true(html.contains("mode-picker mode-search-picker"))
  assert_true(html.contains("title=\"Search across files\""))
  assert_true(html.contains(">Search</span>"))
  assert_true(html.contains("class=\"file-tree search-inventory\""))
}

///|
test "Files and Changes picker labels retain their existing modes" {
  let files = render_picker(@fileeditor.ExplorerFiles)
  assert_true(files.contains("title=\"Open a workspace file\""))
  assert_true(files.contains(">Open File</span>"))
  assert_false(files.contains("mode-search-picker"))
  assert_false(files.contains("mode-review"))

  let review = render_picker(@fileeditor.ExplorerChanges)
  assert_true(review.contains("mode-picker mode-review"))
  assert_true(review.contains("title=\"Review changed files and diffs\""))
  assert_true(review.contains(">Review Changes</span>"))
  assert_false(review.contains("mode-search-picker"))
}
