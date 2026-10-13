// Mounts a viewer over a NESTED indentation-foldable fixture for the
// recursive-folding end-to-end spec
// (`tests/browser/component/folding_nested.spec.js`). The MoonBit side
// asserts the initial render: every line visible, one expanded gutter
// chevron per region (outer 1..5 and inner 2..4, nested), no hidden areas.
// The spec then drives the recursive mouse variants Monaco implements in
// `onEditorMouseUp` (`folding.ts:449-510`): shift- or middle-clicking a
// chevron first folds only the children, then the region itself, and a
// recursive click on the collapsed header unfolds the whole subtree.

///|
fn folding_nested_fixture_model() -> @model.TextModel {
  let lines = [
    "nest_root", "  nest_branch", "    nest_leaf_a", "    nest_leaf_b", "  nest_after",
    "nest_end",
  ]
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/folding-nested-fixture.txt",
    ),
    "folding-nested-fixture.txt",
    "plaintext",
    1,
    "folding-nested-rev-1",
    lines.join("\n"),
  )
}

///|
pub fn run_folding_nested_test() -> Unit {
  let ctx = @support.BrowserTestContext("folding_nested")
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
  viewer.set_model(Some(folding_nested_fixture_model()))
  viewer.handle_initialized()
  wait_for_text(ctx, "nest_leaf_a", 80)
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
    // Two regions — outer (1..5) and inner (2..4) — → two expanded chevrons
    // in the `.cldr` lane (opacity 0 under `showFoldingControls: mouseover`,
    // but present).
    let expanded_count = @support.query_count(
      ".margin-view-overlays .cldr.codicon-folding-expanded",
    )
    ctx.assert_true(
      expanded_count == 2,
      "expected one expanded chevron per nested region, saw \{expanded_count}",
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
