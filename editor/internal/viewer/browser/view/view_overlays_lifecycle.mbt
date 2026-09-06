///|
fn current_line_scroll_changed(event : ViewScrollChangedEvent) -> Bool {
  event.scroll_width_changed || event.scroll_top_changed
}

// Margin aggregate event and render adapters.

///|
fn margin_view_overlays_on_view_event(
  part : MarginViewOverlays,
  event : ViewEvent,
) -> Bool {
  let _self = part
  match event {
    ViewFlushed => true
    ViewTokensChanged(_) => {
      _self.overlays.on_content_or_tokens_changed()
      true
    }
    // The line-decorations lane renders margin decorations
    // (`LinesDecorationsOverlay.onDecorationsChanged` → true); the
    // glyph-margin view part stays deferred.
    ViewDecorationsChanged => true
    ViewScrollChanged(e) => {
      let nested_current_line_dirty = current_line_scroll_changed(e)
      // The retained ViewOverlays collection itself always invalidates on a
      // scroll event; keep the nested predicate evaluated and explicit.
      nested_current_line_dirty || true
    }
    ViewConfigurationChanged(_) => {
      _self.on_configuration_changed()
      _self.current_line_margin.state.on_configuration_changed()
      true
    }
    ViewLineMappingChanged => true
    ViewZonesChanged => true
    // The margin current-line highlight follows the cursor and the focus
    // state (`currentLineHighlight.ts:97-100,:116-123`).
    ViewCursorStateChanged(e) => {
      let nested_current_line_dirty = _self.current_line_margin.state.on_cursor_state_changed(
        e.selections,
      )
      // Pinned `LineNumbersOverlay.onCursorStateChanged` is also false for an
      // absolute-line-number, same-model-line column move. The fixed grouped
      // local handle deliberately over-renders that branch; the focused
      // white-box test proves retained rows/classes/styles perform zero DOM
      // writes when every nested result is unchanged.
      nested_current_line_dirty || true
    }
    ViewFocusChanged(e) => {
      _self.overlays.on_focus_changed(e.is_focused)
      _self.current_line_margin.state.on_focus_changed(e.is_focused) |> ignore
      true
    }
  }
}

///|
fn margin_view_overlays_prepare_render(
  part : MarginViewOverlays,
  context : RenderingContext,
) -> Unit {
  let self = part
  // `ViewOverlays.prepareRender` (`viewOverlays.ts:113-121`).
  self.overlays.prepare_overlays(context)
}

///|
fn margin_view_overlays_render(
  part : MarginViewOverlays,
  context : RestrictedRenderingContext,
) -> Unit {
  let self = part
  // `MarginViewOverlays._viewOverlaysRender` (`viewOverlays.ts:262-266`):
  // render the rows, size the container to `_contentLeft`. The `.margin`
  // clip is viewport-fixed; the rows container carries the vertical rail
  // translation (the viewer's `margin_transform`).
  self.overlays.render_lines(context.viewport)
  let margin_style = "width:\{self.content_left.to_string()}px"
  if self.dom_node.get_attribute("style") != Some(margin_style) {
    self.dom_node.set_attribute("style", margin_style)
  }
  self.render_focused()
  let overlays = self.overlays.dom_node.element()
  let height = context.dimensions.scroll_height.min(1000000.0)
  let overlays_style = "\{context.margin_transform};width:\{self.content_left.to_string()}px;height:\{height.to_string()}px"
  if overlays.get_attribute("style") != Some(overlays_style) {
    overlays.set_attribute("style", overlays_style)
  }
}

///|
fn prepare_current_line_margin_overlay(
  part : CurrentLineMarginHighlightOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  let state = self.state
  let cursor_view_line = state.cursor_line_numbers.get(0)
  self.render_result = prepare_current_line_margin_render(
    context.viewport,
    Some(context.input.view_model),
    cursor_view_line,
    state.selection_is_empty,
    state.focused,
    state.word_wrap,
    state.render_line_highlight,
    state.render_line_highlight_only_when_focus,
    // `_contentLeft`, the margin width (cLH:227).
    state.content_left,
  )
}

