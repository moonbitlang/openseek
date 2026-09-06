// Behavior port of the editor touch-scroll wiring in
// `vscode/src/vs/editor/browser/controller/pointerHandler.ts` and an
// algorithm-fidelity port of the sampling/inertia cluster in
// `vscode/src/vs/base/browser/touch.ts`, pinned at
// b18492a288de038fbc7643aae6de8247029d11bd.
//
// Representation decision: the viewer has one MouseHandler per View, so the
// target registry and synthetic custom events from Monaco's process-global
// Gesture singleton collapse into one private, callback-backed gesture owner.
// Touch coordinates, rolling samples, signs, thresholds, rAF ordering, and
// friction remain source-shaped. Tap/context-menu/pen dispatch is outside this
// slice; an unmoved touch is therefore left to the browser's existing
// compatibility mouse path.

///|
let touch_scroll_friction : Double = -0.005

///|
let touch_scroll_inertia_threshold : Double = 30.0

///|
priv struct TouchScrollData {
  initial_page_x : Double
  initial_page_y : Double
  rolling_timestamps : Array[Double]
  rolling_page_x : Array[Double]
  rolling_page_y : Array[Double]
}

///|
priv struct TouchScrollRuntime {
  now : () -> Double
  schedule_at_next_animation_frame : (() -> Unit) -> @base_common.Disposable
}

///|
fn browser_touch_scroll_runtime() -> TouchScrollRuntime {
  {
    now: @base_browser.wall_clock_now_ms,
    schedule_at_next_animation_frame: callback => {
      @base_browser.schedule_at_next_animation_frame(callback)
    },
  }
}

///|
priv struct TouchScrollGesture {
  runtime : TouchScrollRuntime
  on_translation : (Double, Double) -> Unit
  active_touches : Map[Int, TouchScrollData]
  mut inertia_frame : @base_common.Disposable?
  mut disposed : Bool
}

///|
fn TouchScrollGesture::TouchScrollGesture(
  runtime : TouchScrollRuntime,
  on_translation : (Double, Double) -> Unit,
) -> TouchScrollGesture {
  {
    runtime,
    on_translation,
    active_touches: Map([]),
    inertia_frame: None,
    disposed: false,
  }
}

///|
fn TouchScrollGesture::cancel_inertia(self : TouchScrollGesture) -> Unit {
  if self.inertia_frame is Some(frame) {
    self.inertia_frame = None
    frame.dispose()
  }
}

///|
fn TouchScrollGesture::begin_touch_event(self : TouchScrollGesture) -> Unit {
  if self.disposed {
    return
  }
  self.cancel_inertia()
}

///|
fn TouchScrollGesture::start_touch(
  self : TouchScrollGesture,
  identifier : Int,
  page_x : Double,
  page_y : Double,
  timestamp : Double,
) -> Unit {
  if self.disposed {
    return
  }
  self.active_touches[identifier] = {
    initial_page_x: page_x,
    initial_page_y: page_y,
    rolling_timestamps: [timestamp],
    rolling_page_x: [page_x],
    rolling_page_y: [page_y],
  }
}

///|
fn TouchScrollGesture::move_touch(
  self : TouchScrollGesture,
  identifier : Int,
  page_x : Double,
  page_y : Double,
  timestamp : Double,
) -> Bool {
  if self.disposed {
    return false
  }
  guard self.active_touches.get(identifier) is Some(data) else { return false }
  guard data.rolling_page_x.last() is Some(previous_x) else { return false }
  guard data.rolling_page_y.last() is Some(previous_y) else { return false }
  (self.on_translation)(page_x - previous_x, page_y - previous_y)
  // Monaco removes one sample before pushing when the history already has
  // four entries, retaining a four-point velocity window.
  if data.rolling_page_x.length() > 3 {
    data.rolling_page_x.remove(0) |> ignore
    data.rolling_page_y.remove(0) |> ignore
    data.rolling_timestamps.remove(0) |> ignore
  }
  data.rolling_page_x.push(page_x)
  data.rolling_page_y.push(page_y)
  data.rolling_timestamps.push(timestamp)
  true
}

