// Ported from `vscode/src/vs/editor/browser/editorDom.ts` (vscode submodule
// checked-in source): the coordinate model
// (`PageCoordinates`/`ClientCoordinates`/`EditorPagePosition`/
// `CoordinatesRelativeToEditor` and their factory functions),
// `EditorDomMouseEvent`, `EditorMouseEventFactory` and
// `GlobalEditorPointerMoveMonitor`.
//
// Shape notes:
//   * `EditorMouseEvent extends StandardMouseEvent` ports as
//     `EditorDomMouseEvent` and flattens the base fields
//     into this struct (MoonBit has no inheritance); the constructor populates
//     them from `@base_browser.StandardMouseEvent(...)`.
//   * The single-window omission (see `base/browser/mouse_event.mbt`) drops
//     every `targetWindow`/`getWindow` parameter.
//
// Omissions:
//   * `EditorPointerEventFactory`'s touch/pen dispatch. The mouse path retains
//     Monaco's paired pointerdown-id capture plus mousedown delivery, because
//     only mousedown carries double/triple-click detail.
//   * `DynamicCssRules` and friends (editorDom.ts:288-429) — decoration CSS
//     helpers unrelated to mouse handling.
//   * The keydown monitor-cancel check reads `KeyboardEvent.key` instead of
//     Monaco's `toKeyCodeChord().isModifierKey()` (no keybinding chord port).

