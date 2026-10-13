// Source-derived ViewLines geometry tests for pinned `viewLines.ts` at
// checked-in source.

///|
fn geometry_view_lines(
  lines : Array[ViewLine],
  window : @view_layout.LineWindow,
  visible_range : @base_common.Range,
  layout : @view_layout.ViewLayout,
  fixture : ViewLineFixture,
  scheduler~ : @base_browser.RunOnceScheduler = RunOnceScheduler(200),
  lines_content~ : @rdom.Element = view_line_fixture_context(fixture),
) -> ViewLines {
  let configuration = ViewLinesConfiguration::ViewLinesConfiguration()
  let options_ref = Ref(configuration.view_line_options)
  let last_rendered_data = LastRenderedData::LastRenderedData()
  last_rendered_data.set_current_visible_range(visible_range)
  {
    dom_node: CachedDomNode(view_line_fixture_context(fixture)),
    lines_content: CachedDomNode(lines_content),
    text_range_resting_spot: view_line_fixture_end_node(fixture),
    window,
    lines,
    typical_halfwidth_character_width: configuration.typical_halfwidth_character_width,
    is_viewport_wrapping: configuration.is_viewport_wrapping,
    can_use_layer_hinting: configuration.can_use_layer_hinting,
    view_line_options: configuration.view_line_options,
    view_line_options_ref: options_ref,
    read_configuration: () => configuration,
    view_line_to_model_line: line_number => line_number,
    model_line_text_direction: _line_number => LTR,
    line_factory: () => ViewLine(options=options_ref.val),
    async_update_line_widths: scheduler,
    last_rendered_data,
    max_line_width: 0.0,
    last_layout: Some(layout),
    should_render: true,
    content_viewport_geometry_lease_count: 0,
    rendered_scroll_left: None,
    visible_content_width: None,
  }
}

///|
priv struct GeometryTimerTask {
  handle : Double
  delay_ms : Int32
  callback : () -> Unit
  mut active : Bool
}

///|
priv struct GeometryTimerSpy {
  mut next_handle : Int32
  tasks : Array[GeometryTimerTask]
  cleared : Array[Double]
}

///|
fn GeometryTimerSpy::GeometryTimerSpy() -> GeometryTimerSpy {
  { next_handle: 0, tasks: [], cleared: [], }
}

///|
fn GeometryTimerSpy::set_timeout(
  self : GeometryTimerSpy,
  callback : () -> Unit,
  delay_ms : Int32,
) -> Double {
  self.next_handle += 1
  let handle = self.next_handle.to_double()
  self.tasks.push({ handle, delay_ms, callback, active: true, })
  handle
}

///|
fn GeometryTimerSpy::clear_timeout(
  self : GeometryTimerSpy,
  handle : Double,
) -> Unit {
  self.cleared.push(handle)
  for task in self.tasks {
    if task.handle == handle {
      task.active = false
    }
  }
}

///|
fn GeometryTimerSpy::schedule_timeout(
  self : GeometryTimerSpy,
  callback : () -> Unit,
  delay_ms : Int32,
) -> @base_common.Disposable {
  let handle = self.set_timeout(callback, delay_ms)
  @base_common.Disposable::from(() => self.clear_timeout(handle))
}

///|
fn GeometryTimerSpy::fire_active(self : GeometryTimerSpy) -> Unit {
  for task in self.tasks {
    if task.active {
      task.active = false
      (task.callback)()
    }
  }
}

///|
extern "js" fn new_geometry_style_element() -> @rdom.Element =
  #| () => ({
  #|   style: {
  #|     values: Object.create(null),
  #|     setCount: 0,
  #|     removeCount: 0,
  #|     setProperty(name, value) {
  #|       this.values[name] = String(value);
  #|       this.setCount += 1;
  #|     },
  #|     removeProperty(name) {
  #|       delete this.values[name];
  #|       this.removeCount += 1;
  #|     },
  #|   },
  #| })

