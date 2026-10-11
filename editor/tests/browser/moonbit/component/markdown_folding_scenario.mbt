// Direct public-MarkdownViewer proof for Markdown section folding. The mounted
// white-box suite pins the synchronous fold state machine; this scenario owns
// what only a real browser can observe: computed `display:none`, real toggle
// clicks, caret-based semantic hover against visible and revealed fences, and
// the two pending-hover interleavings of the visibility/invalidation ordering.

///|
fn markdown_folding_source() -> String {
  (
    #|# Folding fixture
    #|
    #|intro paragraph
    #|
    #|## Alpha
    #|
    #|alpha prose
    #|
    #|```mbt check
    #|fn alpha_answer() -> Int { 41 }
    #|```
    #|
    #|## Beta
    #|
    #|beta prose
    #|
    #|```mbt check
    #|fn beta_answer() -> Int { 42 }
    #|```
    #|
    #|### Deep
    #|
    #|deep one
    #|
    #|deep two
    #|
    #|deep three
    #|
    #|deep four
    #|
    #|deep five
    #|
    #|deep six
    #|
  )
}

///|
fn markdown_folding_facts_json(
  viewer : @viewer.MarkdownViewer,
  source : () -> String,
) -> String {
  let current = source()
  let offset_of = needle => {
    match current.find(needle) {
      Some(offset) => Json(offset)
      None => Json::null()
    }
  }
  Json({
    "alpha": offset_of("## Alpha"),
    "beta": offset_of("## Beta"),
    "deep": offset_of("### Deep"),
    "collapsed": Json(viewer.collapsed_sections().map(offset => Json(offset))),
  }).stringify()
}

///|
pub fn run_markdown_folding_test() -> Unit {
  let ctx = @support.BrowserTestContext("markdown_folding")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell markdown-folding-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host markdown-folding-host")
  host.set_attribute("style", "height:420px;width:720px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())
  let _token_registration = @syntax.tokenization_registry.register(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  let hover_harness = MarkdownDocumentHoverHarness::MarkdownDocumentHoverHarness()
  let languages = @languages.Languages()
  let _hover_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    MarkdownDocumentHoverProvider::{ harness: hover_harness, },
  )
  let log_service = @log.LogService()
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="component",
      path="/folding.mbt.md",
    ),
    "folding.mbt.md",
    "moonbit",
    1,
    "markdown-folding-rev-1",
    markdown_folding_source(),
  )
  let viewer = @viewer.MarkdownViewer::create(
    host,
    services~,
    options=MarkdownViewerOptions(theme="dark"),
  )
  viewer.set_model(Some(MarkdownViewerModel(model, MoonBitMarkdown))) |> ignore
  viewer.handle_initialized()
  install_markdown_folding_controls(
    () => markdown_folding_facts_json(viewer, () => model.get_value()),
    () => hover_harness.calls_json(),
    (call_id, outcome) => hover_harness.release(call_id, outcome),
  )
  // The initial seeded state is part of the report so the spec separates
  // "policy seeded wrongly" from "a later interaction broke it".
  ctx.metric_int("initialCollapsedCount", viewer.collapsed_sections().length())
  ctx.assert_true(
    viewer.collapsed_sections().length() == 1,
    "auto-fold seeds exactly the bulky depth-3 section",
  )
  ctx.finish()
}

///|
extern "js" fn install_markdown_folding_controls(
  get_fold_facts : () -> String,
  get_hover_calls : () -> String,
  release_hover : (Int, String) -> Bool,
) -> Unit =
  #| (getFoldFacts, getHoverCalls, releaseHover) => {
  #|   globalThis.__markdownFoldingControls = {
  #|     getFoldFacts: () => JSON.parse(getFoldFacts()),
  #|     getHoverCalls: () => JSON.parse(getHoverCalls()),
  #|     releaseHover: (id, outcome) => releaseHover(id | 0, String(outcome)),
  #|   };
  #| }
