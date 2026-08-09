///|
#warnings("-alert_unstable")
fn render_launcher(actions : LauncherActions) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(launcher_pane(actions)))
}

///|
test "launcher presents Browse, Files, and Review in order" {
  let html = render_launcher({
    browser: Some(@cmd.none),
    files: @cmd.none,
    review: @cmd.none,
  })
  let browse = html.find(">Browse</span>").unwrap()
  let files = html.find(">Files</span>").unwrap()
  let review = html.find(">Review</span>").unwrap()
  assert_true(browse < files && files < review)
  assert_true(html.contains("Review changed files and diffs"))
}

///|
test "remote launcher hides Browse but retains Files and Review" {
  let html = render_launcher({
    browser: None,
    files: @cmd.none,
    review: @cmd.none,
  })
  assert_false(html.contains(">Browse</span>"))
  assert_true(html.contains(">Files</span>"))
  assert_true(html.contains(">Review</span>"))
}
