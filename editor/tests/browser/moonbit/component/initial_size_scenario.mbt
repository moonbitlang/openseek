// Source behavior: Monaco b18492a288de038fbc7643aae6de8247029d11bd
// synchronously measures the construction container in
// `browser/config/elementSizeObserver.ts` before `_attachModel`.
// `widget/codeEditor/codeEditorWidget.ts:1074-1076` keeps the first stabilized
// visible-range publication behind the later `handleInitialized` call.

///|
pub fn run_initial_size_test() -> Unit {
  let ctx = @support.BrowserTestContext("initial_size")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let host = document.create_element("div")
  host.set_attribute("class", "viewer-host initial-size-host")
  host.set_attribute("style", "display:block;width:320px;height:180px;")
  app.append_child(host.as_node())
  let host_width = initial_size_client_width(host)
  let host_height = initial_size_client_height(host)
  ctx.metric_number("hostWidth", host_width)
  ctx.metric_number("hostHeight", host_height)
  ctx.assert_true(
    host_width > 0.0 && host_height > 0.0,
    "initial-size fixture did not mount a nonzero host",
  )

  let viewer = @viewer.Viewer::create(
    host,
    options=ViewerOptions(soft_wrap=false, font_size=12.0, line_height=18.0),
  )
  let mut rendered_notifications = 0
  let rendered_subscription = @viewer_testing.on_did_render_model(
    viewer.get_id(),
    _ => rendered_notifications += 1,
  )
  let initial_layout = viewer.get_layout_info()
  ctx.metric_number("initialLayoutWidth", initial_layout.width)
  ctx.metric_number("initialLayoutHeight", initial_layout.height)
  ctx.assert_true(
    initial_layout.width == host_width,
    "Viewer::create did not synchronously seed layout width from clientWidth",
  )
  ctx.assert_true(
    initial_layout.height == host_height,
    "Viewer::create did not synchronously seed layout height from clientHeight",
  )

  let model = @model.TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="model",
      path="/initial-size.txt",
    ),
    "initial-size.txt",
    "plaintext",
    1,
    "initial-size-rev-1",
    initial_size_source(),
  )
  viewer.set_model(Some(model))
  let visible_ranges = viewer.get_visible_ranges()
  let initial_visible_end_line = if visible_ranges.is_empty() {
    0
  } else {
    visible_ranges[visible_ranges.length() - 1].end_line_number
  }
  ctx.metric_int("initialVisibleEndLine", initial_visible_end_line)
  ctx.assert_true(
    initial_visible_end_line > 1,
    "model attach used the zero-height single-line visible range",
  )
  viewer.handle_initialized()
  initial_size_next_frame(() => {
    ctx.assert_true(
      rendered_notifications > 0,
      "the first mounted flush did not render the attached model",
    )
    rendered_subscription.dispose()
    viewer.dispose()
    model.dispose()
    ctx.finish()
  })
}

///|
fn initial_size_source() -> String {
  (
    #|line 01
    #|line 02
    #|line 03
    #|line 04
    #|line 05
    #|line 06
    #|line 07
    #|line 08
    #|line 09
    #|line 10
    #|line 11
    #|line 12
  )
}

///|
extern "js" fn initial_size_client_width(element : @rdom.Element) -> Double = "(element) => element.clientWidth"

///|
extern "js" fn initial_size_client_height(element : @rdom.Element) -> Double = "(element) => element.clientHeight"

///|
extern "js" fn initial_size_next_frame(callback : () -> Unit) -> Unit = "(callback) => requestAnimationFrame(callback)"
