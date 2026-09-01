// DOM-free Markdown-comment policy and headless CodeEditorWidget integration. The real
// projection, reconciliation, observer, and node-lifecycle contracts live in
// the retained Playwright Markdown-comment suite.

///|
test "Markdown comment width measurements wait for the settled viewport" {
  let callbacks : Array[() -> Unit] = []
  let delays : Array[Int] = []
  let canceled = Ref(0)
  let scheduler = @base_browser.RunOnceScheduler::new_with_timer(
    MarkdownCommentWidthSettleMs,
    (callback, delay_ms) => {
      delays.push(delay_ms)
      callbacks.push(callback)
      let active = Ref(true)
      @base_common.Disposable::from(() => {
        if active.val {
          active.val = false
          canceled.val += 1
        }
      })
    },
  )
  let state = MarkdownCommentContributionState(
    viewport_measure_scheduler=scheduler,
  )
  state.schedule_all_measures()
  state.schedule_all_measures()
  assert_eq(callbacks.length(), 2)
  assert_eq(delays, [MarkdownCommentWidthSettleMs, MarkdownCommentWidthSettleMs])
  assert_eq(canceled.val, 1)
  assert_true(state.viewport_measure_scheduler.is_scheduled())
  guard callbacks.get(1) is Some(settled) else {
    fail("expected the replacement settle callback")
  }
  settled()
  assert_false(state.viewport_measure_scheduler.is_scheduled())

  state.set_viewport_measure_deferred(true)
  state.schedule_all_measures()
  assert_eq(callbacks.length(), 2)
  assert_false(state.viewport_measure_scheduler.is_scheduled())
  state.set_viewport_measure_deferred(false)
  assert_false(state.viewport_measure_scheduler.is_scheduled())
}

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
  start_line_number : Int,
  end_line_number_exclusive : Int,
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
