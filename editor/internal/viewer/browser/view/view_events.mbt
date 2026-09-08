///|
/// Source-shaped configuration payload.  `changed_options` is a typed bitset
/// represented as a deduplicated array because the readonly viewer has a
/// deliberately small option surface.
struct ViewConfigurationChangedEvent {
  changed_options : Array[ViewConfigurationOption]
}

///|
pub fn ViewConfigurationChangedEvent::from_changed_options(
  changed_options : Array[ViewConfigurationOption],
) -> ViewConfigurationChangedEvent {
  let result : Array[ViewConfigurationOption] = []
  for option in changed_options {
    if !result.contains(option) {
      result.push(option)
    }
  }
  { changed_options: result, }
}

///|
fn ViewConfigurationChangedEvent::has_changed(
  self : ViewConfigurationChangedEvent,
  option : ViewConfigurationOption,
) -> Bool {
  self.changed_options.contains(option)
}

///|
/// Consumed `ViewCursorStateChangedEvent` payload. Browser view parts only use
/// the projected view-space selections; model-space selections and the cursor
/// reason remain owned by the root Viewer's public event delivery.
struct ViewCursorStateChangedEvent {
  selections : Array[@core.Selection]
}

///|
pub fn ViewCursorStateChangedEvent::ViewCursorStateChangedEvent(
  selections : Array[@core.Selection],
) -> ViewCursorStateChangedEvent {
  { selections, }
}

///|
struct ViewFocusChangedEvent {
  is_focused : Bool
}

///|
pub fn ViewFocusChangedEvent::ViewFocusChangedEvent(
  is_focused : Bool,
) -> ViewFocusChangedEvent {
  { is_focused, }
}

///|
/// Consumed `ViewScrollChangedEvent` payload. ViewLines needs the new width;
/// view parts use the four independent changed flags. The root Viewer owns the
/// complete position/dimension values used by its public scroll event.
struct ViewScrollChangedEvent {
  scroll_width : Double
  scroll_width_changed : Bool
  scroll_left_changed : Bool
  scroll_height_changed : Bool
  scroll_top_changed : Bool
}

///|
pub fn ViewScrollChangedEvent::ViewScrollChangedEvent(
  scroll_width : Double,
  scroll_width_changed : Bool,
  scroll_left_changed : Bool,
  scroll_height_changed : Bool,
  scroll_top_changed : Bool,
) -> ViewScrollChangedEvent {
  {
    scroll_width,
    scroll_width_changed,
    scroll_left_changed,
    scroll_height_changed,
    scroll_top_changed,
  }
}

///|
/// Inclusive line range carried by `ViewTokensChangedEvent`.
struct ViewTokenChangeRange {
  from_line_number : Int
  to_line_number : Int
}

///|
pub fn ViewTokenChangeRange::ViewTokenChangeRange(
  from_line_number : Int,
  to_line_number : Int,
) -> ViewTokenChangeRange {
  { from_line_number, to_line_number, }
}

///|
struct ViewTokensChangedEvent {
  ranges : Array[ViewTokenChangeRange]
}

///|
pub fn ViewTokensChangedEvent::ViewTokensChangedEvent(
  ranges : Array[ViewTokenChangeRange],
) -> ViewTokensChangedEvent {
  { ranges, }
}
