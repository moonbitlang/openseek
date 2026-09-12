// Real-browser DiffEditor fixture for Markdown-comment contribution policy.
// The public facade owns both kernels; Playwright only selects a source pair,
// switches layout, and resizes the host while observing ordinary pane DOM.

///|
fn diff_markdown_comment_model(
  name : String,
  content : String,
) -> @model.TextModel {
  let uri = @base_common.Uri::from(
    scheme="memory",
    authority="diff-markdown-comments",
    path="/\{name}.mbt",
  ) catch {
    _ => abort("invalid diff Markdown-comment fixture URI")
  }
  TextModel(
    uri,
    "\{name}.mbt",
    "moonbit",
    1,
    "diff-markdown-comments-\{name}",
    content,
  )
}

///|
fn diff_markdown_comment_unchanged_source() -> String {
  (
    #|let before = 1
    #|/// ## Shared comment
    #|/// The same rendered Markdown block is present in both panes.
    #|/// - alpha
    #|/// - beta
    #|let shared_tail = 2
  )
}

///|
fn diff_markdown_comment_original_source() -> String {
  (
    #|let before = 1
    #|/// ## Original comment
    #|/// The old rendered block is intentionally short.
    #|/// old value
    #|let shared_tail = 2
  )
}

///|
fn diff_markdown_comment_modified_source() -> String {
  (
    #|let before = 1
    #|/// ## Modified comment
    #|/// The replacement is deliberately longer so its rich ViewZone has a
    #|/// different measured height after narrow and wide pane layouts.
    #|/// - first replacement item
    #|/// - second replacement item
    #|/// - third replacement item
    #|let shared_tail = 2
  )
}

///|
fn diff_markdown_comment_partial_original_source() -> String {
  (
    #|let before = 1
    #|/// Tiny
    #|/// words
    #|/// stay
    #|/// on
    #|/// one
    #|/// old
    #|let shared_tail = 2
  )
}

///|
fn diff_markdown_comment_partial_modified_source() -> String {
  (
    #|let before = 1
    #|/// Tiny
    #|/// words
    #|/// stay
    #|/// on
    #|/// one
    #|/// new
    #|let shared_tail = 2
  )
}

///|
fn diff_markdown_comment_editor_options(
  folding_mode : String,
) -> @viewer.ViewerOptions {
  match folding_mode {
    "disabled" =>
      ViewerOptions(
        soft_wrap=true,
        smooth_scrolling=false,
        line_numbers_min_chars=1,
        folding=false,
      )
    "never" =>
      ViewerOptions(
        soft_wrap=true,
        smooth_scrolling=false,
        line_numbers_min_chars=1,
        show_folding_controls=Never,
      )
    _ =>
      ViewerOptions(
        soft_wrap=true,
        smooth_scrolling=false,
        line_numbers_min_chars=1,
      )
  }
}

///|
priv struct DiffMarkdownCommentProvider {}

///|
impl @language.MarkdownCommentProvider for DiffMarkdownCommentProvider with fn provide_markdown_comments(
  _self,
  model,
) {
  let snapshot = model.snapshot()
  let blocks : Array[@language.MarkdownCommentBlock] = []
  let mut line_number = 1
  while line_number <= snapshot.line_count() {
    let line = snapshot.get_line_content(line_number).trim()
    if !line.has_prefix("///") {
      line_number += 1
      continue
    }
    let start_line_number = line_number
    let markdown : Array[String] = []
    while line_number <= snapshot.line_count() {
      let line = snapshot.get_line_content(line_number).trim().to_owned()
      if !line.has_prefix("///") {
        break
      }
      let mut content_start = 3
      if content_start < line.length() && line[content_start].to_int() == 32 {
        content_start += 1
      }
      markdown.push(
        line.unsafe_substring(start=content_start, end=line.length()),
      )
      line_number += 1
    }
    blocks.push({
      line_range: LineRange(start_line_number, line_number),
      markdown: "---\n\n" + markdown.join("\n"),
    })
  }
  blocks
}

