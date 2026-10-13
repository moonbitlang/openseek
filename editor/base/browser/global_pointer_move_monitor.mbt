// Ported from `vscode/src/vs/base/browser/globalPointerMoveMonitor.ts`
// (checked-in vscode submodule).
//
// Binding note:
//   * The vendored `@rdom` has no pointer-capture bindings, so the two narrow
//     exception-normalizing FFIs at the bottom preserve the source's
//     capture/release branches.
//   * `DisposableStore` is an `Array[@base_common.Disposable]` (base/common
//     ports no store type).

///|
struct GlobalPointerMoveMonitor {
  hooks : Array[@base_common.Disposable]
  mut pointer_move_callback : ((@rdom.MouseEvent) -> Unit)?
  mut on_stop_callback : ((@rdom.Event?) -> Unit)?
  mut disposed : Bool
}

///|
pub fn GlobalPointerMoveMonitor::GlobalPointerMoveMonitor() -> GlobalPointerMoveMonitor {
  {
    hooks: [],
    pointer_move_callback: None,
    on_stop_callback: None,
    disposed: false,
  }
}

///|
pub fn GlobalPointerMoveMonitor::dispose(
  self : GlobalPointerMoveMonitor,
) -> Unit {
  if self.disposed {
    return
  }
  self.stop_monitoring(false)
  self.disposed = true
}

///|
pub fn GlobalPointerMoveMonitor::stop_monitoring(
  self : GlobalPointerMoveMonitor,
  invoke_stop_callback : Bool,
  browser_event? : @rdom.Event,
) -> Unit {
  if !self.is_monitoring() {
    return
  }
  for hook in self.hooks {
    hook.dispose()
  }
  self.hooks.clear()
  self.pointer_move_callback = None
  let on_stop_callback = self.on_stop_callback
  self.on_stop_callback = None
  if invoke_stop_callback && on_stop_callback is Some(callback) {
    callback(browser_event)
  }
}

///|
fn GlobalPointerMoveMonitor::is_monitoring(
  self : GlobalPointerMoveMonitor,
) -> Bool {
  self.pointer_move_callback is Some(_)
}

///|
/// `startMonitoring` (globalPointerMoveMonitor.ts:49-113): capture on the
/// initial element when possible, otherwise use that element's owning window.
pub fn GlobalPointerMoveMonitor::start_monitoring(
  self : GlobalPointerMoveMonitor,
  initial_element : @rdom.Element,
  pointer_id : Int32,
  initial_buttons : Int32,
  pointer_move_callback : (@rdom.MouseEvent) -> Unit,
  on_stop_callback : (@rdom.Event?) -> Unit,
) -> Unit {
  // `DisposableStore.dispose()` permanently closes Monaco's hook store. Keep
  // the same lifetime boundary explicit for the local array-backed store.
  if self.disposed {
    return
  }
  if self.is_monitoring() {
    self.stop_monitoring(false)
  }
  self.pointer_move_callback = Some(pointer_move_callback)
  self.on_stop_callback = Some(on_stop_callback)
  let event_source : @rdom.EventTarget = if try_set_pointer_capture(
      initial_element, pointer_id,
    ) {
    self.hooks.push(
      @base_common.Disposable::from(() => {
        release_pointer_capture_ignoring_errors(initial_element, pointer_id)
      }),
    )
    initial_element.as_event_target()
  } else {
    // `setPointerCapture` can throw on a valid mouse gesture. Monaco binds
    // the gesture listeners to the owning window in that case.
    owning_window_event_target(initial_element)
  }
  let pointer_move = (event : @rdom.Event) => {
    if cross_realm_mouse_event(event).to_option() is Some(e) {
      if e.get_buttons() != initial_buttons {
        // Buttons state has changed in the meantime
        self.stop_monitoring(true)
      } else {
        e.prevent_default()
        if self.pointer_move_callback is Some(callback) {
          callback(e)
        }
      }
    }
  }
  let pointer_up = (_event : @rdom.Event) => self.stop_monitoring(true)
  event_source.add_event_listener("pointermove", pointer_move)
  event_source.add_event_listener("pointerup", pointer_up)
  self.hooks.push(
    @base_common.Disposable::from(() => {
      event_source.remove_event_listener("pointermove", pointer_move)
    }),
  )
  self.hooks.push(
    @base_common.Disposable::from(() => {
      event_source.remove_event_listener("pointerup", pointer_up)
    }),
  )
}

///|
/// Rabbita's general MouseEvent cast uses the current realm's `instanceof`.
/// A PointerEvent delivered by an iframe's owning window is therefore rejected
/// even though it exposes the MouseEvent contract used by this monitor. Keep
/// this structural conversion local to the known `pointermove` listener.
extern "js" fn cross_realm_mouse_event(
  event : @rdom.Event,
) -> @js.Nullable[@rdom.MouseEvent] =
  #| (event) => typeof event?.buttons === "number" ? event : null

///|
/// Narrow gap-fill for `Element.setPointerCapture`. `false` is the source's
/// exception fallback signal; the DOMException itself is intentionally not
/// observable at this boundary.
extern "js" fn try_set_pointer_capture(
  element : @rdom.Element,
  pointer_id : Int32,
) -> Bool =
  #| (element, pointerId) => {
  #|   try {
  #|     element.setPointerCapture(pointerId);
  #|     return true;
  #|   } catch (_error) {
  #|     return false;
  #|   }
  #| }

///|
/// `releasePointerCapture` sometimes throws after the browser has already
/// dropped capture; Monaco deliberately ignores that DOMException.
extern "js" fn release_pointer_capture_ignoring_errors(
  element : @rdom.Element,
  pointer_id : Int32,
) -> Unit =
  #| (element, pointerId) => {
  #|   try {
  #|     element.releasePointerCapture(pointerId);
  #|   } catch (_error) {
  #|     // Capture is already gone; there is no recovery work.
  #|   }
  #| }

///|
/// PointerEvent.pointerId gap-fill. Pointer events are MouseEvent subclasses,
/// which is the event type exposed by the current Rabbita binding.
pub extern "js" fn mouse_event_pointer_id(event : @rdom.MouseEvent) -> Int32 =
  #| (event) => typeof event.pointerId === "number" ? event.pointerId : 0

///|
/// `dom.getWindow(initialElement)` gap-fill. The global fallback only covers
/// synthetic/test elements without an owner document.
extern "js" fn owning_window_event_target(
  element : @rdom.Element,
) -> @rdom.EventTarget =
  #| (element) => element.ownerDocument?.defaultView ?? globalThis.window
