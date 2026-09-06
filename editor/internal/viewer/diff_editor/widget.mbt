///|
priv enum DiffEditorScrollPane {
  OriginalScrollPane
  ModifiedScrollPane
}

///|
/// The exact modified model range passed to one programmatic centered reveal.
/// Composite hosts retain the range, wait for their item layout to settle, and
/// then measure its current pixel geometry before projecting the child scroll
/// into their outer scroll plane.
pub(all) struct DiffEditorRevealEvent {
  modified_range : @base_common.Range
} derive(Eq, Debug)

///|
pub extend DiffEditorRevealEvent with Eq::{equal, not_equal}

///|
pub extend DiffEditorRevealEvent with Debug::{to_repr}

///|
/// A first-class diff widget that owns two code-editor kernels and one shared
/// diff ViewModel. Product-specific algorithm controls and document
/// presentation routing are intentionally outside this package.
pub struct DiffEditorWidget {
  host : @rdom.Element
  root : @rdom.Element
  panes : @rdom.Element
  original_host : @rdom.Element
  modified_host : @rdom.Element
  sash : @rdom.Element
  overview_root : @rdom.Element
  overview_viewport : @rdom.Element
  status : @rdom.Element
  live_region : @rdom.Element
  editors : DiffEditorEditors
  view_model : DiffEditorViewModel
  mut editor_options : @code_widget.CodeEditorOptions
  mut options : DiffEditorOptions
  layout_state : DiffEditorLayoutState
  pointer_monitor : @base_browser.GlobalPointerMoveMonitor
  lifetime : Array[@base_common.Disposable]
  mut resize_observer : @base_common.Disposable?
  mut original_overview_ruler : @code_widget.CodeEditorOverviewRuler?
  mut modified_overview_ruler : @code_widget.CodeEditorOverviewRuler?
  mut original_decoration_ids : Array[String]
  mut modified_decoration_ids : Array[String]
  mut original_alignment_zone_ids : Array[String]
  mut modified_alignment_zone_ids : Array[String]
  mut inline_deleted_zones : Array[InlineDeletedZone]
  mut original_alignment_geometry : PaneGeometrySnapshot?
  mut modified_alignment_geometry : PaneGeometrySnapshot?
  mut diff_state : DiffState?
  /// The section-host contract is published only after one complete geometry
  /// reconcile has committed both panes' owned alignment zones. Retaining the
  /// last value prevents a host height write followed by `layout()` from
  /// feeding the same height back into the host.
  did_change_content_height : @base_common.Emitter[Double]
  /// Fires only after a concrete hunk reveal has updated the modified cursor
  /// and requested the child editor's own centered reveal.
  did_reveal_change : @base_common.Emitter[DiffEditorRevealEvent]
  mut last_published_content_height : Double?
  /// One VS Code-style `revealFirstDiff` request, bound to the model-pair
  /// generation that was current when the host made it. The request survives
  /// asynchronous diff computation and hidden/layout render barriers, but a
  /// replacement pair makes it stale instead of moving the new document.
  mut pending_reveal_first_diff_generation : Int?
  /// Symmetric request used when a multi-diff host enters this item while
  /// navigating backward.
  mut pending_reveal_last_diff_generation : Int?
  mut reconciling_generation : Int
  mut is_reconciling : Bool
  /// Cancellable paint barrier for the latest outer layout transaction.
  /// Both layouts wait for both kernels because Inline paints the original
  /// editor's real line-number strip and derives paired geometry from it.
  layout_render_waiters : Array[@base_common.Disposable]
  mut layout_render_generation : Int
  mut layout_render_remaining : Int
  /// Model-relative modified viewport captured before an outer layout mutates
  /// pane widths/options. Modified is the canonical viewport: keep this anchor
  /// across the first render and every follow-up Markdown/ViewZone measurement
  /// until a genuine scroll input supersedes it.
  mut pending_layout_modified_viewport : @code_widget.StableCodeEditorViewportState?
  mut has_valid_layout_box : Bool
  mut inline_original_strip_width : Double
  /// Programmatic scroll setters publish `onDidScrollChange` only after the
  /// target editor's render flush. Retain the clamped target value per pane and
  /// axis until that delayed echo is consumed; a synchronous Boolean guard is
  /// already gone when the event arrives and can feed the clamp back upstream.
  mut pending_original_scroll_top_echo : Double?
  mut pending_original_scroll_left_echo : Double?
  mut pending_modified_scroll_top_echo : Double?
  mut pending_modified_scroll_left_echo : Double?
  mut disposed : Bool
}

///|
fn diff_whole_line_decorations(
  ranges : Array[@base_common.Range],
  line_class : String,
  gutter_class : String,
  margin_class : String,
  render_indicators : Bool,
  description : String,
) -> Array[@model.ModelDeltaDecoration] {
  ranges.map(range => {
    range,
    options: if render_indicators {
      ModelDecorationOptions(
        line_class,
        is_whole_line=true,
        lines_decorations_class_name=gutter_class,
        margin_class_name=margin_class,
        description~,
      )
    } else {
      ModelDecorationOptions(
        line_class,
        is_whole_line=true,
        margin_class_name=margin_class,
        description~,
      )
    },
  })
}

///|
pub fn DiffEditorWidget::create(
  host : @rdom.Element,
  services? : @code_widget.CodeEditorServices,
  editor_options? : @code_widget.CodeEditorOptions = @code_widget.CodeEditorOptions::default(),
  options? : DiffEditorOptions = DiffEditorOptions::default(),
  provider : &@diff.DocumentDiffProvider,
) -> DiffEditorWidget {
  let document = @rdom.document()
  let root = document.create_element("section")
  root.set_attribute("class", "moonbit-diff-editor")
  root.set_attribute("role", "region")
  root.set_attribute("aria-label", "File comparison")
  let panes = document.create_element("div")
  panes.set_attribute("class", "moonbit-diff-editor-panes")
  let original_host = document.create_element("div")
  original_host.set_attribute(
    "class", "moonbit-diff-editor-pane moonbit-diff-editor-original",
  )
  original_host.set_attribute("role", "group")
  original_host.set_attribute("aria-label", "Original file")
  let sash = document.create_element("div")
  sash.set_attribute("class", "moonbit-diff-editor-sash")
  sash.set_attribute("role", "separator")
  sash.set_attribute("aria-label", "Resize diff panes")
  sash.set_attribute("aria-orientation", "vertical")
  sash.set_attribute("aria-valuemin", "10")
  sash.set_attribute("aria-valuemax", "90")
  sash.set_attribute("tabindex", "0")
  let modified_host = document.create_element("div")
  modified_host.set_attribute(
    "class", "moonbit-diff-editor-pane moonbit-diff-editor-modified",
  )
  modified_host.set_attribute("role", "group")
  modified_host.set_attribute("aria-label", "Modified file")
  panes.append_child(original_host.as_node())
  panes.append_child(sash.as_node())
  panes.append_child(modified_host.as_node())
  let overview_root = document.create_element("div")
  overview_root.set_attribute("class", "moonbit-diff-overview diffOverview")
  overview_root.set_attribute("aria-hidden", "true")
  overview_root.set_attribute("hidden", "")
  let overview_viewport = document.create_element("div")
  overview_viewport.set_attribute(
    "class", "moonbit-diff-overview-viewport diffViewport",
  )
  overview_root.append_child(overview_viewport.as_node())
  let status = document.create_element("div")
  status.set_attribute("class", "moonbit-diff-editor-status")
  status.set_attribute("hidden", "")
  let live_region = document.create_element("div")
  live_region.set_attribute("class", "moonbit-diff-editor-live-region")
  live_region.set_attribute("aria-live", "polite")
  live_region.set_attribute("aria-atomic", "true")
  root.append_child(panes.as_node())
  root.append_child(overview_root.as_node())
  root.append_child(status.as_node())
  root.append_child(live_region.as_node())
  host.append_child(root.as_node())

  let editors = DiffEditorEditors::create(
    original_host,
    modified_host,
    services?,
    editor_options,
    options.diff_word_wrap,
    options.layout,
    options.render_markdown_comments,
    options.handle_mouse_wheel,
  )
  let view_model = DiffEditorViewModel(provider, options={
    ignore_trim_whitespace: options.ignore_trim_whitespace,
  })
  let widget : DiffEditorWidget = {
    host,
    root,
    panes,
    original_host,
    modified_host,
    sash,
    overview_root,
    overview_viewport,
    status,
    live_region,
    editors,
    view_model,
    editor_options,
    options,
    layout_state: DiffEditorLayoutState(options),
    pointer_monitor: GlobalPointerMoveMonitor(),
    lifetime: [],
    resize_observer: None,
    original_overview_ruler: None,
    modified_overview_ruler: None,
    original_decoration_ids: [],
    modified_decoration_ids: [],
    original_alignment_zone_ids: [],
    modified_alignment_zone_ids: [],
    inline_deleted_zones: [],
    original_alignment_geometry: None,
    modified_alignment_geometry: None,
    diff_state: None,
    did_change_content_height: Emitter(),
    did_reveal_change: Emitter(),
    last_published_content_height: None,
    pending_reveal_first_diff_generation: None,
    pending_reveal_last_diff_generation: None,
    reconciling_generation: 0,
    is_reconciling: false,
    layout_render_waiters: [],
    layout_render_generation: 0,
    layout_render_remaining: 0,
    pending_layout_modified_viewport: None,
    has_valid_layout_box: false,
    inline_original_strip_width: -1.0,
    pending_original_scroll_top_echo: None,
    pending_original_scroll_left_echo: None,
    pending_modified_scroll_top_echo: None,
    pending_modified_scroll_left_echo: None,
    disposed: false,
  }
  widget.install_event_bridges()
  // Establish accessibility/visibility attributes even when the initial host
  // is display:none and therefore has no valid layout transaction yet.
  widget.apply_layout_dom()
  widget.sync_overview_ruler_option()
  widget.resize_observer = @base_browser.observe_element_resize(host, () => {
    widget.layout()
  })
  widget.layout()
  widget
}