///|
extern "js" fn geometry_style_value(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => element.style.values[name] ?? ""

///|
extern "js" fn geometry_style_set_count(element : @rdom.Element) -> Int32 = "(element) => element.style.setCount"

///|
extern "js" fn geometry_style_remove_count(element : @rdom.Element) -> Int32 = "(element) => element.style.removeCount"

///|
test "LastRenderedData initializes and replaces the exact visible Range" {
  let data = LastRenderedData::LastRenderedData()
  assert_true(data.get_current_visible_range() == Range(1, 1, 1, 1))
  data.set_current_visible_range(Range(3, 2, 5, 7))
  assert_true(data.get_current_visible_range() == Range(3, 2, 5, 7))
}

///|
test "ViewLines content viewport geometry is leased cached and scrollbar-safe" {
  let fixture = new_view_line_fixture(10.0, 10.0)
  let lines_content = new_geometry_style_element()
  let layout = @view_layout.ViewLayout(line_height=20, line_count=1)
  let view_lines = geometry_view_lines(
    [],
    { start: 1, end: 1, },
    Range(1, 1, 1, 1),
    layout,
    fixture,
    lines_content~,
  )
  // Ordinary ViewZones retain the model scroll-plane contract until a
  // specialized consumer explicitly acquires it.
  view_lines.publish_content_viewport_geometry(40.0, 200.0)
  assert_eq(geometry_style_set_count(lines_content), 0)
  view_lines.should_render = false
  let first = view_lines.acquire_content_viewport_geometry()
  assert_true(view_lines.should_render)
  view_lines.should_render = false
  let second = view_lines.acquire_content_viewport_geometry()
  assert_false(view_lines.should_render)
  assert_eq(view_lines.content_viewport_geometry_lease_count, 2)
  view_lines.publish_content_viewport_geometry(40.0, 200.0)
  assert_eq(
    geometry_style_value(lines_content, rendered_scroll_left_css_variable),
    "40px",
  )
  assert_eq(
    geometry_style_value(lines_content, visible_content_width_css_variable),
    "186px",
  )
  assert_eq(geometry_style_set_count(lines_content), 2)
  // Replaying an identical render snapshot performs no redundant DOM writes;
  // changing only the horizontal position updates only its variable.
  view_lines.publish_content_viewport_geometry(40.0, 200.0)
  assert_eq(geometry_style_set_count(lines_content), 2)
  view_lines.publish_content_viewport_geometry(45.0, 200.0)
  assert_eq(geometry_style_set_count(lines_content), 3)
  // The width follows the current configured scrollbar size and clamps at
  // zero when the rail is wider than the viewport.
  let wider_scrollbar = {
    ..view_lines.view_line_options,
    vertical_scrollbar_size: 20.0,
  }
  view_lines.on_options_maybe_changed(wider_scrollbar) |> ignore
  view_lines.publish_content_viewport_geometry(45.0, 200.0)
  assert_eq(
    geometry_style_value(lines_content, visible_content_width_css_variable),
    "180px",
  )
  assert_eq(geometry_style_set_count(lines_content), 4)
  view_lines.publish_content_viewport_geometry(45.0, 5.0)
  assert_eq(
    geometry_style_value(lines_content, visible_content_width_css_variable),
    "0px",
  )
  assert_eq(geometry_style_set_count(lines_content), 5)
  // Only the last lease removes the inherited contract and resets both
  // caches. Disposable itself is idempotent.
  first.dispose()
  assert_eq(geometry_style_remove_count(lines_content), 0)
  second.dispose()
  assert_eq(view_lines.content_viewport_geometry_lease_count, 0)
  assert_eq(
    geometry_style_value(lines_content, rendered_scroll_left_css_variable),
    "",
  )
  assert_eq(
    geometry_style_value(lines_content, visible_content_width_css_variable),
    "",
  )
  assert_eq(geometry_style_remove_count(lines_content), 2)
  assert_true(view_lines.rendered_scroll_left is None)
  assert_true(view_lines.visible_content_width is None)
  second.dispose()
  assert_eq(geometry_style_remove_count(lines_content), 2)
  // ViewLines teardown also clears an outstanding lease; a later handle
  // disposal cannot underflow the refcount or perform duplicate DOM removal.
  let third = view_lines.acquire_content_viewport_geometry()
  view_lines.publish_content_viewport_geometry(5.0, 100.0)
  assert_eq(geometry_style_set_count(lines_content), 7)
  view_lines.dispose()
  assert_eq(view_lines.content_viewport_geometry_lease_count, 0)
  assert_eq(geometry_style_remove_count(lines_content), 4)
  third.dispose()
  assert_eq(geometry_style_remove_count(lines_content), 4)
}

///|
test "ViewLines configuration resets widths from exact event bits" {
  let fixture = new_view_line_fixture(10.0, 10.0)
  let layout = @view_layout.ViewLayout(line_height=20, line_count=1)
  let view_lines = geometry_view_lines(
    [],
    { start: 1, end: 1, },
    Range(1, 1, 1, 1),
    layout,
    fixture,
  )
  view_lines.max_line_width = 99.0
  assert_true(view_lines.on_configuration_changed(true, false))
  inspect(view_lines.max_line_width, content="0")
  view_lines.max_line_width = 99.0
  assert_true(view_lines.on_configuration_changed(false, true))
  inspect(view_lines.max_line_width, content="0")
  view_lines.max_line_width = 99.0
  assert_true(view_lines.on_configuration_changed(false, false))
  inspect(view_lines.max_line_width, content="99")
  view_lines.flush_retained_lines()
  inspect(view_lines.max_line_width, content="0")
  assert_true(view_lines.window == { start: 1, end: 1, })
}

///|
test "ViewLines raw multi-line query intersects rounds and adds only model newlines" {
  let first_fixture = new_view_line_fixture(30.0, 10.0)
  let second_fixture = new_view_line_fixture(20.0, 10.0)
  let first_input = geometry_line_input("ab")
  let second_input = geometry_line_input("cd")
  let first = mapped_fixture_line(
    first_input,
    first_fixture,
    first_input.line_content.length() + 1,
  )
  let second = mapped_fixture_line(
    second_input,
    second_fixture,
    second_input.line_content.length() + 1,
  )
  let layout = @view_layout.ViewLayout(line_height=20, line_count=2)
  let view_lines = geometry_view_lines(
    [first, second],
    { start: 1, end: 3, },
    Range(1, 1, 2, 3),
    layout,
    first_fixture,
  )
  guard view_lines.raw_lines_visible_ranges_for_range(Range(1, 1, 2, 2), true)
    is Some(ranges) else {
    fail("expected two line ranges")
  }
  inspect(ranges.length(), content="2")
  let first_range = ranges[0]
  inspect(first_range.0, content="1")
  inspect(first_range.1.length(), content="1")
  inspect(first_range.1[0].0, content="0")
  inspect(first_range.1[0].1, content="27")
  let second_range = ranges[1]
  inspect(second_range.0, content="2")
  inspect(second_range.1[0].0, content="0")
  inspect(second_range.1[0].1, content="10")

  guard view_lines.raw_lines_visible_ranges_for_range(Range(1, 1, 2, 2), false)
    is Some(without_newlines) else {
    fail("expected ranges without newline widths")
  }
  inspect(without_newlines[0].1[0].1, content="20")

  assert_true(
    view_lines.raw_lines_visible_ranges_for_range(Range(8, 1, 9, 1), false)
    is None,
  )
}

///|
test "ViewLines newline width skips wraps and shifts RTL left" {
  let wrapped_fixture = new_view_line_fixture(30.0, 10.0)
  let wrapped_input = geometry_line_input(
    "ab",
    continues_with_wrapped_line=true,
  )
  let wrapped_line = mapped_fixture_line(
    wrapped_input,
    wrapped_fixture,
    wrapped_input.line_content.length() + 1,
  )
  let tail_fixture = new_view_line_fixture(20.0, 10.0)
  let tail_input = geometry_line_input("cd")
  let tail = mapped_fixture_line(
    tail_input,
    tail_fixture,
    tail_input.line_content.length() + 1,
  )
  let layout = @view_layout.ViewLayout(line_height=20, line_count=2)
  let wrapped = geometry_view_lines(
    [wrapped_line, tail],
    { start: 1, end: 3, },
    Range(1, 1, 2, 3),
    layout,
    wrapped_fixture,
  )
  wrapped.install_geometry_readers(_view_line_number => 1, _model_line_number => {
    LTR
  })
  guard wrapped.raw_lines_visible_ranges_for_range(Range(1, 1, 2, 2), true)
    is Some(wrapped_ranges) else {
    fail("expected wrapped ranges")
  }
  inspect(wrapped_ranges[0].1[0].1, content="20")

  let rtl_fixture = new_view_line_fixture(30.0, 10.0)
  // Direction comes from the current model line, not the rendered view-line
  // input. Keep the latter LTR so the reader seam is independently proven.
  let rtl_input = geometry_line_input("ab")
  let rtl_line = mapped_fixture_line(
    rtl_input,
    rtl_fixture,
    rtl_input.line_content.length() + 1,
  )
  let rtl = geometry_view_lines(
    [rtl_line, tail],
    { start: 1, end: 3, },
    Range(1, 1, 2, 3),
    layout,
    rtl_fixture,
  )
  rtl.install_geometry_readers(view_line_number => view_line_number, _model_line_number => {
    RTL
  })
  guard rtl.raw_lines_visible_ranges_for_range(Range(1, 1, 2, 2), true)
    is Some(rtl_ranges) else {
    fail("expected RTL ranges")
  }
  inspect(rtl_ranges[0].1[0].0, content="-7")
  inspect(rtl_ranges[0].1[0].1, content="27")
}

///|
test "ViewLines converter progression covers first middle final and partial windows" {
  let first_fixture = new_view_line_fixture(20.0, 10.0)
  let middle_fixture = new_view_line_fixture(20.0, 10.0)
  let final_fixture = new_view_line_fixture(20.0, 10.0)
  let input = geometry_line_input("ab")
  let first = mapped_fixture_line(input, first_fixture, 3)
  let middle = mapped_fixture_line(input, middle_fixture, 3)
  let last_line = mapped_fixture_line(input, final_fixture, 3)
  let layout = @view_layout.ViewLayout(line_height=20, line_count=3)
  let view_lines = geometry_view_lines(
    [first, middle, last_line],
    { start: 1, end: 4, },
    Range(1, 1, 3, 3),
    layout,
    first_fixture,
  )
  let converter_calls : Array[Int32] = []
  let direction_calls : Array[Int32] = []
  view_lines.install_geometry_readers(
    view_line_number => {
      converter_calls.push(view_line_number)
      if view_line_number <= 2 {
        10
      } else {
        11
      }
    },
    model_line_number => {
      direction_calls.push(model_line_number)
      if model_line_number == 10 {
        RTL
      } else {
        LTR
      }
    },
  )

  guard view_lines.raw_lines_visible_ranges_for_range(Range(1, 2, 3, 2), false)
    is Some(without_newlines) else {
    fail("expected first/middle/final line ranges")
  }
  assert_true(converter_calls.is_empty())
  assert_true(direction_calls.is_empty())
  assert_true(without_newlines.map(range => range.0) == [1, 2, 3])

  guard view_lines.raw_lines_visible_ranges_for_range(Range(1, 2, 3, 2), true)
    is Some(with_newlines) else {
    fail("expected model-aware newline ranges")
  }
  assert_true(converter_calls == [1, 2, 3])
  // View lines 1 and 2 share model line 10. Only the 2 -> 3 transition asks
  // that current model line's direction and appends a newline width.
  assert_true(direction_calls == [10])
  inspect(with_newlines[0].1[0].1, content="10")
  inspect(with_newlines[1].1[0].0, content="-7")
  inspect(with_newlines[1].1[0].1, content="27")
  inspect(with_newlines[2].1[0].1, content="10")

  let partial = geometry_view_lines(
    [middle, last_line],
    { start: 2, end: 4, },
    Range(1, 1, 3, 3),
    layout,
    middle_fixture,
  )
  guard partial.raw_lines_visible_ranges_for_range(Range(1, 1, 3, 2), false)
    is Some(partial_ranges) else {
    fail("expected partial-window overlap")
  }
  assert_true(partial_ranges.map(range => range.0) == [2, 3])
  assert_true(
    partial.raw_lines_visible_ranges_for_range(Range(1, 1, 1, 2), false) is None,
  )
}

///|
test "ViewLines range integerization keeps JavaScript negative-half rounding" {
  inspect(js_math_round(-7.5).to_int(), content="-7")
  inspect(js_math_round(-7.51).to_int(), content="-8")
  inspect(js_math_round(7.5).to_int(), content="8")
}

///|
test "ViewLines width sweep preserves one ceil monotonic and full-document reset" {
  let first_fixture = new_view_line_fixture(42.2, 10.0)
  let second_fixture = new_view_line_fixture(55.1, 10.0)
  let first_input = geometry_line_input("a")
  let second_input = geometry_line_input("b")
  let first = mapped_fixture_line(first_input, first_fixture, 2)
  let second = mapped_fixture_line(second_input, second_fixture, 2)
  let layout = @view_layout.ViewLayout(line_height=20, line_count=2)
  let view_lines = geometry_view_lines(
    [first, second],
    { start: 1, end: 3, },
    Range(1, 1, 2, 2),
    layout,
    first_fixture,
  )
  assert_false(view_lines.update_line_widths_fast())
  inspect(view_lines.max_line_width, content="1")
  view_lines.update_line_widths_slow()
  inspect(view_lines.max_line_width, content="56")

  view_line_fixture_set_width(first_fixture, 10.0)
  view_line_fixture_set_width(second_fixture, 20.0)
  let first_narrow = mapped_fixture_line(first_input, first_fixture, 2)
  let second_narrow = mapped_fixture_line(second_input, second_fixture, 2)
  view_lines.window = { start: 1, end: 2, }
  view_lines.lines = [first_narrow]
  view_lines.update_line_widths_slow()
  inspect(view_lines.max_line_width, content="56")

  view_lines.window = { start: 1, end: 3, }
  view_lines.lines = [first_narrow, second_narrow]
  view_lines.update_line_widths_slow()
  inspect(view_lines.max_line_width, content="20")
  view_lines.ensure_max_line_width(20.01)
  inspect(view_lines.max_line_width, content="21")
}

///|
test "ViewLines scheduler debounces fires the latest callback and disposes pending work" {
  let spy = GeometryTimerSpy::GeometryTimerSpy()
  let scheduler = @base_browser.RunOnceScheduler::new_with_timer(200, (
    callback,
    delay_ms,
  ) => spy.schedule_timeout(callback, delay_ms))
  let fired : Array[Int32] = []
  scheduler.schedule(() => fired.push(1))
  guard scheduler.handle is Some(_) else {
    fail("expected first scheduler handle")
  }
  let first_handle = spy.tasks[0].handle
  scheduler.schedule(() => fired.push(2))
  guard scheduler.handle is Some(_) else {
    fail("expected replacement scheduler handle")
  }
  let second_handle = spy.tasks[1].handle
  assert_false(first_handle == second_handle)
  assert_true(spy.tasks.map(task => task.delay_ms) == [200, 200])
  assert_true(spy.cleared == [first_handle])
  spy.fire_active()
  assert_true(fired == [2])
  assert_false(scheduler.is_scheduled())

  scheduler.schedule(() => fired.push(3))
  guard scheduler.handle is Some(_) else {
    fail("expected disposable scheduler handle")
  }
  let disposed_handle = spy.tasks[2].handle
  scheduler.dispose()
  assert_true(spy.cleared == [first_handle, disposed_handle])
  spy.fire_active()
  assert_true(fired == [2])
}

///|
test "ViewLines 200ms scheduler guards and cancel-before-slow ordering" {
  let spy = GeometryTimerSpy::GeometryTimerSpy()
  let scheduler = @base_browser.RunOnceScheduler::new_with_timer(200, (
    callback,
    delay_ms,
  ) => spy.schedule_timeout(callback, delay_ms))
  let fixture = new_view_line_fixture(12.0, 10.0)
  let input = geometry_line_input("a")
  let line = mapped_fixture_line(input, fixture, 2)
  let layout = @view_layout.ViewLayout(line_height=20, line_count=1)
  let view_lines = geometry_view_lines(
    [line],
    { start: 1, end: 2, },
    Range(1, 1, 1, 2),
    layout,
    fixture,
    scheduler~,
  )
  inspect(view_lines.async_update_line_widths.delay_ms, content="200")
  view_lines.async_update_line_widths.schedule(() => ())
  assert_true(view_lines.async_update_line_widths.is_scheduled())
  let untouched = DomReadingContext::DomReadingContext(
    view_line_fixture_context(fixture),
    view_line_fixture_end_node(fixture),
  )
  view_lines.update_line_widths_slow_if_dom_did_layout(untouched)
  assert_true(view_lines.async_update_line_widths.is_scheduled())
  untouched.mark_did_dom_layout()
  view_lines.update_line_widths_slow_if_dom_did_layout(untouched)
  assert_false(view_lines.async_update_line_widths.is_scheduled())
  inspect(spy.cleared.length(), content="1")
  assert_true(line.get_width_is_fast())
  view_lines.async_update_line_widths.schedule(() => ())
  assert_true(view_lines.async_update_line_widths.is_scheduled())
  view_lines.dispose()
  assert_false(view_lines.async_update_line_widths.is_scheduled())
  inspect(spy.cleared.length(), content="2")
}
