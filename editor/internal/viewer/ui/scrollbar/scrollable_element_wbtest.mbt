///|
/// `_onMouseWheel` delta parity: a pixel-mode trackpad delta of +2.37px
/// normalizes to -2.37/40 wheel units, scales by `SCROLL_WHEEL_SENSITIVITY`
/// to -2.9625, and floors away from zero to a 3px scroll (Monaco scrolls
/// 1.25x the raw pixel delta, never less than a whole pixel).
test "wheel deltas scale by 50/40 and round away from zero" {
  let (delta_left, delta_top) = mouse_wheel_scroll_deltas({
    delta_x: 0.0,
    delta_y: -2.37 / 40.0,
  })
  assert_eq(delta_left, 0.0)
  assert_eq(delta_top, 3.0)
  // Scrolling up mirrors: raw -3px -> +0.075 units -> ceil(3.75) -> -4px.
  let (_, delta_top) = mouse_wheel_scroll_deltas({
    delta_x: 0.0,
    delta_y: 3.0 / 40.0,
  })
  assert_eq(delta_top, -4.0)
  // "otherwise low speed scrolling will never scroll": 0.2px still moves 1px.
  let (_, delta_top) = mouse_wheel_scroll_deltas({
    delta_x: 0.0,
    delta_y: -0.2 / 40.0,
  })
  assert_eq(delta_top, 1.0)
}

///|
/// `scrollPredominantAxis` (default true, matching `resolveOptions` and the
/// editor's scrollbar options): the minor axis is dropped so vertical
/// trackpad scrolling never drifts sideways; ties go to vertical.
test "predominant axis drops the minor delta" {
  let (delta_left, delta_top) = mouse_wheel_scroll_deltas({
    delta_x: -0.3 / 40.0,
    delta_y: -6.0 / 40.0,
  })
  assert_eq(delta_left, 0.0)
  assert_eq(delta_top, 8.0)
  let (delta_left, delta_top) = mouse_wheel_scroll_deltas({
    delta_x: -6.0 / 40.0,
    delta_y: -0.3 / 40.0,
  })
  assert_eq(delta_left, 8.0)
  assert_eq(delta_top, 0.0)
  let (delta_left, delta_top) = mouse_wheel_scroll_deltas(
    { delta_x: -0.3 / 40.0, delta_y: -6.0 / 40.0, },
    scroll_predominant_axis=false,
  )
  assert_eq(delta_left, 1.0)
  assert_eq(delta_top, 8.0)
}

///|
/// The alt-key `fastScrollSensitivity` branch (default 5).
test "alt key applies fast scroll sensitivity" {
  let (_, delta_top) = mouse_wheel_scroll_deltas(
    { delta_x: 0.0, delta_y: -8.0 / 40.0, },
    alt_key=true,
  )
  assert_eq(delta_top, 50.0)
}

///|
test "numberAsPixels adds px to numbers and preserves strings" {
  assert_eq(number_as_pixels(Pixels(12.5)), "12.5px")
  assert_eq(number_as_pixels(Raw("calc(100% - 10px)")), "calc(100% - 10px)")
}

///|
extern "js" fn install_scrollable_timeout_test_browser() -> Unit =
  #| () => {
  #|   class TestElement extends EventTarget {
  #|     constructor(tag = "div") {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.attributes = new Map();
  #|       this.childNodes = [];
  #|       this.children = this.childNodes;
  #|       this.parentNode = null;
  #|       this.scrollTop = 0;
  #|       this.scrollLeft = 0;
  #|       this.scrollWidth = 1000;
  #|       this.scrollHeight = 1000;
  #|       this.rectWidth = 100;
  #|       this.rectHeight = 100;
  #|     }
  #|     setAttribute(name, value) { this.attributes.set(name, String(value)); }
  #|     getAttribute(name) { return this.attributes.get(name) ?? ""; }
  #|     removeAttribute(name) { this.attributes.delete(name); }
  #|     appendChild(child) {
  #|       this.childNodes.push(child);
  #|       child.parentNode = this;
  #|       return child;
  #|     }
  #|     removeChild(child) {
  #|       this.childNodes = this.childNodes.filter((item) => item !== child);
  #|       this.children = this.childNodes;
  #|       child.parentNode = null;
  #|       return child;
  #|     }
  #|     getBoundingClientRect() {
  #|       return {
  #|         x: 0, y: 0, left: 0, top: 0,
  #|         right: this.rectWidth, bottom: this.rectHeight,
  #|         width: this.rectWidth, height: this.rectHeight,
  #|       };
  #|     }
  #|   }
  #|   const ownerDocument = new EventTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.createElement = (tag) => new TestElement(tag);
  #|   globalThis.document = ownerDocument;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__scrollableOriginalSetTimeout = globalThis.setTimeout;
  #|   globalThis.__scrollableOriginalClearTimeout = globalThis.clearTimeout;
  #|   globalThis.__scrollableTimerNextId = 1;
  #|   globalThis.__scrollableTimerActive = new Map();
  #|   globalThis.__scrollableTimerHistory = [];
  #|   globalThis.__scrollableTimerClears = 0;
  #|   globalThis.setTimeout = (callback, _ms) => {
  #|     const id = globalThis.__scrollableTimerNextId++;
  #|     globalThis.__scrollableTimerActive.set(id, callback);
  #|     globalThis.__scrollableTimerHistory.push(callback);
  #|     return id;
  #|   };
  #|   globalThis.clearTimeout = (id) => {
  #|     globalThis.__scrollableTimerClears += 1;
  #|     globalThis.__scrollableTimerActive.delete(id);
  #|   };
  #| }

