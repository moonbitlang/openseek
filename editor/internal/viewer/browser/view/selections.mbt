// Ported from `vscode/src/vs/editor/browser/viewParts/selections/selections.ts`
// (`SelectionsOverlay`), checked-in vscode submodule. The `ContentViewOverlays` row
// shell lives in `view_overlays.mbt`, mirroring Monaco's `viewOverlays.ts`;
// this source unit owns the selection dynamic overlay. Its lifecycle wiring
// lives beside the package-private rendering context.

///|
/// The package-private selection dynamic overlay state: the prepared per-line
/// HTML (`_renderResult`).
priv struct SelectionsOverlay {
  mut render_result : Array[String]
}

///|
fn SelectionsOverlay::SelectionsOverlay() -> SelectionsOverlay {
  { render_result: [], }
}

///|
/// The rounded-corner classification of a selection edge, Monaco's
/// `CornerStyle`: `Extern` rounds outward, `Intern` is a reverse (inverse)
/// corner cut into an adjacent line, `Flat` leaves a straight edge.
priv enum CornerStyle {
  Extern
  Intern
  Flat
} derive(Eq)

///|
/// One measured selection rectangle plus the corner styles of its four corners,
/// Monaco's `HorizontalRangeWithStyle`.
priv struct StyledRange {
  left : Double
  width : Double
  mut start_top : CornerStyle
  mut start_bottom : CornerStyle
  mut end_top : CornerStyle
  mut end_bottom : CornerStyle
}

///|
/// The styled selection rectangles for one view line, Monaco's
/// `LineVisibleRangesWithStyle`.
priv struct LineSelectionRanges {
  line_number : Int
  ranges : Array[StyledRange]
}

///|
fn new_styled_range(left : Double, width : Double) -> StyledRange {
  {
    left,
    width,
    start_top: Extern,
    start_bottom: Extern,
    end_top: Extern,
    end_bottom: Extern,
  }
}

///|
/// Production entrypoint for the pinned `SelectionsOverlay` query shape:
/// `RenderingContext.linesVisibleRangesForRange(selection, true)` has already
/// aggregated, rounded, and newline-extended the measured DOM ranges. The
/// focused styling/HTML entrypoint accepts line numbers plus ordered
/// `(left,width)` pairs, preserving the geometry handoff for direct tests.
fn prepare_selections_render_from_visible_ranges(
  viewport : @view_layout.ViewportData,
  visible_ranges : Array[(Int, Array[(Double, Double)])],
  space_width : Double,
) -> Array[String] {
  let lines : Array[LineSelectionRanges] = []
  for visible_line in visible_ranges {
    let ranges = visible_line.1.map(range => new_styled_range(range.0, range.1))
    if !ranges.is_empty() {
      lines.push({ line_number: visible_line.0, ranges, })
    }
  }
  render_selection_lines(viewport, lines, space_width)
}

///|
fn render_selection_lines(
  viewport : @view_layout.ViewportData,
  lines : Array[LineSelectionRanges],
  space_width : Double,
) -> Array[String] {
  let inner_corners = Array::make(viewport.lines.length(), "")
  let rest_of_selection = Array::make(viewport.lines.length(), "")
  // Rounded selection is always on; enrich unless a line has multiple ranges.
  let styled = !visible_ranges_have_gaps(lines)
  if styled {
    enrich_visible_ranges_with_style(lines, space_width)
  }
  for line in lines {
    let line_index = line.line_number - viewport.start_line_number
    if line_index < 0 || line_index >= rest_of_selection.length() {
      continue
    }
    let (corner_html, selection_html) = render_styled_line_html(line, styled)
    inner_corners[line_index] += corner_html
    rest_of_selection[line_index] += selection_html
  }
  // `output.map(([innerCorners, rest]) => innerCorners + rest)`.
  rest_of_selection.mapi((index, rest) => inner_corners[index] + rest)
}

///|
/// Whether any line carries more than one range, in which case Monaco skips
/// corner enrichment (the staircase math assumes one range per line).
fn visible_ranges_have_gaps(lines : Array[LineSelectionRanges]) -> Bool {
  lines.any(line => line.ranges.length() > 1)
}

