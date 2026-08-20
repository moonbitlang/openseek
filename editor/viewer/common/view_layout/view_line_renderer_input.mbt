///|
/// Fully normalized input for rendering one view line to HTML.
pub struct RenderLineInput {
  use_monospace_optimizations : Bool
  can_use_halfwidth_rightwards_arrow : Bool
  line_content : String
  continues_with_wrapped_line : Bool
  is_basic_ascii : Bool
  contains_rtl : Bool
  faux_indent_length : Int
  line_tokens : Array[LinePart]
  line_decorations : Array[LineDecoration]
  tab_size : Int
  start_visible_column : Int
  space_width : Double
  render_space_width : Double
  render_space_char_code : Int
  stop_rendering_line_after : Int
  render_whitespace : @editor_api.RenderWhitespace
  render_control_characters : Bool
  font_ligatures : Bool
  selections_on_line : Array[@base_common.OffsetRange]
  text_direction : TextDirection
  vertical_scrollbar_size : Double
  render_new_line_when_empty : Bool
} derive(Eq, Debug)

///|
/// Builds line-renderer input from viewport line data plus runtime rendering
/// options.
pub fn RenderLineInput::from_view_line(
  data : ViewLineRenderingData,
  line_decorations? : Array[LineDecoration] = [],
  use_monospace_optimizations? : Bool = true,
  can_use_halfwidth_rightwards_arrow? : Bool = true,
  faux_indent_length? : Int = 0,
  space_width? : Double = 7.2,
  middot_width? : Double = 7.2,
  wsmiddot_width? : Double = 7.2,
  stop_rendering_line_after? : Int = -1,
  render_whitespace? : @editor_api.RenderWhitespace = None,
  render_control_characters? : Bool = false,
  font_ligatures? : Bool = false,
  selections_on_line? : Array[@base_common.OffsetRange] = [],
  vertical_scrollbar_size? : Double = 0.0,
  render_new_line_when_empty? : Bool = false,
) -> RenderLineInput {
  let sorted_line_decorations = line_decorations.copy()
  sorted_line_decorations.sort_by(LineDecoration::compare)
  // Monaco's RenderLineInput constructor sorts selections by start offset.
  let sorted_selections = selections_on_line.copy()
  sorted_selections.sort_by((a, b) => a.start - b.start)
  let wsmiddot_diff = (wsmiddot_width - space_width).abs()
  let middot_diff = (middot_width - space_width).abs()
  let (render_space_width, render_space_char_code) = if wsmiddot_diff <
    middot_diff {
    (wsmiddot_width, ch_word_separator_middot)
  } else {
    // Strict-less above preserves Monaco's U+00B7 tie outcome.
    (middot_width, ch_middot)
  }
  {
    use_monospace_optimizations,
    can_use_halfwidth_rightwards_arrow,
    line_content: data.content,
    continues_with_wrapped_line: data.continues_with_wrapped_line,
    is_basic_ascii: data.is_basic_ascii,
    contains_rtl: data.contains_rtl,
    faux_indent_length,
    line_tokens: data.tokens,
    line_decorations: sorted_line_decorations,
    tab_size: data.tab_size,
    start_visible_column: data.start_visible_column,
    space_width,
    render_space_width,
    render_space_char_code,
    stop_rendering_line_after,
    render_whitespace,
    render_control_characters,
    font_ligatures,
    selections_on_line: sorted_selections,
    text_direction: data.text_direction,
    vertical_scrollbar_size,
    render_new_line_when_empty,
  }
}

///|
pub extend RenderLineInput with Debug::{to_repr}

///|
pub extend RenderLineInput with Eq::{equal, not_equal}
