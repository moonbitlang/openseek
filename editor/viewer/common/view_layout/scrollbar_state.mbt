///|
/// The minimal thumb length, artificially enlarged so it stays clickable.
let minimum_slider_size = 20.0

///|
/// Custom-scrollbar geometry, the Monaco `ScrollbarState` role: pure
/// arithmetic between scroll state and slider (thumb) geometry along one
/// axis. For the vertical bar the "size" axis is height and the slider
/// moves with `scroll_top`; for the horizontal bar substitute width and
/// `scroll_left`. Pixel inputs round to whole CSS pixels like the
/// reference.
struct ScrollbarState {
  arrow_size : Double
  scrollbar_size : Double
  opposite_scrollbar_size : Double
  mut visible_size : Double
  mut scroll_size : Double
  mut scroll_position : Double
  mut computed_available_size : Double
  mut computed_is_needed : Bool
  mut computed_slider_size : Double
  mut computed_slider_ratio : Double
  mut computed_slider_position : Double
}

///|
/// Creates scrollbar geometry state for one axis.
pub fn ScrollbarState::ScrollbarState(
  arrow_size~ : Double = 0.0,
  scrollbar_size~ : Double,
  opposite_scrollbar_size~ : Double = 0.0,
) -> ScrollbarState {
  let state : ScrollbarState = {
    arrow_size: arrow_size.round(),
    scrollbar_size: scrollbar_size.round(),
    opposite_scrollbar_size: opposite_scrollbar_size.round(),
    visible_size: 0.0,
    scroll_size: 0.0,
    scroll_position: 0.0,
    computed_available_size: 0.0,
    computed_is_needed: false,
    computed_slider_size: 0.0,
    computed_slider_ratio: 0.0,
    computed_slider_position: 0.0,
  }
  state.refresh()
  state
}

///|
/// Field-for-field geometry snapshot used by pointer gestures. Monaco's
/// `AbstractScrollbar._sliderPointerDown` clones its state before monitoring
/// so later layout mutations cannot change the drag mapping.
pub fn ScrollbarState::clone(self : ScrollbarState) -> ScrollbarState {
  {
    arrow_size: self.arrow_size,
    scrollbar_size: self.scrollbar_size,
    opposite_scrollbar_size: self.opposite_scrollbar_size,
    visible_size: self.visible_size,
    scroll_size: self.scroll_size,
    scroll_position: self.scroll_position,
    computed_available_size: self.computed_available_size,
    computed_is_needed: self.computed_is_needed,
    computed_slider_size: self.computed_slider_size,
    computed_slider_ratio: self.computed_slider_ratio,
    computed_slider_position: self.computed_slider_position,
  }
}

///|
/// The viewport extent along this scrollbar's axis. Answers whether the
/// geometry changed.
pub fn ScrollbarState::set_visible_size(
  self : ScrollbarState,
  visible_size : Double,
) -> Bool {
  let rounded = visible_size.round()
  if self.visible_size != rounded {
    self.visible_size = rounded
    self.refresh()
    true
  } else {
    false
  }
}

///|
/// The content extent along this scrollbar's axis.
pub fn ScrollbarState::set_scroll_size(
  self : ScrollbarState,
  scroll_size : Double,
) -> Bool {
  let rounded = scroll_size.round()
  if self.scroll_size != rounded {
    self.scroll_size = rounded
    self.refresh()
    true
  } else {
    false
  }
}

///|
/// Sets the scroll position along this axis. Answers whether geometry changed.
pub fn ScrollbarState::set_scroll_position(
  self : ScrollbarState,
  scroll_position : Double,
) -> Bool {
  let rounded = scroll_position.round()
  if self.scroll_position != rounded {
    self.scroll_position = rounded
    self.refresh()
    true
  } else {
    false
  }
}

///|
/// Current scroll position along this axis.
pub fn ScrollbarState::scroll_position(self : ScrollbarState) -> Double {
  self.scroll_position
}

