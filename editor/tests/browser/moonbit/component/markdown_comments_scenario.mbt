// Mounted whole-line Markdown-comment fixture. The scenario constructs the
// public Viewer directly; Playwright observes the resulting projection, DOM,
// input ownership, and model lifecycle through deterministic public-API
// controls rather than reaching into contribution internals. Attachment-count
// evidence uses an explicitly installed private browser diagnostic.

///|
extern "js" fn install_markdown_comments_private_probe() -> Unit =
  #| () => {
  #|   const probe = globalThis.__viewerPrivateTestProbe ?? {};
  #|   probe.acceptTextModelAttachedCount = function(getAttachedCount) {
  #|     this.textModelAttachedCount = getAttachedCount;
  #|   };
  #|   globalThis.__viewerPrivateTestProbe = probe;
  #| }

///|
extern "js" fn markdown_comments_attached_editor_count(
  model : @model.TextModel,
) -> Int =
  #| (model) => {
  #|   const getAttachedCount = globalThis.__viewerPrivateTestProbe?.textModelAttachedCount;
  #|   if (!getAttachedCount) throw new Error('private TextModel attachment diagnostic was not offered');
  #|   return getAttachedCount(model);
  #| }

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
fn markdown_comments_same_key_source() -> String {
  let source =
    #|/// # Start comment
    #|/// Start prose with [fixture link](https://example.test/docs).
    #|alpha_code_truth
    #|let long_neighbor = "horizontal_overflow_sentinel alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega"
    #|/// ## Middle updated
    #|/// The same-key replacement body is intentionally even longer so width changes produce a visible measured-height transition without changing this block's half-open line range.
    #|/// 1. updated first item
    #|/// 2. updated second item
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
    #|/// compact -> viewport: replaced
    #|/// ```
    #|///
    #|/// ![fixture image](https://images.example.test/markdown-comment.svg)
    #|/// EOF paragraph.
  source
}

///|
fn markdown_comments_restructured_source() -> String {
  let source =
    #|preface_code
    #|/// ## Middle moved
    #|/// The former middle block now has a different model range.
    #|alpha_code_truth
    #|/// ### Added comment
    #|/// This block did not exist before source replacement.
    #|omega_code_truth
    #|/// EOF moved
    #|/// The final block also moved to a new model range.
  source
}

///|
fn markdown_comments_replacement_source() -> String {
  let source =
    #|replacement_before
    #|/// # Replacement comment
    #|/// A different TextModel owns this rendered body.
    #|replacement_after
  source
}

///|
fn markdown_comments_folding_source() -> String {
  let source =
    #|fold_header
    #|  /// # Folded Markdown comment
    #|  /// This replacement stays visible through its own source projection.
    #|  folded_child_code
    #|fold_after
  source
}

