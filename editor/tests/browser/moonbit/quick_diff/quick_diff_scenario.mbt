// Mounts a viewer whose quick-diff service holds a baseline that differs
// from the model by one modification, one insertion, and one deletion, for
// the git-gutter end-to-end spec
// (`tests/browser/component/quick_diff.spec.js`). The MoonBit side asserts
// the decoration plumbing put exactly one `.cldr` gutter piece of each
// dirty-diff class into the margin overlay rows; the spec then checks which
// lines they landed on and that the theme colors resolve.

///|
fn quick_diff_fixture_model() -> @model.TextModel {
  // vs the original ["alpha","bravo","charlie","delta","echo"]:
  //   line 2 modified, line 4 inserted, "echo" deleted after line 5.
  let lines = ["alpha", "bravo_changed", "charlie", "inserted_line", "delta"]
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/quick-diff-fixture.txt",
    ),
    "quick-diff-fixture.txt",
    "plaintext",
    1,
    "quick-diff-rev-1",
    lines.join("\n"),
  )
}

///|
pub fn run_quick_diff_test() -> Unit {
  let ctx = @support.BrowserTestContext("quick_diff")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host")
  host.set_attribute("style", "height:300px;width:400px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())
  // Keep the host-owned baseline store concrete; Viewer receives only the
  // callback capability and never owns or disposes this page-lifetime store.
  let quick_diff = @quick_diff_service.QuickDiffService()
  let services = @viewer.ViewerServices(
    quick_diff=quick_diff.quick_diff_handle(),
  )
  let model = quick_diff_fixture_model()
  quick_diff.set_original_content(
    model.uri,
    Some(["alpha", "bravo", "charlie", "delta", "echo"].join("\n")),
  )
  let viewer = @viewer.Viewer::create(host, services~)
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  wait_for_text(ctx, "bravo_changed", 80)
}

///|
/// Polls until the editor surface contains `needle`, then asserts the
/// gutter render and finishes.
fn wait_for_text(
  ctx : @support.BrowserTestContext,
  needle : String,
  remaining : Int,
) -> Unit {
  if @support.query_text(".viewer-host") is Some(text) &&
    text.contains(needle) &&
    @support.query_count(".margin-view-overlays .cldr.dirty-diff-added") == 1 &&
    @support.query_count(".margin-view-overlays .cldr.dirty-diff-modified") == 1 &&
    @support.query_count(".margin-view-overlays .cldr.dirty-diff-deleted") == 1 {
    let added = @support.query_count(
      ".margin-view-overlays .cldr.dirty-diff-added",
    )
    let modified = @support.query_count(
      ".margin-view-overlays .cldr.dirty-diff-modified",
    )
    let deleted = @support.query_count(
      ".margin-view-overlays .cldr.dirty-diff-deleted",
    )
    ctx.metric_int("added", added)
    ctx.metric_int("modified", modified)
    ctx.metric_int("deleted", deleted)
    ctx.assert_true(
      added == 1,
      "expected one added gutter piece, saw \{added.to_string()}",
    )
    ctx.assert_true(
      modified == 1,
      "expected one modified gutter piece, saw \{modified.to_string()}",
    )
    ctx.assert_true(
      deleted == 1,
      "expected one deleted gutter piece, saw \{deleted.to_string()}",
    )
    ctx.finish()
    return
  }
  if remaining <= 0 {
    let saw = match @support.query_text(".viewer-host") {
      Some(text) => text
      None => "<missing viewer host>"
    }
    ctx.fail("timed out waiting for text: \{needle} (saw: \{saw})")
    ctx.finish()
    return
  }
  @support.set_timeout(() => wait_for_text(ctx, needle, remaining - 1), 50)
}
