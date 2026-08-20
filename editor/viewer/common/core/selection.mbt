///|
/// The orientation of a selection: whether the active `position` is at the
/// end (`LTR`) or the start (`RTL`) of the selected range. Mirrors Monaco's
/// `SelectionDirection`.
pub(all) enum SelectionDirection {
  LTR
  RTL
} derive(Eq, Debug)

///|
/// A selection in the editor: a range that carries an orientation. Mirrors
/// Monaco's `core/selection.ts` `Selection`. Both endpoints are model
/// positions (one-based `line_number`, UTF-16 `column`); `selection_start` is
/// the fixed anchor and `position` is the moving active end (the cursor).
///
/// This is pure geometry, like `core/selection.ts`. The model/clipboard
/// boundary — normalizing to document offsets and extracting copy text — lives
/// in the controller layer (`viewer/selection.mbt`), not on this type, matching
/// Monaco's split (clipboard belongs to the editor controller, not the value
/// type).
struct Selection {
  selection_start : @base_common.Position
  position : @base_common.Position
} derive(Eq, Debug)

///|
/// Builds a selection from its anchor (`selection_start`) and active
/// (`position`) endpoints without reordering them; the orientation is kept.
pub fn Selection::Selection(
  selection_start : @base_common.Position,
  position : @base_common.Position,
) -> Selection {
  { selection_start, position }
}

///|
/// Builds a collapsed-or-oriented selection from two model positions, anchor
/// first. Mirrors Monaco's `Selection.fromPositions`.
pub fn Selection::from_positions(
  start : @base_common.Position,
  end : @base_common.Position,
) -> Selection {
  { selection_start: start, position: end }
}

///|
/// The active end of the selection (the cursor). Mirrors `getPosition`.
pub fn Selection::get_position(self : Selection) -> @base_common.Position {
  self.position
}

///|
/// The fixed anchor of the selection. Mirrors `getSelectionStart`.
pub fn Selection::get_selection_start(
  self : Selection,
) -> @base_common.Position {
  self.selection_start
}

///|
/// The ordered start position (top-left). Mirrors `Range.getStartPosition`.
pub fn Selection::start(self : Selection) -> @base_common.Position {
  if position_le(self.selection_start, self.position) {
    self.selection_start
  } else {
    self.position
  }
}

///|
/// The ordered end position (bottom-right). Mirrors `Range.getEndPosition`.
pub fn Selection::end(self : Selection) -> @base_common.Position {
  if position_le(self.selection_start, self.position) {
    self.position
  } else {
    self.selection_start
  }
}

///|
/// The orientation of the selection. Mirrors `Selection.getDirection`.
pub fn Selection::direction(self : Selection) -> SelectionDirection {
  if position_eq(self.selection_start, self.start()) {
    LTR
  } else {
    RTL
  }
}

///|
/// Whether the selection covers no text (anchor and active coincide).
pub fn Selection::is_empty(self : Selection) -> Bool {
  position_eq(self.selection_start, self.position)
}

///|
/// A copy with the ordered start moved. Mirrors `Selection.setStartPosition`:
/// the orientation is kept.
pub fn Selection::set_start_position(
  self : Selection,
  start_line_number : Int,
  start_column : Int,
) -> Selection {
  let new_start : @base_common.Position = Position(
    start_line_number, start_column,
  )
  if self.direction() == LTR {
    Selection(new_start, self.end())
  } else {
    Selection(self.end(), new_start)
  }
}

///|
/// A copy with the ordered end moved. Mirrors `Selection.setEndPosition`:
/// the orientation is kept.
pub fn Selection::set_end_position(
  self : Selection,
  end_line_number : Int,
  end_column : Int,
) -> Selection {
  let new_end : @base_common.Position = Position(end_line_number, end_column)
  if self.direction() == LTR {
    Selection(self.start(), new_end)
  } else {
    Selection(new_end, self.start())
  }
}

///|
/// Whether `a` is at or before `b` in reading order (line, then column).
fn position_le(a : @base_common.Position, b : @base_common.Position) -> Bool {
  a.is_before_or_equal(b)
}

///|
fn position_eq(a : @base_common.Position, b : @base_common.Position) -> Bool {
  a.equals(b)
}

///|
#deprecated
pub extend Selection with Debug::{to_repr}

///|
pub extend Selection with Eq::{equal, not_equal}

///|
#deprecated
pub extend SelectionDirection with Debug::{to_repr}

///|
pub extend SelectionDirection with Eq::{equal, not_equal}