///|
fn TouchScrollGesture::end_touch(
  self : TouchScrollGesture,
  identifier : Int,
  active_touch_count : Int,
  timestamp : Double,
) -> Bool {
  if self.disposed {
    return false
  }
  guard self.active_touches.get(identifier) is Some(data) else { return false }
  guard (data.rolling_page_x.last(), data.rolling_page_y.last())
    is (Some(final_x), Some(final_y)) else {
    self.active_touches.remove(identifier)
    return true
  }
  let moved_x = (data.initial_page_x - final_x).abs()
  let moved_y = (data.initial_page_y - final_y).abs()
  if (
      moved_x >= touch_scroll_inertia_threshold ||
      moved_y >= touch_scroll_inertia_threshold
    ) &&
    active_touch_count == 1 {
    let first_timestamp = data.rolling_timestamps[0]
    let delta_t = data.rolling_timestamps[data.rolling_timestamps.length() - 1] -
      first_timestamp
    if delta_t > 0.0 {
      let first_x = data.rolling_page_x[0]
      let first_y = data.rolling_page_y[0]
      let delta_x = final_x - first_x
      let delta_y = final_y - first_y
      self.schedule_inertia(
        timestamp,
        delta_x.abs() / delta_t,
        if delta_x > 0.0 {
          1.0
        } else {
          -1.0
        },
        delta_y.abs() / delta_t,
        if delta_y > 0.0 {
          1.0
        } else {
          -1.0
        },
      )
    }
  }
  self.active_touches.remove(identifier)
  true
}

///|
fn TouchScrollGesture::schedule_inertia(
  self : TouchScrollGesture,
  previous_timestamp : Double,
  velocity_x : Double,
  direction_x : Double,
  velocity_y : Double,
  direction_y : Double,
) -> Unit {
  if self.disposed {
    return
  }
  self.inertia_frame = Some(
    (self.runtime.schedule_at_next_animation_frame)(() => {
      self.inertia_frame = None
      if self.disposed {
        return
      }
      let now = (self.runtime.now)()
      let delta_t = now - previous_timestamp
      if delta_t <= 0.0 {
        self.schedule_inertia(
          previous_timestamp, velocity_x, direction_x, velocity_y, direction_y,
        )
        return
      }
      let next_velocity_x = velocity_x + touch_scroll_friction * delta_t
      let next_velocity_y = velocity_y + touch_scroll_friction * delta_t
      let mut translation_x = 0.0
      let mut translation_y = 0.0
      let mut stopped = true
      if next_velocity_x > 0.0 {
        stopped = false
        translation_x = direction_x * next_velocity_x * delta_t
      }
      if next_velocity_y > 0.0 {
        stopped = false
        translation_y = direction_y * next_velocity_y * delta_t
      }
      if translation_x != 0.0 || translation_y != 0.0 {
        (self.on_translation)(translation_x, translation_y)
      }
      if !stopped && !self.disposed {
        self.schedule_inertia(
          now, next_velocity_x, direction_x, next_velocity_y, direction_y,
        )
      }
    }),
  )
}

///|
fn TouchScrollGesture::cancel_touches(self : TouchScrollGesture) -> Unit {
  self.active_touches.clear()
  self.cancel_inertia()
}

///|
fn TouchScrollGesture::dispose(self : TouchScrollGesture) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel_touches()
}

