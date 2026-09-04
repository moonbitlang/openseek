///|
priv struct MarkdownDocumentHoverCall {
  id : Int
  model : @model.TextModel
  position : @base_common.Position
  offset : Int
  token : @language.CancellationToken
  gate : AsyncFeatureGate
  mut outcome : String?
}

///|
fn MarkdownDocumentHoverCall::to_json(self : MarkdownDocumentHoverCall) -> Json {
  Json({
    "id": self.id.to_json(),
    "modelIdentity": self.model.identity().to_json(),
    "uri": self.model.uri.to_string().to_json(),
    "revision": self.model.revision.to_json(),
    "hostVersion": self.model.version.to_json(),
    "internalVersion": self.model.get_version_id().to_json(),
    "lineNumber": self.position.line_number.to_json(),
    "column": self.position.column.to_json(),
    "offset": self.offset.to_json(),
    "cancelled": self.token.is_cancellation_requested().to_json(),
    "outcome": match self.outcome {
      Some(outcome) => outcome.to_json()
      None => Json::null()
    },
  })
}

///|
priv struct MarkdownDocumentHoverHarness {
  calls : Array[MarkdownDocumentHoverCall]
  next_id : Ref[Int]
}

///|
fn MarkdownDocumentHoverHarness::MarkdownDocumentHoverHarness() -> MarkdownDocumentHoverHarness {
  { calls: [], next_id: Ref(1), }
}

///|
fn MarkdownDocumentHoverHarness::begin(
  self : MarkdownDocumentHoverHarness,
  model : @model.TextModel,
  position : @base_common.Position,
  token : @language.CancellationToken,
) -> MarkdownDocumentHoverCall {
  let call : MarkdownDocumentHoverCall = {
    id: self.next_id.val,
    model,
    position,
    offset: model.get_offset_at(position),
    token,
    gate: AsyncFeatureGate(),
    outcome: None,
  }
  self.next_id.val += 1
  self.calls.push(call)
  call
}

///|
fn MarkdownDocumentHoverHarness::calls_json(
  self : MarkdownDocumentHoverHarness,
) -> String {
  Json(self.calls.map(call => call.to_json())).stringify()
}

///|
fn MarkdownDocumentHoverHarness::release(
  self : MarkdownDocumentHoverHarness,
  call_id : Int,
  outcome : String,
) -> Bool {
  for call in self.calls {
    if call.id == call_id && call.outcome is None {
      let released = call.gate.release(outcome)
      if released {
        call.outcome = Some(outcome)
      }
      return released
    }
  }
  false
}

///|
priv struct MarkdownDocumentHoverProvider {
  harness : MarkdownDocumentHoverHarness
}

///|
impl @language.HoverProvider for MarkdownDocumentHoverProvider with fn provide_hover(
  self,
  model,
  position,
  token,
) {
  let call = self.harness.begin(model, position, token)
  guard call.gate.wait() is Some(outcome) else { return None }
  let range = if outcome.has_prefix("wide:") {
    model.get_full_model_range()
  } else {
    let offset = model.get_offset_at(position)
    model.snapshot.range_of(
      OffsetRange(
        offset,
        Int::min(offset + 1, model.snapshot.get_value().length()),
      ),
    )
  }
  Some({ range, contents: [PlainText(outcome)], })
}

///|
fn markdown_document_source() -> String {
  (
    #|# Readonly Markdown document
    #|
    #|The original source model remains the document of record. 🪐 [fixture link](https://example.test/docs)
    #|
    #|- [ ] this checkbox stays readonly
    #|
    #|```mbt check
    #|///|
    #|pub fn markdown_answer() -> Int {
    #|  42
    #|}
    #|```
    #|
    #|> - Nested quote/list semantic fence
    #|>
    #|>     ```mbt check
    #|>    	pub fn nested_container() -> Int {
    #|>    	let planet = "🪐"; let nested_answer = 84
    #|>    	nested_answer
    #|>    	}
    #|>     ```
    #|
    #|```mbt test
    #|pub fn ordinary_fence_answer() -> Int {
    #|  0
    #|}
    #|```
  )
}

///|
fn markdown_document_diagram_source() -> String {
  (
    #|# Interactive Markdown diagrams
    #|
    #|```d2
    #|direction: right
    #|source -> shared: D2
    #|shared -> viewport: controls
    #|```
    #|
    #|```uml
    #|@startuml
    #|participant Source
    #|participant SharedViewport
    #|Source -> SharedViewport : UML
    #|@enduml
    #|```
    #|
    #|```mermaid
    #|flowchart LR
    #|  Source --> SharedViewport --> Controls
    #|```
  )
}

