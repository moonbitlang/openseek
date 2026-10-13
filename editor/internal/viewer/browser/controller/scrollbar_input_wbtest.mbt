///|
test "AbstractScrollbar Windows orthogonal reset uses strict greater than 140" {
  assert_false(scrollbar_drag_should_reset(10.0, 149.0, is_windows=true))
  assert_false(scrollbar_drag_should_reset(10.0, 150.0, is_windows=true))
  assert_true(scrollbar_drag_should_reset(10.0, 151.0, is_windows=true))
  assert_false(scrollbar_drag_should_reset(150.0, 10.0, is_windows=true))
  assert_true(scrollbar_drag_should_reset(151.0, 10.0, is_windows=true))
  assert_false(scrollbar_drag_should_reset(10.0, 151.0, is_windows=false))
}

///|
extern "js" fn install_scrollbar_input_test_browser() -> Unit =
  #| () => {
  #|   class TrackingTarget extends EventTarget {
  #|     constructor() {
  #|       super();
  #|       this.__listeners = new Map();
  #|     }
  #|     addEventListener(type, listener, options) {
  #|       let listeners = this.__listeners.get(type);
  #|       if (!listeners) {
  #|         listeners = new Set();
  #|         this.__listeners.set(type, listeners);
  #|       }
  #|       listeners.add(listener);
  #|       super.addEventListener(type, listener, options);
  #|     }
  #|     removeEventListener(type, listener, options) {
  #|       this.__listeners.get(type)?.delete(listener);
  #|       super.removeEventListener(type, listener, options);
  #|     }
  #|     listenerCount(type) {
  #|       return this.__listeners.get(type)?.size ?? 0;
  #|     }
  #|   }
  #|   class TestMouseEvent extends Event {
  #|     constructor(type, init = {}) {
  #|       super(type, { cancelable: true, bubbles: true });
  #|       this.button = init.button ?? 0;
  #|       this.buttons = init.buttons ?? 0;
  #|       this.pointerId = init.pointerId ?? 0;
  #|       this.clientX = init.clientX ?? 0;
  #|       this.clientY = init.clientY ?? 0;
  #|       this.pageX = this.clientX;
  #|       this.pageY = this.clientY;
  #|       this.offsetX = this.clientX;
  #|       this.offsetY = this.clientY;
  #|       this.detail = init.detail ?? 1;
  #|       this.ctrlKey = false;
  #|       this.shiftKey = false;
  #|       this.altKey = false;
  #|       this.metaKey = false;
  #|     }
  #|   }
  #|   const owningWindow = new TrackingTarget();
  #|   const ownerDocument = new TrackingTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.defaultView = owningWindow;
  #|   owningWindow.document = ownerDocument;
  #|   owningWindow.__rafNextId = 1;
  #|   owningWindow.__rafHistory = [];
  #|   owningWindow.__rafActive = new Map();
  #|   owningWindow.__rafCancelCount = 0;
  #|   owningWindow.requestAnimationFrame = (callback) => {
  #|     const id = owningWindow.__rafNextId++;
  #|     owningWindow.__rafHistory.push(callback);
  #|     owningWindow.__rafActive.set(id, callback);
  #|     return id;
  #|   };
  #|   owningWindow.cancelAnimationFrame = (id) => {
  #|     owningWindow.__rafCancelCount += 1;
  #|     owningWindow.__rafActive.delete(id);
  #|   };
  #|   class TestElement extends TrackingTarget {
  #|     constructor(tag = "div") {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.nodeName = tag.toUpperCase();
  #|       this.ownerDocument = ownerDocument;
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
  #|       this.captureCalls = 0;
  #|       this.releaseCalls = 0;
  #|     }
  #|     setAttribute(name, value) {
  #|       const stringValue = String(value);
  #|       this.attributes.set(name, stringValue);
  #|       if (name === "class" && stringValue === "slider active") {
  #|         globalThis.__scrollbarInputTrace?.push("active");
  #|       }
  #|       if (name === "class" && stringValue === "visible scrollbar vertical") {
  #|         globalThis.__scrollbarInputTrace?.push("drag-start");
  #|       }
  #|     }
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
  #|     setPointerCapture(_pointerId) {
  #|       this.captureCalls += 1;
  #|       globalThis.__scrollbarInputTrace?.push("monitor");
  #|     }
  #|     releasePointerCapture(_pointerId) { this.releaseCalls += 1; }
  #|   }
  #|   ownerDocument.createElement = (tag) => new TestElement(tag);
  #|   globalThis.window = owningWindow;
  #|   globalThis.document = ownerDocument;
  #|   globalThis.MouseEvent = TestMouseEvent;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__ScrollbarInputTestElement = TestElement;
  #|   globalThis.__scrollbarInputTrace = [];
  #| }

