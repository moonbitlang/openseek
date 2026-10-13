// Real-browser whole-line Markdown-comment fixture. The scenario constructs the
// public Viewer directly; Playwright observes the resulting projection, DOM,
// input ownership, and real diagram sizing through the smallest deterministic
// public-API control surface. The retained Playwright cases own contribution
// lifecycle and DOM reconciliation; DOM-free policy remains in package tests.

///|
fn markdown_comments_initial_source() -> String {
  let source =
    #|/// # Start comment
    #|/// Start prose with [fixture link](https://example.test/docs).
    #|alpha_code_truth
    #|let long_neighbor = "horizontal_overflow_sentinel alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega"
    #|/// ## Middle comment
    #|/// The **same-key initial phrase** is deliberately long enough to reflow after the public Viewer host becomes narrow.
    #|/// - first item
    #|/// - second item
    #|omega_code_truth
    #|/// ```moonbit
    #|/// let fenced_value = 42
    #|/// ```
    #|///
    #|/// ```diago
    #|/// direction: down
    #|/// viewer -> markdown: source
    #|/// markdown -> parser: parse
    #|/// parser -> layout: layout
    #|/// layout -> svg: render
    #|/// svg -> browser: mount
    #|/// ```
    #|///
    #|/// ```diago
    #|/// compact -> viewport: fit
    #|/// ```
    #|///
    #|/// ![fixture image](https://images.example.test/markdown-comment.svg)
    #|/// EOF paragraph.
  source
}

///|
fn markdown_comments_mermaid_source() -> String {
  let source =
    #|/// # Mermaid fixture
    #|/// Two valid diagrams render independently while the invalid diagram keeps its tokenized source fallback.
    #|///
    #|/// ```mermaid
    #|/// flowchart LR
    #|/// VALID_ONE --> VALID_TWO
    #|/// ```
    #|///
    #|/// ```mermaid
    #|/// sequenceDiagram
    #|/// Alice->>Bob: VALID_SECOND
    #|/// ```
    #|///
    #|/// ```mermaid
    #|/// INVALID
    #|/// ```
    #|///
    #|/// ```Mermaid
    #|/// CASE_SENSITIVE_FALLBACK
    #|/// ```
    #|mermaid_code_truth
  source
}

///|
fn markdown_comments_mermaid_offscreen_source() -> String {
  let source = StringBuilder()
  for line in 1..<=80 {
    if line > 1 {
      source.write_char('\n')
    }
    source <+ "m_pad_\{line}"
  }
  source.write_string(
    (
      #|
      #|/// # Offscreen Mermaid fixture
      #|/// The rendered SVG must participate in measurement before this ViewZone enters the viewport.
      #|///
      #|/// ```mermaid
      #|/// flowchart LR
      #|/// VALID_ONE --> RESPONSIVE_OFFSCREEN
      #|/// ```
      #|mermaid_code_truth
    ),
  )
  source.to_string()
}

///|
fn markdown_comments_state_json(viewer : @viewer.Viewer) -> String {
  let selection = match viewer.get_selection() {
    Some(value) => {
      let anchor = value.get_selection_start()
      let active = value.get_position()
      Json({
        "anchorLine": Json(anchor.line_number),
        "anchorColumn": Json(anchor.column),
        "activeLine": Json(active.line_number),
        "activeColumn": Json(active.column),
      })
    }
    None => Json::null()
  }
  Json({
    "selection": selection,
    "softWrap": Json(viewer.get_options().soft_wrap()),
    "scrollLeft": Json(viewer.get_scroll_left()),
    "scrollWidth": Json(viewer.get_scroll_width()),
    "contentWidth": Json(viewer.get_content_width()),
    "scrollTop": Json(viewer.get_scroll_top()),
    "scrollHeight": Json(viewer.get_scroll_height()),
  }).stringify()
}