///|
pub fn run_diff_markdown_comments_test() -> Unit {
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    abort("missing #app mount point")
  }
  let host = document.create_element("div")
  host.set_attribute("class", "diff-markdown-comments-host")
  host.set_attribute("style", "display:none;width:1100px;height:640px;")
  app.append_child(host.as_node())

  let log_service = @log.LogService()
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
  languages.register_markdown_comment_provider(
    LanguageId("moonbit"),
    DiffMarkdownCommentProvider::{ },
    foldable=true,
  )
  |> ignore
  let feedback = @feedback_contrib.AgentFeedbackService()
  let services = @viewer.ViewerServices(
    agent_feedback=feedback.agent_feedback_handle(),
    languages=languages.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  let editor_options = Ref(diff_markdown_comment_editor_options("default"))
  let layout : Ref[@viewer.DiffEditorLayout] = Ref(Inline)
  let render_markdown_comments = Ref(true)
  let diff_editor = @viewer.DiffEditor::create(
    host,
    services~,
    options=DiffEditorOptions(
      editor_options=editor_options.val,
      layout=layout.val,
      render_markdown_comments=render_markdown_comments.val,
      automatic_inline=false,
    ),
  )
  let content_height_event_count = Ref(0)
  let mut auto_height_enabled = false
  let apply_content_height = content_height => {
    if content_height <= 0.0 {
      return
    }
    @base_browser.set_style_property(
      host,
      "height",
      "\{(content_height.ceil() + 2.0).max(40.0)}px",
    )
    diff_editor.layout()
  }
  diff_editor.on_did_change_content_height(content_height => {
    content_height_event_count.val += 1
    if auto_height_enabled {
      apply_content_height(content_height)
    }
  })
  |> ignore
  let unchanged_original = diff_markdown_comment_model(
    "unchanged-original",
    diff_markdown_comment_unchanged_source(),
  )
  let unchanged_modified = diff_markdown_comment_model(
    "unchanged-modified",
    diff_markdown_comment_unchanged_source(),
  )
  let replacement_original = diff_markdown_comment_model(
    "replacement-original",
    diff_markdown_comment_original_source(),
  )
  let replacement_modified = diff_markdown_comment_model(
    "replacement-modified",
    diff_markdown_comment_modified_source(),
  )
  let partial_original = diff_markdown_comment_model(
    "partial-original",
    diff_markdown_comment_partial_original_source(),
  )
  let partial_modified = diff_markdown_comment_model(
    "partial-modified",
    diff_markdown_comment_partial_modified_source(),
  )
  diff_editor.set_model(
    Some(DiffEditorModel(unchanged_original, unchanged_modified)),
  )
  |> ignore
  host.set_attribute("style", "width:1100px;height:640px;")
  diff_editor.layout()

  install_diff_markdown_comments_controls(
    fixture => {
      let pair : @viewer.DiffEditorModel = match fixture {
        "replacement" =>
          DiffEditorModel(replacement_original, replacement_modified)
        "partial" => DiffEditorModel(partial_original, partial_modified)
        _ => DiffEditorModel(unchanged_original, unchanged_modified)
      }
      diff_editor.set_model(Some(pair)) |> ignore
    },
    layout_name => {
      layout.val = if layout_name == "inline" { Inline } else { SideBySide }
      diff_editor.update_options(
        DiffEditorOptions(
          editor_options=editor_options.val,
          layout=layout.val,
          render_markdown_comments=render_markdown_comments.val,
          automatic_inline=false,
        ),
      )
    },
    width => {
      host.set_attribute("style", "width:\{width}px;height:640px;")
      diff_editor.layout()
    },
    enabled => {
      feedback.set_feedback_enabled(unchanged_original.uri, enabled)
      feedback.set_feedback_enabled(unchanged_modified.uri, enabled)
    },
    folding_mode => {
      editor_options.val = diff_markdown_comment_editor_options(folding_mode)
      diff_editor.update_options(
        DiffEditorOptions(
          editor_options=editor_options.val,
          layout=layout.val,
          render_markdown_comments=render_markdown_comments.val,
          automatic_inline=false,
        ),
      )
    },
    enabled => {
      render_markdown_comments.val = enabled
      diff_editor.update_options(
        DiffEditorOptions(
          editor_options=editor_options.val,
          layout=layout.val,
          render_markdown_comments=enabled,
          automatic_inline=false,
        ),
      )
    },
    () => {
      auto_height_enabled = true
      apply_content_height(diff_editor.get_content_height())
    },
    () => content_height_event_count.val,
    () => diff_editor.get_content_height(),
  )
}

///|
extern "js" fn install_diff_markdown_comments_controls(
  set_fixture : (String) -> Unit,
  set_layout : (String) -> Unit,
  resize : (Int) -> Unit,
  set_feedback_enabled : (Bool) -> Unit,
  set_folding_mode : (String) -> Unit,
  set_render_markdown_comments : (Bool) -> Unit,
  enable_auto_height : () -> Unit,
  content_height_event_count : () -> Int,
  content_height : () -> Double,
) -> Unit =
  #| (setFixture, setLayout, resize, setFeedbackEnabled, setFoldingMode, setRenderMarkdownComments, enableAutoHeight, contentHeightEventCount, contentHeight) => {
  #|   globalThis.__diffMarkdownCommentsControls = Object.freeze({
  #|     set_fixture: setFixture,
  #|     set_layout: setLayout,
  #|     resize,
  #|     set_feedback_enabled: setFeedbackEnabled,
  #|     set_folding_mode: setFoldingMode,
  #|     set_render_markdown_comments: setRenderMarkdownComments,
  #|     enable_auto_height: enableAutoHeight,
  #|     content_height_event_count: contentHeightEventCount,
  #|     content_height: contentHeight,
  #|   });
  #| }
