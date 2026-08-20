///|
/// A half-open range of 1-based view-line numbers the view should render:
/// covers lines `start ..< end` in Monaco's view coordinate space.
pub(all) struct LineWindow {
  start : Int
  end : Int
} derive(Eq, Debug)

///|
#deprecated
pub extend LineWindow with Debug::{to_repr}

///|
pub extend LineWindow with Eq::{equal, not_equal}
