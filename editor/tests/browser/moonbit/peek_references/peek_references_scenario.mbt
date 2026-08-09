// Real-Chromium fixture for the public precomputed-locations References Peek.
// The Viewer receives no ReferencesProvider. Playwright drives the tree and
// preview with trusted input while this fixture owns only caller-supplied
// locations, model-resolution leases, opener observations, and compact state.

///|
priv struct PeekReferencesFixtureState {
  mut resolver_calls : Int
  mut resolver_acquires : Int
  mut resolver_releases : Int
  resolved_uris : Array[String]
  open_modes : Array[String]
  open_uris : Array[String]
  open_lines : Array[Int]
  open_columns : Array[Int]
}

///|
fn peek_references_location(
  uri : @base_common.Uri,
  line : Int,
  start_column : Int,
  end_column : Int,
) -> @language.Location {
  { uri, range: Range(line, start_column, line, end_column) }
}

///|
fn peek_references_code_source() -> String {
  (
    #|target
    #|before target after
    #|target again
    #|anchor here
    #|tail
    #|overflow target 06
    #|overflow target 07
    #|overflow target 08
    #|overflow target 09
    #|overflow target 10
    #|overflow target 11
    #|overflow target 12
    #|overflow target 13
    #|overflow target 14
    #|overflow target 15
    #|overflow target 16
    #|overflow target 17
    #|overflow target 18
    #|overflow target 19
    #|overflow target 20
    #|overflow target 21
    #|overflow target 22
    #|overflow target 23
    #|overflow target 24
  )
}

///|
fn peek_references_remote_source() -> String {
  (
    #|remote target value
    #|other target
  )
}

///|
fn peek_references_other_source() -> String {
  (
    #|third target
    #|tail
  )
}

///|
fn peek_references_markdown_source() -> String {
  (
    #|# References
    #|
    #|```mbt check
    #|let target = 1
    #|let use = target
    #|```
    #|
    #|Markdown tail.
  )
}

///|
fn peek_references_mode_name(mode : @navigation_api.OpenLocationMode) -> String {
  match mode {
    Current => "Current"
    Side => "Side"
  }
}

///|
fn peek_references_state_json(
  code_viewer : @viewer.Viewer,
  markdown_viewer : @viewer.Viewer,
  state : PeekReferencesFixtureState,
) -> String {
  let (code_line, code_column) = match code_viewer.get_position() {
    Some(position) => (position.line_number, position.column)
    None => (-1, -1)
  }
  Json::object({
    "resolverCalls": state.resolver_calls.to_json(),
    "resolverAcquires": state.resolver_acquires.to_json(),
    "resolverReleases": state.resolver_releases.to_json(),
    "resolvedUris": state.resolved_uris.to_json(),
    "openModes": state.open_modes.to_json(),
    "openUris": state.open_uris.to_json(),
    "openLines": state.open_lines.to_json(),
    "openColumns": state.open_columns.to_json(),
    "codePosition": Json::object({
      "line": code_line.to_json(),
      "column": code_column.to_json(),
    }),
    "codeHasTextFocus": code_viewer.has_text_focus().to_json(),
    "markdownHasTextFocus": markdown_viewer.has_text_focus().to_json(),
  }).stringify()
}

