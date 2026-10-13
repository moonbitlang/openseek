///|
pub fn Viewer::get_position(self : Viewer) -> @base_common.Position? {
  self.widget.get_position()
}

///|
pub fn Viewer::get_selection(self : Viewer) -> @core.Selection? {
  self.widget.get_selection()
}

///|
pub fn Viewer::get_selections(self : Viewer) -> Array[@core.Selection]? {
  self.widget.get_selections()
}

///|
pub fn Viewer::set_position(
  self : Viewer,
  position : @base_common.Position,
  source~ : String = "api",
) -> Unit {
  self.widget.set_position(position, source~)
}

///|
pub fn Viewer::set_selection(
  self : Viewer,
  selection : @core.Selection,
  source~ : String = "api",
) -> Unit {
  self.widget.set_selection(selection, source~)
}

///|
pub fn Viewer::set_selections(
  self : Viewer,
  selections : Array[@core.Selection],
  source~ : String = "api",
  reason~ : @editor_api.CursorChangeReason = NotSet,
) -> Unit {
  self.widget.set_selections(selections, source~, reason~)
}

///|
pub fn Viewer::get_visible_ranges(self : Viewer) -> Array[@base_common.Range] {
  self.widget.get_visible_ranges()
}

///|
pub fn Viewer::get_content_width(self : Viewer) -> Double {
  self.widget.get_content_width()
}

///|
pub fn Viewer::get_scroll_width(self : Viewer) -> Double {
  self.widget.get_scroll_width()
}

///|
pub fn Viewer::get_scroll_left(self : Viewer) -> Double {
  self.widget.get_scroll_left()
}

///|
pub fn Viewer::get_content_height(self : Viewer) -> Double {
  self.widget.get_content_height()
}

///|
pub fn Viewer::get_scroll_height(self : Viewer) -> Double {
  self.widget.get_scroll_height()
}

///|
pub fn Viewer::get_scroll_top(self : Viewer) -> Double {
  self.widget.get_scroll_top()
}

///|
pub fn Viewer::set_scroll_top(self : Viewer, value : Double) -> Unit {
  self.widget.set_scroll_top(value)
}

///|
pub fn Viewer::set_scroll_left(self : Viewer, value : Double) -> Unit {
  self.widget.set_scroll_left(value)
}

///|
pub fn Viewer::set_scroll_position(
  self : Viewer,
  scroll_top? : Double,
  scroll_left? : Double,
) -> Unit {
  self.widget.set_scroll_position(scroll_top?, scroll_left?)
}

///|
pub fn Viewer::get_top_for_line_number(
  self : Viewer,
  line_number : Int32,
  include_view_zones~ : Bool = false,
) -> Double {
  self.widget.get_top_for_line_number(line_number, include_view_zones~)
}

///|
pub fn Viewer::get_top_for_position(
  self : Viewer,
  line_number : Int32,
  column : Int32,
) -> Double {
  self.widget.get_top_for_position(line_number, column)
}

///|
pub fn Viewer::get_bottom_for_line_number(
  self : Viewer,
  line_number : Int32,
) -> Double {
  self.widget.get_bottom_for_line_number(line_number)
}

///|
pub fn Viewer::get_line_height_for_position(
  self : Viewer,
  position : @base_common.Position,
) -> Double {
  self.widget.get_line_height_for_position(position)
}

///|
pub fn Viewer::get_visible_column_from_position(
  self : Viewer,
  position : @base_common.Position,
) -> Int32 {
  self.widget.get_visible_column_from_position(position)
}

///|
pub fn Viewer::get_offset_for_column(
  self : Viewer,
  line_number : Int32,
  column : Int32,
) -> Double {
  self.widget.get_offset_for_column(line_number, column)
}

///|
pub fn Viewer::get_width_of_line(self : Viewer, line_number : Int32) -> Double {
  self.widget.get_width_of_line(line_number)
}

///|
pub fn Viewer::get_scrolled_visible_position(
  self : Viewer,
  position : @base_common.Position,
) -> @editor_api.ScrolledVisiblePosition? {
  self.widget.get_scrolled_visible_position(position)
}

///|
pub fn Viewer::get_layout_info(self : Viewer) -> @config.EditorLayoutInfo {
  self.widget.get_layout_info()
}