///|
fn markdown_document_same_uri_source() -> String {
  (
    #|# Same URI replacement model
    #|
    #|```mbt check
    #|pub fn same_uri_answer() -> Int {
    #|  9
    #|}
    #|```
  )
}

///|
fn set_markdown_document_diagnostic(
  markers : @markers.MarkerService,
  model : @model.TextModel,
  symbol : String,
  message : String,
) -> Unit {
  match model.snapshot.get_value().find(symbol) {
    Some(start) =>
      markers.set_diagnostics("markdown-document", model.uri, [
        {
          range: model.snapshot.range_of(
            OffsetRange(start, start + symbol.length()),
          ),
          severity: Warning,
          message,
          tags: None,
        },
      ])
    None => markers.set_diagnostics("markdown-document", model.uri, [])
  }
}

///|
fn set_markdown_document_marker_policy_fixture(
  markers : @markers.MarkerService,
  model : @model.TextModel,
) -> Unit {
  guard model.snapshot.get_value().find("markdown_answer") is Some(start) else {
    return
  }
  let range = model.snapshot.range_of(
    OffsetRange(start, start + "markdown_answer".length()),
  )
  markers.change_one("markdown-document", model.uri, [
    MarkerData(
      severity=Error,
      message="policy error",
      start_line_number=range.start_line_number,
      start_column=range.start_column,
      end_line_number=range.end_line_number,
      end_column=range.end_column,
    ),
    MarkerData(
      severity=Warning,
      message="policy warning",
      start_line_number=range.start_line_number,
      start_column=range.start_column,
      end_line_number=range.end_line_number,
      end_column=range.end_column,
    ),
    MarkerData(
      severity=Hint,
      message="policy unnecessary",
      start_line_number=range.start_line_number,
      start_column=range.start_column,
      end_line_number=range.end_line_number,
      end_column=range.end_column,
      tags=[Unnecessary],
    ),
    MarkerData(
      severity=Hint,
      message="policy deprecated",
      start_line_number=range.start_line_number,
      start_column=range.start_column,
      end_line_number=range.end_line_number,
      end_column=range.end_column,
      tags=[Deprecated],
    ),
  ])
}

///|
fn markdown_document_replacement_source() -> String {
  (
    #|# Replaced Markdown document
    #|
    #|The article target is reused while this projection is replaced.
    #|
    #|```mbt check trailing
    #|pub fn replacement_answer() -> Int {
    #|  7
    #|}
    #|```
    #|
    #|The replacement stays long enough to retain an observable scroll state
    #|while the host swaps between MarkdownViewer and Viewer surfaces.
  )
}

