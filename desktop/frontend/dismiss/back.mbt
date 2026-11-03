// Back closes the topmost open layer.
//
// A layer is anything shown over the page that Back should close before the
// page itself is left: a menu, popover, dialog, the narrow layout's drawer and
// overlay panels, a management page. Each layer mounts `on_back` while it is
// open, at its `Level`, and Back reaches the most recent layer of the highest
// level, whichever component owns it. Within a level, layers stack in the
// order they opened. Levels keep a layer that becomes one late (the narrow
// layout's drawer after a resize) under a dialog that was already open.
//
// Back has three sources. On a keyboard it is an unmodified Escape that nothing
// on the way handled first: the listener sits in the document's bubble phase
// and yields to a default-prevented event, so a focused control (an input
// clearing itself, a menu moving focus back to its trigger) keeps first
// refusal. A host without Escape, such as the Android shell's Back button,
// dispatches the cancelable `openseek-back` event on the document instead,
// which the application root answers through `host_back`:
//
//   !document.dispatchEvent(new Event('openseek-back', { cancelable: true }))
//
// is true exactly when something closed, and false when nothing is open, so
// the host then performs its own Back. The event name is that contract; the
// host knows nothing of the layers or their DOM.
//
// In a browser, Android's Back gesture is a close request: Chromium closes
// the topmost modal `<dialog>` or popover, and otherwise goes back in history.
// While a layer is open, a `CloseWatcher` takes that request for the layers
// too, so an installed web app's Back closes them as the shell's does. The
// Android shell takes Back before its WebView and sends its own event instead.
// Chromium turns an Escape that is not cancelled into a close request too.
// The watcher leaves that Escape to the listener above, whose rules (and the
// controls that consume Escape before it) stay as they were. Browsers without
// `CloseWatcher` keep their own Back.
//
// An auto popover is the browser's own layer, above every registered one, and
// no subscription stands for it. The browser closes it on Escape; the host's
// event and the watcher close it first, since the watcher can sit above it.

///|
const BACK_EVENT : String = "openseek-back"

///|
/// Answer the host's Back event. The application root mounts it once, for its
/// lifetime: the host's Back must reach a browser-owned popover even while no
/// layer is open.
pub fn host_back() -> @sub.Sub {
  @sub.custom_sub(
    "host-back",
    @sub.Scope::Global,
    HostBackSubscription,
    host_back_sub_loader,
  )
}

///|
/// Where a layer sits, bottom to top.
pub(all) enum Level {
  /// A page shown in place of the work surface.
  Page
  /// A panel that covers the page on the narrow layout. Panels keep a fixed
  /// stacking among themselves, so each carries its place in it: a higher
  /// one is drawn above a lower one, whichever opened first.
  Panel(Int32)
  /// A menu or dialog drawn in the page.
  Popup
  /// A modal `<dialog>` or a `popover` element. The browser draws these in its
  /// top layer, above everything in the page, in the order they opened.
  TopLayer
}

///|
/// Whether `self` is drawn below `other`.
fn Level::below(self : Level, other : Level) -> Bool {
  match (self, other) {
    (Panel(lower), Panel(upper)) => lower < upper
    (Page, Panel(_) | Popup | TopLayer)
    | (Panel(_), Popup | TopLayer)
    | (Popup, TopLayer) => true
    _ => false
  }
}

///|
/// Close this layer when Back reaches the top of the layer stack.
///
/// Mount it only while the layer is open; unmounting removes the layer. `key`
/// names the subscription within its component's subscription tree, as for
/// `on_outside_click`. `emit` must close the layer and stay harmless when
/// repeated, since a second Back can arrive before the first one's message
/// has unmounted the layer: dismiss, never toggle.
pub fn on_back(
  key : String,
  level~ : Level = Popup,
  emit : @cmd.Emit[Unit],
) -> @sub.Sub {
  @sub.custom_sub(
    key,
    @sub.Scope::Global,
    BackSubscription(level, emit),
    back_sub_loader,
  )
}

///|
priv suberror HostBackSubscription

///|
priv suberror BackSubscription {
  BackSubscription(Level, @cmd.Emit[Unit])
}

///|
priv struct Layer {
  id : Int32
  mut level : Level
  mut emit : @cmd.Emit[Unit]
  scheduler : &@cmd.Scheduler
}

///|
/// The open layers, oldest first.
let layers : Array[Layer] = []

///|
let next_layer_id : Ref[Int32] = { val: 0, }

///|
/// Close the topmost layer: the most recent of the highest level. False when
/// no layer is open.
fn dismiss_top() -> Bool {
  let mut top : Layer? = None
  for layer in layers {
    if top is Some(current) && layer.level.below(current.level) {
      continue
    }
    top = Some(layer)
  }
  guard top is Some(layer) else { return false }
  layer.scheduler.add((layer.emit)(()))
  true
}

///|
fn open_auto_popover() -> @dom.Element? {
  @dom.document().query_selector("[popover=auto]:popover-open").to_option()
}

