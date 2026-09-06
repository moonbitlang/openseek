///|
/// Browser-side counterpart to the common `Scrollable` model. This owns the
/// Monaco-shaped DOM shell and the custom scrollbar node geometry; callers
/// decide whether scroll positions are written back into `ViewLayout` or a
/// native content element.
struct ScrollableElementDom {
  wrapper : @rdom.Element
  content : @rdom.Element
  vertical_bar : @rdom.Element
  vertical_slider : @rdom.Element
  horizontal_bar : @rdom.Element
  horizontal_slider : @rdom.Element
  vertical_size : Double
  horizontal_size : Double
  vertical_state : @view_layout.ScrollbarState
  horizontal_state : @view_layout.ScrollbarState
  mut vertical_revealed : Bool
  mut horizontal_revealed : Bool
  mut vertical_fade : Bool
  mut horizontal_fade : Bool
  mut mouse_is_over : Bool
  mut is_dragging : Bool
  mut hide_generation : Int
  mut hide_timeout : @base_common.Disposable?
  mut disposed : Bool
}

///|
/// Returns the retained outer scrolling shell.
pub fn ScrollableElementDom::wrapper(
  self : ScrollableElementDom,
) -> @rdom.Element {
  self.wrapper
}

///|
/// Returns the retained native content element.
pub fn ScrollableElementDom::content(
  self : ScrollableElementDom,
) -> @rdom.Element {
  self.content
}

///|
pub(all) enum ScrollableElementOwner {
  EditorScrollableElement
  HoverScrollableElement
}

///|
/// An active scrollbar thumb drag. The owner tag lets gesture-scoped pointer
/// monitoring apply the resulting position to the correct scroll target.
pub(all) struct ScrollbarDrag {
  owner : ScrollableElementOwner
  vertical : Bool
  start_coord : Double
  start_orthogonal_coord : Double
  initial_state : @view_layout.ScrollbarState
}

///|
let default_scrollbar_size = 10.0

///|
let scrollbar_hide_timeout_ms = 500

///|
pub fn ScrollableElementDom::ScrollableElementDom(
  content_class : String,
  vertical_size? : Double = default_scrollbar_size,
  horizontal_size? : Double = default_scrollbar_size,
  content? : @rdom.Element,
) -> ScrollableElementDom {
  let document = @rdom.document()
  let wrapper = document.create_element("div")
  wrapper.set_attribute("class", "monaco-scrollable-element")
  wrapper.set_attribute("role", "presentation")
  let content = match content {
    Some(content) => content
    None => document.create_element("div")
  }
  content.set_attribute("class", content_class)
  let horizontal_bar = document.create_element("div")
  horizontal_bar.set_attribute("class", "scrollbar horizontal invisible")
  horizontal_bar.set_attribute("role", "presentation")
  horizontal_bar.set_attribute("aria-hidden", "true")
  let horizontal_slider = document.create_element("div")
  horizontal_slider.set_attribute("class", "slider")
  horizontal_bar.append_child(horizontal_slider.as_node())
  let vertical_bar = document.create_element("div")
  vertical_bar.set_attribute("class", "scrollbar vertical invisible")
  vertical_bar.set_attribute("role", "presentation")
  vertical_bar.set_attribute("aria-hidden", "true")
  let vertical_slider = document.create_element("div")
  vertical_slider.set_attribute("class", "slider")
  vertical_bar.append_child(vertical_slider.as_node())
  wrapper.append_child(content.as_node())
  wrapper.append_child(horizontal_bar.as_node())
  wrapper.append_child(vertical_bar.as_node())
  {
    wrapper,
    content,
    vertical_bar,
    vertical_slider,
    horizontal_bar,
    horizontal_slider,
    vertical_size,
    horizontal_size,
    vertical_state: ScrollbarState(scrollbar_size=vertical_size),
    horizontal_state: ScrollbarState(
      scrollbar_size=horizontal_size,
      opposite_scrollbar_size=vertical_size,
    ),
    vertical_revealed: false,
    horizontal_revealed: false,
    vertical_fade: false,
    horizontal_fade: false,
    mouse_is_over: false,
    is_dragging: false,
    hide_generation: 0,
    hide_timeout: None,
    disposed: false,
  }
}

///|
fn ScrollableElementDom::cancel_hide_timeout(
  self : ScrollableElementDom,
) -> Unit {
  if self.hide_timeout is Some(timeout) {
    timeout.dispose()
  }
  self.hide_timeout = None
  self.hide_generation += 1
}

