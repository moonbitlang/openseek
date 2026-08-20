///|
#warnings("-alert_unstable")
fn render_launcher(actions : LauncherActions) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(launcher_pane(actions)))
}

///|
#warnings("-alert_unstable")
fn render_tabs(expanded : Bool) -> String {
  let dispatch : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let actions : LauncherActions = {
    browser: None,
    search: @cmd.none,
    files: @cmd.none,
    review: @cmd.none,
  }
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      tabs_bar(
        dispatch,
        State::empty(),
        [],
        actions,
        menu_open=false,
        expanded~,
        toggle_menu=@cmd.none,
        toggle_expanded=@cmd.none,
        toggle_panel=@cmd.none,
      ),
    )
  })
}

///|
test "launcher presents Browse, Search, Files, and Review in order" {
  let html = render_launcher({
    browser: Some(@cmd.none),
    search: @cmd.none,
    files: @cmd.none,
    review: @cmd.none,
  })
  let browse = html.find(">Browse</span>").unwrap()
  let search = html.find(">Search</span>").unwrap()
  let files = html.find(">Files</span>").unwrap()
  let review = html.find(">Review</span>").unwrap()
  assert_true(browse < search && search < files && files < review)
  assert_true(html.contains("Review changed files and diffs"))
  assert_true(html.contains("M10.0195 10.7266C9.06578 11.5217"))
}

///|
test "remote launcher hides Browse but retains Search, Files, and Review" {
  let html = render_launcher({
    browser: None,
    search: @cmd.none,
    files: @cmd.none,
    review: @cmd.none,
  })
  assert_false(html.contains(">Browse</span>"))
  assert_true(html.contains(">Search</span>"))
  assert_true(html.contains(">Files</span>"))
  assert_true(html.contains(">Review</span>"))
}

///|
test "panel toolbar offers expand before hide" {
  let html = render_tabs(false)
  let expand = html.find("title=\"Expand panel\"").unwrap()
  let hide = html.find("title=\"Hide panel\"").unwrap()
  assert_true(expand < hide)
  assert_true(html.contains("aria-label=\"Expand panel\""))
  assert_true(html.contains("aria-pressed=\"false\""))
}

///|
test "expanded panel toolbar offers restore" {
  let html = render_tabs(true)
  assert_true(html.contains("title=\"Restore panel\""))
  assert_true(html.contains("aria-label=\"Restore panel\""))
  assert_true(html.contains("aria-pressed=\"true\""))
}
