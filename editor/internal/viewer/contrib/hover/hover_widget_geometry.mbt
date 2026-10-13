// Phase 4 of `monaco-hover-logic-chain-port.md` — pure geometry/placement
// helpers ported from the content-hover widget cluster
// (`contentHoverRendered.ts`, `contentHoverWidget.ts`). Side-effect-free and
// whitebox-tested; ported ahead of the per-part DOM-structure rework.

///|
/// One hover part as it matters to placement: its (model line/column) range and
/// whether it forces the widget to anchor at that range. Mirrors the
/// `range` / `forceShowAtRange` members `computeHoverPositions` reads off each
/// `IHoverPart`; no viewer participant sets `force_show_at_range` yet.
pub(all) struct HoverPositionPart {
  range : @base_common.Range
  force_show_at_range : Bool
}

///|
/// Monaco `RenderedContentHover.computeHoverPositions` (`contentHoverRendered.ts`
/// :116-164). Computes where the content hover widget anchors. The primary
/// `show_at` is the anchor range start; the secondary `show_at_secondary` is the
/// leftmost start column among the parts that sit entirely on the anchor's start
/// line, clamped down to `secondary_position_column` and back up to
/// `start_column_boundary`. A part with `force_show_at_range` overrides both with
/// its own start position.
///
/// `start_column_boundary` is the model column of the anchor view line's minimum
/// column — Monaco computes it through the coordinates converter; the viewer
/// passes it in (1 when there is no wrapping / model, matching Monaco's
/// `startColumnBoundary = 1` default).
///
/// Returns `(show_at, show_at_secondary)`, Monaco's
/// `{ showAtPosition, showAtSecondaryPosition }`.
pub fn compute_hover_positions(
  anchor_range : @base_common.Range,
  hover_parts : Array[HoverPositionPart],
  start_column_boundary : Int32,
) -> (@base_common.Position, @base_common.Position) {
  // The anchor range is always on a single line.
  let anchor_start_line_number = anchor_range.start_line_number
  let (secondary_position_column, force_show_at_range) = for
    hover_part in hover_parts
    state = (anchor_range.start_column, (None : @base_common.Range?)) {
    let (secondary_position_column, force_show_at_range) = state
    let hover_part_range = hover_part.range
    let on_anchor_start_line = hover_part_range.start_line_number ==
      anchor_start_line_number
    let on_anchor_end_line = hover_part_range.end_line_number ==
      anchor_start_line_number
    let is_on_anchor_line = on_anchor_start_line && on_anchor_end_line
    let secondary_position_column = if is_on_anchor_line {
      // This message has a range that is completely sitting on the anchor line.
      let hover_part_start_column = hover_part_range.start_column
      let min_secondary_position_column = secondary_position_column.min(
        hover_part_start_column,
      )
      min_secondary_position_column.max(start_column_boundary)
    } else {
      secondary_position_column
    }
    let force_show_at_range = if hover_part.force_show_at_range {
      Some(hover_part_range)
    } else {
      force_show_at_range
    }
    continue (secondary_position_column, force_show_at_range)
  } nobreak {
    state
  }
  match force_show_at_range {
    Some(range) => {
      let force_show_at_position = range.get_start_position()
      (force_show_at_position, force_show_at_position)
    }
    None =>
      (
        anchor_range.get_start_position(),
        Position(anchor_start_line_number, secondary_position_column),
      )
  }
}

///|
/// Monaco `computeDistanceFromPointToRectangle` (`contentHoverWidget.ts`
/// :477-483): Euclidean distance from a point to the nearest edge of a
/// rectangle, `0` when the point is inside it.
fn compute_distance_from_point_to_rectangle(
  point_x : Double,
  point_y : Double,
  left : Double,
  top : Double,
  width : Double,
  height : Double,
) -> Double {
  let x = left + width / 2.0 // x center of rectangle
  let y = top + height / 2.0 // y center of rectangle
  let dx = ((point_x - x).abs() - width / 2.0).max(0.0)
  let dy = ((point_y - y).abs() - height / 2.0).max(0.0)
  (dx * dx + dy * dy).sqrt()
}

///|
/// State Monaco's `RenderedContentHover` carries for `isMouseGettingCloser`
/// (`contentHoverWidget.ts` :32-34, :238-276): the pointer position recorded on
/// the first move after the hover showed, and the closest the pointer has been
/// to the widget rectangle so far. Held mutably because the running minimum is
/// updated in place per move, exactly as Monaco mutates the
/// `RenderedContentHover`. Recreated per shown hover (the viewer resets it when
/// the shown view changes, mirroring Monaco's fresh `RenderedContentHover`).
struct MouseCloserState {
  mut initial_pos_x : Double?
  mut initial_pos_y : Double?
  mut closest_distance : Double?
}

///|
pub fn MouseCloserState::MouseCloserState() -> MouseCloserState {
  { initial_pos_x: None, initial_pos_y: None, closest_distance: None, }
}

///|
/// Resets the running state so the next move re-seeds the reference point,
/// standing in for Monaco recreating the `RenderedContentHover` on each show.
pub fn MouseCloserState::reset(self : MouseCloserState) -> Unit {
  self.initial_pos_x = None
  self.initial_pos_y = None
  self.closest_distance = None
}

///|
/// Monaco `ContentHoverWidget.isMouseGettingCloser` (:238-276). On the first
/// call it records the pointer as the reference point and returns `false`;
/// afterwards it returns whether the pointer is no farther than 4px beyond the
/// closest it has ever been to the widget rectangle, tracking that running
/// minimum. The widget rectangle is measured by the host each call and passed in
/// (Monaco's `getDomNodePagePosition(this.getDomNode())`). The `!_renderedHover`
/// guard is implicit: this state only exists while a hover is rendered.
pub fn MouseCloserState::is_mouse_getting_closer(
  self : MouseCloserState,
  posx : Double,
  posy : Double,
  rect_left : Double,
  rect_top : Double,
  rect_width : Double,
  rect_height : Double,
) -> Bool {
  let (initial_x, initial_y) = match (self.initial_pos_x, self.initial_pos_y) {
    (Some(x), Some(y)) => (x, y)
    _ => {
      self.initial_pos_x = Some(posx)
      self.initial_pos_y = Some(posy)
      return false
    }
  }
  let closest_distance = match self.closest_distance {
    Some(distance) => distance
    None => {
      let distance = compute_distance_from_point_to_rectangle(
        initial_x, initial_y, rect_left, rect_top, rect_width, rect_height,
      )
      self.closest_distance = Some(distance)
      distance
    }
  }
  let distance = compute_distance_from_point_to_rectangle(
    posx, posy, rect_left, rect_top, rect_width, rect_height,
  )
  if distance > closest_distance + 4.0 {
    // The mouse is getting farther away.
    return false
  }
  self.closest_distance = Some(closest_distance.min(distance))
  true
}

///|
pub fn hover_part_range(part : HoverPart) -> @base_common.Range {
  match part {
    MarkdownHover(range~, ..) => range
    MarkerHover(range~, ..) => range
    LoadingHover(range~, ..) => range
  }
}
