// Ported from `vscode/src/vs/base/browser/mouseEvent.ts` in the checked-in
// vscode source: the `IMouseEvent` facts as
// `StandardMouseEvent`.
//
// Omissions:
//   * iframe offset correction (`IframeUtils.getPositionOfChildWindowRelativeTo
//     AncestorWindow`, mouseEvent.ts:74-76) — single-window viewer, so the
//     `targetWindow` constructor parameter is dropped and `posx`/`posy` are the
//     raw `pageX`/`pageY`.
//   * `DragMouseEvent` (drag-and-drop text move is not ported; readonly
//     viewer).
//   * `IMouseWheelEvent`/`StandardWheelEvent` — the viewer's existing copy
//     lives in `internal/viewer/ui/scrollbar/mouse_event.mbt`; consolidating it
//     here is a recorded follow-up, not part of this port.
//
// `target` is typed `@rdom.Element?` instead of Monaco's bare `HTMLElement`
// cast (mouseEvent.ts:59): the DOM allows non-element event targets, and the
// hit-test consumer (`HitTestRequest.target : HTMLElement | null`) is already
// nullable in the source.

///|
pub struct StandardMouseEvent {
  browser_event : @rdom.MouseEvent
  left_button : Bool
  middle_button : Bool
  right_button : Bool
  buttons : Int
  target : @rdom.Element?
  detail : Int
  posx : Double
  posy : Double
  ctrl_key : Bool
  shift_key : Bool
  alt_key : Bool
  meta_key : Bool
  timestamp : Double
  default_prevented : Bool
}

///|
pub fn StandardMouseEvent::StandardMouseEvent(
  e : @rdom.MouseEvent,
) -> StandardMouseEvent {
  let detail = ui_event_detail(e)
  {
    browser_event: e,
    left_button: e.get_button() == 0,
    middle_button: e.get_button() == 1,
    right_button: e.get_button() == 2,
    buttons: e.get_buttons(),
    target: e.target().to_element(),
    detail: if event_type(e) == "dblclick" {
      2
    } else if detail == 0 {
      1
    } else {
      detail
    },
    posx: e.get_page_x(),
    posy: e.get_page_y(),
    ctrl_key: e.get_ctrl_key(),
    shift_key: e.get_shift_key(),
    alt_key: e.get_alt_key(),
    meta_key: e.get_meta_key(),
    timestamp: wall_clock_now_ms(),
    default_prevented: event_default_prevented(e),
  }
}

///|
/// FFI gap-fill: the vendored `@rdom` `IsUIEvent` exposes no `detail`.
extern "js" fn ui_event_detail(e : @rdom.MouseEvent) -> Int =
  #| (e) => e.detail | 0

///|
/// FFI gap-fill: no `Event.type` binding in the vendored `@rdom`.
extern "js" fn event_type(e : @rdom.MouseEvent) -> String =
  #| (e) => e.type

///|
/// FFI gap-fill: no `Event.defaultPrevented` binding in the vendored `@rdom`.
extern "js" fn event_default_prevented(e : @rdom.MouseEvent) -> Bool =
  #| (e) => !!e.defaultPrevented