///|
fn DiffEditorWidget::listen(
  self : DiffEditorWidget,
  target : @rdom.EventTarget,
  event_name : String,
  listener : (@rdom.Event) -> Unit,
) -> Unit {
  target.add_event_listener(event_name, listener)
  self.lifetime.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_name, listener)
    }),
  )
}

///|
fn DiffEditorWidget::host_has_positive_layout_box(
  self : DiffEditorWidget,
) -> Bool {
  let rect = self.host.get_bounding_client_rect()
  rect.get_width() > 0.0 && rect.get_height() > 0.0
}

///|
fn DiffEditorWidget::cancel_layout_render_barrier(
  self : DiffEditorWidget,
) -> Unit {
  for waiter in self.layout_render_waiters {
    waiter.dispose()
  }
  self.layout_render_waiters.clear()
  self.layout_render_remaining = 0
}

///|
fn DiffEditorWidget::complete_layout_pane_render(
  self : DiffEditorWidget,
  generation : Int,
) -> Unit {
  if self.disposed ||
    generation != self.layout_render_generation ||
    self.layout_render_remaining <= 0 {
    return
  }
  self.layout_render_remaining -= 1
  if self.layout_render_remaining > 0 {
    return
  }
  self.cancel_layout_render_barrier()
  if !self.host_has_positive_layout_box() {
    self.has_valid_layout_box = false
    self.pending_layout_modified_viewport = None
    return
  }
  self.has_valid_layout_box = true
  // Every outer layout, including height-only resizes, gets exactly one
  // reconcile using geometry from the completed pane render(s).
  self.reconcile_view_model()
  if self.pending_layout_modified_viewport is Some(state) {
    self.restore_modified_viewport_and_sync_original(state)
  }
  self.refresh_overview_viewport()
}

///|
fn DiffEditorWidget::layout_editors_after_render(
  self : DiffEditorWidget,
) -> Unit {
  self.cancel_layout_render_barrier()
  if !self.has_valid_layout_box || !self.host_has_positive_layout_box() {
    self.has_valid_layout_box = false
    self.pending_layout_modified_viewport = None
    return
  }
  self.layout_render_generation += 1
  let generation = self.layout_render_generation
  self.layout_render_remaining = 2
  self.layout_render_waiters.push(
    self.editors.original.after_next_render(() => {
      self.complete_layout_pane_render(generation)
    }),
  )
  self.layout_render_waiters.push(
    self.editors.modified.after_next_render(() => {
      self.complete_layout_pane_render(generation)
    }),
  )
  self.editors.layout(self.layout_state.actual_layout)
}

///|
fn DiffEditorWidget::install_event_bridges(self : DiffEditorWidget) -> Unit {
  self.lifetime.push(
    self.view_model.on_did_change_model(() => {
      self.editors.set_model(self.view_model.get_model())
    }),
  )
  self.lifetime.push(
    self.view_model.on_did_update_diff(() => self.reconcile_view_model()),
  )
  // A stable layout anchor is valid across presentation/geometry churn, but
  // not across edits to the model it names. Content changes retain the model
  // identity, so clear the protected position explicitly before the next diff
  // result can project a new set of zones around it.
  self.lifetime.push(
    self.editors.original.on_did_change_model_content(_ => {
      self.pending_layout_modified_viewport = None
    }),
  )
  self.lifetime.push(
    self.editors.modified.on_did_change_model_content(_ => {
      self.pending_layout_modified_viewport = None
    }),
  )
  // The child layout identity covers model digit bands, model swaps, font
  // measurement, line-number options, and container changes. Recompute the
  // clipped strip only when its derived width actually moved.
  self.lifetime.push(
    self.editors.original.on_did_layout_change(_ => {
      self.schedule_inline_strip_relayout_if_needed()
    }),
  )
  self.lifetime.push(
    self.editors.original.on_did_scroll_change(event => {
      let scroll_top_echo = self.consume_scroll_top_echo(
        OriginalScrollPane,
        event.scroll_top,
      )
      let scroll_left_echo = self.consume_scroll_left_echo(
        OriginalScrollPane,
        event.scroll_left,
      )
      // Layout and Markdown presentation changes can publish scroll facts from
      // the first pane render before the paired geometry transaction is ready.
      // The protected modified anchor is restored when the barrier closes, so
      // never feed this transient original position back into modified.
      if self.layout_render_remaining > 0 &&
        self.pending_layout_modified_viewport is Some(_) {
        return
      }
      if event.scroll_top_changed {
        if !scroll_top_echo {
          self.pending_layout_modified_viewport = None
          self.sync_scroll_top_to(ModifiedScrollPane, event.scroll_top)
        }
      }
      if event.scroll_left_changed {
        if !scroll_left_echo {
          self.pending_layout_modified_viewport = None
          self.sync_scroll_left_to(ModifiedScrollPane, event.scroll_left)
        }
      }
    }),
  )
  self.lifetime.push(
    self.editors.modified.on_did_scroll_change(event => {
      self.refresh_overview_viewport()
      let scroll_top_echo = self.consume_scroll_top_echo(
        ModifiedScrollPane,
        event.scroll_top,
      )
      let scroll_left_echo = self.consume_scroll_left_echo(
        ModifiedScrollPane,
        event.scroll_left,
      )
      if self.layout_render_remaining > 0 &&
        self.pending_layout_modified_viewport is Some(_) {
        return
      }
      if event.scroll_top_changed {
        if !scroll_top_echo {
          self.pending_layout_modified_viewport = None
          self.sync_scroll_top_to(OriginalScrollPane, event.scroll_top)
        }
      }
      if event.scroll_left_changed {
        if !scroll_left_echo {
          self.pending_layout_modified_viewport = None
          self.sync_scroll_left_to(OriginalScrollPane, event.scroll_left)
        }
      }
    }),
  )
  self.lifetime.push(
    self.editors.original.on_did_change_view_zones(() => {
      self.reconcile_geometry_if_changed()
    }),
  )
  self.lifetime.push(
    self.editors.modified.on_did_change_view_zones(() => {
      self.reconcile_geometry_if_changed()
    }),
  )
  self.lifetime.push(
    self.editors.original.on_did_change_hidden_areas(() => {
      self.reconcile_geometry_if_changed()
    }),
  )
  self.lifetime.push(
    self.editors.modified.on_did_change_hidden_areas(() => {
      self.reconcile_geometry_if_changed()
    }),
  )
  self.listen(self.root.as_event_target(), "keydown", event => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    if keyboard.key() == "F7" {
      event.prevent_default()
      event.stop_propagation()
      if keyboard.shift_key() {
        self.reveal_previous_change() |> ignore
      } else {
        self.reveal_next_change() |> ignore
      }
    }
  })
  self.listen(self.overview_root.as_event_target(), "pointerdown", event => {
    if self.options.overview_ruler {
      self.editors.modified.delegate_vertical_scrollbar_pointer_down(event)
    }
  })
  self.listen(self.overview_root.as_event_target(), "wheel", event => {
    if self.options.overview_ruler {
      self.editors.modified.delegate_scroll_from_mouse_wheel_event(event)
      |> ignore
    }
  })
  self.listen(self.sash.as_event_target(), "pointerdown", event => {
    guard event.to_mouse_event() is Some(mouse) && mouse.get_button() == 0 else {
      return
    }
    if !self.options.sash_enabled ||
      self.layout_state.actual_layout != SideBySide {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    let root_left = self.panes.get_bounding_client_rect().get_left()
    self.pointer_monitor.start_monitoring(
      self.sash,
      @base_browser.mouse_event_pointer_id(mouse),
      mouse.get_buttons(),
      pointer_event => {
        let pane_width = self.panes
          .get_bounding_client_rect()
          .get_width()
          .max(1.0)
        let state_relative_offset = (
            Double::from_int(pointer_event.get_client_x()) - root_left
          ) /
          pane_width *
          self.layout_state.width
        if self.layout_state.set_split_from_pointer(state_relative_offset) {
          self.capture_layout_modified_viewport_if_absent()
          self.apply_layout_dom()
          self.layout_editors_after_render()
        }
      },
      _ => (),
    )
  })
  self.listen(self.sash.as_event_target(), "keydown", event => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    let direction = match keyboard.key() {
      "ArrowLeft" => -1.0
      "ArrowRight" => 1.0
      _ => return
    }
    if !self.options.sash_enabled ||
      self.layout_state.actual_layout != SideBySide {
      return
    }
    event.prevent_default()
    event.stop_propagation()
    let next_offset = self.layout_state.width *
      (self.layout_state.split_ratio + direction * 0.02)
    if self.layout_state.set_split_from_pointer(next_offset) {
      self.capture_layout_modified_viewport_if_absent()
      self.apply_layout_dom()
      self.layout_editors_after_render()
    }
  })
}

