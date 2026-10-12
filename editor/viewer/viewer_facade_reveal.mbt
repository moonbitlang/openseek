///|
pub fn Viewer::reveal_line(self : Viewer, line_number : Int32) -> Unit {
  self.widget.reveal_line(line_number)
}

///|
pub fn Viewer::reveal_line_in_center(
  self : Viewer,
  line_number : Int32,
) -> Unit {
  self.widget.reveal_line_in_center(line_number)
}

///|
pub fn Viewer::reveal_line_near_top(self : Viewer, line_number : Int32) -> Unit {
  self.widget.reveal_line_near_top(line_number)
}

///|
pub fn Viewer::reveal_line_in_center_if_outside_viewport(
  self : Viewer,
  line_number : Int32,
) -> Unit {
  self.widget.reveal_line_in_center_if_outside_viewport(line_number)
}

///|
pub fn Viewer::reveal_lines(
  self : Viewer,
  start_line_number : Int32,
  end_line_number : Int32,
) -> Unit {
  self.widget.reveal_lines(start_line_number, end_line_number)
}

///|
pub fn Viewer::reveal_lines_in_center(
  self : Viewer,
  start_line_number : Int32,
  end_line_number : Int32,
) -> Unit {
  self.widget.reveal_lines_in_center(start_line_number, end_line_number)
}

///|
pub fn Viewer::reveal_lines_near_top(
  self : Viewer,
  start_line_number : Int32,
  end_line_number : Int32,
) -> Unit {
  self.widget.reveal_lines_near_top(start_line_number, end_line_number)
}

///|
pub fn Viewer::reveal_lines_in_center_if_outside_viewport(
  self : Viewer,
  start_line_number : Int32,
  end_line_number : Int32,
) -> Unit {
  self.widget.reveal_lines_in_center_if_outside_viewport(
    start_line_number, end_line_number,
  )
}

///|
pub fn Viewer::reveal_position(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  self.widget.reveal_position(position)
}

///|
pub fn Viewer::reveal_position_in_center(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  self.widget.reveal_position_in_center(position)
}

///|
pub fn Viewer::reveal_position_near_top(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  self.widget.reveal_position_near_top(position)
}

///|
pub fn Viewer::reveal_position_in_center_if_outside_viewport(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  self.widget.reveal_position_in_center_if_outside_viewport(position)
}

///|
pub fn Viewer::reveal_range(self : Viewer, range : @base_common.Range) -> Unit {
  self.widget.reveal_range(range)
}

///|
pub fn Viewer::reveal_range_in_center(
  self : Viewer,
  range : @base_common.Range,
) -> Unit {
  self.widget.reveal_range_in_center(range)
}

///|
pub fn Viewer::reveal_range_in_center_if_outside_viewport(
  self : Viewer,
  range : @base_common.Range,
) -> Unit {
  self.widget.reveal_range_in_center_if_outside_viewport(range)
}

///|
pub fn Viewer::reveal_range_near_top(
  self : Viewer,
  range : @base_common.Range,
) -> Unit {
  self.widget.reveal_range_near_top(range)
}

///|
pub fn Viewer::reveal_range_near_top_if_outside_viewport(
  self : Viewer,
  range : @base_common.Range,
) -> Unit {
  self.widget.reveal_range_near_top_if_outside_viewport(range)
}

///|
pub fn Viewer::reveal_range_at_top(
  self : Viewer,
  range : @base_common.Range,
) -> Unit {
  self.widget.reveal_range_at_top(range)
}
