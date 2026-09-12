// The viewer core's side of the `internal/viewer/browser/view` seam: builds the
// `ViewContext` capability struct `View::render` needs (the local analog of
// Monaco's `View` reading its owning `CodeEditorWidget`) and owns the render
// loop entry points. It stays beside the root-owned CodeEditorWidget state so the
// internal view package does not import the public facade and create a
// `internal/viewer/browser/view ↔ viewer` dependency cycle.

///|
fn CodeEditorWidget::build_view_context(
  self : CodeEditorWidget,
  view : @view.View,
) -> @view.ViewContext {
  {
    measure_line_selection: (line_number, start_column, end_column) => {
      view.measure_line_selection(line_number, start_column, end_column)
    },
    measure_line_decorations: (line_number, start_column, end_column) => {
      view.measure_line_selection(
        line_number,
        start_column,
        end_column,
        keep_empty=true,
      )
    },
    offset_for_column: (line_number, column) => {
      view.offset_for_column(line_number, column)
    },
    model_position_to_view_position: position => {
      self
      .model_to_view_position(position.line_number, position.column)
      .unwrap_or(position)
    },
  }
}

///|
/// Monaco `ContentHoverWidget`'s keydown handling, dispatched from the hover
/// widget's own DOM listener via the `ContentHoverWidgetHost.handle_keydown`
/// closure. The keys resolve through the command registry
/// (`hoverActions.ts`'s scroll cluster registered in
/// `hover_contribution.mbt`, gated on `hoverFocused`/`hoverVisible`).
fn CodeEditorWidget::handle_hover_keydown(
  self : CodeEditorWidget,
  event : @rdom.Event,
  keyboard : @rdom.KeyboardEvent,
) -> Unit {
  event.stop_propagation()
  // `KeyMod.CtrlCmd` is Ctrl on Windows/Linux and Cmd on macOS.
  if editor_registry().dispatch_keybinding(
      self,
      keyboard.key(),
      alt=keyboard.alt_key(),
      ctrl_cmd=keyboard.ctrl_key() || keyboard.meta_key(),
      shift=keyboard.shift_key(),
    ) {
    event.prevent_default()
  }
}

///|
/// The rAF-coalesced render loop entry: reads (measurement) before
/// writes, delegates browser DOM work to `View`, then reports the paint
/// facts that were waiting on this flush.
///
/// ```mermaid
/// sequenceDiagram
///   participant F as animation frame
///   participant C as configuration
///   participant VM as ViewModel and layout
///   participant V as browser View
///   participant O as outgoing events
///   F->>C: consume pending measurement
///   alt no model
///     F->>V: paint placeholder
///   else mounted model
///     F->>VM: synchronize rendered window
///     F->>V: render current window
///     V-->>F: DOM is measurable
///     F->>VM: finish deferred horizontal reveal
///     F->>O: publish render telemetry
///     F->>O: publish coalesced scroll event
///   end
/// ```
fn CodeEditorWidget::flush_render(self : CodeEditorWidget) -> Unit {
  if self.disposed {
    return
  }
  // Configuration measurement belongs to the mounted editor, not its optional
  // model/View. Consume it before the no-model branch so `create`/`layout()`
  // keep layout info current while the placeholder is showing.
  if self.configuration.consume_measure_request() {
    self.measure()
  }
  guard self.model_slot.current is Some(model_data) else {
    // No model → no view; the CodeEditorWidget-owned placeholder is the whole paint.
    self.render_placeholder()
    self.publish_render_complete()
    return
  }
  guard model_data.browser is Some(browser) else { return }
  let view = browser.view
  let view_model = model_data.view_model
  // Write phase.
  self.sync_hover_decorations()
  let write_started = @base_browser.monotonic_now_ms()
  let window = browser.sync_rendered_window(view_model)
  let view_context = self.build_view_context(view)
  let configuration = self.configuration.snapshot()
  view.render(view_context, {
    window,
    view_model,
    layout: view_model.view_layout,
    selection_view_range: self.selection_view_range(),
    view_selection: self.view_selection(),
    gutter_width: configuration.gutter_width(
      model_data.model.snapshot.line_count(),
    ),
    line_decorations_width: configuration.layout_decorations_width(),
    space_width: configuration.font_info.space_width,
    typical_fullwidth_character_width: configuration.font_info.typical_fullwidth_character_width,
    editor_has_focus: self.has_text_focus(),
    word_wrap: configuration.word_wrap(),
    render_line_highlight: configuration.options.render_line_highlight,
    render_line_highlight_only_when_focus: configuration.options.render_line_highlight_only_when_focus,
    show_unused: configuration.options.show_unused,
    show_deprecated: configuration.options.show_deprecated,
  })
  // The lines are now in the DOM: a deferred horizontal reveal can measure its
  // target line's client rects and apply the horizontal scroll.
  browser.flush_horizontal_reveal(view_model)
  let patch_ms = @base_browser.monotonic_now_ms() - write_started
  match (self.pending_rendered, browser.rendered_window) {
    (Some(pending), Some(window)) => {
      self.pending_rendered = None
      self.emit_model_rendered({
        model: pending.model,
        line_count: view_model.line_count(),
        rendered_lines: window.end - window.start,
        patch_ms,
        fresh: pending.fresh,
      })
    }
    _ => ()
  }
  if self.scroll_dirty {
    self.scroll_dirty = false
    let position = view_model.view_layout.position()
    let event : @editor_api.ScrollEvent = {
      scroll_top: position.scroll_top,
      scroll_left: position.scroll_left,
      scroll_width: view_model.view_layout.get_scroll_width(),
      scroll_height: view_model.view_layout.get_scroll_height(),
      // Change flags diff against the last fired event; the first event
      // reports every axis as changed.
      scroll_top_changed: true,
      scroll_left_changed: true,
      scroll_width_changed: true,
      scroll_height_changed: true,
    }
    let event = match self.last_scroll_event {
      Some(previous) =>
        {
          ..event,
          scroll_top_changed: event.scroll_top != previous.scroll_top,
          scroll_left_changed: event.scroll_left != previous.scroll_left,
          scroll_width_changed: event.scroll_width != previous.scroll_width,
          scroll_height_changed: event.scroll_height != previous.scroll_height,
        }
      None => event
    }
    self.last_scroll_event = Some(event)
    self.did_scroll.fire(event)
  }
  self.publish_render_complete()
}

