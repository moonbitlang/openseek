///|
/// Content-coordinate scroll surface, Monaco's `CodeEditorWidget.reveal*`
/// family (`vs/editor/browser/widget/codeEditor/codeEditorWidget.ts:705`–
/// `:946`). These take a model `Position` / `Range` ("line 10, column 15") and
/// compute the minimal scroll to bring it into view, complementing the
/// pixel- and delta-based `scroll_*` entry points above. Public reveal APIs are
/// immediate; cursor commands use the source's Smooth request, which the
/// ViewLayout downgrades to immediate for a vertical delta of at most one line
/// and also becomes immediate when smooth scrolling is disabled.

///|
/// Reveals a 1-based model position, aligning its top (`Simple`) and revealing
/// it horizontally.
pub fn CodeEditorWidget::reveal_position(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Unit {
  self.reveal_position_with(position, Simple)
}

///|
/// Reveals a 1-based model position centered only if it is currently outside
/// the viewport (`CenterIfOutsideViewport`), horizontally too.
pub fn CodeEditorWidget::reveal_position_in_center_if_outside_viewport(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Unit {
  self.reveal_position_with(position, CenterIfOutsideViewport)
}

///|
fn CodeEditorWidget::reveal_line_with(
  self : CodeEditorWidget,
  line_number : Int32,
  vertical_type : @view_layout.VerticalRevealType,
) -> Unit {
  // Monaco's `_revealLine`: a single-line collapsed range, no horizontal reveal.
  let range = @base_common.Range(line_number, 1, line_number, 1)
  self.send_reveal_range(range, vertical_type, reveal_horizontal=false)
}

///|
fn CodeEditorWidget::reveal_lines_with(
  self : CodeEditorWidget,
  start_line_number : Int32,
  end_line_number : Int32,
  vertical_type : @view_layout.VerticalRevealType,
) -> Unit {
  // Monaco's `_revealLines`: a multi-line range, no horizontal reveal.
  let range = @base_common.Range(start_line_number, 1, end_line_number, 1)
  self.send_reveal_range(range, vertical_type, reveal_horizontal=false)
}

///|
fn CodeEditorWidget::reveal_position_with(
  self : CodeEditorWidget,
  position : @base_common.Position,
  vertical_type : @view_layout.VerticalRevealType,
) -> Unit {
  // Monaco's `_revealPosition`: a collapsed range at the position, with
  // horizontal reveal.
  let range = @base_common.Range(
    position.line_number,
    position.column,
    position.line_number,
    position.column,
  )
  self.send_reveal_range(range, vertical_type, reveal_horizontal=true)
}

///|
/// Presentation-routing entry for every public model-coordinate reveal.
fn CodeEditorWidget::send_reveal_range(
  self : CodeEditorWidget,
  model_range : @base_common.Range,
  vertical_type : @view_layout.VerticalRevealType,
  reveal_horizontal~ : Bool,
  source~ : String = "",
  minimal_reveal~ : Bool = false,
  scroll_type~ : CursorRevealScrollType = Immediate,
) -> Unit {
  guard self.is_code_presentation() else { return }
  self.send_code_reveal_range(
    model_range,
    vertical_type,
    reveal_horizontal~,
    source~,
    minimal_reveal~,
    scroll_type~,
  )
}

///|
/// The Code reveal pipeline, Monaco's `CodeEditorWidget._sendRevealRange`
/// (`codeEditorWidget.ts:685`) folded together with
/// `ViewLines.onRevealRangeRequest` (`viewLines.ts:269`).
fn CodeEditorWidget::send_code_reveal_range(
  self : CodeEditorWidget,
  model_range : @base_common.Range,
  vertical_type : @view_layout.VerticalRevealType,
  reveal_horizontal~ : Bool,
  source~ : String = "",
  minimal_reveal~ : Bool = false,
  scroll_type~ : CursorRevealScrollType = Immediate,
) -> Unit {
  guard self.is_code_presentation() else { return }
  guard self.get_view_model() is Some(view_model) else { return }
  // (1) Model range → view range: the wrapping-aware step (with word-wrap on,
  // model line ≠ view line). The conversion belongs at this boundary, never in
  // the pure core.
  let view_range = view_model
    .coordinates_converter()
    .model_range_to_view_range(model_range)
  self.send_reveal_view_range(
    view_range,
    vertical_type,
    reveal_horizontal~,
    source~,
    minimal_reveal~,
    scroll_type~,
  )
}

///|
/// Reveals the active cursor's authoritative view position. Cursor navigation
/// already resolved wrap/injected-text ambiguity; converting its model
/// position back to view space can choose a different projection, so command
/// reveal paths enter below the model-to-view boundary.
fn CodeEditorWidget::reveal_view_cursor(
  self : CodeEditorWidget,
  horizontal~ : Bool,
  source~ : String = "",
  minimal_reveal~ : Bool = false,
  scroll_type~ : CursorRevealScrollType = Immediate,
) -> Unit {
  guard self.is_code_presentation() else { return }
  guard self.get_view_model() is Some(view_model) else { return }
  let position = view_model.cursor.view_state().position
  self.send_reveal_view_range(
    Range(
      position.line_number,
      position.column,
      position.line_number,
      position.column,
    ),
    Simple,
    reveal_horizontal=horizontal,
    source~,
    minimal_reveal~,
    scroll_type~,
  )
}

///|
/// Shared post-conversion reveal pipeline. Public model-coordinate reveal APIs
/// reach this through `send_reveal_range`; cursor commands call it with the
/// already-committed view position.
fn cursor_reveal_should_smooth(
  scroll_type : CursorRevealScrollType,
  scroll_top_delta : Double,
  line_height : Int32,
) -> Bool {
  scroll_type == Smooth && scroll_top_delta > line_height.to_double()
}

///|
/// Applies the complete validated scroll position. Passing both axes is
/// load-bearing: a new vertical reveal cancels any older animated horizontal
/// destination by restoring the current validated `scroll_left`, matching
/// `ViewLayout.setScrollPosition(newScrollPosition, scrollType)`.
fn apply_cursor_reveal_scroll_position(
  layout : @view_layout.ViewLayout,
  target : @view_layout.ScrollPosition,
  smooth : Bool,
) -> Unit {
  if smooth {
    layout.scroll_to_smooth(
      scroll_top=target.scroll_top,
      scroll_left=target.scroll_left,
    )
  } else {
    layout.scroll_to(
      scroll_top=target.scroll_top,
      scroll_left=target.scroll_left,
    )
    |> ignore
  }
}

///|
/// Builds the browser-only single-line request without mutating CodeEditorWidget state.
/// A multi-line horizontal reveal deliberately returns `None` without clearing
/// an older request; its scroll-to-base change normally performs cancellation.
fn horizontal_reveal_request_for_range(
  view_range : @base_common.Range,
  minimal_reveal : Bool,
  start_scroll_top : Double,
  stop_scroll_top : Double,
  scroll_type : CursorRevealScrollType,
) -> HorizontalRevealRangeRequest? {
  if view_range.start_line_number != view_range.end_line_number {
    return None
  }
  Some({
    minimal_reveal,
    view_line_number: view_range.start_line_number,
    start_column: view_range.start_column,
    end_column: view_range.end_column,
    start_scroll_top,
    stop_scroll_top,
    scroll_type,
  })
}

///|
fn CodeBrowserData::arm_horizontal_reveal(
  self : CodeBrowserData,
  request : HorizontalRevealRangeRequest,
) -> Unit {
  self.horizontal_reveal_request = Some(request)
}

///|
fn CodeBrowserData::clear_horizontal_reveal(self : CodeBrowserData) -> Unit {
  self.horizontal_reveal_request = None
}

///|
fn CodeEditorWidget::send_reveal_view_range(
  self : CodeEditorWidget,
  view_range : @base_common.Range,
  vertical_type : @view_layout.VerticalRevealType,
  reveal_horizontal~ : Bool,
  source~ : String = "",
  minimal_reveal~ : Bool = false,
  scroll_type~ : CursorRevealScrollType = Immediate,
) -> Unit {
  guard self.get_view_model() is Some(view_model) else { return }
  // (2) Minimal vertical scroll for the view range.
  let scroll_top = view_model.view_layout.compute_scroll_top_to_reveal_range(
    view_range.start_line_number,
    view_range.end_line_number,
    vertical_type,
    source~,
    minimal_reveal~,
  )
  // Monaco's `-1` abort sentinel (oversized multi-cursor reveal); the viewer
  // only reveals single ranges, so this never fires today but is preserved so a
  // sentinel is never mistaken for a real offset.
  if scroll_top == -1.0 {
    return
  }
  let multi_line = view_range.start_line_number != view_range.end_line_number
  let start_scroll_top = view_model.view_layout.position().scroll_top
  let reset_scroll_left = reveal_horizontal && multi_line
  let target = view_model.view_layout.validate_scroll_position({
    scroll_left: if reset_scroll_left {
      Some(0.0)
    } else {
      None
    },
    scroll_top: Some(scroll_top),
  })
  // (3) Install horizontal bookkeeping before applying the reveal scroll,
  // exactly like `ViewLines.onRevealRangeRequest`. The start/stop band keeps
  // the reveal's own vertical scroll from cancelling this request.
  if reveal_horizontal {
    match
      horizontal_reveal_request_for_range(
        view_range,
        minimal_reveal,
        start_scroll_top,
        target.scroll_top,
        scroll_type,
      ) {
      Some(request) =>
        match self.current_code_browser_data() {
          Some(browser) => {
            browser.arm_horizontal_reveal(request)
            self.schedule_render()
          }
          None => ()
        }
      None => ()
    }
  } else {
    match self.current_code_browser_data() {
      Some(browser) => browser.clear_horizontal_reveal()
      None => ()
    }
  }
  // (4) Commit the vertical scroll. A multi-line range under horizontal reveal
  // also resets `scroll_left` to 0 so most of both lines show
  // (`viewLines.ts:282`–`:289`). Smooth requests whose vertical delta is at
  // most one line are downgraded to Immediate (`viewLines.ts:299-301`).
  let scroll_top_delta = (start_scroll_top - target.scroll_top).abs()
  let use_smooth = cursor_reveal_should_smooth(
    scroll_type,
    scroll_top_delta,
    view_model.view_layout.line_height(),
  )
  apply_cursor_reveal_scroll_position(
    view_model.view_layout,
    target,
    use_smooth,
  )
}

///|
/// Flushes a deferred horizontal reveal once its target line has rendered, the
/// Monaco `ViewLines.renderText` horizontal step (`viewLines.ts:623`–`:648`).
/// Called from `flush_render` after the lines are in the DOM. Keeps the request
/// pending if the line is not yet rendered, so a later frame can flush it.
fn CodeBrowserData::flush_horizontal_reveal(
  self : CodeBrowserData,
  view_model : @view_model.ViewModel,
) -> Unit {
  guard self.horizontal_reveal_request is Some(request) else { return }
  // The line is not in the rendered window yet — keep waiting.
  guard self.view.is_line_rendered(request.view_line_number) else { return }
  // The line is rendered: consume the request (Monaco nulls it here) and apply
  // the horizontal scroll, if any was measurable.
  self.horizontal_reveal_request = None
  // `keep_empty=true`: a collapsed range (a `reveal_position` caret) measures to
  // a single zero-width rect at the caret x, which Monaco keeps and reveals.
  let ranges = self.view.measure_line_selection(
    request.view_line_number,
    request.start_column - 1,
    request.end_column - 1,
    keep_empty=true,
  )
  match
    view_model.view_layout.compute_scroll_left_to_reveal(
      ranges,
      vertical_scrollbar_width=@core.editor_vertical_scrollbar_size,
      minimal_reveal=request.minimal_reveal,
    ) {
    Some(scroll_left) =>
      // Set only `scroll_left`; preserve any still-animated vertical target.
      match request.scroll_type {
        Smooth =>
          view_model.view_layout.scroll_to_smooth(
            scroll_top=view_model.view_layout.future_position().scroll_top,
            scroll_left~,
          )
        Immediate => {
          let scroll_top = view_model.view_layout.position().scroll_top
          view_model.view_layout.scroll_to(scroll_top~, scroll_left~) |> ignore
        }
      }
    None => ()
  }
}

///|
fn HorizontalRevealRangeRequest::should_cancel_on_scroll(
  self : HorizontalRevealRangeRequest,
  change : @view_layout.ScrollChange,
) -> Bool {
  if change.left_changed {
    return true
  }
  if !change.top_changed {
    return false
  }
  let scroll_top = change.position.scroll_top
  let low = self.start_scroll_top.min(self.stop_scroll_top)
  let high = self.start_scroll_top.max(self.stop_scroll_top)
  scroll_top < low || scroll_top > high
}

///|
/// Monaco's `ViewLines.onScrollChanged` horizontal-cancel (`viewLines.ts:305`–
/// `:317`): drop a pending horizontal reveal when an unrelated scroll moves the
/// horizontal position, or moves the vertical position outside the reveal's
/// `[start_scroll_top, stop_scroll_top]` band. The reveal's own vertical scroll
/// lands inside that band and does not change `scroll_left`, so it never
/// cancels itself.
fn CodeBrowserData::cancel_horizontal_reveal_on_scroll(
  self : CodeBrowserData,
  change : @view_layout.ScrollChange,
) -> Unit {
  guard self.horizontal_reveal_request is Some(request) else { return }
  if request.should_cancel_on_scroll(change) {
    self.horizontal_reveal_request = None
  }
}