///|
extern "js" fn restore_scrollable_timeout_test_browser() -> Unit =
  #| () => {
  #|   globalThis.setTimeout = globalThis.__scrollableOriginalSetTimeout;
  #|   globalThis.clearTimeout = globalThis.__scrollableOriginalClearTimeout;
  #| }

///|
extern "js" fn scrollable_timeout_test_active_count() -> Int32 =
  #| () => globalThis.__scrollableTimerActive.size

///|
extern "js" fn scrollable_timeout_test_schedule_count() -> Int32 =
  #| () => globalThis.__scrollableTimerHistory.length

///|
extern "js" fn scrollable_timeout_test_clear_count() -> Int32 =
  #| () => globalThis.__scrollableTimerClears

///|
extern "js" fn scrollable_timeout_test_run_history() -> Unit =
  #| () => {
  #|   for (const callback of globalThis.__scrollableTimerHistory) callback();
  #| }

///|
extern "js" fn scrollable_timeout_test_run_pending() -> Unit =
  #| () => {
  #|   const pending = Array.from(globalThis.__scrollableTimerActive.entries());
  #|   globalThis.__scrollableTimerActive.clear();
  #|   for (const [_id, callback] of pending) callback();
  #| }

///|
fn prepare_scrollable_timeout_test(scrollable : ScrollableElementDom) -> Unit {
  scrollable.update_from_model(
    {
      width: 100.0,
      scroll_width: 1000.0,
      height: 100.0,
      scroll_height: 1000.0,
    },
    { scroll_left: 0.0, scroll_top: 0.0, },
  )
}

///|
test "500ms hide timeout is cancellable and inert after disposal" {
  install_scrollable_timeout_test_browser()
  let scrollable = ScrollableElementDom("content")
  prepare_scrollable_timeout_test(scrollable)

  scrollable.reveal_for_scroll()
  assert_true(scrollable.hide_timeout is Some(_))
  assert_eq(scrollable_timeout_test_schedule_count(), 1)
  assert_eq(scrollable_timeout_test_active_count(), 1)
  assert_eq(
    scrollable.vertical_bar.get_attribute("class"),
    Some("visible scrollbar vertical"),
  )

  // A replacement schedule cancels the old browser handle rather than only
  // suppressing it through the generation number.
  scrollable.reveal_for_scroll()
  assert_eq(scrollable_timeout_test_schedule_count(), 2)
  assert_eq(scrollable_timeout_test_clear_count(), 1)
  assert_eq(scrollable_timeout_test_active_count(), 1)

  let visible_class = scrollable.vertical_bar.get_attribute("class")
  scrollable.dispose()
  scrollable.dispose()
  assert_true(scrollable.disposed)
  assert_true(scrollable.hide_timeout is None)
  assert_eq(scrollable_timeout_test_clear_count(), 2)
  assert_eq(scrollable_timeout_test_active_count(), 0)
  // Even a hostile timer seam invoking cancelled callbacks cannot mutate the
  // detached scrollbar because disposal closes the generation guard.
  scrollable_timeout_test_run_history()
  assert_eq(scrollable.vertical_bar.get_attribute("class"), visible_class)
  scrollable.reveal_for_scroll()
  scrollable.mouse_entered()
  scrollable.mouse_left()
  scrollable.drag_started()
  scrollable.drag_ended()
  assert_eq(scrollable_timeout_test_schedule_count(), 2)
  assert_eq(scrollable_timeout_test_active_count(), 0)

  // Mouse-over and active-drag state disable hide scheduling. The ordinary
  // idle path still performs the 500ms fade when its current callback runs.
  let guarded = ScrollableElementDom("guarded")
  prepare_scrollable_timeout_test(guarded)
  assert_false(guarded.is_dragging)
  guarded.mouse_entered()
  guarded.reveal_for_scroll()
  assert_eq(scrollable_timeout_test_active_count(), 0)
  guarded.mouse_left()
  guarded.drag_started()
  assert_true(guarded.is_dragging)
  guarded.reveal_for_scroll()
  assert_eq(scrollable_timeout_test_active_count(), 0)
  guarded.drag_ended()
  assert_false(guarded.is_dragging)
  guarded.reveal_for_scroll()
  assert_eq(scrollable_timeout_test_active_count(), 1)
  scrollable_timeout_test_run_pending()
  assert_true(guarded.hide_timeout is None)
  assert_eq(
    guarded.vertical_bar.get_attribute("class"),
    Some("invisible scrollbar vertical fade"),
  )
  guarded.drag_started()
  assert_true(guarded.is_dragging)
  guarded.dispose()
  assert_false(guarded.is_dragging)
  restore_scrollable_timeout_test_browser()
}