///|
fn MouseHandler::install_touch_scroll_gesture(self : MouseHandler) -> Unit {
  if self.disposed || !touch_input_supported() {
    return
  }
  let gesture = TouchScrollGesture::TouchScrollGesture(
    browser_touch_scroll_runtime(),
    (translation_x, translation_y) => {
      self.apply_touch_scroll_translation(translation_x, translation_y)
    },
  )
  self.touch_scroll_gesture = Some(gesture)
  let target = self.view_helper.lines_content_dom_node
  self.add_non_passive_touch_listener(target, "touchstart", event => {
    let timestamp = @base_browser.wall_clock_now_ms()
    gesture.begin_touch_event()
    for index in 0..<touch_list_length(event, false) {
      gesture.start_touch(
        touch_identifier(event, false, index),
        touch_page_x(event, false, index),
        touch_page_y(event, false, index),
        timestamp,
      )
    }
  })
  self.add_non_passive_touch_listener(target, "touchmove", event => {
    let timestamp = @base_browser.wall_clock_now_ms()
    let mut handled = false
    for index in 0..<touch_list_length(event, true) {
      if gesture.move_touch(
          touch_identifier(event, true, index),
          touch_page_x(event, true, index),
          touch_page_y(event, true, index),
          timestamp,
        ) {
        handled = true
      }
    }
    if handled {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  self.add_non_passive_touch_listener(target, "touchend", event => {
    let timestamp = @base_browser.wall_clock_now_ms()
    let active_touch_count = gesture.active_touches.length()
    for index in 0..<touch_list_length(event, true) {
      gesture.end_touch(
        touch_identifier(event, true, index),
        active_touch_count,
        timestamp,
      )
      |> ignore
    }
  })
  self.add_non_passive_touch_listener(target, "touchcancel", _event => {
    gesture.cancel_touches()
  })
}

///|
fn MouseHandler::add_non_passive_touch_listener(
  self : MouseHandler,
  target : @rdom.Element,
  event_type : String,
  callback : (@rdom.Event) -> Unit,
) -> Unit {
  let cancel = add_non_passive_touch_listener_js(target, event_type, callback)
  self.listeners.push(@base_common.Disposable::from(cancel))
}

///|
fn MouseHandler::apply_touch_scroll_translation(
  self : MouseHandler,
  translation_x : Double,
  translation_y : Double,
) -> Unit {
  if self.disposed {
    return
  }
  guard (self.view_helper.view_layout)() is Some(view_layout) else { return }
  let previous = view_layout.position()
  view_layout.delta_scroll_now(-translation_x, -translation_y)
  if view_layout.position() != previous {
    self.view_helper.editor_scrollable.reveal_for_scroll()
  }
}

///|
extern "js" fn touch_input_supported() -> Bool =
  #| () => {
  #|   const targetWindow = globalThis.window ?? globalThis;
  #|   return "ontouchstart" in targetWindow ||
  #|     (globalThis.navigator?.maxTouchPoints ?? 0) > 0;
  #| }

///|
extern "js" fn add_non_passive_touch_listener_js(
  element : @rdom.Element,
  event_type : String,
  callback : (@rdom.Event) -> Unit,
) -> () -> Unit =
  #| (element, eventType, callback) => {
  #|   element.addEventListener(eventType, callback, { passive: false });
  #|   return () => element.removeEventListener(
  #|     eventType,
  #|     callback,
  #|     { passive: false },
  #|   );
  #| }

///|
extern "js" fn touch_list_length(event : @rdom.Event, changed : Bool) -> Int =
  #| (event, changed) =>
  #|   (changed ? event.changedTouches : event.targetTouches)?.length ?? 0

///|
extern "js" fn touch_identifier(
  event : @rdom.Event,
  changed : Bool,
  index : Int,
) -> Int =
  #| (event, changed, index) =>
  #|   (changed ? event.changedTouches : event.targetTouches).item(index).identifier

///|
extern "js" fn touch_page_x(
  event : @rdom.Event,
  changed : Bool,
  index : Int,
) -> Double =
  #| (event, changed, index) =>
  #|   (changed ? event.changedTouches : event.targetTouches).item(index).pageX

///|
extern "js" fn touch_page_y(
  event : @rdom.Event,
  changed : Bool,
  index : Int,
) -> Double =
  #| (event, changed, index) =>
  #|   (changed ? event.changedTouches : event.targetTouches).item(index).pageY