///|
fn DiffEditorWidget::sync_scroll_top_to(
  self : DiffEditorWidget,
  pane : DiffEditorScrollPane,
  scroll_top : Double,
) -> Unit {
  if self.disposed {
    return
  }
  let target = match pane {
    OriginalScrollPane => self.editors.original
    ModifiedScrollPane => self.editors.modified
  }
  let before = target.get_scroll_top()
  if (before - scroll_top).abs() <= 0.5 {
    return
  }
  target.set_scroll_top(scroll_top)
  let after = target.get_scroll_top()
  if (after - before).abs() > 0.5 {
    match pane {
      OriginalScrollPane => self.pending_original_scroll_top_echo = Some(after)
      ModifiedScrollPane => self.pending_modified_scroll_top_echo = Some(after)
    }
  }
}

///|
fn DiffEditorWidget::sync_scroll_left_to(
  self : DiffEditorWidget,
  pane : DiffEditorScrollPane,
  scroll_left : Double,
) -> Unit {
  if self.disposed {
    return
  }
  let target = match pane {
    OriginalScrollPane => self.editors.original
    ModifiedScrollPane => self.editors.modified
  }
  let before = target.get_scroll_left()
  if (before - scroll_left).abs() <= 0.5 {
    return
  }
  target.set_scroll_left(scroll_left)
  let after = target.get_scroll_left()
  if (after - before).abs() > 0.5 {
    match pane {
      OriginalScrollPane => self.pending_original_scroll_left_echo = Some(after)
      ModifiedScrollPane => self.pending_modified_scroll_left_echo = Some(after)
    }
  }
}

///|
fn DiffEditorWidget::consume_scroll_top_echo(
  self : DiffEditorWidget,
  pane : DiffEditorScrollPane,
  scroll_top : Double,
) -> Bool {
  let expected = match pane {
    OriginalScrollPane => {
      let expected = self.pending_original_scroll_top_echo
      self.pending_original_scroll_top_echo = None
      expected
    }
    ModifiedScrollPane => {
      let expected = self.pending_modified_scroll_top_echo
      self.pending_modified_scroll_top_echo = None
      expected
    }
  }
  match expected {
    Some(expected) => (expected - scroll_top).abs() <= 0.5
    None => false
  }
}

///|
fn DiffEditorWidget::consume_scroll_left_echo(
  self : DiffEditorWidget,
  pane : DiffEditorScrollPane,
  scroll_left : Double,
) -> Bool {
  let expected = match pane {
    OriginalScrollPane => {
      let expected = self.pending_original_scroll_left_echo
      self.pending_original_scroll_left_echo = None
      expected
    }
    ModifiedScrollPane => {
      let expected = self.pending_modified_scroll_left_echo
      self.pending_modified_scroll_left_echo = None
      expected
    }
  }
  match expected {
    Some(expected) => (expected - scroll_left).abs() <= 0.5
    None => false
  }
}

///|
fn DiffEditorWidget::clear_pending_scroll_echoes(
  self : DiffEditorWidget,
) -> Unit {
  self.pending_original_scroll_top_echo = None
  self.pending_original_scroll_left_echo = None
  self.pending_modified_scroll_top_echo = None
  self.pending_modified_scroll_left_echo = None
}

///|
/// Restores the one canonical viewport after a geometry transaction, records
/// its delayed render echo, and only then projects the resulting scroll axes
/// into original. Restoring original independently is unsafe: its Markdown
/// source/zone transition can publish a later scroll event that overwrites the
/// already-restored modified anchor.
fn DiffEditorWidget::restore_modified_viewport_and_sync_original(
  self : DiffEditorWidget,
  state : @code_widget.StableCodeEditorViewportState,
) -> Unit {
  let before_top = self.editors.modified.get_scroll_top()
  let before_left = self.editors.modified.get_scroll_left()
  if !self.editors.modified.restore_stable_viewport_state(state) {
    return
  }
  let after_top = self.editors.modified.get_scroll_top()
  let after_left = self.editors.modified.get_scroll_left()
  if (after_top - before_top).abs() > 0.5 {
    self.pending_modified_scroll_top_echo = Some(after_top)
  }
  if (after_left - before_left).abs() > 0.5 {
    self.pending_modified_scroll_left_echo = Some(after_left)
  }
  self.sync_scroll_top_to(OriginalScrollPane, after_top)
  self.sync_scroll_left_to(OriginalScrollPane, after_left)
}

///|
/// During a layout-generated follow-up (strip width, ResizeObserver, or paired
/// ViewZone measurement), retain the first pre-layout model anchor. A genuine
/// user/programmatic scroll clears it through the scroll bridge above.
fn DiffEditorWidget::capture_layout_modified_viewport_if_absent(
  self : DiffEditorWidget,
) -> Unit {
  if self.pending_layout_modified_viewport is None {
    self.pending_layout_modified_viewport = self.editors.modified.capture_stable_viewport_state()
  }
}

///|
fn DiffEditorWidget::relayout_inline_strip(self : DiffEditorWidget) -> Unit {
  if self.disposed ||
    self.layout_state.actual_layout != Inline ||
    !self.has_valid_layout_box ||
    !self.host_has_positive_layout_box() {
    return
  }
  self.capture_layout_modified_viewport_if_absent()
  self.apply_layout_dom()
  self.layout_editors_after_render()
}