///|
/// Publishes one completed DOM paint after all geometry and coalesced scroll
/// facts from that paint have committed. DiffEditor uses this seam instead of
/// inferring paint completion from optional scroll-extent changes.
fn CodeEditorWidget::publish_render_complete(self : CodeEditorWidget) -> Unit {
  if self.disposed {
    return
  }
  self.render_generation += 1
  self.did_render.fire(self.render_generation)
}

///|
/// Runs `callback` once after a render newer than the call site has completed.
/// The returned handle cancels the waiter. The captured generation prevents a
/// render already in progress (or a late callback retained by a former diff
/// layout transaction) from crossing the fence.
pub fn CodeEditorWidget::after_next_render(
  self : CodeEditorWidget,
  callback : () -> Unit,
) -> @base_common.Disposable {
  if self.disposed {
    return @base_common.Disposable::from(() => ())
  }
  let target_generation = self.render_generation + 1
  let mut registration : @base_common.Disposable? = None
  let listener = self.did_render.event(generation => {
    if generation < target_generation {
      return
    }
    match registration {
      Some(disposable) => {
        registration = None
        disposable.dispose()
      }
      None => return
    }
    callback()
  })
  registration = Some(listener)
  self.schedule_render()
  @base_common.Disposable::from(() => {
    match registration {
      Some(disposable) => {
        registration = None
        disposable.dispose()
      }
      None => ()
    }
  })
}

///|
/// Repaints the CodeEditorWidget-owned no-model placeholder (the `flush_render`
/// no-model arm): the empty-state classes plus the `placeholder` option's
/// message text.
fn CodeEditorWidget::render_placeholder(self : CodeEditorWidget) -> Unit {
  let options = self.configuration.snapshot().options
  match self.mount {
    Headless => ()
    Mounted(mounted) =>
      mounted.render_placeholder(
        @view.empty_editor_class_name(
          show_unused=options.show_unused,
          show_deprecated=options.show_deprecated,
        ),
        options.placeholder,
      )
  }
}

///|
fn CodeEditorWidget::schedule_render(self : CodeEditorWidget) -> Unit {
  // Headless (never attached) → no rAF loop; with a container the flush
  // paints either the per-model view or the no-model placeholder.
  if self.disposed {
    return
  }
  match self.mount {
    Headless => ()
    Mounted(mounted) =>
      mounted.schedule_render(() => if !self.disposed { self.flush_render() })
  }
}