///|
let escape_listener : @dom.Listener = event => {
  guard !event.get_default_prevented() &&
    event.to_keyboard_event() is Some(keyboard) &&
    keyboard.key() == "Escape" &&
    !keyboard.is_composing() &&
    !keyboard.repeat() &&
    !keyboard.ctrl_key() &&
    !keyboard.meta_key() &&
    !keyboard.alt_key() &&
    !keyboard.shift_key() else {
    return
  }
  // The browser closes an open auto popover on this Escape unless the event
  // is prevented.
  guard open_auto_popover() is None else { return }
  if dismiss_top() {
    event.prevent_default()
  }
}

///|
fn close_auto_popover() -> Bool {
  guard open_auto_popover().bind(element => element.to_html_element())
    is Some(popover) else {
    return false
  }
  popover.hide_popover()
  true
}

///|
/// Close the browser's auto popover, or else the topmost layer. False when
/// neither is open.
fn back() -> Bool {
  close_auto_popover() || dismiss_top()
}

///|
let back_listener : @dom.Listener = event => {
  if back() {
    event.prevent_default()
  }
}

///|
/// Watch for the browser's next close request. `on_close` learns whether an
/// Escape keydown raised it: the request follows that keydown in the same task,
/// and a capture listener on the window sees the key before any handler can
/// stop it. `on_close` runs in a later task, once the browser has finished
/// with the request, so a watcher it creates waits for the next one. Returns
/// the function that stops watching, which also drops a request whose
/// `on_close` has not run yet: a layer opened in between replaced this watcher,
/// and the request must not close the layer the person has not seen. Where the
/// browser has no `CloseWatcher`, it does nothing.
extern "js" fn watch_close_request(on_close : (Bool) -> Unit) -> () -> Unit =
  #|(onClose) => {
  #|  if (typeof CloseWatcher !== 'function') return () => {};
  #|  let escape = false;
  #|  const key = event => {
  #|    if (event.key !== 'Escape') return;
  #|    escape = true;
  #|    setTimeout(() => { escape = false; }, 0);
  #|  };
  #|  addEventListener('keydown', key, true);
  #|  let pending;
  #|  const watcher = new CloseWatcher();
  #|  watcher.onclose = () => {
  #|    removeEventListener('keydown', key, true);
  #|    const fromEscape = escape;
  #|    pending = setTimeout(() => onClose(fromEscape), 0);
  #|  };
  #|  return () => {
  #|    removeEventListener('keydown', key, true);
  #|    clearTimeout(pending);
  #|    watcher.destroy();
  #|  };
  #|}

///|
/// Stops the watcher that is waiting for a close request, while one is.
let stop_close_watch : Ref[(() -> Unit)?] = { val: None, }

///|
fn stop_watching_close_requests() -> Unit {
  if stop_close_watch.val is Some(stop) {
    stop()
    stop_close_watch.val = None
  }
}

///|
/// Keep one watcher waiting while a layer is open. One request closes one
/// layer; the next watcher is created for the next request.
///
/// The browser asks the most recent watcher first, and a modal `<dialog>` has
/// its own. A layer that opens over such a dialog, such as a menu inside it,
/// renews the watcher so the request reaches the menu before the dialog.
fn watch_close_requests() -> Unit {
  guard stop_close_watch.val is None && !layers.is_empty() else { return }
  stop_close_watch.val = Some(
    watch_close_request(from_escape => {
      stop_close_watch.val = None
      // Escape belongs to the listener above. Only the auto popover the
      // watcher covered, which that listener leaves to the browser, closes.
      if from_escape {
        close_auto_popover() |> ignore
      } else {
        back() |> ignore
      }
      watch_close_requests()
    }),
  )
}

///|
fn host_back_sub_loader(
  payload : Error,
  _scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  guard payload is HostBackSubscription else { return None }
  let target = @dom.document().as_event_target()
  target.add_event_listener(BACK_EVENT, back_listener)
  Some({
    unload: _ => target.remove_event_listener(BACK_EVENT, back_listener),
    update_tagger: _ => (),
  })
}

///|
fn back_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    BackSubscription(level, emit) => {
      let id = next_layer_id.val
      next_layer_id.val += 1
      let target = @dom.document().as_event_target()
      // The document listens for Escape only while some layer is open.
      if layers.is_empty() {
        target.add_event_listener("keydown", escape_listener)
      }
      layers.push({ id, level, emit, scheduler, })
      stop_watching_close_requests()
      watch_close_requests()
      Some({
        unload: _ => {
          guard layers.search_by(layer => layer.id == id) is Some(index) else {
            return
          }
          layers.remove(index) |> ignore
          if layers.is_empty() {
            target.remove_event_listener("keydown", escape_listener)
            stop_watching_close_requests()
          }
        },
        update_tagger: payload => {
          guard payload is BackSubscription(level, next) &&
            layers.search_by(layer => layer.id == id) is Some(index) else {
            return
          }
          layers[index].level = level
          layers[index].emit = next
        },
      })
    }
    _ => None
  }
}
