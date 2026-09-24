// Real DOM selections are driven by the paired Playwright test. This host
// exposes only public model changes and the feedback persisted by the service.

///|
fn markdown_feedback_source() -> String {
  (
    #|# Feedback fixture
    #|
    #|这个功能支持 **自动保存**，也支持手动保存。
    #|
    #|第二段包含 *独立说明*，用于跨段选择。
    #|
    #|- Parent item
    #|  - Nested **review target** has details.
    #|
    #|| Feature | Description |
    #|| --- | --- |
    #|| Save | **table target** with context |
    #|
    #|```text
    #|code target with context
    #|```
    #|
    #|![Feedback image](https://example.test/browser-tests/feedback-fixture.svg)
    #|
    #|Unselected tail paragraph.
  )
}

///|
pub fn run_markdown_feedback_test() -> Unit {
  let ctx = @support.BrowserTestContext("markdown_feedback")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("class", "editor-shell")
  shell.set_attribute("data-theme", "dark")
  let host = document.create_element("div")
  host.set_attribute("class", "markdown-feedback-host")
  host.set_attribute("style", "height:420px;width:800px;")
  shell.append_child(host.as_node())
  app.append_child(shell.as_node())
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="component",
    path="/feedback.md",
  )
  let model = @model.TextModel(
    uri,
    "feedback.md",
    "markdown",
    1,
    "markdown-feedback-rev-1",
    markdown_feedback_source(),
  )
  let current_model = Ref(model)
  let feedback = @feedback_contrib.AgentFeedbackService()
  let handle = feedback.agent_feedback_handle()
  let submitted = Ref(0)
  let _submit_registration = feedback.on_did_submit_feedback(event => {
    submitted.val += event.items.length()
  })
  feedback.set_feedback_enabled(uri, true)
  let services = @viewer.ViewerServices(agent_feedback=handle)
  let viewer = @viewer.MarkdownViewer::create(
    host,
    services~,
    options=MarkdownViewerOptions(theme="dark"),
  )
  viewer.set_model(Some(MarkdownViewerModel(model, OrdinaryMarkdown))) |> ignore
  viewer.handle_initialized()
  install_markdown_feedback_controls(
    () => {
      let items = handle
        .get_feedback(uri)
        .map(item => {
          let range = item.range
          Json({
            "text": item.text.to_json(),
            "resource": item.resource.to_string().to_json(),
            "range": Json([
              range.start_line_number.to_json(),
              range.start_column.to_json(),
              range.end_line_number.to_json(),
              range.end_column.to_json(),
            ]),
            "source": current_model.val.get_value_in_range(range).to_json(),
            "submitted": (item.state == Submitted).to_json(),
          })
        })
      Json({ "items": items.to_json(), "submitted": submitted.val.to_json() }).stringify()
    },
    () => current_model.val.get_value(),
    source => current_model.val.set_value(source),
    source => {
      // Deliberately keep URI and version equal: stale DOM must be rejected
      // using model identity, not just URI/version equality.
      let replacement = @model.TextModel(
        uri, "feedback.md", "markdown", 1, "markdown-feedback-rev-1", source,
      )
      let previous = current_model.val
      current_model.val = replacement
      viewer.set_model(Some(MarkdownViewerModel(replacement, OrdinaryMarkdown)))
      |> ignore
      previous.dispose()
    },
  )
  ctx.finish()
}

///|
extern "js" fn install_markdown_feedback_controls(
  get_feedback : () -> String,
  get_source : () -> String,
  set_source : (String) -> Unit,
  replace_same_uri : (String) -> Unit,
) -> Unit =
  #| (getFeedback, getSource, setSource, replaceSameUri) => {
  #|   globalThis.__markdownFeedbackControls = {
  #|     getFeedback: () => JSON.parse(getFeedback()),
  #|     getSource,
  #|     setSource,
  #|     replaceSameUri,
  #|   };
  #| }
