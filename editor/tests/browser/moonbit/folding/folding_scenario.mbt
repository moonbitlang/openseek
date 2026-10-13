// Mounts a viewer over an indentation-foldable fixture for the folding
// end-to-end spec (`tests/browser/component/folding.spec.js`). The MoonBit
// side asserts the initial render: every line visible, one expanded gutter
// chevron per indent region, no hidden areas. The spec then drives the real
// mouse/keyboard interactions (chevron click folds, second click unfolds,
// Ctrl/Cmd+Shift+[ folds at the cursor).

///|
fn folding_fixture_model() -> @model.TextModel {
  let lines = [
    "fold_top", "  fold_child_a", "  fold_child_b", "fold_mid", "  fold_tail",
  ]
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/folding-fixture.txt",
    ),
    "folding-fixture.txt",
    "plaintext",
    1,
    "folding-rev-1",
    lines.join("\n"),
  )
}

///|
pub fn run_folding_test() -> Unit {
  let ctx = @support.BrowserTestContext("folding")
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
  let viewer = @viewer.Viewer::create(host)
  viewer.set_model(Some(folding_fixture_model()))
  viewer.handle_initialized()
  wait_for_text(ctx, "fold_child_a", 80)
}

///|
/// Polls until the editor surface contains `needle`, then asserts the
/// initial folding render and finishes.
fn wait_for_text(
  ctx : @support.BrowserTestContext,
  needle : String,
  remaining : Int32,
) -> Unit {
  if @support.query_text(".viewer-host") is Some(text) && text.contains(needle) {
    // Two indent regions → two expanded chevrons in the `.cldr` lane
    // (opacity 0 under `showFoldingControls: mouseover`, but present).
    let expanded_count = @support.query_count(
      ".margin-view-overlays .cldr.codicon-folding-expanded",
    )
    ctx.assert_true(
      expanded_count == 2,
      "expected one expanded chevron per indent region, saw \{expanded_count}",
    )
    ctx.assert_true(
      @support.query_count(
        ".margin-view-overlays .cldr.codicon-folding-collapsed",
      ) ==
      0,
      "no region should start collapsed",
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