///|
fn DiffEditorWidget::inline_original_width(
  self : DiffEditorWidget,
  decorations_left : Double,
) -> Double {
  let overview_width = if self.options.overview_ruler { 30.0 } else { 0.0 }
  let panes_width = (self.layout_state.width - overview_width).max(0.0)
  decorations_left.max(5.0).min(panes_width)
}

///|
fn DiffEditorWidget::schedule_inline_strip_relayout_if_needed(
  self : DiffEditorWidget,
) -> Unit {
  @base_browser.queue_microtask(() => {
    if self.disposed || self.layout_state.actual_layout != Inline {
      return
    }
    let next_width = self.inline_original_width(
      self.editors.original.get_layout_info().decorations_left,
    )
    if (next_width - self.inline_original_strip_width).abs() > 0.5 {
      self.relayout_inline_strip()
    }
  })
}

///|
fn DiffEditorWidget::clear_decorations(self : DiffEditorWidget) -> Unit {
  self.original_decoration_ids = self.editors.original.delta_decorations(
    self.original_decoration_ids,
    [],
  )
  self.modified_decoration_ids = self.editors.modified.delta_decorations(
    self.modified_decoration_ids,
    [],
  )
}

///|
fn changed_line_range(
  line_range : @base_common.LineRange,
  snapshot : @model.TextSnapshot,
) -> @base_common.Range? {
  if line_range.is_empty() {
    return None
  }
  let end_line_number = line_range.end_line_number_exclusive - 1
  Some(
    Range(
      line_range.start_line_number,
      1,
      end_line_number,
      snapshot.get_line_max_column(end_line_number),
    ),
  )
}

///|
fn whole_line_character_decoration(
  range : @base_common.Range,
  class_name : String,
  description : String,
) -> @model.ModelDeltaDecoration {
  {
    range,
    options: ModelDecorationOptions(
      class_name,
      is_whole_line=true,
      description~,
    ),
  }
}

///|
fn inner_character_decoration(
  range : @base_common.Range,
  class_name : String,
  description : String,
) -> @model.ModelDeltaDecoration {
  let is_empty = range.is_empty()
  {
    range,
    options: ModelDecorationOptions(
      if is_empty {
        class_name + " diff-range-empty"
      } else {
        class_name
      },
      should_fill_line_on_line_break=!is_empty,
      description~,
    ),
  }
}

///|
// Direct port of the non-move branches in DiffEditorDecorations. The renderer
// iterates DiffState mappings themselves; no second feature-projection model
// can reorder or reinterpret a change.
fn DiffEditorWidget::apply_diff_state_decorations(
  self : DiffEditorWidget,
  diff_state : DiffState,
  model : DiffEditorModelData,
) -> Unit {
  let original_snapshot = model.original.snapshot()
  let modified_snapshot = model.modified.snapshot()
  let original_decorations : Array[@model.ModelDeltaDecoration] = []
  let modified_decorations : Array[@model.ModelDeltaDecoration] = []
  for mapping in diff_state.mappings {
    let change = mapping.line_range_mapping
    let original_range = changed_line_range(change.original, original_snapshot)
    let modified_range = changed_line_range(change.modified, modified_snapshot)
    if original_range is Some(range) {
      original_decorations.append(
        diff_whole_line_decorations(
          [range],
          "diff-editor-line-delete",
          "delete-sign codicon codicon-diff-remove",
          "diff-editor-gutter-delete",
          self.options.render_indicators,
          "diff-editor-original-line",
        ),
      )
    }
    if modified_range is Some(range) {
      modified_decorations.append(
        diff_whole_line_decorations(
          [range],
          "diff-editor-line-insert",
          "insert-sign codicon codicon-diff-insert",
          "diff-editor-gutter-insert",
          self.options.render_indicators,
          "diff-editor-modified-line",
        ),
      )
    }
    if change.modified.is_empty() || change.original.is_empty() {
      if original_range is Some(range) {
        original_decorations.push(
          whole_line_character_decoration(
            range, "diff-editor-char-delete", "diff-editor-original-character",
          ),
        )
      }
      if modified_range is Some(range) {
        modified_decorations.push(
          whole_line_character_decoration(
            range, "diff-editor-char-insert", "diff-editor-modified-character",
          ),
        )
      }
    } else if change.inner_changes is Some(inner_changes) {
      for inner in inner_changes {
        if change.original.contains(inner.original.start_line_number) {
          original_decorations.push(
            inner_character_decoration(
              inner.original,
              "diff-editor-char-delete",
              "diff-editor-original-character",
            ),
          )
        }
        if change.modified.contains(inner.modified.start_line_number) {
          modified_decorations.push(
            inner_character_decoration(
              inner.modified,
              "diff-editor-char-insert",
              "diff-editor-modified-character",
            ),
          )
        }
      }
    }
  }
  self.original_decoration_ids = self.editors.original.delta_decorations(
    self.original_decoration_ids,
    original_decorations,
  )
  self.modified_decoration_ids = self.editors.modified.delta_decorations(
    self.modified_decoration_ids,
    modified_decorations,
  )
}

///|
fn alignment_view_zone_specs(
  spacers : Array[ManagedAlignmentSpacer],
  pane_class : String,
) -> Array[@code_widget.ManagedCodeEditorViewZoneSpec] {
  spacers.map(spacer => {
    let node = @rdom.document().create_element("div")
    node.set_attribute(
      "class",
      "moonbit-diff-editor-alignment-spacer \{pane_class}",
    )
    node.set_attribute("aria-hidden", "true")
    ManagedCodeEditorViewZoneSpec(
      spacer.after_line_number,
      spacer.height_in_px,
      node,
    )
  })
}

///|
fn replace_alignment_zones(
  editor : @code_widget.CodeEditorWidget,
  previous_ids : Array[String],
  specs : Array[@code_widget.ManagedCodeEditorViewZoneSpec],
  generation : Int,
) -> Array[String] {
  if previous_ids.is_empty() && specs.is_empty() {
    []
  } else {
    editor.apply_managed_view_zones(previous_ids, specs, generation)
  }
}

///|
fn DiffEditorWidget::clear_inline_deleted_zones(
  self : DiffEditorWidget,
) -> Unit {
  self.inline_deleted_zones.clear()
}

///|
fn DiffEditorWidget::capture_alignment_geometry(
  self : DiffEditorWidget,
) -> (PaneGeometrySnapshot?, PaneGeometrySnapshot?) {
  (
    self.editors.original
    .geometry_snapshot(self.original_alignment_zone_ids)
    .map(pane_geometry_from_code_editor),
    self.editors.modified
    .geometry_snapshot(self.modified_alignment_zone_ids)
    .map(pane_geometry_from_code_editor),
  )
}

///|
fn DiffEditorWidget::modified_viewport_for_geometry_transaction(
  self : DiffEditorWidget,
) -> @code_widget.StableCodeEditorViewportState? {
  match self.pending_layout_modified_viewport {
    Some(state) => Some(state)
    None => self.editors.modified.capture_stable_viewport_state()
  }
}

///|
fn DiffEditorWidget::clear_overview_ruler(
  self : DiffEditorWidget,
  generation : Int,
) -> Unit {
  if self.original_overview_ruler is Some(ruler) {
    ruler.clear(generation)
  }
  if self.modified_overview_ruler is Some(ruler) {
    ruler.clear(generation)
  }
}

///|
fn DiffEditorWidget::apply_overview_diff_state(
  self : DiffEditorWidget,
  diff_state : DiffState,
  generation : Int,
) -> Unit {
  if self.original_overview_ruler is Some(ruler) {
    ruler.set_entries(
      generation,
      original_diff_overview_ruler_entries(diff_state),
    )
  }
  if self.modified_overview_ruler is Some(ruler) {
    ruler.set_entries(
      generation,
      modified_diff_overview_ruler_entries(diff_state),
    )
  }
}

