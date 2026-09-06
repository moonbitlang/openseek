// The viewer core's side of the content-hover widget seam: Monaco's
// `ContentHoverWidgetWrapper._showHover`/`_hideHover` (driving the persistent
// `ContentHoverWidget` when `_setCurrentResult` changed the shown result) plus
// the `ICodeEditor` surface the widget consumes (`addContentWidget` /
// `layoutContentWidget` / `render`), expressed as `CodeEditorWidget::` glue beside the
// root-owned CodeEditorWidget state. Keeping the contribution package below the facade
// also avoids an internal-contribution -> root-viewer dependency.

///|
/// Reconciles the persistent content-hover widget with the controller's
/// derived view. Idempotent (dedupes on the `HoverWidgetView`), so every
/// hover-state chokepoint may call it: Monaco's `_setCurrentResult` calls
/// `_showHover`/`_hideHover` exactly when the result object changed.
fn CodeEditorWidget::sync_content_hover_widget(self : CodeEditorWidget) -> Unit {
  guard self.content_hover_contribution() is Some(state) else { return }
  let hc = state.controller
  let loading_message = if hc.hover.operation.shows_loading_message() {
    hc.hover.anchor.bind(anchor => {
      self.make_hover_computer().create_loading_message(anchor)
    })
  } else {
    None
  }
  let widget_view = hc.hover.widget_view_with_loading(loading_message)
  if widget_view == state.widget_view {
    return
  }
  state.widget_view = widget_view
  match widget_view {
    Some(view) =>
      match self.ensure_content_hover_widget() {
        Some(widget) => widget.show(self.rendered_content_hover(view))
        None => ()
      }
    None =>
      match state.widget {
        Some(widget) => widget.hide()
        None => ()
      }
  }
}

///|
/// Logical live visibility after participant-selected loading augmentation.
/// This is the source of truth for controller scheduling/command predicates;
/// it stays correct in headless tests where no DOM widget can be mounted.
fn CodeEditorWidget::content_hover_visible(self : CodeEditorWidget) -> Bool {
  match self.content_hover_contribution() {
    Some(state) => state.widget_view is Some(_)
    None => false
  }
}

///|
/// Wrapper mouseleave: hide only when the pointer also left the editor root.
fn CodeEditorWidget::on_content_hover_widget_mouse_leave(
  self : CodeEditorWidget,
  posx : Double,
  posy : Double,
) -> Unit {
  guard self.current_code_view() is Some(view) else {
    self.hide_content_hover()
    return
  }
  let rect = view.root.get_bounding_client_rect()
  if !@hover.mouse_within_element(
      rect.get_left(),
      rect.get_top(),
      rect.get_width(),
      rect.get_height(),
      posx,
      posy,
    ) {
    self.hide_content_hover()
  }
}

///|
/// Monaco `RenderedContentHover`'s constructor work
/// (`contentHoverRendered.ts`): resolve where the widget anchors
/// (`computeHoverPositions` over the parts, with the anchor view line's
/// minimum column as the `startColumnBoundary`) and hand the ordered parts to
/// the browser widget, which owns their retained DOM rendering.
fn CodeEditorWidget::rendered_content_hover(
  self : CodeEditorWidget,
  view : @hover.HoverWidgetView,
) -> @hover_browser.RenderedContentHover {
  let placement_parts : Array[@hover.HoverPositionPart] = view.parts.map(part => {
    range: @hover.hover_part_range(part),
    force_show_at_range: false,
  })
  // `startColumnBoundary` (`contentHoverRendered.ts:127-133`): the anchor view
  // line's minimum column, converted back to model space — under wrapping this
  // is the wrapped row's first model column.
  let anchor_start = view.anchor_range.get_start_position()
  let start_column_boundary = match
    self.model_to_view_position(anchor_start.line_number, anchor_start.column) {
    Some(view_position) =>
      self.view_to_model(Position(view_position.line_number, 1)).column
    None => 1
  }
  let (show_at_position, show_at_secondary_position) = @hover.compute_hover_positions(
    view.anchor_range,
    placement_parts,
    start_column_boundary,
  )
  let language_id = match self.get_view_model() {
    Some(view_model) => view_model.language_id()
    None => ""
  }
  {
    show_at_position,
    show_at_secondary_position,
    parts: view.parts,
    language_id,
  }
}

///|
/// Lazily constructs the widget and mounts it — Monaco's
/// `ContentHoverWidget` constructor calling `_editor.addContentWidget(this)`.
/// The widget itself is created once per `CodeEditorWidget`; each per-model `View`
/// re-adds it through the code presentation's widget re-add loop
/// (`cew:1893-1899`).
/// `None` before a view exists.
fn CodeEditorWidget::ensure_content_hover_widget(
  self : CodeEditorWidget,
) -> @hover_browser.ContentHoverWidget? {
  guard self.content_hover_contribution() is Some(state) else { return None }
  match state.widget {
    Some(widget) => Some(widget)
    None => {
      let mounted = match self.mount {
        Headless => return None
        Mounted(mounted) => mounted
      }
      guard self.current_code_view() is Some(view) else { return None }
      let widget = @hover_browser.ContentHoverWidget({
        // Monaco's `ContentHoverWidget` retains the editor and measures its
        // stable `_domElement`; a per-model View root is disposed on every
        // `setModel` transition and cannot outlive this persistent widget.
        root: mounted.container,
        layout_content_widget: () => self.layout_content_hover_widget(),
        render_now: () => self.flush_render(),
        focus_editor: () => self.focus(),
        scrolled_visible_position_top: position => {
          self.scrolled_visible_position_top(position)
        },
        // Monaco reads `EditorOption.lineHeight` — configuration, not layout.
        line_height: () => {
          self.configuration.snapshot().font_info.line_height.to_double()
        },
        keep_hover_open: () => self.keep_hover_open(),
        handle_mouseleave: (posx, posy) => {
          self.on_content_hover_widget_mouse_leave(posx, posy)
        },
        handle_keydown: (event, keyboard) => {
          self.handle_hover_keydown(event, keyboard)
        },
        hook_scrollable_scrollbar_input: (scrollable, owner) => {
          match self.current_code_browser_data() {
            Some(browser) =>
              browser.mouse_handler.hook_scrollable_scrollbar_input(
                scrollable, owner,
              )
            None => ()
          }
        },
      })
      state.widget = Some(widget)
      view.content_widgets.add_widget(widget.content_widget_handle())
      Some(widget)
    }
  }
}

///|
/// Monaco `ICodeEditor.layoutContentWidget(widget)`: re-read the widget's
/// `get_position()` into the content-widgets part and repaint.
fn CodeEditorWidget::layout_content_hover_widget(
  self : CodeEditorWidget,
) -> Unit {
  guard self.current_code_view() is Some(view) else { return }
  guard self.content_hover_contribution() is Some(state) else { return }
  guard state.widget is Some(widget) else { return }
  view.content_widgets.set_widget_position(widget.content_widget_handle())
  self.schedule_render()
}

///|
/// Monaco `ICodeEditor.getScrolledVisiblePosition(position).top`: the model
/// position's line top in editor-viewport pixels.
fn CodeEditorWidget::scrolled_visible_position_top(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> Double {
  guard self.get_view_model() is Some(view_model) else { return 0.0 }
  match self.model_to_view_position(position.line_number, position.column) {
    Some(view_position) =>
      view_model.view_layout.vertical_offset_for_line(view_position.line_number) -
      view_model.view_layout.position().scroll_top
    None => 0.0
  }
}
