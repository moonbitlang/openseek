///|
/// How a selection was anchored, mirroring Monaco's `SelectionStartKind`. A
/// plain click anchors `Simple`; double/triple-click anchors `Word`/`Line`, and
/// continuation gestures preserve and extend the corresponding anchor range.
pub(all) enum SelectionStartKind {
  Simple
  Word
  Line
} derive(Eq, Debug)

///|
/// The cursor state on either the model or the view model, a faithful port of
/// Monaco's `cursorCommon.ts` `SingleCursorState`. `selection_start` is the
/// anchor *range* (a region for word/line selection, collapsed for simple) and
/// `position` is the moving active end; the derived `selection` carries the
/// orientation. Positions are one-based (`line_number`, UTF-16 `column`),
/// matching Monaco's `Position`.
///
/// The two leftover-visible-column fields retain the desired visual column
/// while vertical movement crosses lines of different widths. The anchor-side
/// value is preserved while extending a selection; collapsing a selection
/// replaces both values with the active movement residue.
pub struct SingleCursorState {
  selection_start_start : @base_common.Position
  selection_start_end : @base_common.Position
  selection_start_kind : SelectionStartKind
  selection_start_leftover_visible_columns : Int
  position : @base_common.Position
  leftover_visible_columns : Int
} derive(Eq, Debug)

///|
/// Builds a cursor state from an explicit anchor range and active position.
pub fn SingleCursorState::SingleCursorState(
  selection_start_start : @base_common.Position,
  selection_start_end : @base_common.Position,
  selection_start_kind : SelectionStartKind,
  position : @base_common.Position,
  selection_start_leftover_visible_columns? : Int = 0,
  leftover_visible_columns? : Int = 0,
) -> SingleCursorState {
  {
    selection_start_start,
    selection_start_end,
    selection_start_kind,
    selection_start_leftover_visible_columns,
    position,
    leftover_visible_columns,
  }
}

///|
/// A collapsed cursor at `position` (anchor and active coincide, `Simple`).
fn SingleCursorState::collapsed(
  position : @base_common.Position,
) -> SingleCursorState {
  SingleCursorState(position, position, Simple, position)
}

///|
/// Whether the anchor range is collapsed to a point.
fn SingleCursorState::selection_start_is_empty(
  self : SingleCursorState,
) -> Bool {
  self.selection_start_start.equals(self.selection_start_end)
}

///|
/// The derived selection (anchor, active) carrying orientation. Transcribes
/// Monaco's `SingleCursorState._computeSelection`: an active end strictly after
/// the anchor's start uses that start as the selection anchor; equality or a
/// position before the start (selecting backward over a word/line) uses the
/// anchor range's end.
pub fn SingleCursorState::selection(
  self : SingleCursorState,
) -> @core.Selection {
  if self.selection_start_is_empty() ||
    not_before_or_equal(self.position, self.selection_start_start) {
    Selection(self.selection_start_start, self.position)
  } else {
    Selection(self.selection_start_end, self.position)
  }
}

///|
/// Whether this state selects any text (mirrors Monaco `hasSelection`).
pub fn SingleCursorState::has_selection(self : SingleCursorState) -> Bool {
  !self.selection().is_empty() || !self.selection_start_is_empty()
}

///|
/// Moves the cursor, transcribing Monaco's `SingleCursorState.move` (`move` is
/// a reserved word here). In selection mode only the active `position` moves
/// (the anchor is kept); out of selection mode the whole state collapses to the
/// new point.
pub fn SingleCursorState::moved(
  self : SingleCursorState,
  in_selection_mode : Bool,
  position : @base_common.Position,
  leftover_visible_columns? : Int = 0,
) -> SingleCursorState {
  if in_selection_mode {
    { ..self, position, leftover_visible_columns }
  } else {
    SingleCursorState(
      position,
      position,
      Simple,
      position,
      selection_start_leftover_visible_columns=leftover_visible_columns,
      leftover_visible_columns~,
    )
  }
}

///|
/// Whether `a` is strictly after `b` in reading order, i.e. `!a.isBeforeOrEqual(b)`.
fn not_before_or_equal(
  a : @base_common.Position,
  b : @base_common.Position,
) -> Bool {
  !a.is_before_or_equal(b)
}

///|
pub extend SelectionStartKind with Debug::{to_repr}

///|
pub extend SelectionStartKind with Eq::{equal, not_equal}

///|
pub extend SingleCursorState with Debug::{to_repr}

///|
pub extend SingleCursorState with Eq::{equal, not_equal}
