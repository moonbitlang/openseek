///|
/// Diff/clear state for the live viewport region.
///
/// Steady-state redraws diff the new surface against the last one drawn so the
/// renderer can skip unchanged physical rows. A terminal resize drops that
/// cached surface. When it does, the old physical *footprint* must still be
/// remembered so the next redraw can erase rows the moved/shrunken region no
/// longer covers.
///
/// The two states make that lifecycle explicit:
///
///   - `Drawn(surface)`: `surface` is on screen at the viewport's current `top`,
///     so redraws can diff against it row by row.
///   - `Stale(top, height)`: the cached surface was dropped, but the region it
///     occupied is remembered so the next redraw clears any rows it vacates.
priv enum FrameCache {
  Drawn(@surface.Surface)
  Stale(top~ : Int, height~ : Int)
}

///|
/// The cached surface available for row-level diffing, if any, placed at the
/// viewport's current live top.
///
/// Only `Drawn` carries trustworthy on-screen content; `Stale` has no surface to
/// diff against, so the next redraw rewrites every covered row.
fn FrameCache::placed_surface(
  self : FrameCache,
  live_top~ : Int,
) -> PlacedSurface? {
  match self {
    Drawn(surface) => Some({ surface, top: live_top })
    Stale(top=_, height=_) => None
  }
}

///|
/// Drop the cached surface but remember the region it covered so a later redraw
/// can clear vacated rows. Called when a resize makes the cached physical rows
/// untrustworthy.
///
/// Only `Drawn` has a footprint worth remembering; `Stale` already holds no live
/// surface, so it is left unchanged.
fn FrameCache::invalidate(self : FrameCache, live_top~ : Int) -> FrameCache {
  match self {
    Drawn(surface) => Stale(top=live_top, height=surface.height())
    Stale(top=_, height=_) => self
  }
}
