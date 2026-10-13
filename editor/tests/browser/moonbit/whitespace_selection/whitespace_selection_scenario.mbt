// Browser test for the Stage-2 `RenderWhitespace::Selection` default (plan:
// monaco-render-whitespace-control-options-port.md). It mounts a *default*
// viewer (`ViewerOptions::default()`, now `render_whitespace=Selection`) over
// whitespace-bearing lines and asserts that, with no selection, no whitespace
// glyphs render — the half this scenario can prove headlessly. The companion
// Playwright spec then drags a selection over the lines and asserts the `.mtkw`
// dots appear under it and move when the selection changes (the re-render
// coupling: `viewLine.ts:94-100` / `view_layer.mbt` `render_text`).

///|
/// Two lines, each with leading and internal whitespace. `Selection` mode paints
/// dots only inside a selection, so at rest (no selection) these render none.
fn whitespace_selection_source_text() -> String {
  "    alpha   beta\n    gamma   delta"
}

///|
pub fn run_whitespace_selection_test() -> Unit {
  let ctx = @support.BrowserTestContext("whitespace_selection")
  let done = Ref(false)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/whitespace-selection.txt",
  )
  let model = @model.TextModel(
    uri,
    "whitespace-selection.txt",
    "plaintext",
    1,
    "whitespace-selection-rev-1",
    whitespace_selection_source_text(),
  )
  match mount_host() {
    Some(host) => {
      // Default options (`ViewerOptions()` = all defaults):
      // render_whitespace=Selection, render_control_characters on. No selection
      // is set, so nothing should dot.
      let viewer = @viewer.Viewer::create(
        host,
        options=ViewerOptions(
          placeholder="Loading whitespace-selection fixture...",
        ),
      )
      viewer.set_model(Some(model))
      viewer.handle_initialized()
      @support.set_timeout(() => poll_selection(ctx, done, 100), 50)
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
fn poll_selection(
  ctx : @support.BrowserTestContext,
  done : Ref[Bool],
  remaining : Int32,
) -> Unit {
  if done.val {
    return
  }
  if @support.query_count(".view-line") > 0 {
    // With Selection mode and no selection, the whitespace renderer's Selection
    // branch sees empty per-line ranges and paints nothing.
    let dots = @support.query_count(".view-line .mtkw")
    ctx.assert_true(
      dots == 0,
      "expected no whitespace dots without a selection, found \{dots}",
    )
    ctx.metric_int("initialWhitespaceSpans", dots)
    done.val = true
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for the whitespace-selection lines to render")
    done.val = true
    ctx.finish()
  } else {
    @support.set_timeout(() => poll_selection(ctx, done, remaining - 1), 30)
  }
}

///|
fn mount_host() -> @rdom.Element? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      host.set_attribute("style", "height:160px;width:360px;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}
