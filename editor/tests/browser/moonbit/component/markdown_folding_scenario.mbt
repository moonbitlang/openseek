// Direct public-Viewer proof for Markdown section folding. The mounted
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
/// The same document after an agent rewrote Beta's fence: Beta's fingerprint
/// changes, every other section is untouched.
fn markdown_folding_replacement_source() -> String {
  markdown_folding_source().replace(
    old="fn beta_answer() -> Int { 42 }",
    new="fn beta_answer() -> Int { 43 } // rewritten",
  )
}

///|
fn markdown_folding_facts_json(
  viewer : @viewer.Viewer,
  source : () -> String,
) -> String {
  let current = source()
  let offset_of = needle => {
    match current.find(needle) {
      Some(offset) => offset.to_json()
      None => Json::null()
    }
  }
  Json::object({
    "alpha": offset_of("## Alpha"),
    "beta": offset_of("## Beta"),
    "deep": offset_of("### Deep"),
    "collapsed": viewer
    .collapsed_markdown_sections()
    .map(offset => offset.to_json())
    .to_json(),
  }).stringify()
}

///|
fn run_markdown_folding_test() -> Unit {
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
  let token_registration = @syntax.tokenization_registry.register(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  let hover_harness = MarkdownDocumentHoverHarness::new()
  let languages = @languages.Languages()
  let hover_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    MarkdownDocumentHoverProvider::{ harness: hover_harness },
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
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(theme="dark"),
  )
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  install_markdown_folding_controls(
    () => markdown_folding_facts_json(viewer, () => model.get_value()),
    offset => viewer.toggle_markdown_section_at(offset),
    () => model.set_value(markdown_folding_replacement_source()),
    () => hover_harness.calls_json(),
    (call_id, outcome) => hover_harness.release(call_id, outcome),
    () => {
      viewer.dispose()
      hover_registration.dispose()
      token_registration.dispose()
    },
  )
  // The initial seeded state is part of the report so the spec separates
  // "policy seeded wrongly" from "a later interaction broke it".
  ctx.metric_int(
    "initialCollapsedCount",
    viewer.collapsed_markdown_sections().length(),
  )
  ctx.assert_true(
    viewer.collapsed_markdown_sections().length() == 1,
    "auto-fold seeds exactly the bulky depth-3 section",
  )
  ctx.finish()
}

///|
extern "js" fn install_markdown_folding_controls(
  get_fold_facts : () -> String,
  toggle_at_offset : (Int) -> Bool,
  replace_source : () -> Unit,
  get_hover_calls : () -> String,
  release_hover : (Int, String) -> Bool,
  dispose : () -> Unit,
) -> Unit =
  #| (
  #|   getFoldFacts,
  #|   toggleAtOffset,
  #|   replaceSource,
  #|   getHoverCalls,
  #|   releaseHover,
  #|   dispose,
  #| ) => {
  #|   globalThis.__markdownFoldingControls = {
  #|     getFoldFacts: () => JSON.parse(getFoldFacts()),
  #|     toggleAtOffset: (offset) => toggleAtOffset(offset | 0),
  #|     replaceSource: () => replaceSource(),
  #|     getHoverCalls: () => JSON.parse(getHoverCalls()),
  #|     releaseHover: (id, outcome) => releaseHover(id | 0, String(outcome)),
  #|     dispose: () => dispose(),
  #|   };
  #| }
