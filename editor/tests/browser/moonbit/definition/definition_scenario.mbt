// Real-Chromium fixture for goto-definition, definition-link, Peek Definition,
// and provider-backed Peek References. Playwright drives trusted mouse,
// modifier, wheel, and keyboard events; this MoonBit side supplies only the
// public Viewer, isolated language providers, and deterministic readback of
// public editor state.

///|
#external
priv type BrowserDefinitionGate

///|
extern "js" fn BrowserDefinitionGate::new() -> BrowserDefinitionGate =
  #| () => {
  #|   let release;
  #|   const promise = new Promise(resolve => { release = resolve; });
  #|   return { promise, release };
  #| }

///|
extern "js" fn BrowserDefinitionGate::promise(
  self : BrowserDefinitionGate,
) -> @js.Promise[@js.Value] = "gate => gate.promise"

///|
extern "js" fn BrowserDefinitionGate::release(
  self : BrowserDefinitionGate,
) -> Unit = "gate => gate.release()"

///|
async fn BrowserDefinitionGate::wait(self : BrowserDefinitionGate) -> Unit {
  self.promise().wait() |> ignore
}

///|
priv struct BrowserDefinitionProvider {
  calls : Ref[Int]
  source_uri : @base_common.Uri
  location : @language.Location
  alternate_location : @language.Location?
  redirect_location : @language.Location?
  multiple : Ref[Bool]
  redirect : Ref[Bool]
  delay : Ref[Bool]
  pending : Ref[Bool]
  release : BrowserDefinitionGate?
  reference_line : Int
}

///|
impl @language.DefinitionProvider for BrowserDefinitionProvider with fn provide_definition(
  self,
  model,
  position,
  _token,
) {
  if model.uri.to_string() == self.source_uri.to_string() &&
    position.line_number == self.reference_line &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    self.calls.val += 1
    if self.delay.val {
      self.pending.val = true
      match self.release {
        Some(release) => release.wait() catch { _ => () }
        None => ()
      }
      self.pending.val = false
    }
    let primary = match (self.redirect.val, self.redirect_location) {
      (true, Some(location)) => location
      _ => self.location
    }
    match (self.multiple.val, self.alternate_location) {
      (true, Some(alternate)) => [primary, alternate]
      _ => [primary]
    }
  } else {
    []
  }
}

///|
priv struct BrowserReferencesProvider {
  calls : Ref[Int]
  code_uri : @base_common.Uri
  markdown_uri : @base_common.Uri
}

///|
impl @language.ReferencesProvider for BrowserReferencesProvider with fn provide_references(
  self,
  model,
  position,
  _token,
) {
  if model.uri.to_string() == self.code_uri.to_string() &&
    position.line_number == 2 &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    self.calls.val += 1
    [
      { uri: self.code_uri, range: Range(1, 5, 1, 21), },
      { uri: self.code_uri, range: Range(2, 11, 2, 27), },
    ]
  } else if model.uri.to_string() == self.markdown_uri.to_string() &&
    position.line_number == 2 &&
    position.column >= definition_reference_start_column() &&
    position.column <= definition_reference_end_column() {
    self.calls.val += 1
    [
      { uri: self.markdown_uri, range: Range(2, 11, 2, 27), },
      {
        uri: self.markdown_uri,
        range: Range(
          markdown_definition_line(),
          5,
          markdown_definition_line(),
          21,
        ),
      },
    ]
  } else {
    []
  }
}

///|
priv struct BrowserDefinitionFixtureState {
  mut resolver_calls : Int
  opened_uris : Array[String]
  opened_modes : Array[String]
}

///|
fn browser_definition_open_mode(
  mode : @navigation_api.OpenLocationMode,
) -> String {
  match mode {
    Current => "Current"
    Side => "Side"
  }
}

///|
fn definition_reference_start_column() -> Int {
  11
}

///|
fn definition_reference_end_column() -> Int {
  27
}

///|
fn definition_source() -> String {
  let lines : Array[String] = [
    "let definition_alpha = 1", "let use = definition_alpha",
  ]
  for index in 3..<=90 {
    lines.push("filler_line_\{index}")
  }
  lines.join("\n")
}

///|
fn markdown_definition_source() -> String {
  let lines = [
    "```mbt check", "let use = definition_alpha", "```", "", "```mbt", "let ordinary = definition_alpha",
    "```", "",
  ]
  for index in 1..<=40 {
    lines.push("Markdown projection filler \{index}.")
  }
  lines.append(["", "```mbt check", "let definition_alpha = 1", "```"])
  lines.join("\n")
}

///|
fn markdown_definition_line() -> Int {
  51
}

