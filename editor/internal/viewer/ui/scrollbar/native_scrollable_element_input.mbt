///|
/// One native-content scrollbar input lifetime. Editor scrollbars write into
/// `ViewLayout`; this adapter is for a `ScrollableElementDom` whose content
/// element owns its browser scroll offsets, such as hover or Peek results.
///
/// Pointer behavior deliberately matches the shared `MouseHandler` scrollbar
/// path: hover reveals the rails, track presses jump to the pointer, thumb
/// drags retain the pointerdown geometry, and Windows resets a drag after the
/// pointer moves more than 140 px away from the rail.
struct NativeScrollableElementInput {
  scrollable : ScrollableElementDom
  pointer_monitor : @base_browser.GlobalPointerMoveMonitor
  listeners : Array[@base_common.Disposable]
  mut resize_observer : @base_common.Disposable?
  mut drag : NativeScrollbarDrag?
  mut disposed : Bool
}

///|
priv struct NativeScrollbarDrag {
  vertical : Bool
  start_coord : Double
  start_orthogonal_coord : Double
  initial_state : @view_layout.ScrollbarState
}

///|
/// Installs native scroll synchronization plus the shared rail/thumb gestures.
/// The caller still owns where the wrapper is mounted.
#alias(new, deprecated)
pub fn NativeScrollableElementInput::NativeScrollableElementInput(
  scrollable : ScrollableElementDom,
) -> NativeScrollableElementInput {
  let input : NativeScrollableElementInput = {
    scrollable,
    pointer_monitor: GlobalPointerMoveMonitor(),
    listeners: [],
    resize_observer: None,
    drag: None,
    disposed: false,
  }
  input.install_listeners()
  input.resize_observer = @base_browser.observe_element_resize(
    scrollable.wrapper,
    () => input.refresh(),
  )
  input
}

///|
/// Re-reads the native viewport, content extent, and current offsets.
pub fn NativeScrollableElementInput::refresh(
  self : NativeScrollableElementInput,
) -> Unit {
  if !self.disposed {
    self.scrollable.update_from_native_content()
  }
}

///|
/// Removes every listener and pending pointer/resize lifetime exactly once.
pub fn NativeScrollableElementInput::dispose(
  self : NativeScrollableElementInput,
) -> Unit {
  if self.disposed {
    return
  }
  self.end_drag()
  self.disposed = true
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  self.resize_observer = None
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
  self.pointer_monitor.dispose()
  self.scrollable.dispose()
}

///|
fn NativeScrollableElementInput::install_listeners(
  self : NativeScrollableElementInput,
) -> Unit {
  self.listen(self.scrollable.wrapper, "mouseover", _ => {
    self.scrollable.mouse_entered()
  })
  self.listen(self.scrollable.wrapper, "mousemove", _ => {
    self.scrollable.mouse_entered()
  })
  self.listen(self.scrollable.wrapper, "mouseleave", _ => {
    self.scrollable.mouse_left()
  })
  self.listen(self.scrollable.content, "scroll", _ => {
    if !self.disposed {
      self.scrollable.update_from_native_content()
      self.scrollable.reveal_for_scroll()
    }
  })
  self.install_axis(vertical=true)
  self.install_axis(vertical=false)
}

///|
fn NativeScrollableElementInput::install_axis(
  self : NativeScrollableElementInput,
  vertical~ : Bool,
) -> Unit {
  let slider = self.scrollable.slider(vertical)
  self.listen(slider, "pointerdown", event => {
    match event.to_mouse_event() {
      Some(mouse) if mouse.get_button() == 0 => {
        event.prevent_default()
        event.stop_propagation()
        self.start_drag(vertical~, mouse)
      }
      _ => ()
    }
  })
  self.listen(slider, "click", event => {
    match event.to_mouse_event() {
      Some(mouse) if mouse.get_button() == 0 => event.stop_propagation()
      _ => ()
    }
  })
  self.listen(self.scrollable.track(vertical), "pointerdown", event => {
    match event.to_mouse_event() {
      Some(mouse) => {
        event.prevent_default()
        event.stop_propagation()
        let desired = self.scrollable.desired_position_from_track(
          vertical~,
          mouse,
        )
        self.scrollable.native_scroll_to(vertical~, desired)
      }
      None => ()
    }
  })
}

///|
fn NativeScrollableElementInput::listen(
  self : NativeScrollableElementInput,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn NativeScrollableElementInput::start_drag(
  self : NativeScrollableElementInput,
  vertical~ : Bool,
  mouse : @rdom.MouseEvent,
) -> Unit {
  if self.disposed {
    return
  }
  guard mouse.target().to_element() is Some(initial_element) else { return }
  self.end_drag()
  self.drag = Some({
    vertical,
    start_coord: drag_coord(mouse, vertical),
    start_orthogonal_coord: native_scrollbar_orthogonal_coord(mouse, vertical),
    initial_state: self.scrollable.state(vertical).clone(),
  })
  self.scrollable.set_slider_active(vertical~, true)
  self.pointer_monitor.start_monitoring(
    initial_element,
    @base_browser.mouse_event_pointer_id(mouse),
    mouse.get_buttons(),
    moved => self.handle_drag_move(moved),
    _ => self.end_drag(),
  )
  self.scrollable.drag_started()
}

///|
fn NativeScrollableElementInput::handle_drag_move(
  self : NativeScrollableElementInput,
  mouse : @rdom.MouseEvent,
) -> Unit {
  guard !self.disposed && self.drag is Some(drag) else { return }
  mouse.prevent_default()
  let orthogonal_coord = native_scrollbar_orthogonal_coord(mouse, drag.vertical)
  let desired = if native_scrollbar_drag_should_reset(
      drag.start_orthogonal_coord,
      orthogonal_coord,
    ) {
    drag.initial_state.scroll_position()
  } else {
    drag.initial_state.desired_position_from_delta(
      drag_coord(mouse, drag.vertical) - drag.start_coord,
    )
  }
  self.scrollable.native_scroll_to(vertical=drag.vertical, desired)
}

///|
fn NativeScrollableElementInput::end_drag(
  self : NativeScrollableElementInput,
) -> Unit {
  self.pointer_monitor.stop_monitoring(false)
  match self.drag {
    Some(drag) => {
      self.scrollable.set_slider_active(vertical=drag.vertical, false)
      self.scrollable.drag_ended()
    }
    None => ()
  }
  self.drag = None
}

///|
fn native_scrollbar_orthogonal_coord(
  mouse : @rdom.MouseEvent,
  vertical : Bool,
) -> Double {
  if vertical {
    mouse.get_client_x()
  } else {
    mouse.get_client_y()
  }
}

///|
fn native_scrollbar_drag_should_reset(
  initial_orthogonal_coord : Double,
  current_orthogonal_coord : Double,
) -> Bool {
  @base_common.platform_is_win32() &&
  (current_orthogonal_coord - initial_orthogonal_coord).abs() > 140.0
}