///|
fn prepare_lines_decorations_overlay(
  part : LinesDecorationsOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  // `ctx.getDecorationsInViewport()` (`linesDecorations.ts:73`): the same
  // cached viewport decoration collection the content overlays read.
  let decorations = context.input.view_model
    .decorations()
    .get_decorations_viewport_data(context.viewport.visible_range).decorations
  let to_render = @view_model.lines_decorations_to_render(decorations)
  let class_names_per_line = @view_model.dedup_margin_decorations(
    context.viewport.start_line_number,
    context.viewport.start_line_number + context.viewport.lines.length() - 1,
    to_render,
  )
  // `layoutInfo.decorationsLeft`: the lane sits between the line numbers
  // and the content.
  let line_numbers_width = context.gutter_width -
    context.input.line_decorations_width
  self.render_result = prepare_lines_decorations_render(
    class_names_per_line,
    decorations_left=line_numbers_width,
    decorations_width=context.input.line_decorations_width,
  )
}

///|
fn prepare_margin_decorations_overlay(
  part : MarginDecorationsOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  let decorations = context.input.view_model
    .decorations()
    .get_decorations_viewport_data(context.viewport.visible_range).decorations
  let to_render = margin_decorations_to_render(decorations)
  let class_names_per_line = dedup_whole_margin_decorations(
    context.viewport.start_line_number,
    context.viewport.start_line_number + context.viewport.lines.length() - 1,
    to_render,
  )
  self.render_result = prepare_margin_decorations_render(class_names_per_line)
}

///|
fn prepare_line_numbers_overlay(
  part : LineNumbersOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  // `layoutInfo.lineNumbersLeft`/`lineNumbersWidth`: the band left of the
  // line-decorations lane.
  let line_numbers_width = context.gutter_width -
    context.input.line_decorations_width
  let active_model_line_number = context.input.view_selection.map(selection => {
    context.input.view_model
    .coordinates_converter()
    .view_position_to_model_position(selection.get_position()).line_number
  })
  self.render_result = prepare_line_numbers_render(
    context.viewport,
    Some(context.input.view_model),
    active_model_line_number,
    left=0.0,
    width=line_numbers_width,
  )
}

// OverlayWidgets retains ordinary lifecycle membership so a dirty event can
// converge even though its current prepare/write phases are empty.

///|
fn overlay_widgets_on_view_event(
  _part : OverlayWidgets,
  event : ViewEvent,
) -> Bool {
  match event {
    ViewScrollChanged(e) => e.scroll_width_changed || e.scroll_height_changed
    ViewConfigurationChanged(_) => true
    _ => false
  }
}

///|
fn overlay_widgets_prepare_render(
  _part : OverlayWidgets,
  _context : RenderingContext,
) -> Unit {
  ()
}

///|
fn overlay_widgets_render(
  _part : OverlayWidgets,
  _context : RestrictedRenderingContext,
) -> Unit {
  ()
}

// EditorScrollbar event and render adapters.

///|
fn editor_scrollbar_on_view_event(
  _part : EditorScrollbar,
  event : ViewEvent,
) -> Bool {
  match event {
    ViewScrollChanged(_) => true
    ViewConfigurationChanged(_) => true
    _ => false
  }
}

///|
fn editor_scrollbar_prepare_render(
  _part : EditorScrollbar,
  _context : RenderingContext,
) -> Unit {
  ()
}

///|
fn editor_scrollbar_render(
  part : EditorScrollbar,
  context : RestrictedRenderingContext,
) -> Unit {
  let self = part
  // `EditorScrollbar._setLayout` (`editorScrollbar.ts:109-123`): the scrollable
  // shell starts at contentLeft; the shared lines-content rail itself is free
  // to move left by the current synthetic scroll position.
  self.scrollbar_dom_node.set_left(Pixels(context.gutter_width))
  self.scrollbar_dom_node.set_width(Pixels(context.dimensions.width))
  self.scrollbar_dom_node.set_height(Pixels(context.dimensions.height))
  self.editor_scrollable.update_from_model(context.dimensions, context.position)
}

// Event and render adapters for `ContentViewOverlays` (`view_overlays.mbt`, this
// package — Monaco's `viewOverlays.ts`). The dynamic overlays prepare in the
// read phase (measuring off the freshly written line DOM) and the rows write
// in `render`, Monaco's split.