///|
fn markdown_comments_offscreen_source() -> String {
  let source = StringBuilder()
  for line in 1..<=80 {
    if line > 1 {
      source.write_char('\n')
    }
    if line == 10 {
      source.write_string(
        "offscreen_horizontal_overflow_sentinel alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega",
      )
    } else {
      source <+ "offscreen_code_line_\{line}"
    }
  }
  source.write_string(
    (
      #|
      #|/// # Offscreen measured comment
      #|/// This paragraph is intentionally long enough to wrap at several editor widths before the replacement zone first enters the viewport.
      #|///
      #|/// - first measured item
      #|/// - second measured item
      #|/// - third measured item
      #|/// - fourth measured item
      #|///
      #|/// ```diago
      #|/// direction: down
      #|/// offscreen -> viewport: initialize
      #|/// viewport -> browser: reveal
      #|/// ```
      #|///
      #|/// ![fixture image](https://images.example.test/markdown-comment.svg)
      #|/// Final offscreen paragraph.
    ),
  )
  source.to_string()
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
fn markdown_comments_mermaid_delayed_old_source() -> String {
  let source =
    #|/// # Mermaid delayed fixture
    #|/// ```mermaid
    #|/// flowchart LR
    #|/// DELAYED_OLD --> STALE
    #|/// ```
    #|mermaid_code_truth
  source
}

///|
fn markdown_comments_mermaid_delayed_new_source() -> String {
  let source =
    #|/// # Mermaid delayed fixture
    #|/// ```mermaid
    #|/// flowchart LR
    #|/// CURRENT_NEW --> CURRENT
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
fn markdown_comments_state_json(
  viewer : @viewer.Viewer,
  primary : @model.TextModel,
  replacement : @model.TextModel,
) -> String {
  let attached_kind = match viewer.get_model() {
    Some(current) if current.same(primary) => "primary"
    Some(current) if current.same(replacement) => "replacement"
    Some(_) => "other"
    None => "none"
  }
  let selection = match viewer.get_selection() {
    Some(value) => {
      let anchor = value.get_selection_start()
      let active = value.get_position()
      Json::object({
        "anchorLine": anchor.line_number.to_json(),
        "anchorColumn": anchor.column.to_json(),
        "activeLine": active.line_number.to_json(),
        "activeColumn": active.column.to_json(),
      })
    }
    None => Json::null()
  }
  Json::object({
    "attachedKind": attached_kind.to_json(),
    "attachedValue": viewer.get_value().to_json(),
    "selection": selection,
    "primaryValue": primary.get_value().to_json(),
    "primaryVersion": primary.get_version_id().to_json(),
    "primaryAttachedEditors": markdown_comments_attached_editor_count(primary).to_json(),
    "replacementValue": replacement.get_value().to_json(),
    "replacementAttachedEditors": markdown_comments_attached_editor_count(
      replacement,
    ).to_json(),
    "softWrap": viewer.get_options().soft_wrap().to_json(),
    "scrollLeft": viewer.get_scroll_left().to_json(),
    "scrollWidth": viewer.get_scroll_width().to_json(),
    "contentWidth": viewer.get_content_width().to_json(),
    "scrollTop": viewer.get_scroll_top().to_json(),
    "scrollHeight": viewer.get_scroll_height().to_json(),
  }).stringify()
}

///|
fn run_markdown_comments_test() -> Unit {
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

  install_markdown_comments_private_probe()
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
  let replacement = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/markdown-comments-replacement.mbt",
    ),
    "markdown-comments-replacement.mbt",
    "moonbit",
    2,
    "markdown-comments-replacement-rev-1",
    markdown_comments_replacement_source(),
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
    host,
    root,
    () => markdown_comments_state_json(viewer, primary, replacement),
    () => viewer.set_value(markdown_comments_same_key_source()),
    () => viewer.set_value(markdown_comments_restructured_source()),
    () => viewer.set_value(markdown_comments_initial_source()),
    () => viewer.set_value(markdown_comments_folding_source()),
    () => viewer.set_value(markdown_comments_offscreen_source()),
    () => viewer.set_value(markdown_comments_mermaid_source()),
    () => viewer.set_value(markdown_comments_mermaid_delayed_old_source()),
    () => viewer.set_value(markdown_comments_mermaid_delayed_new_source()),
    () => viewer.set_value(markdown_comments_mermaid_offscreen_source()),
    () => viewer.update_options(viewer.get_options().with_theme("light")),
    () => viewer.update_options(viewer.get_options().with_theme("dark")),
    width => {
      host.set_attribute("style", "height:680px;width:\{width}px;")
      viewer.layout()
    },
    () => viewer.set_selection(Selection(Position(3, 1), Position(3, 17))),
    () => viewer.focus(),
    () => viewer.set_model(None),
    () => {
      viewer.set_model(Some(replacement))
      viewer.handle_initialized()
    },
    () => {
      viewer.set_model(Some(primary))
      viewer.handle_initialized()
    },
    () => viewer.set_scroll_top(viewer.get_scroll_height()),
    top => viewer.set_scroll_top(top.to_double()),
    left => viewer.set_scroll_left(left.to_double()),
    enabled => {
      viewer.update_options(viewer.get_options().with_soft_wrap(enabled))
    },
    () => viewer.dispose(),
  )
  poll_markdown_comments_ready(ctx, 120)
}