///|
fn run_peek_references_browser_test() -> Unit {
  let ctx = @support.BrowserTestContext("peek_references")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }

  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell peek-references-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "min-height:100vh;padding:16px;")
  let code_host = document.create_element("div")
  code_host.set_attribute("class", "viewer-host peek-references-code-host")
  code_host.set_attribute("style", "height:360px;width:760px;")
  let markdown_host = document.create_element("div")
  markdown_host.set_attribute(
    "class", "viewer-host peek-references-markdown-host",
  )
  markdown_host.set_attribute(
    "style", "height:360px;width:760px;margin-top:24px;",
  )
  shell.append_child(code_host.as_node())
  shell.append_child(markdown_host.as_node())
  app.append_child(shell.as_node())

  let source_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/src/source.mbt",
  )
  let remote_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/lib/remote.mbt",
  )
  let other_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/vendor/other.mbt",
  )
  let markdown_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/docs/references.mbt.md",
  )
  let source_model = @model.TextModel(
    source_uri,
    "source.mbt",
    "moonbit",
    1,
    "peek-references-source-rev-1",
    peek_references_code_source(),
  )
  let remote_model = @model.TextModel(
    remote_uri,
    "remote.mbt",
    "moonbit",
    1,
    "peek-references-remote-rev-1",
    peek_references_remote_source(),
  )
  let other_model = @model.TextModel(
    other_uri,
    "other.mbt",
    "moonbit",
    1,
    "peek-references-other-rev-1",
    peek_references_other_source(),
  )
  let markdown_model = @model.TextModel(
    markdown_uri,
    "references.mbt.md",
    "markdown",
    1,
    "peek-references-markdown-rev-1",
    peek_references_markdown_source(),
  )
  let state : PeekReferencesFixtureState = {
    resolver_calls: 0,
    resolver_acquires: 0,
    resolver_releases: 0,
    resolved_uris: [],
    open_modes: [],
    open_uris: [],
    open_lines: [],
    open_columns: [],
  }
  let resolver = @navigation_api.TextModelResolverHandle(resolve=(
    resource,
    _token,
  ) => {
    state.resolver_calls += 1
    state.resolved_uris.push(resource.to_string())
    let resolved = if resource.to_string() == remote_uri.to_string() {
      Some(remote_model)
    } else if resource.to_string() == other_uri.to_string() {
      Some(other_model)
    } else {
      None
    }
    match resolved {
      Some(model) => {
        state.resolver_acquires += 1
        Some(
          TextModelReference(model, release=() => state.resolver_releases += 1),
        )
      }
      None => None
    }
  })
  let opener = @navigation_api.LocationOpenerHandle(open=request => {
    state.open_modes.push(peek_references_mode_name(request.mode))
    state.open_uris.push(request.location.uri.to_string())
    state.open_lines.push(request.location.range.start_line_number)
    state.open_columns.push(request.location.range.start_column)
    true
  })
  let services = @viewer.ViewerServices(
    location_opener=opener,
    text_model_resolver=resolver,
  )
  let options = @viewer.ViewerOptions(
    soft_wrap=false,
    smooth_scrolling=false,
    folding=false,
  )
  let code_viewer = @viewer.Viewer::create(code_host, services~, options~)
  code_viewer.set_model(Some(source_model))
  code_viewer.set_position(Position(4, 1))
  code_viewer.handle_initialized()
  let markdown_viewer = @viewer.Viewer::create(
    markdown_host,
    services~,
    options~,
  )
  markdown_viewer.set_model(Some(markdown_model))
  markdown_viewer.handle_initialized()

  let code_locations : Array[@language.Location] = [
    peek_references_location(remote_uri, 1, 8, 14),
    peek_references_location(source_uri, 1, 1, 7),
    peek_references_location(other_uri, 1, 7, 13),
    peek_references_location(source_uri, 3, 1, 7),
    peek_references_location(remote_uri, 2, 7, 13),
    peek_references_location(source_uri, 2, 8, 14),
  ]
  let markdown_locations : Array[@language.Location] = [
    peek_references_location(markdown_uri, 4, 5, 11),
    peek_references_location(markdown_uri, 5, 11, 17),
  ]
  let overflow_locations : Array[@language.Location] = []
  for line in 1..<=24 {
    overflow_locations.push(peek_references_location(source_uri, line, 1, 2))
  }
  guard code_viewer.get_dom_node() is Some(code_root) else {
    ctx.fail("mounted Code Viewer did not expose its root")
    ctx.finish()
    return
  }
  guard markdown_viewer.get_dom_node() is Some(markdown_root) else {
    ctx.fail("mounted Markdown Viewer did not expose its root")
    ctx.finish()
    return
  }
  install_peek_references_controls(
    code_root,
    markdown_root,
    () => peek_references_state_json(code_viewer, markdown_viewer, state),
    () => {
      code_viewer.set_position(Position(4, 1))
      code_viewer.show_references(Position(4, 1), code_locations)
    },
    () => code_viewer.show_references(Position(4, 2), code_locations),
    () => code_viewer.show_references(Position(4, 1), []),
    () => code_viewer.show_references(Position(4, 1), overflow_locations),
    () => markdown_viewer.show_references(Position(5, 11), markdown_locations),
    () => code_viewer.focus(),
    () => markdown_viewer.focus(),
    () => {
      state.open_modes.clear()
      state.open_uris.clear()
      state.open_lines.clear()
      state.open_columns.clear()
    },
  )
  wait_for_peek_references_fixture(ctx, 100)
}

///|
fn wait_for_peek_references_fixture(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  if @support.query_count(
      ".peek-references-code-host > .monaco-editor.readonly-editor",
    ) ==
    1 &&
    @support.query_count(
      ".peek-references-markdown-host > .moonbit-viewer-markdown-document",
    ) ==
    1 {
    ctx.assert_true(
      @support.query_count(
        ".peek-references-code-host > .monaco-editor.readonly-editor",
      ) ==
      1,
      "expected exactly one rendered Code Viewer",
    )
    ctx.assert_true(
      @support.query_count(
        ".peek-references-markdown-host > .moonbit-viewer-markdown-document",
      ) ==
      1,
      "expected exactly one rendered Markdown Viewer",
    )
    ctx.finish()
    return
  }
  if remaining <= 0 {
    ctx.fail("timed out waiting for Peek References fixture render")
    ctx.finish()
    return
  }
  @support.set_timeout(
    () => wait_for_peek_references_fixture(ctx, remaining - 1),
    30,
  )
}

///|
extern "js" fn install_peek_references_controls(
  code_root : @rdom.Element,
  markdown_root : @rdom.Element,
  state_json : () -> String,
  show_code : () -> Unit,
  show_code_other_anchor : () -> Unit,
  show_code_empty : () -> Unit,
  show_code_overflow : () -> Unit,
  show_markdown : () -> Unit,
  focus_code : () -> Unit,
  focus_markdown : () -> Unit,
  clear_opens : () -> Unit,
) -> Unit =
  #| (
  #|   codeRoot,
  #|   markdownRoot,
  #|   stateJson,
  #|   showCode,
  #|   showCodeOtherAnchor,
  #|   showCodeEmpty,
  #|   showCodeOverflow,
  #|   showMarkdown,
  #|   focusCode,
  #|   focusMarkdown,
  #|   clearOpens,
  #| ) => {
  #|   globalThis.__peekReferencesControls = {
  #|     codeRoot,
  #|     markdownRoot,
  #|     state: () => JSON.parse(stateJson()),
  #|     show_code: showCode,
  #|     show_code_other_anchor: showCodeOtherAnchor,
  #|     show_code_empty: showCodeEmpty,
  #|     show_code_overflow: showCodeOverflow,
  #|     show_markdown: showMarkdown,
  #|     focus_code: focusCode,
  #|     focus_markdown: focusMarkdown,
  #|     clear_opens: clearOpens,
  #|   };
  #| }
