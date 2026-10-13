// Reference coverage for the touch-scroll behavior and inertia cluster in
// `vscode/src/vs/base/browser/touch.ts` and
// `vscode/src/vs/editor/browser/controller/pointerHandler.ts`, pinned at
// b18492a288de038fbc7643aae6de8247029d11bd.

///|
priv struct TouchScrollTestHarness {
  mut now : Double
  mut next_handle : Int32
  frames : Map[Int32, () -> Unit]
  translations : Array[(Double, Double)]
  mut cancel_count : Int32
}

///|
fn TouchScrollTestHarness::TouchScrollTestHarness() -> TouchScrollTestHarness {
  {
    now: 0.0,
    next_handle: 1,
    frames: Map([]),
    translations: [],
    cancel_count: 0,
  }
}

///|
fn TouchScrollTestHarness::runtime(
  self : TouchScrollTestHarness,
) -> TouchScrollRuntime {
  {
    now: () => self.now,
    schedule_at_next_animation_frame: callback => {
      let handle = self.next_handle
      self.next_handle += 1
      self.frames[handle] = callback
      @base_common.Disposable::from(() => {
        if self.frames.get(handle) is Some(_) {
          self.frames.remove(handle)
          self.cancel_count += 1
        }
      })
    },
  }
}

///|
fn TouchScrollTestHarness::gesture(
  self : TouchScrollTestHarness,
) -> TouchScrollGesture {
  TouchScrollGesture(self.runtime(), (x, y) => self.translations.push((x, y)))
}

///|
fn TouchScrollTestHarness::run_next_frame(
  self : TouchScrollTestHarness,
  now : Double,
) -> Unit {
  let pending = self.frames.to_array()
  guard pending.length() == 1 else {
    abort("expected exactly one pending animation frame")
  }
  let (handle, callback) = pending[0]
  self.frames.remove(handle)
  self.now = now
  callback()
}

///|
test "pointerHandler touch change preserves translation signs and ViewLayout events" {
  let layout = @view_layout.ViewLayout(line_height=20, line_count=200)
  layout.set_viewport_size(width=100.0, height=100.0) |> ignore
  layout.set_max_line_width(400.0) |> ignore
  let changes : Array[@view_layout.ScrollChange] = []
  let subscription = layout.on_did_scroll(change => changes.push(change))
  let gesture = TouchScrollGesture::TouchScrollGesture(
    {
      now: () => 0.0,
      schedule_at_next_animation_frame: _ => {
        @base_common.Disposable::from(() => ())
      },
    },
    (translation_x, translation_y) => {
      layout.delta_scroll_now(-translation_x, -translation_y)
    },
  )
  gesture.begin_touch_event()
  gesture.start_touch(1, 100.0, 100.0, 0.0)
  assert_true(gesture.move_touch(1, 80.0, 60.0, 10.0))
  assert_eq(layout.position().scroll_left, 20.0)
  assert_eq(layout.position().scroll_top, 40.0)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].delta_left, 20.0)
  assert_eq(changes[0].delta_top, 40.0)
  subscription.dispose()
  gesture.dispose()
  layout.dispose()
}

///|
test "touch.ts rolling window and friction retain source arithmetic" {
  let harness = TouchScrollTestHarness::TouchScrollTestHarness()
  let gesture = harness.gesture()
  gesture.begin_touch_event()
  gesture.start_touch(7, 100.0, 100.0, 0.0)
  assert_true(gesture.move_touch(7, 90.0, 80.0, 10.0))
  assert_true(gesture.move_touch(7, 80.0, 60.0, 20.0))
  assert_true(gesture.move_touch(7, 70.0, 40.0, 30.0))
  assert_true(gesture.move_touch(7, 60.0, 20.0, 40.0))
  guard gesture.active_touches.get(7) is Some(data) else {
    fail("expected active touch data")
  }
  assert_eq(data.rolling_timestamps.length(), 4)
  assert_eq(data.rolling_timestamps[0], 10.0)
  assert_eq(data.rolling_page_x[0], 90.0)
  assert_eq(data.rolling_page_y[0], 80.0)
  assert_true(gesture.end_touch(7, 1, 40.0))
  assert_eq(harness.frames.length(), 1)
  harness.run_next_frame(50.0)
  // Rolling samples yield 1px/ms x and 2px/ms y. Friction is applied before
  // translation: (1 - .005*10)*10 and (2 - .005*10)*10.
  let (translation_x, translation_y) = harness.translations.last().unwrap()
  assert_eq(translation_x, -9.5)
  assert_eq(translation_y, -19.5)
  assert_eq(harness.frames.length(), 1)
  gesture.dispose()
  assert_eq(harness.frames.length(), 0)
  assert_eq(harness.cancel_count, 1)
}