///|
extern "js" fn scrollbar_input_test_element() -> @rdom.Element =
  #| () => new globalThis.__ScrollbarInputTestElement()

///|
extern "js" fn scrollbar_input_test_non_element_mouse(
  button : Int32,
  buttons : Int32,
  pointer_id : Int32,
) -> @rdom.MouseEvent =
  #| (button, buttons, pointerId) => {
  #|   const event = new MouseEvent("pointerdown", {
  #|     button, buttons, pointerId, clientX: 0, clientY: 0,
  #|   });
  #|   window.dispatchEvent(event);
  #|   return event;
  #| }

///|
extern "js" fn scrollbar_input_test_listener_count(
  element : @rdom.Element,
  event_type : String,
) -> Int32 =
  #| (element, type) => element.listenerCount(type)

///|
extern "js" fn scrollbar_input_test_raf_cancel_count() -> Int32 =
  #| () => window.__rafCancelCount

///|
extern "js" fn scrollbar_input_test_run_raf_history() -> Unit =
  #| () => {
  #|   for (const callback of window.__rafHistory) callback(0);
  #| }

///|
test "DragScrolling disposal cancels and disables its pending animation frame" {
  install_scrollbar_input_test_browser()
  let root = scrollbar_input_test_element()
  let editor_scrollable = @scrollbar.ScrollableElementDom("editor")
  let hover_scrollable = @scrollbar.ScrollableElementDom("hover")
  let helper : PointerHandlerHelper = {
    view_dom_node: root,
    lines_content_dom_node: scrollbar_input_test_element(),
    view_lines_dom_node: scrollbar_input_test_element(),
    focus_text_area: () => (),
    get_last_render_data: () => abort("disposed rAF reached render data"),
    render_now: () => abort("disposed rAF rendered"),
    should_suppress_mouse_down_on_view_zone: _ => false,
    get_position_from_dom_info: (_element, _offset) => None,
    visible_range_for_position: (_line, _column) => None,
    get_line_width: _ => 0.0,
    view_model: () => abort("disposed rAF read the ViewModel"),
    get_layout_info: () => abort("disposed rAF read layout"),
    get_font_info: () => abort("disposed rAF read font info"),
    get_current_selection: () => None,
    dispatch_mouse: _ => abort("disposed rAF dispatched"),
    before_mouse_down_selection: (_event, _target) => false,
    emit_mouse_down: (_event, _target) => (),
    emit_mouse_up: (_event, _target) => (),
    emit_mouse_move: (_event, _target) => (),
    emit_context_menu: (_event, _target) => (),
    emit_mouse_drag: (_event, _target) => (),
    emit_mouse_leave: _ => (),
    overflow_guard: scrollbar_input_test_element(),
    editor_scrollable,
    hover_scrollable: () => Some(hover_scrollable),
    view_layout: () => None,
    schedule_render: () => (),
  }
  let factory = MouseTargetFactory(helper)
  let mouse = scrollbar_input_test_non_element_mouse(0, 1, 77)
  let editor_event = @editor_browser.EditorDomMouseEvent(mouse, true, root)
  let operation = DragScrollingOperation::DragScrollingOperation(
    TopBottom,
    helper,
    factory,
    (_position, _in_selection_mode, _reveal_type) => {
      abort("disposed rAF dispatched")
    },
    @editor_browser.MouseTarget::create_outside_editor(
      1,
      Position(1, 1),
      Below,
      20.0,
    ),
    editor_event,
  )
  assert_true(operation.animation_frame_id is Some(_))
  operation.dispose()
  operation.dispose()
  assert_true(operation.disposed)
  assert_true(operation.animation_frame_id is None)
  assert_eq(scrollbar_input_test_raf_cancel_count(), 1)
  // Force even the cancelled browser callback to run: the disposed guard must
  // return before any ViewModel/layout/render/dispatch seam above is touched.
  scrollbar_input_test_run_raf_history()
}