///|
fn definition_state_json(
  viewer : @viewer.Viewer,
  provider_calls : Ref[Int],
  markdown_provider_calls : Ref[Int],
  references_provider_calls : Ref[Int],
  markdown_provider_pending : Ref[Bool],
  fixture : BrowserDefinitionFixtureState,
) -> String {
  let position = match viewer.get_position() {
    Some(position) =>
      Json({
        "line": position.line_number.to_json(),
        "column": position.column.to_json(),
      })
    None => Json::null()
  }
  let selection = match viewer.get_selection() {
    Some(selection) => {
      let anchor = selection.get_selection_start()
      let active = selection.get_position()
      Json({
        "anchorLine": anchor.line_number.to_json(),
        "anchorColumn": anchor.column.to_json(),
        "activeLine": active.line_number.to_json(),
        "activeColumn": active.column.to_json(),
      })
    }
    None => Json::null()
  }
  Json({
    "position": position,
    "selection": selection,
    "providerCalls": provider_calls.val.to_json(),
    "markdownProviderCalls": markdown_provider_calls.val.to_json(),
    "referencesProviderCalls": references_provider_calls.val.to_json(),
    "markdownProviderPending": markdown_provider_pending.val.to_json(),
    "resolverCalls": fixture.resolver_calls.to_json(),
    "openedUris": fixture.opened_uris.to_json(),
    "openedModes": fixture.opened_modes.to_json(),
    "scrollTop": viewer.get_scroll_top().to_json(),
    "scrollHeight": viewer.get_scroll_height().to_json(),
    "hasTextFocus": viewer.has_text_focus().to_json(),
  }).stringify()
}

///|
pub fn run_definition_browser_test() -> Unit {
  let ctx = @support.BrowserTestContext("definition")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell definition-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;padding:16px;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host definition-host")
  host.set_attribute("style", "height:360px;width:760px;")
  let markdown_host = document.create_element("div")
  markdown_host.set_attribute("class", "viewer-host definition-markdown-host")
  markdown_host.set_attribute(
    "style", "height:360px;width:760px;margin-top:16px;",
  )
  shell.append_child(host.as_node())
  shell.append_child(markdown_host.as_node())
  app.append_child(shell.as_node())

  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/definition-fixture.mbt",
  )
  let model = @model.TextModel(
    uri,
    "definition-fixture.mbt",
    "moonbit",
    1,
    "definition-rev-1",
    definition_source(),
  )
  let provider_calls = Ref(0)
  let provider_multiple = Ref(false)
  let provider = BrowserDefinitionProvider::{
    calls: provider_calls,
    source_uri: uri,
    location: { uri, range: Range(1, 5, 1, 21), },
    alternate_location: Some({ uri, range: Range(3, 1, 3, 14), }),
    redirect_location: None,
    multiple: provider_multiple,
    redirect: Ref(false),
    delay: Ref(false),
    pending: Ref(false),
    release: None,
    reference_line: 2,
  }
  let markdown_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/definition-fixture.mbt.md",
  )
  let markdown_model = @model.TextModel(
    markdown_uri,
    "definition-fixture.mbt.md",
    "moonbit",
    1,
    "definition-markdown-rev-1",
    markdown_definition_source(),
  )
  let markdown_replacement_model = @model.TextModel(
    markdown_uri,
    "definition-fixture.mbt.md",
    "moonbit",
    1,
    "definition-markdown-replacement-rev-1",
    markdown_definition_source(),
  )
  let markdown_provider_calls = Ref(0)
  let markdown_provider_delay = Ref(false)
  let markdown_provider_pending = Ref(false)
  let markdown_provider_release = BrowserDefinitionGate::new()
  let remote_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/definition-remote.mbt",
  )
  let remote_model = @model.TextModel(
    remote_uri, "definition-remote.mbt", "moonbit", 1, "definition-remote-rev-1",
    "let remote_definition_alpha = 1\nlet remote_use = remote_definition_alpha",
  )
  let markdown_provider = BrowserDefinitionProvider::{
    calls: markdown_provider_calls,
    source_uri: markdown_uri,
    location: {
      uri: markdown_uri,
      range: Range(
        markdown_definition_line(),
        5,
        markdown_definition_line(),
        21,
      ),
    },
    alternate_location: Some({ uri: markdown_uri, range: Range(6, 5, 6, 21), }),
    redirect_location: None,
    multiple: Ref(false),
    redirect: Ref(false),
    delay: markdown_provider_delay,
    pending: markdown_provider_pending,
    release: Some(markdown_provider_release),
    reference_line: 2,
  }
  let references_provider_calls = Ref(0)
  let references_provider = BrowserReferencesProvider::{
    calls: references_provider_calls,
    code_uri: uri,
    markdown_uri,
  }
  let languages = @languages.Languages()
  languages.register_definition_provider(LanguageId("moonbit"), provider)
  |> ignore
  languages.register_definition_provider(
    LanguageId("moonbit"),
    markdown_provider,
  )
  |> ignore
  languages.register_references_provider(
    LanguageId("moonbit"),
    references_provider,
  )
  |> ignore
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let fixture : BrowserDefinitionFixtureState = {
    resolver_calls: 0,
    opened_uris: [],
    opened_modes: [],
  }
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    fixture.resolver_calls += 1
    if resource.to_string() != remote_uri.to_string() {
      None
    } else {
      Some(TextModelReference(remote_model, release=() => ()))
    }
  })
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    fixture.opened_uris.push(request.location.uri.to_string())
    fixture.opened_modes.push(browser_definition_open_mode(request.mode))
    true
  })
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    location_opener=opener,
    text_model_resolver=resolver,
    log_service=log_handle,
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(
      soft_wrap=false,
      smooth_scrolling=false,
      folding=false,
    ),
  )
  viewer.set_model(Some(model))
  viewer.set_position(Position(1, 1))
  viewer.handle_initialized()
  let markdown_viewer = @viewer.MarkdownViewer::create(
    markdown_host,
    services~,
    options=MarkdownViewerOptions(theme="dark"),
  )
  markdown_viewer.set_model(
    Some(MarkdownViewerModel(markdown_model, MoonBitMarkdown)),
  )
  |> ignore
  markdown_viewer.handle_initialized()
  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("mounted Viewer did not expose its root")
    ctx.finish()
    return
  }
  guard markdown_viewer.get_dom_node() is Some(markdown_root) else {
    ctx.fail("mounted Markdown Viewer did not expose its root")
    ctx.finish()
    return
  }
  install_definition_controls(
    root,
    markdown_root,
    () => {
      definition_state_json(
        viewer, provider_calls, markdown_provider_calls, references_provider_calls,
        markdown_provider_pending, fixture,
      )
    },
    () => viewer.set_scroll_top(0.0),
    () => viewer.set_selection(Selection(Position(2, 11), Position(2, 27))),
    () => provider_multiple.val = true,
    () => markdown_provider_delay.val = true,
    () => {
      markdown_provider_delay.val = false
      markdown_provider_release.release()
    },
    () => {
      markdown_model.set_value(
        (
          $|\{markdown_definition_source()}
          $|
          $|Projection generation changed.
        ),
      )
    },
    () => {
      markdown_viewer.set_model(
        Some(MarkdownViewerModel(markdown_replacement_model, MoonBitMarkdown)),
      )
      |> ignore
    },
  )
  wait_for_definition_fixture(ctx, 100)
}