///|
test "touch inertia exclusions and cancellation close every gesture lifetime" {
  let harness = TouchScrollTestHarness::TouchScrollTestHarness()
  let gesture = harness.gesture()

  // Sub-30px movement scrolls during the gesture but does not coast.
  gesture.begin_touch_event()
  gesture.start_touch(1, 0.0, 0.0, 0.0)
  assert_true(gesture.move_touch(1, 29.0, 29.0, 10.0))
  assert_true(gesture.end_touch(1, 1, 10.0))
  assert_eq(harness.frames.length(), 0)

  // A zero-duration velocity window cannot start a finite inertia operation.
  gesture.begin_touch_event()
  gesture.start_touch(2, 0.0, 0.0, 20.0)
  assert_true(gesture.move_touch(2, 40.0, 0.0, 20.0))
  assert_true(gesture.end_touch(2, 1, 20.0))
  assert_eq(harness.frames.length(), 0)

  // Both touches ending in the same multi-touch event observe count=2.
  gesture.begin_touch_event()
  gesture.start_touch(3, 0.0, 0.0, 30.0)
  gesture.start_touch(4, 0.0, 0.0, 30.0)
  assert_true(gesture.move_touch(3, 40.0, 0.0, 40.0))
  assert_true(gesture.move_touch(4, 0.0, 40.0, 40.0))
  assert_true(gesture.end_touch(3, 2, 40.0))
  assert_true(gesture.end_touch(4, 2, 40.0))
  assert_eq(harness.frames.length(), 0)

  // A fresh touch cancels pending inertia.
  gesture.begin_touch_event()
  gesture.start_touch(5, 0.0, 0.0, 50.0)
  assert_true(gesture.move_touch(5, 40.0, 0.0, 60.0))
  assert_true(gesture.end_touch(5, 1, 60.0))
  assert_eq(harness.frames.length(), 1)
  gesture.begin_touch_event()
  assert_eq(harness.frames.length(), 0)
  assert_eq(harness.cancel_count, 1)

  // The touchcancel path clears active identifiers and pending inertia.
  gesture.start_touch(6, 1.0, 1.0, 70.0)
  assert_true(gesture.move_touch(6, 41.0, 1.0, 80.0))
  assert_true(gesture.end_touch(6, 1, 80.0))
  assert_eq(harness.frames.length(), 1)
  gesture.cancel_touches()
  assert_eq(gesture.active_touches.length(), 0)
  assert_eq(harness.frames.length(), 0)
  assert_eq(harness.cancel_count, 2)

  // Per-View teardown cancels the final pending inertia frame and is
  // idempotent.
  gesture.begin_touch_event()
  gesture.start_touch(7, 0.0, 0.0, 90.0)
  assert_true(gesture.move_touch(7, 40.0, 0.0, 100.0))
  assert_true(gesture.end_touch(7, 1, 100.0))
  assert_eq(harness.frames.length(), 1)
  gesture.dispose()
  assert_eq(harness.frames.length(), 0)
  assert_eq(harness.cancel_count, 3)
  gesture.dispose()
  assert_true(gesture.disposed)
}

///|
extern "js" fn enable_scrollbar_input_touch_support() -> Unit =
  #| () => { window.ontouchstart = null; }

///|
extern "js" fn dispatch_scrollbar_input_touch(
  element : @rdom.Element,
  event_type : String,
  identifier : Int32,
  page_x : Double,
  page_y : Double,
) -> Int32 =
  #| (element, eventType, identifier, pageX, pageY) => {
  #|   const point = { identifier, pageX, pageY, target: element };
  #|   const active = eventType === "touchend" || eventType === "touchcancel"
  #|     ? []
  #|     : [point];
  #|   const changed = [point];
  #|   active.item = index => active[index];
  #|   changed.item = index => changed[index];
  #|   const event = new Event(eventType, { bubbles: true, cancelable: true });
  #|   Object.defineProperties(event, {
  #|     targetTouches: { value: active },
  #|     changedTouches: { value: changed },
  #|   });
  #|   element.dispatchEvent(event);
  #|   return (event.defaultPrevented ? 1 : 0) | (event.cancelBubble ? 2 : 0);
  #| }