///|
fn poll_markdown_comments_ready(
  ctx : @support.BrowserTestContext,
  remaining : Int,
) -> Unit {
  let zones = @support.query_count(".moonbit-viewer-markdown-comment")
  let diagrams = @support.query_count(
    ".markdown-comments-host .moonbit-viewer-markdown-diagram-content > svg",
  )
  let text = @support.query_text(".markdown-comments-host")
  if zones == 3 &&
    diagrams == 2 &&
    text.contains("Start comment") &&
    text.contains("Middle comment") &&
    text.contains("EOF paragraph") &&
    markdown_comments_controls_installed() {
    ctx.metric_int("initialZones", zones)
    ctx.metric_int("initialDiagrams", diagrams)
    ctx.metric_int(
      "visibleSourceLines",
      @support.query_count(".markdown-comments-host .view-line"),
    )
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
  host : @rdom.Element,
  initial_root : @rdom.Element,
  state_json : () -> String,
  same_key_update : () -> Unit,
  restructure : () -> Unit,
  restore_initial : () -> Unit,
  folding_source : () -> Unit,
  offscreen_source : () -> Unit,
  mermaid_source : () -> Unit,
  mermaid_delayed_old_source : () -> Unit,
  mermaid_delayed_new_source : () -> Unit,
  mermaid_offscreen_source : () -> Unit,
  theme_light : () -> Unit,
  theme_dark : () -> Unit,
  resize : (Int) -> Unit,
  set_model_selection : () -> Unit,
  focus : () -> Unit,
  detach : () -> Unit,
  attach_replacement : () -> Unit,
  reattach_primary : () -> Unit,
  scroll_to_bottom : () -> Unit,
  set_scroll_top : (Int) -> Unit,
  set_scroll_left : (Int) -> Unit,
  set_soft_wrap : (Bool) -> Unit,
  dispose_viewer : () -> Unit,
) -> Unit =
  #| (host, initialRoot, stateJson, sameKeyUpdate, restructure,
  #|  restoreInitial, foldingSource, offscreenSource, mermaidSource,
  #|  mermaidDelayedOldSource, mermaidDelayedNewSource, mermaidOffscreenSource,
  #|  themeLight, themeDark, resize, setModelSelection, focus, detach,
  #|  attachReplacement, reattachPrimary, scrollToBottom, setScrollTop,
  #|  setScrollLeft, setSoftWrap, disposeViewer) => {
  #|   const keyLog = [];
  #|   const copyLog = [];
  #|   let disposed = false;
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
  #|     });
  #|   });
  #|   globalThis.__markdownCommentsControls = {
  #|     host,
  #|     initialRoot,
  #|     state: () => ({ ...JSON.parse(stateJson()), disposed }),
  #|     keys: () => [...keyLog],
  #|     copies: () => [...copyLog],
  #|     clear_input_log: () => {
  #|       keyLog.length = 0;
  #|       copyLog.length = 0;
  #|       delete globalThis.__readonlyEditorCopiedText;
  #|       delete globalThis.__readonlyEditorCopiedHtml;
  #|     },
  #|     same_key_update: sameKeyUpdate,
  #|     restructure,
  #|     restore_initial: restoreInitial,
  #|     folding_source: foldingSource,
  #|     offscreen_source: offscreenSource,
  #|     mermaid_source: mermaidSource,
  #|     mermaid_delayed_old_source: mermaidDelayedOldSource,
  #|     mermaid_delayed_new_source: mermaidDelayedNewSource,
  #|     mermaid_offscreen_source: mermaidOffscreenSource,
  #|     theme_light: themeLight,
  #|     theme_dark: themeDark,
  #|     resize,
  #|     set_model_selection: setModelSelection,
  #|     focus,
  #|     detach,
  #|     attach_replacement: attachReplacement,
  #|     reattach_primary: reattachPrimary,
  #|     scroll_to_bottom: scrollToBottom,
  #|     set_scroll_top: setScrollTop,
  #|     set_scroll_left: setScrollLeft,
  #|     set_soft_wrap: setSoftWrap,
  #|     dispose: () => {
  #|       disposeViewer();
  #|       disposed = true;
  #|     },
  #|   };
  #| }