///|
fn DiffEditorWidget::refresh_overview_viewport(self : DiffEditorWidget) -> Unit {
  if self.disposed || !self.options.overview_ruler {
    return
  }
  let viewport_height = self.overview_root
    .get_bounding_client_rect()
    .get_height()
    .max(0.0)
  let layout_info = self.editors.modified.get_layout_info()
  let geometry = diff_overview_viewport_geometry(
    viewport_height,
    self.editors.modified.get_scroll_height().max(viewport_height),
    self.editors.modified.get_scroll_top().max(0.0),
    layout_info.vertical_scrollbar_width,
  )
  @base_browser.set_style_property(
    self.overview_viewport,
    "top",
    "\{geometry.top}px",
  )
  @base_browser.set_style_property(
    self.overview_viewport,
    "height",
    "\{geometry.height}px",
  )
  self.overview_viewport.set_attribute(
    "data-diff-viewport-top",
    geometry.top.to_string(),
  )
  self.overview_viewport.set_attribute(
    "data-diff-viewport-height",
    geometry.height.to_string(),
  )
}

///|
fn DiffEditorWidget::sync_overview_ruler_option(
  self : DiffEditorWidget,
) -> Unit {
  if !self.options.overview_ruler {
    self.root.remove_attribute("data-overview-ruler")
    self.overview_root.set_attribute("hidden", "")
    if self.original_overview_ruler is Some(ruler) {
      ruler.dispose()
    }
    if self.modified_overview_ruler is Some(ruler) {
      ruler.dispose()
    }
    self.original_overview_ruler = None
    self.modified_overview_ruler = None
    return
  }
  self.root.set_attribute("data-overview-ruler", "true")
  self.overview_root.remove_attribute("hidden")
  if self.original_overview_ruler is None {
    let ruler = self.editors.original.create_overview_ruler(
      external_host=self.overview_root,
    )
    ruler
    .get_dom_node()
    .set_attribute(
      "class", "decorationsOverviewRuler moonbit-code-overview-ruler original diffOverviewRuler",
    )
    ruler.get_dom_node().set_attribute("data-diff-overview-side", "original")
    self.original_overview_ruler = Some(ruler)
  }
  if self.modified_overview_ruler is None {
    let ruler = self.editors.modified.create_overview_ruler(
      external_host=self.overview_root,
    )
    ruler
    .get_dom_node()
    .set_attribute(
      "class", "decorationsOverviewRuler moonbit-code-overview-ruler modified diffOverviewRuler",
    )
    ruler.get_dom_node().set_attribute("data-diff-overview-side", "modified")
    self.modified_overview_ruler = Some(ruler)
  }
  match self.diff_state {
    Some(diff_state) =>
      self.apply_overview_diff_state(diff_state, self.reconciling_generation)
    _ => self.clear_overview_ruler(self.reconciling_generation)
  }
  self.refresh_overview_viewport()
}

///|
fn DiffEditorWidget::sync_failure_diagnostic(self : DiffEditorWidget) -> Unit {
  match self.view_model.get_failure_diagnostic() {
    Some(diagnostic) => {
      let message = if diagnostic == "provider error" {
        "Unable to compute this diff."
      } else {
        "The diff provider returned an invalid result."
      }
      self.root.set_attribute("data-diff-failure", diagnostic)
      self.status.remove_attribute("hidden")
      self.status.set_inner_html(message)
      self.live_region.set_inner_html(message)
    }
    None => {
      self.root.remove_attribute("data-diff-failure")
      self.status.set_attribute("hidden", "")
      self.status.set_inner_html("")
      self.live_region.set_inner_html("")
    }
  }
}

///|
fn DiffEditorWidget::commit_empty_diff_features(
  self : DiffEditorWidget,
  generation : Int,
) -> Unit {
  let modified_viewport = self.modified_viewport_for_geometry_transaction()
  self.clear_decorations()
  self.original_alignment_zone_ids = replace_alignment_zones(
    self.editors.original,
    self.original_alignment_zone_ids,
    [],
    generation,
  )
  self.clear_inline_deleted_zones()
  self.modified_alignment_zone_ids = replace_alignment_zones(
    self.editors.modified,
    self.modified_alignment_zone_ids,
    [],
    generation,
  )
  if modified_viewport is Some(state) {
    self.restore_modified_viewport_and_sync_original(state)
  }
  self.clear_overview_ruler(generation)
  self.original_alignment_geometry = None
  self.modified_alignment_geometry = None
  self.diff_state = None
  self.sync_failure_diagnostic()
}

///|
fn DiffEditorWidget::commit_diff_state(
  self : DiffEditorWidget,
  diff_state : DiffState,
  model : DiffEditorModelData,
  generation : Int,
) -> Unit {
  let modified_viewport = self.modified_viewport_for_geometry_transaction()
  let (original_geometry, modified_geometry) = self.capture_alignment_geometry()
  let (original_specs, modified_specs, next_inline_deleted_zones) = match
    (self.layout_state.actual_layout, original_geometry, modified_geometry) {
    (SideBySide, Some(original_geometry), Some(modified_geometry)) => {
      let spacers = compute_managed_alignment_spacers(
        diff_state, original_geometry, modified_geometry,
      )
      (
        alignment_view_zone_specs(
          spacers.original(),
          "moonbit-diff-editor-original-alignment-spacer",
        ),
        alignment_view_zone_specs(
          spacers.modified(),
          "moonbit-diff-editor-modified-alignment-spacer",
        ),
        [],
      )
    }
    (Inline, Some(original_geometry), Some(modified_geometry)) => {
      let alignments = compute_inline_range_alignments(
        diff_state, original_geometry, modified_geometry,
      )
      let inline_zones = inline_deleted_view_zone_specs(
        self.editors.modified,
        model.original,
        alignments,
        self.options.render_indicators,
      )
      (
        inline_zones.original_specs,
        inline_zones.modified_specs,
        inline_zones.zones,
      )
    }
    _ => ([], [], [])
  }
  self.original_alignment_geometry = original_geometry
  self.modified_alignment_geometry = modified_geometry
  self.apply_diff_state_decorations(diff_state, model)
  self.original_alignment_zone_ids = replace_alignment_zones(
    self.editors.original,
    self.original_alignment_zone_ids,
    original_specs,
    generation,
  )
  self.clear_inline_deleted_zones()
  self.modified_alignment_zone_ids = replace_alignment_zones(
    self.editors.modified,
    self.modified_alignment_zone_ids,
    modified_specs,
    generation,
  )
  self.inline_deleted_zones = next_inline_deleted_zones
  if modified_viewport is Some(state) {
    self.restore_modified_viewport_and_sync_original(state)
  }
  self.apply_overview_diff_state(diff_state, generation)
  self.diff_state = Some(diff_state)
  self.sync_failure_diagnostic()
  self.refresh_overview_viewport()
}

///|
fn DiffEditorWidget::reconcile_geometry_if_changed(
  self : DiffEditorWidget,
) -> Unit {
  // Always re-enter through the paired transaction. Besides committing both
  // sides' derived alignment zones, `reconcile_view_model` owns the pane-render
  // barrier, positive-layout, model-pair, and generation fences. Publishing
  // directly from this child event would expose the exact one-pane
  // intermediate state this event is designed to hide.
  if self.diff_state is None || self.view_model.get_diff() is None {
    self.reconcile_view_model()
    return
  }
  let (original, modified) = self.capture_alignment_geometry()
  let geometry_changed = alignment_geometry_pair_changed(
    original,
    modified,
    self.original_alignment_geometry,
    self.modified_alignment_geometry,
  )
  let content_height = self.get_content_height()
  let content_height_changed = content_height > 0.0 &&
    self.last_published_content_height != Some(content_height)
  if geometry_changed || content_height_changed {
    // Even the content-height-only path must cross the complete reconciliation
    // gate; it must never publish directly from one child editor.
    self.reconcile_view_model()
  }
}