///|
/// Whether the content overflows the viewport on this axis.
pub fn ScrollbarState::is_needed(self : ScrollbarState) -> Bool {
  self.computed_is_needed
}

///|
/// The track length: the viewport minus the paired scrollbar's thickness.
pub fn ScrollbarState::rectangle_large_size(self : ScrollbarState) -> Double {
  self.computed_available_size
}

///|
/// The scrollbar's thickness.
pub fn ScrollbarState::rectangle_small_size(self : ScrollbarState) -> Double {
  self.scrollbar_size
}

///|
/// Computed slider length in CSS pixels.
pub fn ScrollbarState::slider_size(self : ScrollbarState) -> Double {
  self.computed_slider_size
}

///|
/// Computed slider offset inside the track.
pub fn ScrollbarState::slider_position(self : ScrollbarState) -> Double {
  self.computed_slider_position
}

///|
/// The scroll position that centers the slider on a track offset: track
/// page jumps that land the thumb under the mouse.
pub fn ScrollbarState::desired_position_from_offset(
  self : ScrollbarState,
  offset : Double,
) -> Double {
  if !self.computed_is_needed {
    return 0.0
  }
  let desired_slider_position = offset -
    self.arrow_size -
    self.computed_slider_size / 2.0
  (desired_slider_position / self.computed_slider_ratio).round()
}

///|
/// The scroll position one page up or down from the current one,
/// depending on whether the track offset is before or after the slider.
pub fn ScrollbarState::desired_position_from_offset_paged(
  self : ScrollbarState,
  offset : Double,
) -> Double {
  if !self.computed_is_needed {
    return 0.0
  }
  let corrected_offset = offset - self.arrow_size
  if corrected_offset < self.computed_slider_position {
    self.scroll_position - self.visible_size
  } else {
    self.scroll_position + self.visible_size
  }
}

///|
/// The scroll position that moves the slider by `delta` track pixels:
/// wheel-style relative moves.
pub fn ScrollbarState::desired_position_from_delta(
  self : ScrollbarState,
  delta : Double,
) -> Double {
  if !self.computed_is_needed {
    return 0.0
  }
  let desired_slider_position = self.computed_slider_position + delta
  (desired_slider_position / self.computed_slider_ratio).round()
}

///|
/// The scroll position that puts the slider at an absolute track
/// position: thumb drags track the slider position captured at drag
/// start plus the pointer travel, like the reference.
pub fn ScrollbarState::desired_position_from_slider(
  self : ScrollbarState,
  slider_position : Double,
) -> Double {
  if !self.computed_is_needed {
    return 0.0
  }
  (slider_position / self.computed_slider_ratio).round()
}

///|
fn ScrollbarState::refresh(self : ScrollbarState) -> Unit {
  let computed_available_size = 0.0.max(
    self.visible_size - self.opposite_scrollbar_size,
  )
  let computed_representable_size = 0.0.max(
    computed_available_size - 2.0 * self.arrow_size,
  )
  let computed_is_needed = self.scroll_size > 0.0 &&
    self.scroll_size > self.visible_size
  if !computed_is_needed {
    self.computed_available_size = computed_available_size.round()
    self.computed_is_needed = false
    self.computed_slider_size = computed_representable_size.round()
    self.computed_slider_ratio = 0.0
    self.computed_slider_position = 0.0
    return
  }
  // Artificially enlarge a too-small thumb so the mouse can grab it.
  let computed_slider_size = minimum_slider_size
    .max(
      (self.visible_size * computed_representable_size / self.scroll_size).floor(),
    )
    .round()
  // The slider moves over `representable - slider` as the position moves
  // over `scroll - visible`.
  let computed_slider_ratio = (
      computed_representable_size - computed_slider_size
    ) /
    (self.scroll_size - self.visible_size)
  self.computed_available_size = computed_available_size.round()
  self.computed_is_needed = true
  self.computed_slider_size = computed_slider_size
  self.computed_slider_ratio = computed_slider_ratio
  self.computed_slider_position = (self.scroll_position * computed_slider_ratio).round()
}
