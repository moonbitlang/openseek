///|
/// Inline decoration over a line-local offset range.
pub struct InlineDecoration {
  range : @base_common.OffsetRange
  class_name : String
  decoration_type : InlineDecorationType
} derive(Eq, Debug)

///|
/// Builds an inline decoration.
pub fn InlineDecoration::InlineDecoration(
  range : @base_common.OffsetRange,
  class_name : String,
  decoration_type? : InlineDecorationType = Regular,
) -> InlineDecoration {
  { range, class_name, decoration_type }
}

///|
pub extend InlineDecoration with Debug::{to_repr}

///|
pub extend InlineDecoration with Eq::{equal, not_equal}
