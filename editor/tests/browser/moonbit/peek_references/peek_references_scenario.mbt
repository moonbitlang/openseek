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
  { uri, range: Range(line, start_column, line, end_column), }
}

///|
fn peek_references_code_source() -> String {
  (
    #|target
    #|before target after
    #|target again
    #|anchor here
    #|tail
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
fn peek_references_mode_name(mode : @navigation_api.OpenLocationMode) -> String {
  match mode {
    Current => "Current"
    Side => "Side"
  }
}

///|
fn peek_references_state_json(
  code_viewer : @viewer.Viewer,
  state : PeekReferencesFixtureState,
) -> String {
  Json({
    "resolverCalls": state.resolver_calls.to_json(),
    "resolverAcquires": state.resolver_acquires.to_json(),
    "resolverReleases": state.resolver_releases.to_json(),
    "resolvedUris": state.resolved_uris.to_json(),
    "openModes": state.open_modes.to_json(),
    "openUris": state.open_uris.to_json(),
    "openLines": state.open_lines.to_json(),
    "openColumns": state.open_columns.to_json(),
    "codeHasTextFocus": code_viewer.has_text_focus().to_json(),
  }).stringify()
}

///|
pub fn run_peek_references_browser_test() -> Unit {
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
  shell.append_child(code_host.as_node())
  app.append_child(shell.as_node())

  let source_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/src/source.mbt",
  )
  let remote_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/remote.mbt",
  )
  let other_uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="references",
    path="/workspace/vendor/other.mbt",
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
    resource_path_label=uri => {
      let root = try! @base_common.Uri::parse("inmemory://references/workspace")
      if @base_common.ext_uri.is_equal_or_parent(uri, root) {
        @base_common.ext_uri.relative_path(root, uri)
      } else {
        None
      }
    },
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
  let code_locations : Array[@language.Location] = [
    peek_references_location(remote_uri, 1, 8, 14),
    peek_references_location(source_uri, 1, 1, 7),
    peek_references_location(other_uri, 1, 7, 13),
    peek_references_location(source_uri, 3, 1, 7),
    peek_references_location(remote_uri, 2, 7, 13),
    peek_references_location(source_uri, 2, 8, 14),
  ]
  guard code_viewer.get_dom_node() is Some(_) else {
    ctx.fail("mounted Code Viewer did not expose its root")
    ctx.finish()
    return
  }
  install_peek_references_controls(
    () => peek_references_state_json(code_viewer, state),
    () => {
      code_viewer.set_position(Position(4, 1))
      code_viewer.show_references(Position(4, 1), code_locations)
    },
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
    1 {
    ctx.assert_true(
      @support.query_count(
        ".peek-references-code-host > .monaco-editor.readonly-editor",
      ) ==
      1,
      "expected exactly one rendered Code Viewer",
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
  state_json : () -> String,
  show_code : () -> Unit,
  clear_opens : () -> Unit,
) -> Unit =
  #| (stateJson, showCode, clearOpens) => {
  #|   globalThis.__peekReferencesControls = {
  #|     state: () => JSON.parse(stateJson()),
  #|     show_code: showCode,
  #|     clear_opens: clearOpens,
  #|   };
  #| }
