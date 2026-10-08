///|
/// Bounds display work without truncating the underlying model or selection.
pub(all) enum LineRenderingLimit {
  Unlimited
  Characters(Int)
} derive(Eq, Debug)

///|
pub extend LineRenderingLimit with Eq::{equal, not_equal}

///|
pub extend LineRenderingLimit with Debug::{to_repr}

///|
/// Adapter to the existing low-level renderer's stopRenderingLineAfter option.
pub fn LineRenderingLimit::stop_offset(self : LineRenderingLimit) -> Int {
  match self {
    Unlimited => -1
    Characters(count) => count.max(1)
  }
}