///|
pub fn run_markdown_document_test() -> Unit {
  let ctx = @support.BrowserTestContext("markdown_document")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell markdown-document-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host markdown-document-host")
  host.set_attribute("style", "height:220px;width:720px;")
  let secondary_host = document.create_element("div")
  secondary_host.set_attribute(
    "class", "viewer-host markdown-document-host-secondary",
  )
  secondary_host.set_attribute("style", "height:180px;width:720px;")
  shell.append_child(host.as_node())
  shell.append_child(secondary_host.as_node())
  app.append_child(shell.as_node())

  let token_registration = @syntax.tokenization_registry.register(
    "moonbit",
    @lang_moonbit.MoonBitTokenizer(),
  )
  let hover_harness = MarkdownDocumentHoverHarness::MarkdownDocumentHoverHarness()
  let languages = @languages.Languages()
  let hover_registration = languages.register_hover_provider(
    LanguageId("moonbit"),
    MarkdownDocumentHoverProvider::{ harness: hover_harness, },
  )
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let markers = @markers.MarkerService()
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    markers=MarkerStore(markers.marker_service_handle()),
    log_service=log_handle,
  )
  let markdown_model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="component",
      path="/literate.mbt.md",
    ),
    "literate.mbt.md",
    "moonbit",
    1,
    "markdown-document-rev-1",
    markdown_document_source(),
  )
  let same_uri_model = @model.TextModel(
    markdown_model.uri,
    "literate.mbt.md",
    "moonbit",
    1,
    "markdown-document-rev-1",
    markdown_document_same_uri_source(),
  )
  let code_model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="component",
      path="/ordinary.mbt",
    ),
    "ordinary.mbt",
    "moonbit",
    1,
    "markdown-document-code-rev-1",
    "pub fn ordinary_code() -> Int { 1 }",
  )
  set_markdown_document_diagnostic(
    markers, markdown_model, "markdown_answer", "initial markdown diagnostic",
  )
  let viewer = @viewer.MarkdownViewer::create(
    host,
    services~,
    options=MarkdownViewerOptions(theme="dark"),
  )
  let secondary_viewer = @viewer.MarkdownViewer::create(
    secondary_host,
    services~,
    options=MarkdownViewerOptions(theme="dark"),
  )
  viewer.set_model(Some(MarkdownViewerModel(markdown_model, MoonBitMarkdown)))
  |> ignore
  secondary_viewer.set_model(
    Some(MarkdownViewerModel(markdown_model, MoonBitMarkdown)),
  )
  |> ignore
  viewer.handle_initialized()
  secondary_viewer.handle_initialized()
  let code_viewer : Ref[@viewer.Viewer?] = Ref(None)
  install_markdown_document_controls(
    () => markdown_model.get_value(),
    () => markdown_model.set_value(markdown_document_diagram_source()),
    () => {
      markdown_model.set_value(markdown_document_replacement_source())
      set_markdown_document_diagnostic(
        markers, markdown_model, "replacement_answer", "replacement markdown diagnostic",
      )
    },
    theme => viewer.update_options(viewer.get_options().with_theme(theme)),
    () => {
      viewer.set_model(None) |> ignore
      let code = @viewer.Viewer::create(
        host,
        services~,
        options=ViewerOptions(theme="dark"),
      )
      code.set_model(Some(code_model))
      code.handle_initialized()
      code_viewer.val = Some(code)
    },
    () => {
      match code_viewer.val {
        Some(code) => {
          code.dispose()
          code_viewer.val = None
        }
        None => ()
      }
      viewer.set_model(
        Some(MarkdownViewerModel(markdown_model, MoonBitMarkdown)),
      )
      |> ignore
    },
    () => {
      set_markdown_document_diagnostic(
        markers, same_uri_model, "same_uri_answer", "same URI markdown diagnostic",
      )
      viewer.set_model(
        Some(MarkdownViewerModel(same_uri_model, MoonBitMarkdown)),
      )
      |> ignore
    },
    () => hover_harness.calls_json(),
    (call_id, outcome) => hover_harness.release(call_id, outcome),
    message => {
      if viewer.get_model() is Some(viewer_model) {
        let model = viewer_model.model
        let symbol = if model.get_value().contains("replacement_answer") {
          "replacement_answer"
        } else if model.get_value().contains("same_uri_answer") {
          "same_uri_answer"
        } else {
          "markdown_answer"
        }
        set_markdown_document_diagnostic(markers, model, symbol, message)
      }
    },
    () => set_markdown_document_marker_policy_fixture(markers, markdown_model),
    show_unused => {
      viewer.update_options(MarkdownViewerOptions(theme="dark", show_unused~))
    },
    top => set_markdown_document_scroll_top(top),
    width => {
      host.set_attribute("style", "height:220px;width:\{width}px;")
      viewer.layout()
      match code_viewer.val {
        Some(code) => code.layout()
        None => ()
      }
    },
    () => {
      match code_viewer.val {
        Some(code) => code.dispose()
        None => ()
      }
      viewer.dispose()
      secondary_viewer.dispose()
      services.dispose()
      markdown_model.dispose()
      same_uri_model.dispose()
      code_model.dispose()
      hover_registration.dispose()
      token_registration.dispose()
      markers.dispose()
    },
  )
  poll_markdown_document_ready(ctx, markdown_model, 100)
}

///|
extern "js" fn set_markdown_document_scroll_top(top : Double) -> Unit =
  #| (top) => {
  #|   const viewport = document.querySelector(
  #|     '.markdown-document-host > .moonbit-viewer-markdown-document > .moonbit-viewer-markdown-document-viewport',
  #|   );
  #|   if (viewport) viewport.scrollTop = top;
  #| }

