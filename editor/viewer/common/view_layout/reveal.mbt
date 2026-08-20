///|
/// Monaco's `VerticalRevealType` (`vs/editor/common/viewEvents.ts`): how a
/// reveal aligns the target range inside the viewport.
pub(all) enum VerticalRevealType {
  Simple
  Center
  CenterIfOutsideViewport
  NearTop
  NearTopIfOutsideViewport
  Top
  Bottom
} derive(Eq, Debug)

///|
/// The minimal `scroll_top` that brings the 1-based **view**-line range
/// `[start_line, end_line]` into the viewport, aligned per `vertical_type`.
/// A 1:1 port of Monaco's `ViewLines._computeScrollTopToRevealRange`
/// (`vs/editor/browser/viewParts/viewLines/viewLines.ts:693`).
///
/// Pure model state: works entirely in view coordinates, so it stays
/// `moon test`-able without a browser. Model→view conversion happens at the
/// `Viewer` boundary before this is called (with word-wrap on, model line ≠
/// view line).
///
/// Scope cuts vs. Monaco (all confirmed absent in the viewer):
/// - No `cursorSurroundingLines` / sticky-scroll scroll-off padding, so
///   `paddingTop = paddingBottom = 0` (`viewLines.ts:720`–`:736`). Only the
///   behavioral `+1 line` bottom pad for `Simple` / `Bottom` survives
///   (`:737`–`:742`) only when `minimal_reveal=false`. Mouse-source regular
///   reveals add the source's one-line top pad; minimal cursor reveals add no
///   top/bottom padding.
/// - No multi-selection. The box is always a single range, so an oversized box
///   reveals its top (Monaco's single-range branch, `:754`) instead of returning
///   the `-1` abort sentinel — that sentinel is reserved for the oversized
///   multi-cursor case the viewer never exposes. This port therefore does not
///   produce `-1.0`; `Viewer::send_reveal_range` still guards on it defensively.
///
/// The returned value is unclamped (it may be negative, e.g. a `NearTop` reveal
/// near the document top); `Scrollable::set_position` clamps it into the valid
/// scroll range, mirroring Monaco's `validateScrollPosition` step.
pub fn ViewLayout::compute_scroll_top_to_reveal_range(
  self : ViewLayout,
  start_line : Int,
  end_line : Int,
  vertical_type : VerticalRevealType,
  source? : String = "",
  minimal_reveal? : Bool = false,
) -> Double {
  // The source uses the future viewport so consecutive animated reveal
  // requests compose against their already-requested destination.
  let viewport_start_y = self.future_position().scroll_top
  let viewport_height = self.dimensions().height
  let viewport_end_y = viewport_start_y + viewport_height
  let line_height = self.line_height.to_double()
  let mut box_start_y = self.vertical_offset_for_line(start_line)
  let mut box_end_y = self.vertical_offset_for_line(end_line) + line_height
  let should_ignore_scroll_off = source == "mouse" || minimal_reveal
  if should_ignore_scroll_off && !minimal_reveal {
    // Reveal one more line above for a non-minimal mouse drag.
    box_start_y -= line_height
  }
  if !minimal_reveal {
    match vertical_type {
      Simple | Bottom => box_end_y += line_height
      _ => ()
    }
  }
  if box_end_y - box_start_y > viewport_height {
    // The box is larger than the viewport: a single range, so reveal its top.
    box_start_y
  } else {
    match vertical_type {
      NearTop | NearTopIfOutsideViewport =>
        if vertical_type is NearTopIfOutsideViewport &&
          viewport_start_y <= box_start_y &&
          box_end_y <= viewport_end_y {
          // Box is already in the viewport... do nothing.
          viewport_start_y
        } else {
          // A gap that is 20% of the viewport, with a minimum of 5 lines.
          let desired_gap_above = (5.0 * line_height).max(viewport_height * 0.2)
          // Scroll just above the box with the desired gap, but never push the
          // box out of the viewport.
          let desired_scroll_top = box_start_y - desired_gap_above
          let min_scroll_top = box_end_y - viewport_height
          min_scroll_top.max(desired_scroll_top)
        }
      Center | CenterIfOutsideViewport =>
        if vertical_type is CenterIfOutsideViewport &&
          viewport_start_y <= box_start_y &&
          box_end_y <= viewport_end_y {
          // Box is already in the viewport... do nothing.
          viewport_start_y
        } else {
          // Box is outside the viewport... center it.
          let box_middle_y = (box_start_y + box_end_y) / 2.0
          0.0.max(box_middle_y - viewport_height / 2.0)
        }
      _ =>
        compute_minimum_scrolling(
          viewport_start_y,
          viewport_end_y,
          box_start_y,
          box_end_y,
          reveal_at_start=vertical_type is Top,
          reveal_at_end=vertical_type is Bottom,
        )
    }
  }
}

