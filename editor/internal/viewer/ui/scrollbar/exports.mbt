// Explicit staged scrollbar contracts. The raw CSS arm is retained for the
// source-shaped CachedDomNode API even though current production callers use
// numeric pixel lengths only.

///|
/// A CSS length accepted by Monaco's `numberAsPixels`: numeric values gain a
/// `px` suffix while already-formed CSS strings pass through unchanged.
pub(all) enum CssLength {
  Pixels(Double)
  Raw(String)
} derive(Eq, Debug)

///|
pub extend CssLength with Debug::{to_repr}

///|
pub extend CssLength with Eq::{equal, not_equal}