///|
pub fn run_markdown_comments_test() -> Unit {
  let ctx = @support.BrowserTestContext("markdown_comments")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell markdown-comments-shell")
  shell.set_attribute("data-theme", "dark")
  shell.set_attribute("style", "height:100vh;display:block;")
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host markdown-comments-host")
  host.set_attribute("style", "height:680px;width:520px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())

  let primary = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/markdown-comments.mbt",
    ),
    "markdown-comments.mbt",
    "moonbit",
    1,
    "markdown-comments-rev-1",
    markdown_comments_initial_source(),
  )
  let log_service = @log.LogService()
  let log_handle = log_service.log_handle()
  let languages = @languages.Languages()
  languages.set_language_configuration("moonbit", {
    comments: Some({
      line_comment: Some(LineCommentRule("///")),
      block_comment: None,
    }),
    folding_rules: None,
  })
  languages.set_tokens_provider("moonbit", @lang_moonbit.MoonBitTokenizer())
  |> ignore
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_handle),
    log_service=log_handle,
  )
  let viewer = @viewer.Viewer::create(
    host,
    services~,
    options=ViewerOptions(soft_wrap=false, smooth_scrolling=false),
  )
  viewer.set_model(Some(primary))
  viewer.handle_initialized()
  guard viewer.get_dom_node() is Some(root) else {
    ctx.fail("missing mounted Viewer root")
    ctx.finish()
    return
  }
  install_markdown_comments_controls(
    root,
    () => markdown_comments_state_json(viewer),
    () => viewer.set_value(markdown_comments_mermaid_source()),
    () => viewer.set_value(markdown_comments_mermaid_offscreen_source()),
    () => viewer.update_options(viewer.get_options().with_theme("light")),
    () => viewer.update_options(viewer.get_options().with_theme("dark")),
    width => {
      host.set_attribute("style", "height:680px;width:\{width}px;")
      viewer.layout()
    },
    () => viewer.set_selection(Selection(Position(3, 1), Position(3, 17))),
    () => viewer.focus(),
    () => viewer.set_scroll_top(viewer.get_scroll_height()),
    top => viewer.set_scroll_top(top.to_double()),
    left => viewer.set_scroll_left(left.to_double()),
    enabled => {
      viewer.update_options(viewer.get_options().with_soft_wrap(enabled))
    },
  )
  poll_markdown_comments_ready(ctx, 120)
}

///|
fn poll_markdown_comments_ready(
  ctx : @support.BrowserTestContext,
  remaining : Int32,
) -> Unit {
  let zones = @support.query_count(".moonbit-viewer-markdown-comment")
  let diagrams = @support.query_count(
    ".markdown-comments-host .moonbit-viewer-markdown-diagram-content > svg",
  )
  let text = @support.query_text(".markdown-comments-host")
  if zones == 3 &&
    diagrams == 2 &&
    text is Some(text) &&
    text.contains("Start comment") &&
    text.contains("Middle comment") &&
    text.contains("EOF paragraph") &&
    markdown_comments_controls_installed() {
    ctx.metric_int("initialZones", zones)
    ctx.metric_int("initialDiagrams", diagrams)
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for mounted Markdown-comment projection")
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_markdown_comments_ready(ctx, remaining - 1),
      30,
    )
  }
}

///|
extern "js" fn markdown_comments_controls_installed() -> Bool =
  #| () => Boolean(globalThis.__markdownCommentsControls)

///|
extern "js" fn install_markdown_comments_controls(
  initial_root : @rdom.Element,
  state_json : () -> String,
  mermaid_source : () -> Unit,
  mermaid_offscreen_source : () -> Unit,
  theme_light : () -> Unit,
  theme_dark : () -> Unit,
  resize : (Int32) -> Unit,
  set_model_selection : () -> Unit,
  focus : () -> Unit,
  scroll_to_bottom : () -> Unit,
  set_scroll_top : (Int32) -> Unit,
  set_scroll_left : (Int32) -> Unit,
  set_soft_wrap : (Bool) -> Unit,
) -> Unit =
  #| (initialRoot, stateJson, mermaidSource, mermaidOffscreenSource,
  #|  themeLight, themeDark, resize, setModelSelection, focus,
  #|  scrollToBottom, setScrollTop, setScrollLeft, setSoftWrap) => {
  #|   const keyLog = [];
  #|   const copyLog = [];
  #|   initialRoot.addEventListener('keydown', (event) => {
  #|     keyLog.push({
  #|       key: event.key,
  #|       defaultPrevented: event.defaultPrevented,
  #|       targetRole: event.target?.getAttribute?.('role') ?? '',
  #|       targetClass: event.target?.className ?? '',
  #|     });
  #|   });
  #|   initialRoot.addEventListener('copy', (event) => {
  #|     copyLog.push({
  #|       defaultPrevented: event.defaultPrevented,
  #|       nativeSelection: document.getSelection()?.toString() ?? '',
  #|       targetClass: event.target?.className ?? '',
  #|       plain: event.clipboardData?.getData('text/plain') ?? '',
  #|       html: event.clipboardData?.getData('text/html') ?? '',
  #|     });
  #|   });
  #|   globalThis.__markdownCommentsControls = {
  #|     state: () => JSON.parse(stateJson()),
  #|     keys: () => [...keyLog],
  #|     copies: () => [...copyLog],
  #|     copied_payload: () => {
  #|       const latest = copyLog.at(-1);
  #|       return { plain: latest?.plain ?? '', html: latest?.html ?? '' };
  #|     },
  #|     clear_input_log: () => {
  #|       keyLog.length = 0;
  #|       copyLog.length = 0;
  #|     },
  #|     mermaid_source: mermaidSource,
  #|     mermaid_offscreen_source: mermaidOffscreenSource,
  #|     theme_light: themeLight,
  #|     theme_dark: themeDark,
  #|     resize,
  #|     set_model_selection: setModelSelection,
  #|     focus,
  #|     scroll_to_bottom: scrollToBottom,
  #|     set_scroll_top: setScrollTop,
  #|     set_scroll_left: setScrollLeft,
  #|     set_soft_wrap: setSoftWrap,
  #|   };
  #| }