///|
fn poll_markdown_document_ready(
  ctx : @support.BrowserTestContext,
  model : @model.TextModel,
  remaining : Int,
) -> Unit {
  let root_count = @support.query_count(
    ".markdown-document-host > .moonbit-viewer-markdown-document",
  )
  let code_blocks = @support.query_count(
    ".markdown-document-host [data-markdown-code-block]",
  )
  let keyword_tokens = @support.query_count(
    ".markdown-document-host .moonbit-viewer-markdown-code-block .mtk3",
  )
  let semantic_lines = @support.query_count(
    ".markdown-document-host .moonbit-viewer-markdown-code-line",
  )
  let phrase_dividers = @support.query_count(
    ".markdown-document-host [data-markdown-phrase-divider=\"true\"]",
  )
  let diagnostics = @support.query_count(
    ".markdown-document-host .moonbit-viewer-markdown-diagnostic.squiggly-warning",
  )
  if root_count == 1 &&
    code_blocks == 3 &&
    keyword_tokens > 0 &&
    semantic_lines == 8 &&
    phrase_dividers == 1 &&
    diagnostics > 0 {
    ctx.assert_true(
      @support.query_count(".markdown-document-host > .monaco-editor") == 0,
      "Markdown presentation retained a hidden code-editor root",
    )
    ctx.assert_true(
      @support.query_attribute(
        ".markdown-document-host [data-markdown-code-block]", "data-markdown-semantic",
      ) ==
      Some("moonbit-check"),
      "compiler-compatible .mbt.md fence was not classified semantically",
    )
    ctx.assert_true(
      @support.query_attribute(
        ".markdown-document-host > .moonbit-viewer-markdown-document", "data-source-uri",
      ) ==
      Some(model.uri.to_string()),
      "Markdown root lost the original source URI",
    )
    ctx.assert_true(
      @support.query_count(
        ".markdown-document-host .moonbit-viewer-markdown-document-article input[disabled]",
      ) ==
      1,
      "Markdown checkbox was not rendered readonly",
    )
    ctx.metric_int("rootCount", root_count)
    ctx.metric_int("codeBlocks", code_blocks)
    ctx.metric_int("keywordTokens", keyword_tokens)
    ctx.metric_int("semanticLines", semantic_lines)
    ctx.metric_int("phraseDividers", phrase_dividers)
    ctx.metric_int("diagnostics", diagnostics)
    match
      @support.query_attribute(
        ".markdown-document-host > .moonbit-viewer-markdown-document", "data-source-uri",
      ) {
      Some(source_uri) => ctx.metric_string("sourceUri", source_uri)
      None => ()
    }
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail(
      "timed out waiting for Markdown document render: roots=\{root_count}, blocks=\{code_blocks}, tokens=\{keyword_tokens}",
    )
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_markdown_document_ready(ctx, model, remaining - 1),
      25,
    )
  }
}

///|
extern "js" fn install_markdown_document_controls(
  get_model_value : () -> String,
  show_diagrams : () -> Unit,
  replace_source : () -> Unit,
  update_theme : (String) -> Unit,
  show_code : () -> Unit,
  show_markdown : () -> Unit,
  show_same_uri_markdown : () -> Unit,
  get_hover_calls : () -> String,
  release_hover : (Int, String) -> Bool,
  update_marker : (String) -> Unit,
  set_marker_policy_fixture : () -> Unit,
  set_marker_unused_visibility : (Bool) -> Unit,
  set_scroll_top : (Double) -> Unit,
  resize_host : (Double) -> Unit,
  dispose : () -> Unit,
) -> Unit =
  #| (
  #|   getModelValue,
  #|   showDiagrams,
  #|   replaceSource,
  #|   updateTheme,
  #|   showCode,
  #|   showMarkdown,
  #|   showSameUriMarkdown,
  #|   getHoverCalls,
  #|   releaseHover,
  #|   updateMarker,
  #|   setMarkerPolicyFixture,
  #|   setMarkerUnusedVisibility,
  #|   setScrollTop,
  #|   resizeHost,
  #|   dispose,
  #| ) => {
  #|   globalThis.__markdownDocumentControls = {
  #|     getModelValue,
  #|     showDiagrams,
  #|     replaceSource,
  #|     updateTheme,
  #|     showCode,
  #|     showMarkdown,
  #|     showSameUriMarkdown,
  #|     getHoverCalls: () => JSON.parse(getHoverCalls()),
  #|     releaseHover,
  #|     updateMarker,
  #|     setMarkerPolicyFixture,
  #|     setMarkerUnusedVisibility,
  #|     setScrollTop,
  #|     resizeHost,
  #|     dispose,
  #|   };
  #| }