///|
/// Cancels delayed visibility work. DOM removal remains the owner's
/// responsibility because editor and hover scrollables have different hosts.
pub fn ScrollableElementDom::dispose(self : ScrollableElementDom) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel_hide_timeout()
  self.is_dragging = false
  self.set_slider_active(vertical=true, false)
  self.set_slider_active(vertical=false, false)
}

///|
pub fn ScrollableElementDom::set_wrapper_class(
  self : ScrollableElementDom,
  class_name : String,
) -> Unit {
  self.wrapper.set_attribute("class", class_name)
}

///|
pub fn ScrollableElementDom::update_from_model(
  self : ScrollableElementDom,
  dimensions : @view_layout.ScrollDimensions,
  position : @view_layout.ScrollPosition,
  horizontal_left? : Double,
) -> Unit {
  self.vertical_state.set_visible_size(dimensions.height) |> ignore
  self.vertical_state.set_scroll_size(dimensions.scroll_height) |> ignore
  self.vertical_state.set_scroll_position(position.scroll_top) |> ignore
  self.write_vertical_bar()
  self.horizontal_state.set_visible_size(dimensions.width) |> ignore
  self.horizontal_state.set_scroll_size(dimensions.scroll_width) |> ignore
  self.horizontal_state.set_scroll_position(position.scroll_left) |> ignore
  self.write_horizontal_bar(horizontal_left?)
}

///|
pub fn ScrollableElementDom::update_from_native_content(
  self : ScrollableElementDom,
) -> Unit {
  let content_rect = self.content.get_bounding_client_rect()
  self.update_from_model(
    {
      width: content_rect.get_width(),
      scroll_width: self.content.get_scroll_width(),
      height: content_rect.get_height(),
      scroll_height: self.content.get_scroll_height(),
    },
    {
      scroll_left: self.content.get_scroll_left(),
      scroll_top: self.content.get_scroll_top(),
    },
  )
}

///|
fn ScrollableElementDom::write_vertical_bar(
  self : ScrollableElementDom,
) -> Unit {
  let needed = self.vertical_state.is_needed()
  if !needed {
    self.set_bar_visibility(vertical=true, revealed=false, fade=false)
  }
  self.vertical_bar.set_attribute(
    "class",
    self.scrollbar_class(vertical=true, needed~),
  )
  self.vertical_bar.set_attribute(
    "style",
    "width:\{self.vertical_size.to_string()}px;height:\{self.vertical_state.rectangle_large_size().to_string()}px;right:0px;top:0px",
  )
  self.vertical_slider.set_attribute(
    "style",
    if needed {
      "width:\{self.vertical_size.to_string()}px;height:\{self.vertical_state.slider_size().to_string()}px;transform:translateY(\{self.vertical_state.slider_position().to_string()}px)"
    } else {
      ""
    },
  )
}

///|
fn ScrollableElementDom::write_horizontal_bar(
  self : ScrollableElementDom,
  horizontal_left? : Double,
) -> Unit {
  let needed = self.horizontal_state.is_needed()
  if !needed {
    self.set_bar_visibility(vertical=false, revealed=false, fade=false)
  }
  self.horizontal_bar.set_attribute(
    "class",
    self.scrollbar_class(vertical=false, needed~),
  )
  let mut bar_style = "height:\{self.horizontal_size.to_string()}px;width:\{self.horizontal_state.rectangle_large_size().to_string()}px;bottom:0px"
  if horizontal_left is Some(left) {
    bar_style = "\{bar_style};left:\{left.to_string()}px"
  }
  self.horizontal_bar.set_attribute("style", bar_style)
  self.horizontal_slider.set_attribute(
    "style",
    if needed {
      "height:\{self.horizontal_size.to_string()}px;width:\{self.horizontal_state.slider_size().to_string()}px;transform:translateX(\{self.horizontal_state.slider_position().to_string()}px)"
    } else {
      ""
    },
  )
}

///|
fn ScrollableElementDom::scrollbar_class(
  self : ScrollableElementDom,
  vertical~ : Bool,
  needed~ : Bool,
) -> String {
  let axis = if vertical { "vertical" } else { "horizontal" }
  if needed && self.bar_is_revealed(vertical) {
    "visible scrollbar \{axis}"
  } else {
    let mut class_name = "invisible scrollbar \{axis}"
    if needed && self.bar_has_fade(vertical) {
      class_name = "\{class_name} fade"
    }
    class_name
  }
}

///|
fn ScrollableElementDom::bar_is_revealed(
  self : ScrollableElementDom,
  vertical : Bool,
) -> Bool {
  if vertical {
    self.vertical_revealed
  } else {
    self.horizontal_revealed
  }
}

