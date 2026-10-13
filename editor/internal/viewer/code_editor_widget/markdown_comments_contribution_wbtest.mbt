// DOM-free Markdown-comment policy and headless CodeEditorWidget integration. The real
// projection, reconciliation, observer, and node-lifecycle contracts live in
// the retained Playwright Markdown-comment suite.

///|
test "Markdown comments mark only exact mermaid fences and keep safe fallback source" {
  let exact = @markdown_core.render_markdown(
    (
      #|```mermaid
      #|flowchart LR
      #|A[<script>alert(1)</script>] --> B
      #|```
    ),
    language_id="moonbit",
    code_block_renderer=render_markdown_comment_code_block,
  )
  assert_true(
    exact.html.contains(
      "data-diagram-language=\"mermaid\" data-mermaid-state=\"fallback\"",
    ),
  )
  assert_true(exact.html.contains("monaco-tokenized-source"))
  assert_true(exact.html.contains("&lt;script&gt;"))
  assert_false(exact.html.contains("<script>"))

  let differently_cased = @markdown_core.render_markdown(
    (
      #|```Mermaid
      #|flowchart LR
      #|A --> B
      #|```
    ),
    language_id="moonbit",
    code_block_renderer=render_markdown_comment_code_block,
  )
  assert_false(differently_cased.html.contains("data-diagram-language"))
  assert_true(differently_cased.html.contains("monaco-tokenized-source"))

  let unlabelled = @markdown_core.render_markdown(
    (
      #|```
      #|flowchart LR
      #|A --> B
      #|```
    ),
    language_id="mermaid",
    code_block_renderer=render_markdown_comment_code_block,
  )
  assert_false(unlabelled.html.contains("data-diagram-language"))
  assert_true(unlabelled.html.contains("monaco-tokenized-source"))
}

///|
test "original Markdown-comment source uses escaped token HTML" {
  let html = render_markdown_comment_original_source(
    "/// <script>alert(1)</script>\n/// let answer = 42", "moonbit",
  )
  assert_true(html.contains("monaco-tokenized-source"))
  assert_true(html.contains("&lt;script&gt;"))
  assert_false(html.contains("<script>"))
  assert_true(html.contains("let answer = 42"))
}

///|
fn markdown_contribution_block(
  start_line_number : Int32,
  end_line_number_exclusive : Int32,
  markdown : String,
) -> @language.MarkdownCommentBlock {
  {
    line_range: LineRange(start_line_number, end_line_number_exclusive),
    markdown,
  }
}

///|
priv struct MutableMarkdownContributionProvider {
  blocks : Ref[Array[@language.MarkdownCommentBlock]]
}

///|
impl @language.MarkdownCommentProvider for MutableMarkdownContributionProvider with fn provide_markdown_comments(
  self,
  _model,
) {
  self.blocks.val.copy()
}

///|
fn markdown_contribution_state(
  viewer : CodeEditorWidget,
) -> MarkdownCommentContributionState {
  viewer.markdown_comment_contribution().unwrap()
}

///|
test "headless Markdown contribution never hides source without replacement DOM" {
  let registry = @languages.Languages()
  let log_service = @log.LogService()
  let provider_blocks = Ref([
    markdown_contribution_block(2, 4, "headless comment"),
  ])
  let registration = registry.register_markdown_comment_provider(
    LanguageId("plaintext"),
    MutableMarkdownContributionProvider::{ blocks: provider_blocks, },
  )
  defer registration.dispose()
  let services = CodeEditorServices(
    languages=registry.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  defer services.dispose()
  let model = test_model(
    (
      #|one
      #|two
      #|three
      #|four
      #|five
    ),
  )
  defer model.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(services~)
  defer viewer.dispose()
  viewer.set_model(Some(model))
  assert_eq(markdown_contribution_state(viewer).rendered.length(), 0)
  assert_true(viewer.test_view_model().get_hidden_areas() == [])
  assert_eq(viewer.test_view_model().line_count(), 5)
  assert_eq(
    viewer.get_value(),
    (
      #|one
      #|two
      #|three
      #|four
      #|five
    ),
  )

  provider_blocks.val = [markdown_contribution_block(1, 2, "changed")]
  viewer.set_value(
    (
      #|ONE
      #|TWO
      #|THREE
      #|FOUR
      #|FIVE
    ),
  )
  assert_eq(markdown_contribution_state(viewer).rendered.length(), 0)
  assert_true(viewer.test_view_model().get_hidden_areas() == [])
  assert_eq(viewer.test_view_model().line_count(), 5)
}
