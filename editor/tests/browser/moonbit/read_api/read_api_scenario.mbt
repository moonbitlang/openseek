// Browser test for the DOM-measured read-API trio — the pieces that can only be
// validated with real client-rect measurement: `get_offset_for_column`,
// `get_width_of_line`, and `get_scrolled_visible_position`. It attaches a no-wrap
// viewer over a tall document of long lines and asserts the measured offsets are
// monotonic, the line width bounds them, off-screen lines report `-1`, and the
// scrolled visible position tracks scrollTop/scrollLeft (per project history,
// view-axis pixel math is caught only by the browser suite).

///|
pub fn run_read_api_test() -> Unit {
  let ctx = @support.BrowserTestContext("read_api")
  let done = Ref(false)
  let uri = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/read-api.txt",
  )
  let model = @model.TextModel(
    uri,
    "read-api.txt",
    "plaintext",
    1,
    "read-api-rev-1",
    read_api_source_text(),
  )
  match mount_host() {
    Some(host) => {
      let viewer = @viewer.Viewer::create(
        host,
        options=ViewerOptions(
          soft_wrap=false,
          placeholder="Loading read-api fixture...",
        ),
      )
      viewer.set_model(Some(model))
      viewer.handle_initialized()
      // Wait until the first line has rendered and been measured, then run the
      // measurement assertions synchronously (every getter flushes internally).
      @support.set_timeout(() => poll_read_api(ctx, viewer, done, 100), 100)
    }
    None => {
      ctx.fail("missing #app mount point")
      ctx.finish()
    }
  }
}

///|
fn poll_read_api(
  ctx : @support.BrowserTestContext,
  viewer : @viewer.Viewer,
  done : Ref[Bool],
  remaining : Int32,
) -> Unit {
  if done.val {
    return
  }
  // Line 1 is measurable once it has rendered (an unrendered line returns -1).
  if viewer.get_offset_for_column(1, 1) >= 0.0 {
    assert_read_api(ctx, viewer)
    done.val = true
    ctx.finish()
  } else if remaining <= 0 {
    ctx.fail("timed out waiting for the first line to render and measure")
    done.val = true
    ctx.finish()
  } else {
    @support.set_timeout(
      () => poll_read_api(ctx, viewer, done, remaining - 1),
      30,
    )
  }
}

///|
fn assert_read_api(
  ctx : @support.BrowserTestContext,
  viewer : @viewer.Viewer,
) -> Unit {
  // (1) getOffsetForColumn: column 1 sits at the line start (~0), and offsets
  // grow with the column on the same line.
  let o1 = viewer.get_offset_for_column(1, 1)
  let o5 = viewer.get_offset_for_column(1, 5)
  let o9 = viewer.get_offset_for_column(1, 9)
  ctx.assert_true(
    o1 < 1.0,
    "offset at column 1 is not at the line start (\{o1})",
  )
  ctx.assert_true(o5 > o1, "offset did not grow from column 1 to 5")
  ctx.assert_true(o9 > o5, "offset did not grow from column 5 to 9")

  // (2) getWidthOfLine bounds every interior caret offset.
  let width = viewer.get_width_of_line(1)
  ctx.assert_true(width >= o9, "line width (\{width}) is below column-9 offset")

  // (3) getScrolledVisiblePosition at the top: top 0, the uniform line height,
  // and left == the content-left gutter (offset 0 + gutter - scrollLeft 0).
  let layout = viewer.get_layout_info()
  let svp1 = viewer.get_scrolled_visible_position(Position(1, 1)).unwrap()
  ctx.assert_true(
    svp1.top == 0.0,
    "scrolled top at line 1 is not 0 (\{svp1.top})",
  )
  ctx.assert_true(
    svp1.height == 18.0,
    "scrolled height is not the line height (\{svp1.height})",
  )
  ctx.assert_true(
    (svp1.left - layout.content_left).abs() < 1.0,
    "scrolled left (\{svp1.left}) is not the content-left gutter (\{layout.content_left})",
  )
  let svp2 = viewer.get_scrolled_visible_position(Position(2, 1)).unwrap()
  ctx.assert_true(
    svp2.top == 18.0,
    "scrolled top at line 2 is not one line down (\{svp2.top})",
  )

  // (4) Off-screen lines are not rendered → -1, mirroring Monaco's
  // visibleRangeForPosition → null.
  ctx.assert_true(
    viewer.get_offset_for_column(55, 1) == -1.0,
    "off-screen line offset is not -1",
  )
  ctx.assert_true(
    viewer.get_width_of_line(55) == -1.0,
    "off-screen line width is not -1",
  )

  // (5) Horizontal scroll shifts the scrolled left by exactly the scroll delta;
  // the relative-to-line offset itself is scroll-independent.
  let left_before = viewer
    .get_scrolled_visible_position(Position(1, 5))
    .unwrap().left
  viewer.set_scroll_position(scroll_top=0.0, scroll_left=20.0)
  let left_after = viewer.get_scrolled_visible_position(Position(1, 5)).unwrap().left
  ctx.assert_true(
    (left_before - left_after - 20.0).abs() < 0.1,
    "horizontal scroll did not shift the scrolled left by 20 (\{left_before} -> \{left_after})",
  )

  // (6) Vertical scroll subtracts scrollTop: line 3 (offset 36) lands at top 0
  // after scrolling down two lines.
  viewer.set_scroll_position(scroll_top=36.0, scroll_left=0.0)
  let svp3 = viewer.get_scrolled_visible_position(Position(3, 1)).unwrap()
  ctx.assert_true(
    svp3.top == 0.0,
    "vertical scroll did not subtract scrollTop (\{svp3.top})",
  )
  ctx.metric_number("offsetColumn1", o1)
  ctx.metric_number("offsetColumn9", o9)
  ctx.metric_number("lineWidth", width)
  ctx.metric_number("contentLeft", layout.content_left)
}

///|
fn mount_host() -> @rdom.Element? {
  let document = @rdom.document()
  match document.query_selector("#app").to_option() {
    Some(app) => {
      let shell = document.create_element("main")
      shell.set_attribute("class", "editor-shell")
      shell.set_attribute("data-theme", "dark")
      shell.set_attribute("style", "height:100vh;display:block;")
      let host = document.create_element("div")
      host.set_attribute("class", "viewer-host")
      // Narrow + short so far lines are off-screen and lines overflow horizontally.
      host.set_attribute("style", "height:120px;width:240px;")
      shell.append_child(host.as_node())
      app.append_child(shell.as_node())
      Some(host)
    }
    None => None
  }
}

///|
/// 60 lines, each long enough that the line overflows the viewport and the late
/// lines fall outside the rendered window.
fn read_api_source_text() -> String {
  let out = StringBuilder()
  for i in 0..<60 {
    if i > 0 {
      out.write_char('\n')
    }
    out <+ "line\{i}"
    for _ in 0..<100 {
      out.write_char('x')
    }
  }
  out.to_string()
}
