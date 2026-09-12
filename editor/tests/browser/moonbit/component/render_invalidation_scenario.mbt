// Browser fixture for runtime render-invalidation coverage. Playwright drives
// the public Viewer option/decoration APIs through these controls and observes
// the real rendered DOM; no private view hook is used to manufacture a frame.

///|
priv struct RenderInvalidationHoverProvider {}

///|
priv struct RenderInvalidationTokenizer {}

///|
impl @syntax.LineTokenizer for RenderInvalidationTokenizer with fn initial_state(
  _self,
) {
  TokenizerState()
}

///|
impl @syntax.LineTokenizer for RenderInvalidationTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  if line_text.length() > 0 {
    tokens.push({ start: 0, end: 1, tag: Keyword, })
    if line_text.length() > 1 {
      tokens.push({
        start: line_text.length() - 1,
        end: line_text.length(),
        tag: Keyword,
      })
    }
  }
  (tokens, state)
}

///|
impl @language.HoverProvider for RenderInvalidationHoverProvider with fn provide_hover(
  _self,
  model,
  position,
  _token,
) {
  let offset = model.get_offset_at(position)
  for needle in ["anchor", "mapping-target"] {
    if model.snapshot.get_value().find(needle) is Some(start) {
      if offset >= start && offset < start + needle.length() {
        return Some({
          range: model.snapshot.range_of(
            OffsetRange(start, start + needle.length()),
          ),
          contents: [PlainText("render invalidation hover")],
        })
      }
    }
  }
  None
}

///|
fn render_invalidation_source() -> String {
  "prefix anchor target  \u{202E}  \nthis is a deliberately long line with padding padding and enough trailing text to wrap into continuations when soft wrapping is enabled\n\ttab-stop\nmapping-target final line"
}

///|
fn render_invalidation_position_json(viewer : @viewer.Viewer) -> String {
  match viewer.get_position() {
    Some(position) =>
      "{\"line\":\{position.line_number},\"column\":\{position.column}}"
    None => "null"
  }
}

///|
pub fn run_render_invalidation_test() -> Unit {
  let ctx = @support.BrowserTestContext("render_invalidation")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell render-invalidation-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let style = document.create_element("style")
  style.set_inner_html(
    ".render-invalidation-spacing { letter-spacing: 8px !important; }",
  )
  shell.append_child(style.as_node())
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host render-invalidation-host")
  host.set_attribute("style", "height:180px;width:420px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())
  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/render-invalidation.txt",
    ),
    "render-invalidation.txt",
    "plaintext",
    1,
    "render-invalidation-rev-1",
    render_invalidation_source(),
  )
  let languages = @languages.Languages()
  languages.register_hover_provider(LanguageId("plaintext"), RenderInvalidationHoverProvider::{
  })
  |> ignore
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    log_service=log_handle,
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(
      soft_wrap=false,
      render_whitespace=None,
      render_control_characters=false,
      render_line_highlight=None,
      render_line_highlight_only_when_focus=false,
      render_validation_decorations=On,
      smooth_scrolling=false,
    ),
  )
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  viewer.set_position(Position(1, 21))
  viewer.delta_decorations([], [
    {
      range: Range(2, 1, 2, 7),
      options: ModelDecorationOptions(
        "squiggly-warning",
        message="render invalidation validation",
        show_if_collapsed=true,
        description="render invalidation validation",
      ),
    },
  ])
  |> ignore
  let mut spacing_ids : Array[String] = []
  let mut token_registration : @base_common.Disposable? = None
  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("viewer did not expose its root DOM node")
    ctx.finish()
    return
  }
  install_render_invalidation_controls(
    mode => {
      match mode {
        "none" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(None),
          )
        "boundary" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(Boundary),
          )
        "selection" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(Selection),
          )
        "trailing" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(Trailing),
          )
        "all" =>
          viewer.update_options(
            viewer.get_options().with_render_whitespace(All),
          )
        _ => ()
      }
    },
    enabled => {
      viewer.update_options(
        viewer.get_options().with_render_control_characters(enabled),
      )
    },
    () => {
      if spacing_ids.length() > 0 {
        viewer.remove_decorations(spacing_ids)
      }
      spacing_ids = viewer.delta_decorations([], [
        {
          range: Range(1, 1, 1, 7),
          options: ModelDecorationOptions(
            "",
            inline_class_name="render-invalidation-spacing",
            inline_class_name_affects_letter_spacing=true,
            description="render invalidation spacing",
          ),
        },
      ])
    },
    () => {
      viewer.remove_decorations(spacing_ids)
      spacing_ids = []
    },
    () => render_invalidation_position_json(viewer),
    () => viewer.focus(),
    () => {
      if token_registration is Some(registration) {
        registration.dispose()
      }
      token_registration = Some(
        languages.set_tokens_provider("plaintext", RenderInvalidationTokenizer::{
        }),
      )
    },
  )
  @support.set_timeout(() => poll_render_invalidation_ready(ctx, root, 100), 30)
}

///|
fn poll_render_invalidation_ready(
  ctx : @support.BrowserTestContext,
  root : @rdom.Element,
  remaining : Int,
) -> Unit {
  let line_count = @support.query_count(".render-invalidation-host .view-line")
  let validation_count = @support.query_count(
    ".render-invalidation-host .cdr.squiggly-warning",
  )
  if line_count > 0 && validation_count > 0 {
    let root_class = root.get_attribute("class")
    ctx.assert_true(
      root_class is Some(class_name) && class_name.contains("readonly-editor"),
      "viewer root did not finish mounting",
    )
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for render-invalidation fixture")
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_render_invalidation_ready(ctx, root, remaining - 1),
      30,
    )
  }
}

///|
extern "js" fn install_render_invalidation_controls(
  set_whitespace : (String) -> Unit,
  set_control : (Bool) -> Unit,
  add_spacing_decoration : () -> Unit,
  remove_spacing_decoration : () -> Unit,
  position_json : () -> String,
  focus : () -> Unit,
  recolor_tokens : () -> Unit,
) -> Unit =
  #| (setWhitespace, setControl, addSpacingDecoration,
  #|  removeSpacingDecoration, positionJson, focus, recolorTokens) => {
  #|   globalThis.__renderInvalidationControls = {
  #|     set_whitespace: setWhitespace,
  #|     set_control: setControl,
  #|     add_spacing_decoration: addSpacingDecoration,
  #|     remove_spacing_decoration: removeSpacingDecoration,
  #|     position: () => JSON.parse(positionJson()),
  #|     focus,
  #|     recolor_tokens: recolorTokens,
  #|   };
  #| }
