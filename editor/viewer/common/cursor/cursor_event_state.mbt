///|
/// The paired model/view cursor state. Both sides are committed atomically;
/// live callers provide one side and the cursor derives the other.
pub struct CursorState {
  model_state : SingleCursorState
  view_state : SingleCursorState
} derive(Eq, Debug)

///|
/// Retains a complete model/view pair.
fn CursorState::CursorState(
  model_state : SingleCursorState,
  view_state : SingleCursorState,
) -> CursorState {
  { model_state, view_state, }
}

///|
/// Model-only `PartialCursorState`: the view property is exactly absent.
priv struct PartialModelCursorState {
  model_state : SingleCursorState
  view_state : SingleCursorState?
} derive(Eq, Debug)

///|
fn PartialModelCursorState::PartialModelCursorState(
  model_state : SingleCursorState,
) -> PartialModelCursorState {
  { model_state, view_state: None, }
}

///|
/// View-only `PartialCursorState`: the model property is exactly absent.
priv struct PartialViewCursorState {
  model_state : SingleCursorState?
  view_state : SingleCursorState
} derive(Eq, Debug)

///|
fn PartialViewCursorState::PartialViewCursorState(
  view_state : SingleCursorState,
) -> PartialViewCursorState {
  { model_state: None, view_state, }
}

///|
/// Source-shaped partial cursor-state union. Live callers normally provide
/// exactly one side; `FullCursorState` represents the retained complete-state
/// member used by snapshots/reprojection tests.
#warnings("-unused_constructor")
enum PartialCursorState {
  FullCursorState(CursorState)
  ModelCursorState(PartialModelCursorState)
  ViewCursorState(PartialViewCursorState)
} derive(Eq, Debug)

///|
pub fn CursorState::from_model_state(
  state : SingleCursorState,
) -> PartialCursorState {
  ModelCursorState(PartialModelCursorState(state))
}

///|
pub fn CursorState::from_view_state(
  state : SingleCursorState,
) -> PartialCursorState {
  ViewCursorState(PartialViewCursorState(state))
}

///|
/// Builds the source's collapsed Simple anchor from one model selection.
pub fn CursorState::from_model_selection(
  selection : @core.Selection,
) -> PartialCursorState {
  let anchor = selection.get_selection_start()
  CursorState::from_model_state(
    SingleCursorState(anchor, anchor, Simple, selection.get_position()),
  )
}

///|
/// Converts model selections in source order.
pub fn CursorState::from_model_selections(
  selections : Array[@core.Selection],
) -> Array[PartialCursorState] {
  [
    for selection in selections => CursorState::from_model_selection(selection)
  ]
}

///|
fn PartialCursorState::model_state(
  self : PartialCursorState,
) -> SingleCursorState? {
  match self {
    FullCursorState(state) => Some(state.model_state)
    ModelCursorState(state) => Some(state.model_state)
    ViewCursorState(state) => state.model_state
  }
}

///|
fn PartialCursorState::view_state(
  self : PartialCursorState,
) -> SingleCursorState? {
  match self {
    FullCursorState(state) => Some(state.view_state)
    ModelCursorState(state) => state.view_state
    ViewCursorState(state) => Some(state.view_state)
  }
}

///|
/// One accepted full cursor transition. `has_outgoing_event` is false for a
/// view-only reprojection: the view changed and must render, but public model
/// cursor listeners must remain silent. A content flush deliberately carries
/// `old_selections=None` and old version `0` even when both visible states are
/// the origin.
pub struct CursorStateChange {
  old_selections : Array[@core.Selection]?
  selections : Array[@core.Selection]
  old_model_version_id : Int
  model_version_id : Int
  source : String
  reason : @editor_api.CursorChangeReason
  reached_max_cursor_count : Bool
  has_outgoing_event : Bool
} derive(Debug)

///|
/// Internal equality snapshot used by `CursorsController` to distinguish a
/// full no-op, a view-only change, and a public model-state change.
struct CursorModelState {
  model_version_id : Int
  cursor_state : CursorState
} derive(Eq)

///|
pub extend CursorModelState with Eq::{equal, not_equal}

///|
pub extend CursorState with Debug::{to_repr}

///|
pub extend CursorState with Eq::{equal, not_equal}

///|
pub extend CursorStateChange with Debug::{to_repr}

///|
pub extend PartialCursorState with Debug::{to_repr}

///|
pub extend PartialCursorState with Eq::{equal, not_equal}