///|
/// Publish the final paired height, never an intermediate child-editor height.
/// In particular, a Markdown-comment ViewZone first changes one pane, then the
/// diff geometry transaction replaces alignment zones in both panes. This
/// method runs only after that transaction and updates the retained value
/// before firing so a synchronous host resize cannot re-enter with a duplicate.
fn DiffEditorWidget::publish_content_height_if_changed(
  self : DiffEditorWidget,
) -> Unit {
  if self.disposed {
    return
  }
  let content_height = self.get_content_height()
  if content_height <= 0.0 ||
    self.last_published_content_height == Some(content_height) {
    return
  }
  self.last_published_content_height = Some(content_height)
  self.did_change_content_height.fire(content_height)
}

///|
fn DiffEditorWidget::reconcile_view_model(self : DiffEditorWidget) -> Unit {
  if self.disposed ||
    self.editors.is_committing_model_pair() ||
    self.is_reconciling {
    return
  }
  if self.layout_render_remaining > 0 {
    return
  }
  if !self.has_valid_layout_box || !self.host_has_positive_layout_box() {
    self.has_valid_layout_box = false
    return
  }
  let committed_model_generation = self.editors.committed_model_generation()
  if !self.editors.same_model(self.view_model.get_model()) {
    return
  }
  // Keep the pair commit as the outer boundary while constructing DiffState.
  if self.editors.is_committing_model_pair() ||
    self.editors.committed_model_generation() != committed_model_generation {
    return
  }
  self.is_reconciling = true
  defer {
    self.is_reconciling = false
    // `commit_diff_state` has now replaced both sides' alignment zones. A
    // section host can synchronously adopt this height without observing the
    // one-pane Markdown/ViewZone intermediate state.
    self.publish_content_height_if_changed()
  }
  self.reconciling_generation += 1
  let generation = self.reconciling_generation
  guard self.view_model.get_diff() is Some(document_diff) &&
    self.view_model.get_model() is Some(model) else {
    self.commit_empty_diff_features(generation)
    self.try_reveal_first_diff()
    self.try_reveal_last_diff()
    return
  }
  let diff_state = DiffState::from_diff_result(document_diff)
  self.commit_diff_state(diff_state, model, generation)
  self.try_reveal_first_diff()
  self.try_reveal_last_diff()
}

///|
fn DiffEditorWidget::clear_diff_features_for_transition(
  self : DiffEditorWidget,
) -> Unit {
  if self.editors.is_committing_model_pair() ||
    self.is_reconciling ||
    (
      self.diff_state is None &&
      self.original_decoration_ids.is_empty() &&
      self.modified_decoration_ids.is_empty() &&
      self.original_alignment_zone_ids.is_empty() &&
      self.modified_alignment_zone_ids.is_empty() &&
      self.inline_deleted_zones.is_empty()
    ) {
    return
  }
  self.is_reconciling = true
  defer {
    self.is_reconciling = false
  }
  self.reconciling_generation += 1
  self.commit_empty_diff_features(self.reconciling_generation)
}

///|
pub fn DiffEditorWidget::set_model(
  self : DiffEditorWidget,
  model : DiffEditorModelData?,
) -> DiffEditorModelData? {
  if self.disposed || same_model_pair(self.view_model.get_model(), model) {
    return None
  }
  self.pending_reveal_first_diff_generation = None
  self.pending_reveal_last_diff_generation = None
  self.pending_layout_modified_viewport = None
  self.clear_pending_scroll_echoes()
  self.clear_diff_features_for_transition()
  self.layout_editors_after_render()
  // DiffEditorViewModel is the sole pair/ownership authority. Its synchronous
  // model event mirrors the committed pair into both kernels before the diff
  // update event clears or rebuilds feature artifacts.
  let previous = self.view_model.set_model(model)
  // A model transaction clears a previous provider/validator failure
  // synchronously. Reconciliation can be held behind the render barrier, so
  // do not leave the old diagnostic painted until the next pane render.
  self.sync_failure_diagnostic()
  match model {
    Some(_) if !self.editors.is_committing_model_pair() => {
      self.editors.original.handle_initialized()
      self.editors.modified.handle_initialized()
    }
    _ => ()
  }
  previous
}

///|
pub fn DiffEditorWidget::get_model(
  self : DiffEditorWidget,
) -> DiffEditorModelData? {
  self.view_model.get_model()
}

///|
pub fn DiffEditorWidget::set_diff_provider(
  self : DiffEditorWidget,
  provider : &@diff.DocumentDiffProvider,
) -> Unit {
  self.view_model.set_provider(provider)
  self.sync_failure_diagnostic()
}

///|
pub fn DiffEditorWidget::update_options(
  self : DiffEditorWidget,
  editor_options : @code_widget.CodeEditorOptions,
  options : DiffEditorOptions,
) -> Unit {
  if self.disposed {
    return
  }
  let valid_layout_box = self.host_has_positive_layout_box()
  if valid_layout_box {
    self.capture_layout_modified_viewport_if_absent()
  } else {
    self.pending_layout_modified_viewport = None
  }
  self.editor_options = editor_options
  self.options = options
  self.sync_overview_ruler_option()
  if !valid_layout_box {
    self.has_valid_layout_box = false
    self.cancel_layout_render_barrier()
  }
  let layout_changed_from_options = self.layout_state.update_options(
    options,
    recompute_layout=false,
  )
  if valid_layout_box {
    ignore(
      self.layout_state.layout(
        self.host.get_bounding_client_rect().get_width().max(0.0),
      ) ||
      layout_changed_from_options,
    )
  } else {
    ignore(layout_changed_from_options)
  }
  if valid_layout_box {
    self.has_valid_layout_box = true
    self.editors.update_options(
      editor_options,
      options.diff_word_wrap,
      self.layout_state.actual_layout,
      options.handle_mouse_wheel,
    )
    self.apply_layout_dom()
    self.editors.sync_markdown_comment_presentations(
      self.layout_state.actual_layout,
      options.render_markdown_comments,
    )
    self.layout_editors_after_render()
  }
  self.view_model.update_options({
    ignore_trim_whitespace: options.ignore_trim_whitespace,
  })
}

///|
pub fn DiffEditorWidget::get_layout(
  self : DiffEditorWidget,
) -> DiffEditorLayout {
  self.layout_state.actual_layout
}

///|
/// Total height required by the taller pane, including diff alignment view
/// zones. Hosts that stack independent DiffEditors use this to size each
/// section without introducing a nested vertical scrollbar.
pub fn DiffEditorWidget::get_content_height(self : DiffEditorWidget) -> Double {
  self.editors.original
  .get_content_height()
  .max(self.editors.modified.get_content_height())
}

///|
/// Fires after a complete paired geometry transaction changes the final
/// content height. The payload already includes Markdown/foreign ViewZones and
/// both panes' committed alignment zones.
pub fn DiffEditorWidget::on_did_change_content_height(
  self : DiffEditorWidget,
  listener : (Double) -> Unit,
) -> @base_common.Disposable {
  self.did_change_content_height.event(listener)
}