///|
/// Monaco's `ViewLines.HORIZONTAL_EXTRA_PX` (`viewLines.ts:101`): extra room
/// revealed to the left of a horizontal box so the target is not flush against
/// the viewport edge.
let horizontal_extra_px : Double = 30.0

///|
/// Monaco's `EditorOption.revealHorizontalRightPadding` default (`editorOptions.ts`
/// `EditorIntOption(..., 15, 0, 1000)`): extra room revealed to the right of a
/// horizontal box.
let reveal_horizontal_right_padding : Double = 15.0

///|
/// The minimal `scroll_left` that brings a horizontal box into view, the pure
/// half of Monaco's `ViewLines._computeScrollLeftToReveal` (`viewLines.ts:784`).
/// The DOM measurement (`measure_line_selection`) lives on `Viewer`; `ranges`
/// are its `(left, width)` client rects in content coordinates (0 = line start).
/// Returns `None` when there is nothing to measure (the line is not rendered, or
/// the range collapsed to a zero-width caret the measurement helper drops).
///
/// `vertical_scrollbar_width` is passed in because the scrollbar geometry is a
/// rendering concern owned by `Viewer`, not by the pure layout core.
pub fn ViewLayout::compute_scroll_left_to_reveal(
  self : ViewLayout,
  ranges : Array[(Double, Double)],
  vertical_scrollbar_width~ : Double,
  minimal_reveal? : Bool = false,
) -> Double? {
  guard ranges is [(first_left, first_width), ..] else { return None }
  let (box_start_x, box_end_x) = for
    range in ranges[1:]
    box_start_x = first_left.round(),
    box_end_x = (first_left + first_width).round() {
    let (left, width) = range
    continue box_start_x.min(left.round()),
      box_end_x.max((left + width).round())
  } nobreak {
    (box_start_x, box_end_x)
  }
  let (box_start_x, box_end_x) = if minimal_reveal {
    (box_start_x, box_end_x)
  } else {
    (
      0.0.max(box_start_x - horizontal_extra_px),
      box_end_x + reveal_horizontal_right_padding,
    )
  }
  // Horizontal measurement uses the current viewport; only the vertical
  // reveal composition above consults the future animated destination.
  let viewport_start_x = self.position().scroll_left
  let viewport_end_x = viewport_start_x +
    self.dimensions().width -
    vertical_scrollbar_width
  Some(
    compute_minimum_scrolling(
      viewport_start_x, viewport_end_x, box_start_x, box_end_x,
    ),
  )
}

///|
/// The minimal scroll that fits a box into a viewport, Monaco's shared
/// `ViewLines._computeMinimumScrolling` (`viewLines.ts:838`), used by both the
/// vertical and horizontal reveal math. `reveal_at_start` / `reveal_at_end`
/// force the box to the viewport's leading / trailing edge (the `Top` / `Bottom`
/// reveal types).
///
/// Replicates Monaco's `| 0` integer truncation of all four pixel inputs for
/// pixel-parity: MoonBit's `Double::to_int` truncates toward zero like JS `| 0`
/// across the 32-bit scroll range the viewer operates in.
fn compute_minimum_scrolling(
  viewport_start : Double,
  viewport_end : Double,
  box_start : Double,
  box_end : Double,
  reveal_at_start? : Bool = false,
  reveal_at_end? : Bool = false,
) -> Double {
  let viewport_start = viewport_start.to_int().to_double()
  let viewport_end = viewport_end.to_int().to_double()
  let box_start = box_start.to_int().to_double()
  let box_end = box_end.to_int().to_double()
  let viewport_length = viewport_end - viewport_start
  let box_length = box_end - box_start
  if box_length < viewport_length {
    // The box would fit in the viewport.
    if reveal_at_start {
      box_start
    } else if reveal_at_end {
      0.0.max(box_end - viewport_length)
    } else if box_start < viewport_start {
      // The box is above the viewport.
      box_start
    } else if box_end > viewport_end {
      // The box is below the viewport.
      0.0.max(box_end - viewport_length)
    } else {
      viewport_start
    }
  } else {
    // The box would not fit in the viewport: reveal the beginning of the box.
    box_start
  }
}

///|
#deprecated
pub extend VerticalRevealType with Debug::{to_repr}

///|
pub extend VerticalRevealType with Eq::{equal, not_equal}
