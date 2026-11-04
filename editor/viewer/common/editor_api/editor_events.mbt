///|
/// Monaco's `IModelChangedEvent`: the old and new model resource identifiers,
/// with `None` representing the detached side of a swap.
#derive(Debug)
pub(all) struct ModelChangedEvent {
  old_model_url : @base_common.Uri?
  new_model_url : @base_common.Uri?
}

///|
/// Monaco's `ScrollEvent`, reduced to position and extent facts plus their
/// per-axis change flags.
#derive(Debug)
pub(all) struct ScrollEvent {
  scroll_top : Double
  scroll_left : Double
  scroll_width : Double
  scroll_height : Double
  scroll_top_changed : Bool
  scroll_left_changed : Bool
  scroll_width_changed : Bool
  scroll_height_changed : Bool
}

///|
/// A model position projected to scrolled viewport pixels, matching Monaco's
/// `getScrolledVisiblePosition` return shape.
#derive(Eq, Debug)
pub(all) struct ScrolledVisiblePosition {
  top : Double
  left : Double
  height : Double
}

///|
pub extend ModelChangedEvent with Debug::{to_repr}

///|
pub extend ScrollEvent with Debug::{to_repr}

///|
pub extend ScrolledVisiblePosition with Debug::{to_repr}

///|
pub extend ScrolledVisiblePosition with Eq::{equal, not_equal}