///|
fn content_view_overlays_on_view_event(
  part : ContentViewOverlays,
  event : ViewEvent,
) -> Bool {
  let _self = part
  match event {
    ViewFlushed => true
    ViewTokensChanged(_) => {
      _self.overlays.on_content_or_tokens_changed()
      true
    }
    // `DecorationsOverlay.onDecorationsChanged` (`decorations.ts:44-46`).
    ViewDecorationsChanged => true
    // `DecorationsOverlay.onConfigurationChanged` (`decorations.ts:39-43`)
    // and `AbstractLineHighlightOverlay.onConfigurationChanged` (`:87-96`)
    // both re-read their live configuration before returning true.
    ViewConfigurationChanged(_) => {
      _self.on_configuration_changed()
      _self.current_line.state.on_configuration_changed()
      true
    }
    ViewScrollChanged(e) => {
      let nested_current_line_dirty = current_line_scroll_changed(e)
      nested_current_line_dirty || true
    }
    ViewCursorStateChanged(e) => {
      let nested_current_line_dirty = _self.current_line.state.on_cursor_state_changed(
        e.selections,
      )
      // The selections overlay consumes every cursor event.
      nested_current_line_dirty || true
    }
    ViewLineMappingChanged => true
    ViewZonesChanged => true
    // `ViewOverlays.onFocusChanged` (`viewOverlays.ts:76-79`).
    ViewFocusChanged(e) => {
      _self.overlays.on_focus_changed(e.is_focused)
      _self.current_line.state.on_focus_changed(e.is_focused) |> ignore
      true
    }
  }
}

///|
fn content_view_overlays_prepare_render(
  part : ContentViewOverlays,
  context : RenderingContext,
) -> Unit {
  let self = part
  // `ViewOverlays.prepareRender` (`viewOverlays.ts:113-121`): each dynamic
  // overlay builds its per-line `_renderResult` off the read context.
  self.overlays.prepare_overlays(context)
}

///|
fn content_view_overlays_render(
  part : ContentViewOverlays,
  context : RestrictedRenderingContext,
) -> Unit {
  let self = part
  // `ContentViewOverlays._viewOverlaysRender` (`viewOverlays.ts:225-229`):
  // render the rows, then size the container to
  // `max(ctx.scrollWidth, contentWidth)`.
  self.overlays.render_lines(context.viewport)
  let width = context.dimensions.scroll_width.max(self.content_width)
  self.set_focused(self.overlays.is_focused)
  self.overlays.dom_node.set_width(Pixels(width))
}

// Content-overlay lifecycle wiring stays beside the package-private
// `RenderingContext`; the focused overlay source units provide the pure HTML
// builders it invokes.

///|
fn prepare_current_line_overlay(
  part : CurrentLineHighlightOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  let state = self.state
  let cursor_view_line = state.cursor_line_numbers.get(0)
  self.render_result = prepare_current_line_render(
    context.viewport,
    Some(context.input.view_model),
    cursor_view_line,
    state.selection_is_empty,
    state.focused,
    state.word_wrap,
    state.render_line_highlight,
    state.render_line_highlight_only_when_focus,
    // `max(ctx.scrollWidth, this._contentWidth)` (cLH:211).
    context.dimensions.scroll_width.max(state.content_width),
  )
}

///|
fn prepare_selections_overlay(
  part : SelectionsOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  let visible_ranges : Array[(Int, Array[(Double, Double)])] = []
  if context.input.selection_view_range is Some(selection) &&
    context.lines_visible_ranges_for_range(selection, true) is Some(lines) {
    for line in lines {
      let ranges = line.ranges.map(range => {
        (range.left.to_double(), range.width.to_double())
      })
      visible_ranges.push((line.line_number, ranges))
    }
  }
  self.render_result = prepare_selections_render_from_visible_ranges(
    context.viewport,
    visible_ranges,
    context.input.space_width,
  )
}

///|
fn prepare_decorations_overlay(
  part : DecorationsOverlay,
  context : RenderingContext,
) -> Unit {
  let self = part
  // `ctx.getDecorationsInViewport()` (`decorations.ts:68`): the viewport's
  // decoration collection (a cache hit — the viewport data resolved the same
  // range).
  let decorations = context.input.view_model
    .decorations()
    .get_decorations_viewport_data(context.viewport.visible_range).decorations
  self.render_result = prepare_decorations_render(
    decorations,
    context.viewport.start_line_number,
    context.viewport.end_line_number,
    line_number => {
      context.input.view_model.lines().get_view_line_max_column(line_number)
    },
    context.view_context.measure_line_decorations,
    context.input.space_width,
  )
}
