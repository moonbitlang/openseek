///|
/// View-model line data before it is expanded into full render input.
pub(all) struct ViewLineRenderingData {
  min_column : Int32
  max_column : Int32
  content : String
  continues_with_wrapped_line : Bool
  contains_rtl : Bool
  is_basic_ascii : Bool
  tokens : Array[LinePart]
  inline_decorations : Array[InlineDecoration]
  tab_size : Int32
  start_visible_column : Int32
  text_direction : TextDirection
  has_variable_fonts : Bool
} derive(Eq, Debug)

///|
pub extend ViewLineRenderingData with Debug::{to_repr}

///|
pub extend ViewLineRenderingData with Eq::{equal, not_equal}
