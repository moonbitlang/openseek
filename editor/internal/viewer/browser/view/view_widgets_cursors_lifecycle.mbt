// ContentWidgets lifecycle wiring projects the shared RenderingContext into
// the focused `ContentWidgetsRenderContext` capability record.

///|
// Widget position changes invalidate this part directly through
// `set_widget_position` (Monaco `setWidgetPosition`'s `setShouldRender`). The
// mapping family also reprojects retained model anchors synchronously before
// returning `true`; configuration delegates its exact `layoutInfo` bit to all
// retained widgets before dirtying.
fn content_widgets_on_view_event(
  part : ContentWidgets,
  event : ViewEvent,
) -> Bool {
  let self = part
  match event {
    ViewFlushed => true
    ViewConfigurationChanged(e) => {
      self.on_configuration_changed(e.has_changed(LayoutInfo))
      true
    }
    ViewDecorationsChanged => true
    ViewLineMappingChanged => {
      self.update_anchors_view_positions()
      true
    }
    ViewScrollChanged(_) => true
    ViewZonesChanged => true
    _ => false
  }
}

///|
/// Monaco `ViewContentWidgets.prepareRender`: compute each widget's box
/// layout for this frame from its recorded anchors.
fn content_widgets_prepare_render(
  part : ContentWidgets,
  context : RenderingContext,
) -> Unit {
  let self = part
  self.prepare_render_widgets(context.content_widgets_render_context())
}

///|
/// Monaco `ViewContentWidgets.render`: write each widget's `top`/`left`/
/// `visibility` onto its mounted DOM — never content, never a re-mount.
fn content_widgets_render(
  part : ContentWidgets,
  context : RestrictedRenderingContext,
) -> Unit {
  let self = part
  self.render_widgets(
    context.position.scroll_top,
    context.viewport.big_numbers_delta.to_double(),
  )
}

// `ViewCursors` lifecycle wiring stays beside the shared
// `RenderingContext` / `ViewContext` capabilities it consumes.

///|
// Event map from the consumed `viewCursors.ts` slice: `onFlushed` (:180),
// token/decorations invalidation (:176,:200), `onScrollChanged`
// (:197, unconditionally true), `onCursorStateChanged` (:161),
// `onConfigurationChanged` (:112), `onZonesChanged` (:219), `onFocusChanged`
// (:183 — Monaco flips visibility inline and returns false; the readonly port
// performs the same immediate `on_focus_changed` side effect without dirtying
// the part). No `onLineMappingChanged` handler in Monaco —
// a remap that moves the cursor arrives as `ViewCursorStateChanged` via the
// reprojected view selection.
fn view_cursors_on_view_event(part : ViewCursors, event : ViewEvent) -> Bool {
  let self = part
  match event {
    ViewFlushed => true
    ViewScrollChanged(_) => true
    ViewCursorStateChanged(e) => {
      self.last_position = match e.selections {
        [primary, ..] => Some(primary.get_position())
        [] => None
      }
      let selection_is_empty = match e.selections {
        [primary, ..] => primary.is_empty()
        [] => true
      }
      // `ViewCursors.onCursorStateChanged` updates the layer class
      // synchronously, but only when the selection shape crosses the
      // empty/nonempty boundary. Keep the last rendered cursor rectangle
      // paired with its old position until the next render completes.
      if self.selection_is_empty != selection_is_empty {
        self.selection_is_empty = selection_is_empty
        self.dom_node.set_attribute(
          "class",
          cursors_layer_class(!self.selection_is_empty),
        )
      }
      true
    }
    ViewDecorationsChanged => true
    ViewConfigurationChanged(_) => true
    ViewTokensChanged(e) =>
      self.last_position is Some(position) &&
      e.ranges.any(range => {
        position.line_number >= range.from_line_number &&
        position.line_number <= range.to_line_number
      })
    ViewZonesChanged => true
    ViewFocusChanged(e) => {
      // Source `onFocusChanged`: update cursor visibility immediately, but do
      // not dirty the part.
      self.on_focus_changed(e.is_focused)
      false
    }
    _ => false
  }
}

///|
// `ViewCursor._prepareRender` (`viewCursor.ts:163-203`), Line-style arm: the
// caret x is `ctx.visibleRangeForPosition(position)` — the port measures it
// off the rendered line DOM (`View::offset_for_column` via the
// `ViewContext.offset_for_column` seam; `-1` = line not rendered → Monaco's
// "Outside viewport → null"). The caret top is the line's viewport-relative
// vertical offset, like every flat overlay piece. The result is stored as
// the part's `render_data` (Monaco's `this._renderData`).
fn view_cursors_prepare_render(
  part : ViewCursors,
  context : RenderingContext,
) -> Unit {
  let self = part
  self.render_data = match context.input.view_selection {
    None => None
    Some(selection) => {
      let position = selection.get_position()
      let index = position.line_number - context.viewport.start_line_number
      if index < 0 || index >= context.viewport.lines.length() {
        None
      } else {
        let left = (context.view_context.offset_for_column)(
          position.line_number,
          position.column,
        )
        if left < 0.0 {
          None
        } else {
          Some(
            prepare_cursor_render_data(
              left,
              context.viewport.relative_vertical_offset[index],
              context.viewport.line_height,
              @base_browser.device_pixel_ratio(),
            ),
          )
        }
      }
    }
  }
  // Monaco's `ViewCursor._position`, kept even while outside the viewport so
  // token-range invalidation can test the primary cursor line exactly.
  self.last_position = context.input.view_selection.map(selection => {
    selection.get_position()
  })
}

///|
fn view_cursors_render(
  part : ViewCursors,
  context : RestrictedRenderingContext,
) -> Unit {
  let self = part
  let has_selection = match context.input.view_selection {
    Some(selection) => !selection.is_empty()
    None => false
  }
  self.render_cursor(
    has_selection~,
    editor_has_focus=context.input.editor_has_focus,
  )
  // Source `ViewCursors._renderData` is an array built only by this render
  // pass. Pair the freshly painted rectangle with the position prepared for
  // this same pass; later cursor events leave this pair intact for hit tests.
  self.last_rendered_position = self.last_position
}