///|
fn wait_for_definition_fixture(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  if @support.query_text(".definition-host") is Some(code_text) &&
    code_text.contains("definition_alpha") &&
    @support.query_text(".definition-markdown-host") is Some(markdown_text) &&
    markdown_text.contains("definition_alpha") {
    ctx.assert_true(
      @support.query_count(".definition-host > .monaco-editor.readonly-editor") ==
      1,
      "expected exactly one rendered outer Viewer",
    )
    ctx.finish()
    return
  }
  if remaining <= 0 {
    ctx.fail("timed out waiting for definition fixture render")
    ctx.finish()
    return
  }
  @support.set_timeout(
    () => wait_for_definition_fixture(ctx, remaining - 1),
    30,
  )
}

///|
extern "js" fn install_definition_controls(
  outer_root : @rdom.Element,
  markdown_root : @rdom.Element,
  state_json : () -> String,
  reset_scroll : () -> Unit,
  select_reference : () -> Unit,
  enable_multiple_definitions : () -> Unit,
  delay_markdown_provider : () -> Unit,
  release_markdown_provider : () -> Unit,
  replace_markdown_source : () -> Unit,
  replace_markdown_model : () -> Unit,
) -> Unit =
  #| (
  #|   outerRoot,
  #|   markdownRoot,
  #|   stateJson,
  #|   resetScroll,
  #|   selectReference,
  #|   enableMultipleDefinitions,
  #|   delayMarkdownProvider,
  #|   releaseMarkdownProvider,
  #|   replaceMarkdownSource,
  #|   replaceMarkdownModel,
  #| ) => {
  #|   globalThis.__definitionControls = {
  #|     outerRoot,
  #|     markdownRoot,
  #|     state: () => JSON.parse(stateJson()),
  #|     reset_scroll: resetScroll,
  #|     select_reference: selectReference,
  #|     enable_multiple_definitions: enableMultipleDefinitions,
  #|     delay_markdown_provider: delayMarkdownProvider,
  #|     release_markdown_provider: releaseMarkdownProvider,
  #|     replace_markdown_source: replaceMarkdownSource,
  #|     replace_markdown_model: replaceMarkdownModel,
  #|   };
  #| }