///|
fn ScrollableElementDom::bar_has_fade(
  self : ScrollableElementDom,
  vertical : Bool,
) -> Bool {
  if vertical {
    self.vertical_fade
  } else {
    self.horizontal_fade
  }
}

///|
fn ScrollableElementDom::set_bar_visibility(
  self : ScrollableElementDom,
  vertical~ : Bool,
  revealed~ : Bool,
  fade~ : Bool,
) -> Unit {
  if vertical {
    self.vertical_revealed = revealed
    self.vertical_fade = fade
  } else {
    self.horizontal_revealed = revealed
    self.horizontal_fade = fade
  }
}

///|
fn ScrollableElementDom::write_bar_visibility_class(
  self : ScrollableElementDom,
  vertical : Bool,
) -> Unit {
  let needed = self.state(vertical).is_needed()
  self
  .track(vertical)
  .set_attribute("class", self.scrollbar_class(vertical~, needed~))
}

///|
fn ScrollableElementDom::reveal_scrollbars(self : ScrollableElementDom) -> Unit {
  if self.disposed {
    return
  }
  self.cancel_hide_timeout()
  if self.vertical_state.is_needed() {
    self.set_bar_visibility(vertical=true, revealed=true, fade=false)
    self.write_bar_visibility_class(true)
  }
  if self.horizontal_state.is_needed() {
    self.set_bar_visibility(vertical=false, revealed=true, fade=false)
    self.write_bar_visibility_class(false)
  }
}

///|
fn ScrollableElementDom::hide_scrollbars_if_idle(
  self : ScrollableElementDom,
) -> Unit {
  if self.disposed || self.mouse_is_over || self.is_dragging {
    return
  }
  self.set_bar_visibility(
    vertical=true,
    revealed=false,
    fade=self.vertical_state.is_needed(),
  )
  self.set_bar_visibility(
    vertical=false,
    revealed=false,
    fade=self.horizontal_state.is_needed(),
  )
  self.write_bar_visibility_class(true)
  self.write_bar_visibility_class(false)
}

///|
fn ScrollableElementDom::schedule_hide_scrollbars(
  self : ScrollableElementDom,
) -> Unit {
  if self.disposed || self.mouse_is_over || self.is_dragging {
    return
  }
  self.cancel_hide_timeout()
  let generation = self.hide_generation
  self.hide_timeout = Some(
    @base_browser.schedule_timeout(
      () => {
        if !self.disposed && self.hide_generation == generation {
          self.hide_timeout = None
          self.hide_scrollbars_if_idle()
        }
      },
      scrollbar_hide_timeout_ms,
    ),
  )
}

///|
pub fn ScrollableElementDom::reveal_for_scroll(
  self : ScrollableElementDom,
) -> Unit {
  if self.disposed {
    return
  }
  self.reveal_scrollbars()
  self.schedule_hide_scrollbars()
}

///|
pub fn ScrollableElementDom::mouse_entered(self : ScrollableElementDom) -> Unit {
  if self.disposed || self.mouse_is_over {
    return
  }
  self.mouse_is_over = true
  self.reveal_scrollbars()
}

///|
pub fn ScrollableElementDom::mouse_left(self : ScrollableElementDom) -> Unit {
  if self.disposed {
    return
  }
  self.mouse_is_over = false
  self.hide_scrollbars_if_idle()
}

///|
pub fn ScrollableElementDom::drag_started(self : ScrollableElementDom) -> Unit {
  if self.disposed {
    return
  }
  self.is_dragging = true
  self.reveal_scrollbars()
}

///|
pub fn ScrollableElementDom::drag_ended(self : ScrollableElementDom) -> Unit {
  if self.disposed {
    return
  }
  self.is_dragging = false
  self.hide_scrollbars_if_idle()
}

///|
pub fn ScrollableElementDom::state(
  self : ScrollableElementDom,
  vertical : Bool,
) -> @view_layout.ScrollbarState {
  if vertical {
    self.vertical_state
  } else {
    self.horizontal_state
  }
}

///|
pub fn ScrollableElementDom::track(
  self : ScrollableElementDom,
  vertical : Bool,
) -> @rdom.Element {
  if vertical {
    self.vertical_bar
  } else {
    self.horizontal_bar
  }
}

///|
pub fn ScrollableElementDom::slider(
  self : ScrollableElementDom,
  vertical : Bool,
) -> @rdom.Element {
  if vertical {
    self.vertical_slider
  } else {
    self.horizontal_slider
  }
}