///|
fn touch_input_test_handler(
  lines_content : @rdom.Element,
  editor_scrollable : @scrollbar.ScrollableElementDom,
  layout : @view_layout.ViewLayout,
) -> MouseHandler {
  let root = scrollbar_input_test_element()
  MouseHandler({
    view_dom_node: root,
    lines_content_dom_node: lines_content,
    view_lines_dom_node: scrollbar_input_test_element(),
    focus_text_area: () => (),
    get_last_render_data: () => abort("unused touch test helper"),
    render_now: () => (),
    should_suppress_mouse_down_on_view_zone: _ => false,
    get_position_from_dom_info: (_element, _offset) => None,
    visible_range_for_position: (_line, _column) => None,
    get_line_width: _ => 0.0,
    view_model: () => None,
    get_layout_info: () => abort("unused touch test helper"),
    get_font_info: () => abort("unused touch test helper"),
    get_current_selection: () => None,
    dispatch_mouse: _ => (),
    before_mouse_down_selection: (_event, _target) => false,
    emit_mouse_down: (_event, _target) => (),
    emit_mouse_up: (_event, _target) => (),
    emit_mouse_move: (_event, _target) => (),
    emit_context_menu: (_event, _target) => (),
    emit_mouse_drag: (_event, _target) => (),
    emit_mouse_leave: _ => (),
    overflow_guard: scrollbar_input_test_element(),
    editor_scrollable,
    hover_scrollable: () => None,
    view_layout: () => Some(layout),
    schedule_render: () => (),
  })
}

///|
test "touch DOM listeners consume boundary moves, reveal, and dispose" {
  install_scrollbar_input_test_browser()
  enable_scrollbar_input_touch_support()
  let lines_content = scrollbar_input_test_element()
  let editor_scrollable = @scrollbar.ScrollableElementDom(
    "lines-content",
    content=lines_content,
  )
  editor_scrollable.update_from_model(
    { width: 100.0, scroll_width: 400.0, height: 100.0, scroll_height: 4000.0, },
    { scroll_left: 0.0, scroll_top: 0.0, },
  )
  let layout = @view_layout.ViewLayout(line_height=20, line_count=200)
  layout.set_viewport_size(width=100.0, height=100.0) |> ignore
  layout.set_max_line_width(400.0) |> ignore
  let handler = touch_input_test_handler(
    lines_content, editor_scrollable, layout,
  )
  assert_eq(scrollbar_input_test_listener_count(lines_content, "touchstart"), 1)
  assert_eq(scrollbar_input_test_listener_count(lines_content, "touchmove"), 1)

  dispatch_scrollbar_input_touch(lines_content, "touchstart", 1, 50.0, 50.0)
  |> ignore
  // Pulling down at scrollTop=0 remains clamped, but the editor still owns
  // the gesture so the surrounding page cannot take over.
  assert_eq(
    dispatch_scrollbar_input_touch(lines_content, "touchmove", 1, 50.0, 80.0),
    3,
  )
  assert_eq(layout.position().scroll_top, 0.0)
  // Reversing upward uses the previous touch sample and reveals the custom
  // scrollbar only after the actual ViewLayout position changes.
  assert_eq(
    dispatch_scrollbar_input_touch(lines_content, "touchmove", 1, 30.0, 0.0),
    3,
  )
  assert_eq(layout.position().scroll_left, 20.0)
  assert_eq(layout.position().scroll_top, 80.0)
  let scrollbar_class = editor_scrollable.track(true).get_attribute("class")
  assert_true(
    scrollbar_class is Some(class_name) && class_name.contains("visible"),
  )
  dispatch_scrollbar_input_touch(lines_content, "touchcancel", 1, 30.0, 0.0)
  |> ignore
  handler.dispose()
  handler.dispose()
  assert_eq(scrollbar_input_test_listener_count(lines_content, "touchstart"), 0)
  assert_eq(scrollbar_input_test_listener_count(lines_content, "touchmove"), 0)
  layout.dispose()
}
