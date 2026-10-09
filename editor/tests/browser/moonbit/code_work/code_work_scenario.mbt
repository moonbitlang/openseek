///|
pub fn run_prepared_folding_test() -> Unit {
  let ctx = @support.BrowserTestContext("prepared_folding")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing app")
    ctx.finish()
    return
  }
  let host = document.create_element("div")
  host.set_attribute("style", "width:600px;height:400px;")
  app.append_child(host.as_node())
  let text = Array::makei(800, i => "fn f\{i}() -> Unit {\n  let x = 1\n}\n").join(
    "",
  )
  let model = @model.TextModel(
    try! @base_common.Uri::from(scheme="inmemory", path="/prepared.mbt"),
    "prepared.mbt",
    "moonbit",
    1,
    "1",
    text,
  )
  let viewer = @viewer.Viewer::create(
    host,
    options=ViewerOptions(soft_wrap=false, line_height=18.0),
  )
  let job = viewer.prepare_model(model, result => {
    match result {
      Err(_) => ctx.fail("worker folding failed")
      Ok(_) => {
        viewer.set_model(Some(model))
        viewer.fold_top_level()
        viewer.handle_initialized()
        viewer.render()
        let view_lines = (viewer.get_content_height() / 18.0).to_int()
        ctx.metric_int("viewLines", view_lines)
        ctx.assert_true(
          view_lines == 801,
          "first committed view is the complete collapsed outline",
        )
        ctx.assert_true(
          viewer.get_value() == text,
          "folding retains full source",
        )
        ctx.assert_true(
          !(@support.query_text(".view-lines") is Some(text) &&
          text.contains("let")),
          "first paint contains no expanded body",
        )
        viewer.set_model(None)
        let mut warm_ready = false
        let warm_job = viewer.prepare_model(model, result => {
          warm_ready = result is Ok(_)
        })
        ctx.assert_true(
          warm_ready, "warm preparation reuses the versioned structural ranges",
        )
        warm_job.dispose()
        // Leave the actual folded surface available to Playwright.
        viewer.set_model(Some(model))
        viewer.fold_top_level()
        viewer.render()
      }
    }
    ctx.finish()
  })
  // The model and viewer own the fixture lifetime; preserve the active job.
  ignore(job)
}

///|
pub fn run_worker_timeout_test() -> Unit {
  let ctx = @support.BrowserTestContext("worker_timeout")
  let request = @protocol.CodeWorkerRequest::Diff(
    original="a",
    modified="b",
    ignore_trim_whitespace=false,
  )
  let mut canceled_callbacks = 0
  let mut heartbeat = false
  match
    @code_worker.compute(request, _ => canceled_callbacks += 1, max_time_ms=30) {
    None => {
      ctx.fail("worker unavailable")
      ctx.finish()
      return
    }
    Some(job) => job.dispose()
  }
  @support.set_timeout(() => heartbeat = true, 10)
  match
    @code_worker.compute(
      request,
      result => {
        ctx.assert_true(
          result is Err(TimedOut),
          "busy worker is preempted by the main-thread deadline",
        )
        ctx.assert_true(
          heartbeat, "main-thread heartbeat runs while worker is busy",
        )
        @support.set_timeout(
          () => {
            ctx.assert_true(
              canceled_callbacks == 0,
              "cancel suppresses completion and its deadline callback",
            )
            ctx.finish()
          },
          70,
        )
      },
      max_time_ms=50,
    ) {
    None => {
      ctx.fail("worker unavailable")
      ctx.finish()
    }
    Some(job) => ignore(job)
  }
}