///|
pub fn ScrollableElementDom::desired_position_from_track(
  self : ScrollableElementDom,
  vertical~ : Bool,
  mouse : @rdom.MouseEvent,
) -> Double {
  let rect = self.track(vertical).get_bounding_client_rect()
  let offset = if vertical {
    mouse.get_client_y() - rect.get_top()
  } else {
    mouse.get_client_x() - rect.get_left()
  }
  self.state(vertical).desired_position_from_offset(offset)
}

///|
pub fn ScrollableElementDom::set_slider_active(
  self : ScrollableElementDom,
  vertical~ : Bool,
  active : Bool,
) -> Unit {
  let slider = self.slider(vertical)
  if active {
    slider.set_attribute("class", "slider active")
  } else {
    slider.set_attribute("class", "slider")
  }
}

///|
pub fn ScrollableElementDom::native_scroll_to(
  self : ScrollableElementDom,
  vertical~ : Bool,
  position : Double,
) -> Unit {
  if vertical {
    self.content.set_scroll_top(position)
  } else {
    self.content.set_scroll_left(position)
  }
  self.update_from_native_content()
  self.reveal_for_scroll()
}

///|
pub fn ScrollableElementDom::native_scroll_by(
  self : ScrollableElementDom,
  delta_left? : Double = 0.0,
  delta_top? : Double = 0.0,
) -> Unit {
  self.content.set_scroll_top(self.content.get_scroll_top() + delta_top)
  self.content.set_scroll_left(self.content.get_scroll_left() + delta_left)
  self.update_from_native_content()
  self.reveal_for_scroll()
}

///|
pub fn ScrollableElementDom::native_page_delta(
  self : ScrollableElementDom,
) -> Double {
  self.content.get_bounding_client_rect().get_height()
}

///|
/// `SCROLL_WHEEL_SENSITIVITY` (scrollableElement.ts): pixels scrolled per
/// normalized wheel unit.
let scroll_wheel_sensitivity : Double = 50.0

///|
/// The wheel-delta computation of `ScrollableElement._onMouseWheel`
/// (scrollableElement.ts): `mouseWheelScrollSensitivity` scaling,
/// `scrollPredominantAxis` filtering, the non-mac shift-to-horizontal
/// conversion, alt-key `fastScrollSensitivity`, then
/// `SCROLL_WHEEL_SENSITIVITY` with away-from-zero rounding so low-speed
/// scrolling still moves a whole pixel. Answers pixel deltas to add to the
/// scroll position — the sign flip back out of wheel units is Monaco's
/// `futureScrollPosition.scrollTop - deltaScrollTop`. Option defaults mirror
/// `resolveOptions`. The editor controller uses these deltas for both the
/// classified physical-wheel smooth path and the trackpad immediate path.
pub fn mouse_wheel_scroll_deltas(
  event : StandardWheelEvent,
  alt_key? : Bool = false,
  shift_key? : Bool = false,
  mouse_wheel_scroll_sensitivity? : Double = 1.0,
  fast_scroll_sensitivity? : Double = 5.0,
  scroll_predominant_axis? : Bool = true,
) -> (Double, Double) {
  let mut delta_y = event.delta_y * mouse_wheel_scroll_sensitivity
  let mut delta_x = event.delta_x * mouse_wheel_scroll_sensitivity
  if scroll_predominant_axis {
    if delta_y.abs() >= delta_x.abs() {
      delta_x = 0.0
    } else {
      delta_y = 0.0
    }
  }
  // Convert vertical scrolling to horizontal if shift is held, this
  // is handled at a higher level on Mac
  let shift_convert = !@base_common.is_macintosh && shift_key
  if shift_convert && delta_x == 0.0 {
    delta_x = delta_y
    delta_y = 0.0
  }
  if alt_key {
    // fastScrolling
    delta_x *= fast_scroll_sensitivity
    delta_y *= fast_scroll_sensitivity
  }
  (
    -away_from_zero(scroll_wheel_sensitivity * delta_x),
    -away_from_zero(scroll_wheel_sensitivity * delta_y),
  )
}

///|
/// `deltaScrollTop < 0 ? Math.floor(...) : Math.ceil(...)` — "Here we convert
/// values such as -0.3 to -1 or 0.3 to 1, otherwise low speed scrolling will
/// never scroll".
fn away_from_zero(value : Double) -> Double {
  if value < 0.0 {
    value.floor()
  } else {
    value.ceil()
  }
}

///|
pub fn drag_coord(mouse : @rdom.MouseEvent, vertical : Bool) -> Double {
  if vertical {
    mouse.get_client_y()
  } else {
    mouse.get_client_x()
  }
}
