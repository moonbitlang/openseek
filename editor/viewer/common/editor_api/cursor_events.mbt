///|
/// Why a cursor transition occurred, Monaco's `CursorChangeReason`
/// (`cursorEvents.ts`). Readonly producers use `NotSet` for API defaults,
/// `Explicit` for keyboard/pointer gestures, and `ContentFlush` for whole-model
/// replacement; the remaining values are accepted caller metadata.
pub(all) enum CursorChangeReason {
  NotSet
  ContentFlush
  RecoverFromMarkers
  Explicit
  Paste
  Undo
  Redo
} derive(Eq, Debug)

///|
/// Monaco's `ICursorPositionChangedEvent`. The viewer is single-cursor, so
/// `secondary_positions` is always empty.
pub(all) struct CursorPositionChangedEvent {
  position : @base_common.Position
  secondary_positions : Array[@base_common.Position]
  reason : CursorChangeReason
  source : String
} derive(Debug)

///|
/// Monaco's `ICursorSelectionChangedEvent`, reduced to the viewer's
/// single-cursor contract. `old_selections` is absent for a content flush and
/// contains the former primary selection for ordinary transitions.
pub(all) struct CursorSelectionChangedEvent {
  selection : @core.Selection
  secondary_selections : Array[@core.Selection]
  model_version_id : Int
  old_selections : Array[@core.Selection]?
  old_model_version_id : Int
  source : String
  reason : CursorChangeReason
} derive(Debug)

///|
#deprecated
pub extend CursorChangeReason with Debug::{to_repr}

///|
pub extend CursorChangeReason with Eq::{equal, not_equal}

///|
#deprecated
pub extend CursorPositionChangedEvent with Debug::{to_repr}

///|
#deprecated
pub extend CursorSelectionChangedEvent with Debug::{to_repr}