///|
/// Fires after a first/last/next/previous hunk reveal with the exact modified
/// model range sent through the centered reveal pipeline.
pub fn DiffEditorWidget::on_did_reveal_change(
  self : DiffEditorWidget,
  listener : (DiffEditorRevealEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_reveal_change.event(listener)
}

///|
/// Re-measure a reveal range against the modified pane's latest wrapping and
/// ViewZone layout. MultiDiff hosts call this after their own section height
/// has committed instead of retaining stale event-time pixel coordinates.
pub fn DiffEditorWidget::get_modified_vertical_reveal_bounds(
  self : DiffEditorWidget,
  range : @base_common.Range,
) -> (Double, Double)? {
  self.editors.modified.get_vertical_reveal_bounds(range)
}

///|
/// Largest horizontal overflow of either code pane. MultiDiffEditor uses one
/// outer horizontal scrollbar and projects its offset into every item, just as
/// VS Code's DiffEditorItemTemplate reports `maxScroll` to its parent widget.
pub fn DiffEditorWidget::get_max_scroll_left(self : DiffEditorWidget) -> Double {
  let original = (self.editors.original.get_scroll_width() -
  self.editors.original.get_layout_info().content_width).max(0.0)
  let modified = (self.editors.modified.get_scroll_width() -
  self.editors.modified.get_layout_info().content_width).max(0.0)
  original.max(modified)
}

///|
/// Apply the MultiDiffEditor's shared horizontal offset to both panes. The
/// existing pane synchronization absorbs any resulting scroll event echo.
pub fn DiffEditorWidget::set_scroll_left(
  self : DiffEditorWidget,
  scroll_left : Double,
) -> Unit {
  self.editors.original.set_scroll_left(scroll_left)
  self.editors.modified.set_scroll_left(scroll_left)
}

///|
pub fn DiffEditorWidget::get_diff(
  self : DiffEditorWidget,
) -> @diff.DocumentDiff? {
  self.view_model.get_diff()
}

///|
pub fn DiffEditorWidget::is_diff_up_to_date(self : DiffEditorWidget) -> Bool {
  self.view_model.is_diff_up_to_date()
}

///|
pub fn DiffEditorWidget::on_did_update_diff(
  self : DiffEditorWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.view_model.on_did_update_diff(() => {
    if !self.disposed &&
      !self.editors.is_committing_model_pair() &&
      self.editors.same_model(self.view_model.get_model()) {
      listener()
    }
  })
}

///|
priv enum DiffNavigationPane {
  ModifiedNavigationPane
}

///|
priv struct DiffNavigationRevealPlan {
  pane : DiffNavigationPane
  range : @base_common.Range
}

///|
fn navigation_reveal_range(
  range : @base_common.LineRange,
  line_count : Int,
) -> @base_common.Range {
  if range.is_empty() {
    // Empty sides are positions between physical lines. A code editor still
    // needs a valid model coordinate, so represent the position as a
    // collapsed range on the nearest modified/original line.
    let anchor = range.start_line_number.clamp(min=1, max=line_count.max(1))
    return Range(anchor, 1, anchor, 1)
  }
  // Match `LineRange.toExclusiveRange()`: the end line stays exclusive. The
  // reveal path validates the resulting EOF position against the model.
  Range(range.start_line_number, 1, range.end_line_number_exclusive, 1)
}

///|
fn diff_navigation_reveal_plan(
  _layout : DiffEditorLayout,
  change : @diff.DetailedLineRangeMapping,
  _original_line_count : Int,
  modified_line_count : Int,
) -> DiffNavigationRevealPlan? {
  if change.modified.is_empty() && change.original.is_empty() {
    return None
  }
  // F7 is bound through pinned `commands.ts` to the Accessible Diff Viewer.
  // This editor-return adaptation always stays in the modified pane, using a
  // valid collapsed modified coordinate for a deletion-only group.
  Some({
    pane: ModifiedNavigationPane,
    range: navigation_reveal_range(change.modified, modified_line_count),
  })
}

///|
fn navigation_range_announcement(
  side : String,
  empty_kind : String,
  range : @base_common.LineRange,
) -> String {
  if range.is_empty() {
    "\{side} \{empty_kind} anchor at line \{range.start_line_number}"
  } else {
    "\{side} lines \{range.start_line_number} through " +
    "\{range.end_line_number_exclusive - 1}"
  }
}

///|
fn diff_navigation_announcement(target : DiffNavigationTarget) -> String {
  let change = target.change
  "Change \{target.change_index + 1} of \{target.change_count}; " +
  navigation_range_announcement("original", "insertion", change.original) +
  "; " +
  navigation_range_announcement("modified", "deletion", change.modified)
}

///|
fn DiffEditorWidget::announce_navigation_target(
  self : DiffEditorWidget,
  target : DiffNavigationTarget,
) -> Unit {
  self.live_region.set_inner_html(diff_navigation_announcement(target))
}

///|
fn DiffEditorWidget::reveal_navigation_target(
  self : DiffEditorWidget,
  target : DiffNavigationTarget,
) -> Bool {
  guard self.reveal_change(
    target.change,
    source="diffEditor.accessibleDiffViewer",
  ) else {
    return false
  }
  self.announce_navigation_target(target)
  true
}

///|
/// Shared exact-mapping reveal used by both raw first-diff navigation and the
/// Accessible Diff Viewer projection. Programmatic navigation supersedes a
/// viewport captured for an in-flight layout; otherwise that layout's final
/// restore could immediately undo this reveal.
fn DiffEditorWidget::reveal_change(
  self : DiffEditorWidget,
  change : @diff.DetailedLineRangeMapping,
  source~ : String,
) -> Bool {
  guard self.view_model.get_model() is Some(model) else { return false }
  self.pending_layout_modified_viewport = None
  let modified_anchor = change.modified.start_line_number.clamp(
    min=1,
    max=model.modified.get_line_count().max(1),
  )
  self.editors.modified.set_position(Position(modified_anchor, 1), source~)
  guard diff_navigation_reveal_plan(
      self.layout_state.actual_layout,
      change,
      model.original.get_line_count(),
      model.modified.get_line_count(),
    )
    is Some(plan) else {
    return false
  }
  match plan.pane {
    ModifiedNavigationPane => {
      self.editors.modified.reveal_range_in_center(plan.range)
      self.did_reveal_change.fire({ modified_range: plan.range, })
    }
  }
  true
}

///|
/// Consume a deferred first-diff request only after the exact requested pair
/// has both a ready diff and committed renderer state. This is the callback
/// equivalent of pinned VS Code's `waitForDiff().then(_goTo(mappings[0]))`,
/// with the additional layout barrier required by this widget's two kernels.
fn DiffEditorWidget::try_reveal_first_diff(self : DiffEditorWidget) -> Unit {
  guard self.pending_reveal_first_diff_generation is Some(generation) else {
    return
  }
  if self.editors.committed_model_generation() != generation ||
    !self.editors.same_model(self.view_model.get_model()) {
    self.pending_reveal_first_diff_generation = None
    return
  }
  match self.view_model.get_state() {
    Pending => return
    NoModel | Failed => {
      self.pending_reveal_first_diff_generation = None
      return
    }
    Ready => ()
  }
  guard self.diff_state is Some(diff_state) else { return }
  self.pending_reveal_first_diff_generation = None
  if !diff_state.mappings.is_empty() {
    self.reveal_change(
      diff_state.mappings[0].line_range_mapping,
      source="diffEditor.revealFirstDiff",
    )
    |> ignore
  }
}

///|
/// Request a one-shot reveal of the current comparison's first raw mapping.
/// Unlike F7 navigation this is not cursor-relative and does not merge nearby
/// mappings into Accessible Diff Viewer groups.
pub fn DiffEditorWidget::reveal_first_diff(self : DiffEditorWidget) -> Unit {
  if self.disposed || self.view_model.get_model() is None {
    return
  }
  // Deferred edge reveals are one last-writer-wins request. A MultiDiff host
  // can request the last hunk while this initial first-hunk request is waiting
  // for diff/layout readiness; allowing both to fire would leave the cursor at
  // the last hunk while the parent consumes the first hunk's scroll event.
  self.pending_reveal_last_diff_generation = None
  self.pending_reveal_first_diff_generation = Some(
    self.editors.committed_model_generation(),
  )
  // A host can request the reveal after an already-ready pair is installed.
  // Pending/hidden pairs retain the request until reconciliation completes.
  self.try_reveal_first_diff()
}

///|
/// Consume a deferred final-diff request under the same model/layout fences as
/// `reveal_first_diff`.
fn DiffEditorWidget::try_reveal_last_diff(self : DiffEditorWidget) -> Unit {
  guard self.pending_reveal_last_diff_generation is Some(generation) else {
    return
  }
  if self.editors.committed_model_generation() != generation ||
    !self.editors.same_model(self.view_model.get_model()) {
    self.pending_reveal_last_diff_generation = None
    return
  }
  match self.view_model.get_state() {
    Pending => return
    NoModel | Failed => {
      self.pending_reveal_last_diff_generation = None
      return
    }
    Ready => ()
  }
  guard self.diff_state is Some(diff_state) else { return }
  self.pending_reveal_last_diff_generation = None
  guard !diff_state.mappings.is_empty() else { return }
  self.reveal_change(
    diff_state.mappings[diff_state.mappings.length() - 1].line_range_mapping,
    source="diffEditor.revealLastDiff",
  )
  |> ignore
}

///|
/// Request a one-shot reveal of the current comparison's final raw mapping.
/// Multi-diff hosts use this when Shift+F7 crosses into the previous item.
pub fn DiffEditorWidget::reveal_last_diff(self : DiffEditorWidget) -> Unit {
  if self.disposed || self.view_model.get_model() is None {
    return
  }
  self.pending_reveal_first_diff_generation = None
  self.pending_reveal_last_diff_generation = Some(
    self.editors.committed_model_generation(),
  )
  self.try_reveal_last_diff()
}

///|
pub fn DiffEditorWidget::reveal_next_change(self : DiffEditorWidget) -> Bool {
  guard self.view_model.get_model() is Some(model) else { return false }
  let current_line = self.editors.modified
    .get_position()
    .map_or(1, position => position.line_number)
  guard self.diff_state is Some(diff_state) &&
    diff_state.next_change_from_modified_line(
      current_line,
      model.modified.get_line_count(),
    )
    is Some(target) else {
    return false
  }
  self.reveal_navigation_target(target)
}

///|
/// Reveal the next change only when it remains inside this comparison. A
/// multi-diff host uses `false` as the signal to advance to its next item.
pub fn DiffEditorWidget::reveal_next_change_without_wrap(
  self : DiffEditorWidget,
) -> Bool {
  let current_line = self.editors.modified
    .get_position()
    .map_or(1, position => position.line_number)
  guard self.diff_state is Some(diff_state) &&
    diff_state.next_change_from_modified_line_without_wrap(current_line)
    is Some(target) else {
    return false
  }
  self.reveal_navigation_target(target)
}

///|
pub fn DiffEditorWidget::reveal_previous_change(
  self : DiffEditorWidget,
) -> Bool {
  let current_line = self.editors.modified
    .get_position()
    .map_or(1, position => position.line_number)
  guard self.diff_state is Some(diff_state) &&
    diff_state.previous_change_from_modified_line(current_line) is Some(target) else {
    return false
  }
  self.reveal_navigation_target(target)
}

///|
/// Reveal the previous change only when it remains inside this comparison.
pub fn DiffEditorWidget::reveal_previous_change_without_wrap(
  self : DiffEditorWidget,
) -> Bool {
  let current_line = self.editors.modified
    .get_position()
    .map_or(1, position => position.line_number)
  guard self.diff_state is Some(diff_state) &&
    diff_state.previous_change_from_modified_line_without_wrap(current_line)
    is Some(target) else {
    return false
  }
  self.reveal_navigation_target(target)
}

///|
fn DiffEditorWidget::apply_layout_dom(self : DiffEditorWidget) -> Unit {
  let ratio = self.layout_state.split_ratio
  self.sash.set_attribute("aria-valuenow", (ratio * 100.0).round().to_string())
  match self.layout_state.actual_layout {
    SideBySide => {
      self.inline_original_strip_width = -1.0
      self.root.set_attribute(
        "class", "moonbit-diff-editor moonbit-diff-editor-side-by-side",
      )
      self.root.set_attribute("data-render-mode", "side-by-side")
      self.root.remove_attribute("data-inline-original-width")
      self.original_host.remove_attribute("hidden")
      self.original_host.remove_attribute("aria-hidden")
      if self.options.sash_enabled {
        self.sash.remove_attribute("hidden")
        self.sash.remove_attribute("aria-hidden")
        self.sash.set_attribute("tabindex", "0")
      } else {
        self.sash.set_attribute("hidden", "")
        self.sash.set_attribute("aria-hidden", "true")
        self.sash.remove_attribute("tabindex")
      }
      self.modified_host.set_attribute("aria-label", "Modified file")
      self.original_host.set_attribute(
        "style",
        "flex-basis: \{ratio * 100.0}%;",
      )
      self.modified_host.set_attribute(
        "style",
        "flex-basis: \{(1.0 - ratio) * 100.0}%;",
      )
    }
    Inline => {
      self.root.set_attribute(
        "class", "moonbit-diff-editor moonbit-diff-editor-inline",
      )
      self.root.set_attribute("data-render-mode", "inline")
      self.original_host.remove_attribute("hidden")
      self.original_host.remove_attribute("aria-hidden")
      self.sash.set_attribute("hidden", "")
      self.sash.set_attribute("aria-hidden", "true")
      self.sash.remove_attribute("tabindex")
      self.modified_host.set_attribute("aria-label", "Modified file")
      let overview_width = if self.options.overview_ruler { 30.0 } else { 0.0 }
      let panes_width = (self.layout_state.width - overview_width).max(0.0)
      let original_width = self.inline_original_width(
        self.editors.original.get_layout_info().decorations_left,
      )
      self.inline_original_strip_width = original_width
      let modified_width = (panes_width - original_width).max(0.0)
      self.root.set_attribute(
        "data-inline-original-width",
        original_width.to_string(),
      )
      self.original_host.set_attribute(
        "style",
        "left:0px;width:\{original_width}px;flex-basis:auto;",
      )
      self.modified_host.set_attribute(
        "style",
        "left:\{original_width}px;width:\{modified_width}px;flex-basis:auto;",
      )
    }
  }
}

///|
pub fn DiffEditorWidget::layout(self : DiffEditorWidget) -> Unit {
  if self.disposed {
    return
  }
  let rect = self.host.get_bounding_client_rect()
  let width = rect.get_width()
  let height = rect.get_height()
  if width <= 0.0 || height <= 0.0 {
    self.has_valid_layout_box = false
    self.pending_layout_modified_viewport = None
    self.cancel_layout_render_barrier()
    return
  }
  self.has_valid_layout_box = true
  self.capture_layout_modified_viewport_if_absent()
  self.layout_state.layout(width) |> ignore
  self.editors.update_options(
    self.editor_options,
    self.options.diff_word_wrap,
    self.layout_state.actual_layout,
    self.options.handle_mouse_wheel,
  )
  self.apply_layout_dom()
  self.editors.sync_markdown_comment_presentations(
    self.layout_state.actual_layout,
    self.options.render_markdown_comments,
  )
  self.layout_editors_after_render()
}

///|
pub fn DiffEditorWidget::focus(self : DiffEditorWidget) -> Unit {
  self.editors.focus()
}

///|
pub fn DiffEditorWidget::dispose(self : DiffEditorWidget) -> Unit {
  if self.disposed {
    return
  }
  self.clear_diff_features_for_transition()
  self.disposed = true
  if self.resize_observer is Some(observer) {
    observer.dispose()
  }
  self.resize_observer = None
  self.pointer_monitor.dispose()
  self.cancel_layout_render_barrier()
  for disposable in self.lifetime {
    disposable.dispose()
  }
  self.lifetime.clear()
  self.view_model.dispose()
  if self.original_overview_ruler is Some(ruler) {
    ruler.dispose()
  }
  if self.modified_overview_ruler is Some(ruler) {
    ruler.dispose()
  }
  self.original_overview_ruler = None
  self.modified_overview_ruler = None
  self.editors.dispose()
  self.original_decoration_ids.clear()
  self.modified_decoration_ids.clear()
  self.original_alignment_zone_ids.clear()
  self.modified_alignment_zone_ids.clear()
  self.clear_inline_deleted_zones()
  self.original_alignment_geometry = None
  self.modified_alignment_geometry = None
  self.diff_state = None
  self.last_published_content_height = None
  self.pending_reveal_first_diff_generation = None
  self.pending_reveal_last_diff_generation = None
  self.reconciling_generation = 0
  self.is_reconciling = false
  self.layout_render_generation = 0
  self.has_valid_layout_box = false
  self.inline_original_strip_width = -1.0
  self.clear_pending_scroll_echoes()
  self.did_change_content_height.dispose()
  self.did_reveal_change.dispose()
  self.host.remove_child(self.root.as_node())
}
