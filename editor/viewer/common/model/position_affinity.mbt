///|
/// Which side of an injected-text or soft-wrap boundary a position resolves
/// to, `PositionAffinity` (`model.ts:1455-1480`).
#derive(Eq, Debug)
pub(all) enum PositionAffinity {
  /// Prefers the left most position.
  Left
  /// Prefers the right most position.
  Right
  /// No preference.
  None
  /// If the given position is on injected text, prefers the position left of
  /// it.
  LeftOfInjectedText
  /// If the given position is on injected text, prefers the position right of
  /// it.
  RightOfInjectedText
}

///|
pub extend PositionAffinity with Debug::{to_repr}

///|
pub extend PositionAffinity with Eq::{equal, not_equal}
