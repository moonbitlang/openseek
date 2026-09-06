///|
/// Whether a one-based view line currently has a rendered DOM node — the gate
/// the deferred horizontal reveal waits on before measuring (the line node may
/// not exist until a vertical scroll brings the line into the window).
pub fn View::is_line_rendered(self : View, view_line_number : Int) -> Bool {
  self.view_lines.line_node_at(view_line_number) is Some(_)
}

///|
/// Pixel x of a 1-based view column on a rendered view line, relative to the
/// line node's left edge — Monaco's `View.getOffsetForColumn` →
/// `ViewLines.visibleRangeForPosition(...).left`. Measures the zero-width caret
/// rect at the column (`keep_empty=true`). Returns `-1` when the line is not in
/// the rendered window, mirroring Monaco's `visibleRangeForPosition` → `null`.
pub fn View::offset_for_column(
  self : View,
  view_line_number : Int,
  view_column : Int,
) -> Double {
  self.view_lines
  .raw_visible_range_for_position(view_line_number, view_column)
  .unwrap_or(-1.0)
}

///|
/// Rendered width of a view line, Monaco's `View.getLineWidth` →
/// `ViewLines.getLineWidth`. This reads the retained rendered-line width cache,
/// including generated content. Returns `-1` when the line is not rendered.
pub fn View::line_width(
  self : View,
  view_line_number : Int,
  _view_max_column : Int,
) -> Double {
  self.view_lines.get_line_width(view_line_number)
}

///|
/// Measured horizontal selection rectangles `(left, width)` for the zero-based
/// view-column range `[start_column, end_column)` on one rendered view line.
/// Returns an empty list when the line is outside the rendered window.
///
/// `CharacterMapping` is one-based, so each zero-based column is shifted by one
/// before resolving its DOM position. The retained `keep_empty` label preserves
/// the existing public call surface; source RangeUtil keeps collapsed rects in
/// both modes, so the source-shaped producer no longer filters on this value.
pub fn View::measure_line_selection(
  self : View,
  view_line_number : Int,
  start_column : Int,
  end_column : Int,
  keep_empty? : Bool = false,
) -> Array[(Double, Double)] {
  ignore(keep_empty)
  guard self.view_lines.visible_ranges_for_line_range(
      view_line_number,
      start_column + 1,
      end_column + 1,
    )
    is Some((_outside_rendered_line, ranges)) else {
    return []
  }
  ranges
}

///|
/// `ViewLines.visibleRangeForPosition` (viewLines.ts:502-508) in the shape
/// the mouse hit test consumes: the measured caret x of a view position as a
/// `HorizontalPosition`, `None` when the line is outside the rendered window
/// (the source's `null`).
pub fn View::visible_range_for_position(
  self : View,
  view_line_number : Int,
  view_column : Int,
) -> HorizontalPosition? {
  self.view_lines
  .raw_visible_range_for_position(view_line_number, view_column)
  .map(left => HorizontalPosition(left))
}