///|
/// Coordinates relative to the whole document (e.g. mouse event's pageX and
/// pageY) — `PageCoordinates` (editorDom.ts:19-30).
pub(all) struct PageCoordinates {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
pub fn PageCoordinates::to_client_coordinates(
  self : PageCoordinates,
) -> ClientCoordinates {
  {
    client_x: self.x - window_scroll_x(),
    client_y: self.y - window_scroll_y(),
  }
}

///|
/// Coordinates within the application's client area — `ClientCoordinates`
/// (editorDom.ts:39-50).
pub(all) struct ClientCoordinates {
  client_x : Double
  client_y : Double
} derive(Eq, Debug)

///|
pub fn ClientCoordinates::to_page_coordinates(
  self : ClientCoordinates,
) -> PageCoordinates {
  {
    x: self.client_x + window_scroll_x(),
    y: self.client_y + window_scroll_y(),
  }
}

///|
/// The position of the editor in the page — `EditorPagePosition`
/// (editorDom.ts:55-64).
pub struct EditorPagePosition {
  x : Double
  y : Double
  width : Double
  height : Double
} derive(Eq, Debug)

///|
/// Coordinates relative to the (top;left) of the editor, scale-corrected —
/// `CoordinatesRelativeToEditor` (editorDom.ts:72-79). Can be negative when
/// the mouse is outside the editor.
pub struct CoordinatesRelativeToEditor {
  x : Double
  y : Double
} derive(Eq, Debug)

///|
/// `createEditorPagePosition` (editorDom.ts:81-84):
/// `dom.getDomNodePagePosition` is the bounding client rect shifted by the
/// window scroll.
pub fn create_editor_page_position(
  editor_view_dom_node : @rdom.Element,
) -> EditorPagePosition {
  let rect = editor_view_dom_node.get_bounding_client_rect()
  {
    x: rect.get_left() + window_scroll_x(),
    y: rect.get_top() + window_scroll_y(),
    width: rect.get_width(),
    height: rect.get_height(),
  }
}

///|
/// `createCoordinatesRelativeToEditor` (editorDom.ts:86-103): inverse-applies
/// a `transform: scale()` detected as the ratio between the measured rect and
/// the unscaled `offsetWidth`/`offsetHeight`.
pub fn create_coordinates_relative_to_editor(
  editor_view_dom_node : @rdom.Element,
  editor_page_position : EditorPagePosition,
  pos : PageCoordinates,
) -> CoordinatesRelativeToEditor {
  let scale_x = editor_page_position.width /
    @base_browser.element_offset_width(editor_view_dom_node)
  let scale_y = editor_page_position.height /
    @base_browser.element_offset_height(editor_view_dom_node)
  let relative_x = (pos.x - editor_page_position.x) / scale_x
  let relative_y = (pos.y - editor_page_position.y) / scale_y
  { x: relative_x, y: relative_y, }
}

///|
pub fn EditorDomMouseEvent::EditorDomMouseEvent(
  e : @rdom.MouseEvent,
  is_from_pointer_capture : Bool,
  editor_view_dom_node : @rdom.Element,
) -> EditorDomMouseEvent {
  let base = @base_browser.StandardMouseEvent(e)
  {
    browser_event: base.browser_event,
    left_button: base.left_button,
    middle_button: base.middle_button,
    right_button: base.right_button,
    buttons: base.buttons,
    target: base.target,
    detail: base.detail,
    posx: base.posx,
    posy: base.posy,
    ctrl_key: base.ctrl_key,
    shift_key: base.shift_key,
    alt_key: base.alt_key,
    meta_key: base.meta_key,
    timestamp: base.timestamp,
    default_prevented: base.default_prevented,
    is_from_pointer_capture,
    pos: { x: base.posx, y: base.posy, },
    editor_view_dom_node,
    editor_pos_cache: None,
    relative_pos_cache: None,
  }
}

///|
/// Editor's coordinates relative to the whole document (lazy, editorDom.ts:122-126).
pub fn EditorDomMouseEvent::editor_pos(
  self : EditorDomMouseEvent,
) -> EditorPagePosition {
  match self.editor_pos_cache {
    Some(pos) => pos
    None => {
      let pos = create_editor_page_position(self.editor_view_dom_node)
      self.editor_pos_cache = Some(pos)
      pos
    }
  }
}

///|
/// Coordinates relative to the (top;left) of the editor (lazy,
/// editorDom.ts:133-137). Preferred because they account for transformations;
/// can be negative outside the editor.
pub fn EditorDomMouseEvent::relative_pos(
  self : EditorDomMouseEvent,
) -> CoordinatesRelativeToEditor {
  match self.relative_pos_cache {
    Some(pos) => pos
    None => {
      let pos = create_coordinates_relative_to_editor(
        self.editor_view_dom_node,
        self.editor_pos(),
        self.pos,
      )
      self.relative_pos_cache = Some(pos)
      pos
    }
  }
}

///|
/// `MouseDownOperation.start` overwrites `e.detail` with the computed
/// multi-click count before the event is emitted (mouseHandler.ts:456-457);
/// the field is package-private-mutable, so the write crosses through this
/// setter.
pub fn EditorDomMouseEvent::set_detail(
  self : EditorDomMouseEvent,
  detail : Int,
) -> Unit {
  self.detail = detail
}

///|
pub fn EditorDomMouseEvent::prevent_default(self : EditorDomMouseEvent) -> Unit {
  self.browser_event.prevent_default()
}

///|
pub fn EditorDomMouseEvent::stop_propagation(
  self : EditorDomMouseEvent,
) -> Unit {
  self.browser_event.stop_propagation()
}

///|
/// `EditorMouseEventFactory` (editorDom.ts:149-194): DOM-listener wrappers
/// producing `EditorDomMouseEvent`s anchored to the editor's view DOM node.
struct EditorMouseEventFactory {
  editor_view_dom_node : @rdom.Element
}

///|
pub fn EditorMouseEventFactory::EditorMouseEventFactory(
  editor_view_dom_node : @rdom.Element,
) -> EditorMouseEventFactory {
  { editor_view_dom_node, }
}

///|
fn EditorMouseEventFactory::listen(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  event_type : String,
  callback : (EditorDomMouseEvent) -> Unit,
) -> @base_common.Disposable {
  let handler = (event : @rdom.Event) => {
    match event.to_mouse_event() {
      Some(mouse) =>
        callback(EditorDomMouseEvent(mouse, false, self.editor_view_dom_node))
      None => ()
    }
  }
  target.add_event_listener(event_type, handler)
  @base_common.Disposable::from(() => {
    target.remove_event_listener(event_type, handler)
  })
}

///|
pub fn EditorMouseEventFactory::on_mouse_up(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  callback : (EditorDomMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.listen(target, "mouseup", callback)
}

///|
pub fn EditorMouseEventFactory::on_mouse_down(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  callback : (EditorDomMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.listen(target, "mousedown", callback)
}

///|
/// `EditorMouseEventFactory.onContextMenu` (editorDom.ts:177-181).
pub fn EditorMouseEventFactory::on_context_menu(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  callback : (EditorDomMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.listen(target, "contextmenu", callback)
}

///|
/// `EditorPointerEventFactory.onPointerDown`'s mouse seam: capture the
/// PointerEvent id separately, then reuse it when the following mousedown
/// starts global monitoring. PointerEvent.detail is always zero and therefore
/// cannot replace the ordinary mousedown event.
pub fn EditorMouseEventFactory::on_pointer_down(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  callback : (EditorDomMouseEvent, Int) -> Unit,
) -> @base_common.Disposable {
  self.listen(target, "pointerdown", event => {
    callback(event, @base_browser.mouse_event_pointer_id(event.browser_event))
  })
}

///|
pub fn EditorMouseEventFactory::on_mouse_leave(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  callback : (EditorDomMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.listen(target, "mouseleave", callback)
}

///|
pub fn EditorMouseEventFactory::on_mouse_move(
  self : EditorMouseEventFactory,
  target : @rdom.Element,
  callback : (EditorDomMouseEvent) -> Unit,
) -> @base_common.Disposable {
  self.listen(target, "mousemove", callback)
}

///|
/// `GlobalEditorPointerMoveMonitor` (editorDom.ts:231-280): wraps the base
/// monitor and installs a capturing keydown listener that cancels monitoring
/// when a non-modifier key is pressed.
struct GlobalEditorPointerMoveMonitor {
  editor_view_dom_node : @rdom.Element
  global_pointer_move_monitor : @base_browser.GlobalPointerMoveMonitor
  mut keydown_listener : @base_common.Disposable?
  mut disposed : Bool
}

///|
pub fn GlobalEditorPointerMoveMonitor::GlobalEditorPointerMoveMonitor(
  editor_view_dom_node : @rdom.Element,
) -> GlobalEditorPointerMoveMonitor {
  {
    editor_view_dom_node,
    global_pointer_move_monitor: GlobalPointerMoveMonitor(),
    keydown_listener: None,
    disposed: false,
  }
}

///|
fn GlobalEditorPointerMoveMonitor::dispose_keydown_listener(
  self : GlobalEditorPointerMoveMonitor,
) -> Unit {
  if self.keydown_listener is Some(listener) {
    listener.dispose()
  }
  self.keydown_listener = None
}

///|
pub fn GlobalEditorPointerMoveMonitor::dispose(
  self : GlobalEditorPointerMoveMonitor,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.dispose_keydown_listener()
  self.global_pointer_move_monitor.dispose()
}

///|
/// `startMonitoring` (editorDom.ts:244-275), including the pointer id used by
/// the base monitor's capture/fallback lifecycle.
pub fn GlobalEditorPointerMoveMonitor::start_monitoring(
  self : GlobalEditorPointerMoveMonitor,
  initial_element : @rdom.Element,
  pointer_id : Int,
  initial_buttons : Int,
  pointer_move_callback : (EditorDomMouseEvent) -> Unit,
  on_stop_callback : (@rdom.Event?) -> Unit,
) -> Unit {
  if self.disposed {
    return
  }
  // The base monitor restarts an active gesture with `stopMonitoring(false)`,
  // so its prior stop callback cannot release the capture listener. Release
  // it before installing the next gesture's listener.
  self.dispose_keydown_listener()
  // Add a <<capture>> keydown event listener that will cancel the monitoring
  // if something other than a modifier key is pressed
  let keydown = (event : @rdom.Event) => {
    let key = keyboard_event_key(event)
    if key == "Control" || key == "Shift" || key == "Alt" || key == "Meta" {
      // Allow modifier keys
      return
    }
    self.global_pointer_move_monitor.stop_monitoring(true, browser_event=event)
  }
  document_add_keydown_capture(keydown)
  self.keydown_listener = Some(
    @base_common.Disposable::from(() => document_remove_keydown_capture(keydown)),
  )
  self.global_pointer_move_monitor.start_monitoring(
    initial_element,
    pointer_id,
    initial_buttons,
    e => {
      pointer_move_callback(
        EditorDomMouseEvent(e, true, self.editor_view_dom_node),
      )
    },
    e => {
      self.dispose_keydown_listener()
      on_stop_callback(e)
    },
  )
}

///|
pub fn GlobalEditorPointerMoveMonitor::stop_monitoring(
  self : GlobalEditorPointerMoveMonitor,
) -> Unit {
  self.global_pointer_move_monitor.stop_monitoring(true)
}

///|
/// FFI gap-fills (no window-scroll / offset-size / capturing-listener /
/// `KeyboardEvent.key` bindings in the vendored `@rdom`).
extern "js" fn window_scroll_x() -> Double = "() => window.scrollX"

///|
extern "js" fn window_scroll_y() -> Double = "() => window.scrollY"

///|
extern "js" fn keyboard_event_key(e : @rdom.Event) -> String =
  #| (e) => e.key || ""

///|
extern "js" fn document_add_keydown_capture(
  callback : (@rdom.Event) -> Unit,
) -> Unit =
  #| (cb) => document.addEventListener("keydown", cb, true)

///|
extern "js" fn document_remove_keydown_capture(
  callback : (@rdom.Event) -> Unit,
) -> Unit =
  #| (cb) => document.removeEventListener("keydown", cb, true)

///|
pub extend ClientCoordinates with Debug::{to_repr}

///|
pub extend ClientCoordinates with Eq::{equal, not_equal}

///|
pub extend CoordinatesRelativeToEditor with Debug::{to_repr}

///|
pub extend CoordinatesRelativeToEditor with Eq::{equal, not_equal}

///|
pub extend EditorPagePosition with Debug::{to_repr}

///|
pub extend EditorPagePosition with Eq::{equal, not_equal}

///|
pub extend PageCoordinates with Debug::{to_repr}

///|
pub extend PageCoordinates with Eq::{equal, not_equal}
