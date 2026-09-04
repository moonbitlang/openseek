///|
fn main {
  match scenario_parameter().to_option() {
    Some(scenario) => run_scenario(scenario)
    None => report_runner_failure("missing required `scenario` query parameter")
  }
}

///|
fn run_scenario(scenario : String) -> Unit {
  match scenario {
    "agent-feedback" => @agent_feedback.run_agent_feedback_test()
    "base-browser" => @base_browser_scenario.run_base_browser_test()
    "browser-geometry" => @component.run_browser_geometry_test()
    "code-lens" => @component.run_code_lens_test()
    "cursor-input-events" => @component.run_cursor_input_events_test()
    "definition-navigation" => @definition.run_definition_browser_test()
    "diff-editor-lifecycle" => @component.run_diff_editor_lifecycle_test()
    "diff-markdown-comments" => @component.run_diff_markdown_comments_test()
    "folding" => @folding.run_folding_test()
    "folding-nested" => @folding_nested.run_folding_nested_test()
    "initial-size" => @component.run_initial_size_test()
    "markdown-comments" => @component.run_markdown_comments_test()
    "markdown-document" => @component.run_markdown_document_test()
    "markdown-folding" => @component.run_markdown_folding_test()
    "model-swap" => @model_swap.run_model_swap_test()
    "peek-references" => @peek_references.run_peek_references_browser_test()
    "quick-diff" => @quick_diff.run_quick_diff_test()
    "read-api" => @read_api.run_read_api_test()
    "render-invalidation" => @component.run_render_invalidation_test()
    "view-zones" => @component.run_view_zones_test()
    "viewer-api" => @component.run_viewer_api_test()
    "whitespace-selection" =>
      @whitespace_selection.run_whitespace_selection_test()
    _ => report_runner_failure("unknown browser scenario: `\{scenario}`")
  }
}

///|
fn report_runner_failure(message : String) -> Unit {
  let ctx = @support.BrowserTestContext("browser_runner")
  ctx.fail(message)
  ctx.finish()
}

///|
extern "js" fn scenario_parameter() -> @js.Nullable[String] =
  #| () => new URLSearchParams(location.search).get("scenario")
