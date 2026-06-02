// Mapping a `@surface.Surface` onto physical terminal rows. Placement pairs
// terminal-agnostic surface content with the first physical row where it is
// drawn, so it belongs to the renderer rather than the surface vocabulary.

///|
/// A surface after terminal placement. `top` is the 1-based terminal row where
/// the surface's row 0 is drawn; height comes from the surface itself.
priv struct PlacedSurface {
  surface : @surface.Surface
  top : Int
}

///|
/// The surface line shown at terminal row `row`. `None` when the row falls
/// outside the placed surface's own rows.
fn PlacedSurface::line_at_terminal_row(
  self : PlacedSurface,
  row~ : Int,
) -> @surface.Line? {
  let index = row - self.top
  if index >= 0 && index < self.surface.height() {
    Some(self.surface.line_at(index))
  } else {
    None
  }
}

///|
/// Whether two surfaces place the cursor on the same physical cell, accounting
/// for each surface's placement.
fn PlacedSurface::same_terminal_cursor(
  self : PlacedSurface,
  other : PlacedSurface,
) -> Bool {
  self.cursor_terminal_row() == other.cursor_terminal_row() &&
  self.cursor_terminal_col() == other.cursor_terminal_col()
}

///|
/// The cursor row in 1-based terminal coordinates.
fn PlacedSurface::cursor_terminal_row(self : PlacedSurface) -> Int {
  self.top + self.surface.cursor().row()
}

///|
/// The cursor column in 1-based terminal coordinates.
fn PlacedSurface::cursor_terminal_col(self : PlacedSurface) -> Int {
  1 + self.surface.cursor().col()
}
