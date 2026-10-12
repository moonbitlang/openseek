///|
extern "js" fn install_editor_pointer_monitor_test_browser() -> Unit =
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
  #|   class TestMouseEvent extends Event {}
  #|   const owningWindow = new TrackingTarget();
  #|   const ownerDocument = new TrackingTarget();
  #|   ownerDocument.nodeType = 9;
  #|   ownerDocument.defaultView = owningWindow;
  #|   owningWindow.document = ownerDocument;
  #|   class TestElement extends TrackingTarget {
  #|     constructor() {
  #|       super();
  #|       this.nodeType = 1;
  #|       this.ownerDocument = ownerDocument;
  #|       this.captureCalls = 0;
  #|       this.releaseCalls = 0;
  #|     }
  #|     setPointerCapture(_pointerId) { this.captureCalls += 1; }
  #|     releasePointerCapture(_pointerId) { this.releaseCalls += 1; }
  #|   }
  #|   ownerDocument.createElement = () => new TestElement();
  #|   globalThis.window = owningWindow;
  #|   globalThis.document = ownerDocument;
  #|   globalThis.MouseEvent = TestMouseEvent;
  #|   globalThis.Element = TestElement;
  #|   globalThis.__EditorPointerMonitorTestElement = TestElement;
  #| }

///|
extern "js" fn editor_pointer_monitor_test_element() -> @rdom.Element =
  #| () => new globalThis.__EditorPointerMonitorTestElement()

///|
extern "js" fn editor_pointer_monitor_test_document_listener_count(
  event_type : String,
) -> Int32 =
  #| (type) => document.listenerCount(type)

///|
extern "js" fn editor_pointer_monitor_test_element_listener_count(
  element : @rdom.Element,
  event_type : String,
) -> Int32 =
  #| (element, type) => element.listenerCount(type)

///|
extern "js" fn editor_pointer_monitor_test_capture_calls(
  element : @rdom.Element,
) -> Int32 =
  #| (element) => element.captureCalls

///|
extern "js" fn editor_pointer_monitor_test_release_calls(
  element : @rdom.Element,
) -> Int32 =
  #| (element) => element.releaseCalls

///|
extern "js" fn editor_pointer_monitor_test_dispatch_key(key : String) -> Unit =
  #| (key) => {
  #|   const event = new Event("keydown", { cancelable: true });
  #|   Object.defineProperty(event, "key", { value: key });
  #|   document.dispatchEvent(event);
  #| }

///|
test "GlobalEditorPointerMoveMonitor releases keydown on restart, stop, and dispose" {
  install_editor_pointer_monitor_test_browser()
  let editor_root = editor_pointer_monitor_test_element()
  let initial_element = editor_pointer_monitor_test_element()
  let stops = Ref(0)
  let monitor = GlobalEditorPointerMoveMonitor(editor_root)

  monitor.start_monitoring(initial_element, 17, 1, _ => (), _ => stops.val += 1)
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 1)
  assert_eq(
    editor_pointer_monitor_test_element_listener_count(
      initial_element, "pointermove",
    ),
    1,
  )

  // Restart uses stop(false) in the base monitor. The wrapper must therefore
  // release the old capture-keydown listener before overwriting its slot.
  monitor.start_monitoring(initial_element, 18, 1, _ => (), _ => stops.val += 1)
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 1)
  assert_eq(editor_pointer_monitor_test_capture_calls(initial_element), 2)
  assert_eq(editor_pointer_monitor_test_release_calls(initial_element), 1)
  assert_eq(stops.val, 0)

  // Modifier-only keydowns preserve the gesture; any other key stops it.
  editor_pointer_monitor_test_dispatch_key("Shift")
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 1)
  assert_eq(stops.val, 0)
  editor_pointer_monitor_test_dispatch_key("x")
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 0)
  assert_eq(
    editor_pointer_monitor_test_element_listener_count(
      initial_element, "pointermove",
    ),
    0,
  )
  assert_eq(stops.val, 1)

  monitor.start_monitoring(initial_element, 19, 1, _ => (), _ => stops.val += 1)
  monitor.stop_monitoring()
  assert_eq(stops.val, 2)
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 0)

  monitor.start_monitoring(initial_element, 20, 1, _ => (), _ => stops.val += 1)
  monitor.dispose()
  monitor.dispose()
  assert_eq(stops.val, 2)
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 0)
  assert_eq(
    editor_pointer_monitor_test_element_listener_count(
      initial_element, "pointermove",
    ),
    0,
  )

  // A disposed wrapper is permanently closed and cannot leak a new listener.
  monitor.start_monitoring(initial_element, 21, 1, _ => (), _ => stops.val += 1)
  assert_eq(editor_pointer_monitor_test_document_listener_count("keydown"), 0)
  assert_eq(editor_pointer_monitor_test_capture_calls(initial_element), 4)
}