///|
/// Classifies each selection corner by comparing a line's single range to the
/// lines above and below, a transcription of Monaco's
/// `_enrichVisibleRangesWithStyle` (minus the previous-frame cache). Where edges
/// line up the corner is `Flat`, where this line is narrower the corner is
/// `Extern` (rounds outward), and where it is wider it is `Intern` (a reverse
/// corner cut into the neighbor).
fn enrich_visible_ranges_with_style(
  lines : Array[LineSelectionRanges],
  space_width : Double,
) -> Unit {
  let epsilon = space_width / 4.0
  for i in 0..<lines.length() {
    let cur = lines[i].ranges[0]
    let cur_left = cur.left
    let cur_right = cur.left + cur.width
    if i > 0 {
      let prev = lines[i - 1].ranges[0]
      let prev_left = prev.left
      let prev_right = prev.left + prev.width
      if (cur_left - prev_left).abs() < epsilon {
        cur.start_top = Flat
      } else if cur_left > prev_left {
        cur.start_top = Intern
      }
      if (cur_right - prev_right).abs() < epsilon {
        cur.end_top = Flat
      } else if prev_left < cur_right && cur_right < prev_right {
        cur.end_top = Intern
      }
    }
    if i + 1 < lines.length() {
      let next = lines[i + 1].ranges[0]
      let next_left = next.left
      let next_right = next.left + next.width
      if (cur_left - next_left).abs() < epsilon {
        cur.start_bottom = Flat
      } else if next_left < cur_left && cur_left < next_right {
        cur.start_bottom = Intern
      }
      if (cur_right - next_right).abs() < epsilon {
        cur.end_bottom = Flat
      } else if cur_right < next_right {
        cur.end_bottom = Intern
      }
    }
  }
}

///|
/// One line's `(innerCornerOutput, restOfSelectionOutput)` pair, transcribing
/// Monaco's `_actualRenderOneSelection` loop body for the single-selection
/// case (`hasMultipleSelections` false → `top`/`bottom` are `0`): reverse
/// corners are a selection layer plus an editor-background layer carrying the
/// inverse radius classes; the main rectangle carries its outward radius
/// classes.
fn render_styled_line_html(
  line : LineSelectionRanges,
  styled : Bool,
) -> (String, String) {
  for range in line.ranges; output = ("", "") {
    let (inner_corner_output, rest_of_selection_output) = output
    let start_inner_corner = if styled &&
      (range.start_top == Intern || range.start_bottom == Intern) {
      // Reverse rounded corner to the left: first the selection (blue
      // layer), then the background (white layer) with inverse radius.
      let left = range.left - rounded_piece_width
      let class_name = editor_background_class_name +
        (if range.start_top == Intern { " top-right-radius" } else { "" }) +
        (if range.start_bottom == Intern { " bottom-right-radius" } else { "" })
      selection_piece_html(selection_class_name, left, rounded_piece_width) +
      selection_piece_html(class_name, left, rounded_piece_width)
    } else {
      ""
    }
    let end_inner_corner = if styled &&
      (range.end_top == Intern || range.end_bottom == Intern) {
      // Reverse rounded corner to the right.
      let left = range.left + range.width
      let class_name = editor_background_class_name +
        (if range.end_top == Intern { " top-left-radius" } else { "" }) +
        (if range.end_bottom == Intern { " bottom-left-radius" } else { "" })
      selection_piece_html(selection_class_name, left, rounded_piece_width) +
      selection_piece_html(class_name, left, rounded_piece_width)
    } else {
      ""
    }
    let class_name = selection_class_name +
      (if styled && range.start_top == Extern {
        " top-left-radius"
      } else {
        ""
      }) +
      (if styled && range.start_bottom == Extern {
        " bottom-left-radius"
      } else {
        ""
      }) +
      (if styled && range.end_top == Extern { " top-right-radius" } else { "" }) +
      (if styled && range.end_bottom == Extern {
        " bottom-right-radius"
      } else {
        ""
      })
    continue (
        inner_corner_output + start_inner_corner + end_inner_corner,
        rest_of_selection_output +
        selection_piece_html(class_name, range.left, range.width),
      )
  } nobreak {
    output
  }
}

///|
/// `SelectionsOverlay.SELECTION_CLASS_NAME`.
let selection_class_name = "selected-text"

///|
/// `SelectionsOverlay.EDITOR_BACKGROUND_CLASS_NAME`: the reverse-corner white
/// layer's class.
let editor_background_class_name = "monaco-editor-background"

///|
/// Width of a reverse-corner piece, Monaco's `ROUNDED_PIECE_WIDTH`.
let rounded_piece_width = 10.0

///|
/// `_createSelectionPiece` (`selections.ts:258-269`); the single selection
/// makes `top`/`bottom` constantly `0`.
fn selection_piece_html(
  class_name : String,
  left : Double,
  width : Double,
) -> String {
  "<div class=\"cslr \{class_name}\" style=\"top:0px;bottom:0px;left:\{left.to_string()}px;width:\{width.to_string()}px;\"></div>"
}
