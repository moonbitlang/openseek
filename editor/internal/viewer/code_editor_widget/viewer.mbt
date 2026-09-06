///|
/// The embeddable readonly code viewer, the `vs/editor` (Monaco) role: an
/// browser `View` owning the rendered lines, the scroll and
/// layout model, the input bridge, and the feature controllers. It is
/// constructed independently from document sources, attached into a
/// host-provided stable element, and reports lifecycle facts through typed
/// subscriptions; it knows nothing about transports, shell reload policy,
/// provider watches, or harness event formats.
///
/// All methods are plain calls (the host wraps them in its own effect
/// system if it has one). The host must never render its own children
/// into the element passed to `attach`.
struct CodeEditorWidget {
  services : CodeEditorServices
  /// Services created by an omitted constructor argument belong to this
  /// CodeEditorWidget. An explicitly supplied bundle remains caller-owned and may be
  /// shared by other Viewers.
  owns_services : Bool
  mut disposed : Bool
  /// CodeEditorWidget-id registration in the lower JS-only testing registry. It is
  /// generation-safe and owns all workbench/browser-test observations and
  /// private controls for this CodeEditorWidget.
  mut testing_registration : @base_common.Disposable?
  /// CodeEditorWidget-lifetime subscriptions, distinct from ModelData's swap-scoped
  /// listeners and View's browser-resource store.
  lifetime_disposables : Array[@base_common.Disposable]
  /// CodeEditorWidget-lifetime options, measured geometry, font facts, and derived
  /// layout identity behind one configuration transition owner.
  configuration : EditorConfigurationState
  did_change_model : @base_common.Emitter[@editor_api.ModelChangedEvent]
  /// Package-private lifecycle diagnostic fired immediately after the
  /// outgoing model's `on_before_detached` transition.
  did_detach_model_for_diagnostics : @base_common.Emitter[Unit]
  /// Monaco's `onDidChangeModelContent` (`cew:105`), re-fired from the
  /// installed model's public content event by the `attach_model`
  /// subscription.
  did_change_model_content : @base_common.Emitter[
    @model.ModelContentChangedEvent,
  ]
  did_change_cursor_position : @base_common.Emitter[
    @editor_api.CursorPositionChangedEvent,
  ]
  did_change_cursor_selection : @base_common.Emitter[
    @editor_api.CursorSelectionChangedEvent,
  ]
  /// ViewModel cursor facts wait here until each item can be delivered as one
  /// adjacent position/selection pair. The drain gate prevents reentrant
  /// listeners from interleaving a later pair; content barriers hold Flush
  /// facts until the corresponding public model-content callback completes.
  cursor_delivery : CursorEventDelivery
  did_build_view_model : @base_common.Emitter[
    @viewer_testing.ViewModelBuiltObservation,
  ]
  did_scroll : @base_common.Emitter[@editor_api.ScrollEvent]
  /// Internal `onDidLayoutChange` counterpart. DiffEditor consumes the complete
  /// layout info so its clipped original line-number strip follows model digit
  /// bands and asynchronously refreshed font metrics.
  did_change_layout_info : @base_common.Emitter[@config.EditorLayoutInfo]
  /// Public `onDidChangeViewZones`. The source emitter participates in a
  /// widget-wide delivery queue; that cross-event queue remains the explicit
  /// CEW-001 deferral, while this dedicated emitter preserves the event's own
  /// listener semantics.
  did_change_view_zones : @base_common.Emitter[Unit]
  /// Public `onDidChangeHiddenAreas`, relayed from the current model's outgoing
  /// ViewModel dispatcher only after its complete mapping transaction.
  did_change_hidden_areas : @base_common.Emitter[Unit]
  did_dispose : @base_common.Emitter[Unit]
  /// Public mouse events (`onMouseDown`/`onMouseUp`/`onMouseMove`/
  /// `onMouseLeave`/`onContextMenu`, see `mouse_events.mbt`), fired from the
  /// controller's notify seams; contributions subscribe like Monaco's editor
  /// controllers.
  did_mouse_down : @base_common.Emitter[@editor_browser.EditorMouseEvent]
  did_mouse_up : @base_common.Emitter[@editor_browser.EditorMouseEvent]
  did_mouse_move : @base_common.Emitter[@editor_browser.EditorMouseEvent]
  did_context_menu : @base_common.Emitter[@editor_browser.EditorMouseEvent]
  did_mouse_leave : @base_common.Emitter[
    @editor_browser.PartialEditorMouseEvent,
  ]
  /// The last fired scroll event's facts, the diff base for the next event's
  /// `*_changed` flags (Monaco's `ScrollEvent` carries per-axis change bits).
  mut last_scroll_event : @editor_api.ScrollEvent?
  /// CodeEditorWidget-lifetime generation/current-model owner. Browser-only state lives
  /// under the current ModelData rather than beside it on the root CodeEditorWidget.
  model_slot : ViewerModelSlot
  /// One-way browser attachment aggregate. It owns the caller host, the
  /// atomic no-model placeholder, render publication, and DOM focus state.
  mut mount : ViewerMount
  /// Registered overlay widgets by id (Monaco's `_overlayWidgets`), re-added
  /// to every per-model view (`cew:1901-1905`).
  overlay_widgets : Map[String, @editor_browser.OverlayWidget]
  /// Kernel-owned overview rulers. The handles survive model swaps, reattach
  /// to the new per-model View, and are disposed before the editor tears that
  /// View down. Higher-level coordinators only submit immutable entries.
  overview_rulers : Array[CodeEditorOverviewRuler]
  /// Monotonic paint generation used by the internal `after_next_render`
  /// primitive. A waiter captures `render_generation + 1`, so a callback from
  /// an older layout transaction can never satisfy a newer render fence.
  mut render_generation : Int
  did_render : @base_common.Emitter[Int]
  mut pending_rendered : PendingRendered?
  mut scroll_dirty : Bool
  /// This editor's decoration `ownerId` (Monaco's per-widget editor id): the
  /// filter handed to `ViewModelDecorations` and the ownerId of the public
  /// `delta_decorations` API.
  editor_id : Int
  /// The per-editor contribution owner around the registry's sole concrete
  /// instance map, including its two-phase disposal lifecycle.
  contributions : EditorContributions
}

///|
priv struct PendingRendered {
  model : @model.TextModel
  fresh : Bool
}

///|
/// A deferred horizontal reveal, Monaco's `HorizontalRevealRangeRequest`. Holds
/// the 1-based view line/columns to measure once rendered, plus the scroll-top
/// band (`[start_scroll_top, stop_scroll_top]`) outside which an intervening
/// vertical scroll cancels the request.
priv enum CursorRevealScrollType {
  Smooth
  Immediate
} derive(Eq)

///|
priv struct HorizontalRevealRangeRequest {
  minimal_reveal : Bool
  view_line_number : Int
  start_column : Int
  end_column : Int
  start_scroll_top : Double
  stop_scroll_top : Double
  scroll_type : CursorRevealScrollType
}

///|
struct CodeEditorViewState {
  scroll_top : Double
  scroll_left : Double
  folding_state : @folding_browser.FoldingStateMemento?
} derive(Debug)

///|
/// Creates a viewer instance. An omitted service bundle is created and owned
/// internally; an explicit bundle is borrowed and may be shared. Call
/// `attach` before setting documents so the first render has a DOM view to
/// measure and patch.
fn CodeEditorWidget::CodeEditorWidget(
  services? : CodeEditorServices,
  options? : CodeEditorOptions = CodeEditorOptions::default(),
  initial_container? : @rdom.Element,
  contributions? : CodeEditorContributionDescriptors = CodeEditorContributionDescriptors::standalone(),
) -> CodeEditorWidget {
  let (services, owns_services) = match services {
    Some(services) => (services, false)
    None => (CodeEditorServices(), true)
  }
  let font_info = @config.FontInfo::estimated(
    options.bare_font_info(pixel_ratio=@base_browser.device_pixel_ratio()),
  )
  let (initial_width, initial_height) = match initial_container {
    Some(container) => read_container_size(container)
    None => (0.0, 0.0)
  }
  let viewer : CodeEditorWidget = {
    services,
    owns_services,
    disposed: false,
    testing_registration: None,
    lifetime_disposables: [],
    configuration: EditorConfigurationState(
      options,
      font_info,
      initial_width~,
      initial_height~,
    ),
    did_change_model: Emitter(),
    did_detach_model_for_diagnostics: Emitter(),
    did_change_model_content: Emitter(),
    did_change_cursor_position: Emitter(),
    did_change_cursor_selection: Emitter(),
    cursor_delivery: CursorEventDelivery(),
    did_build_view_model: Emitter(),
    did_scroll: Emitter(),
    did_change_layout_info: Emitter(),
    did_change_view_zones: Emitter(),
    did_change_hidden_areas: Emitter(),
    did_dispose: Emitter(),
    did_mouse_down: Emitter(),
    did_mouse_up: Emitter(),
    did_mouse_move: Emitter(),
    did_context_menu: Emitter(),
    did_mouse_leave: Emitter(),
    last_scroll_event: None,
    model_slot: ViewerModelSlot(),
    mount: Headless,
    overlay_widgets: Map([]),
    overview_rulers: [],
    render_generation: 0,
    did_render: Emitter(),
    pending_rendered: None,
    scroll_dirty: false,
    editor_id: next_editor_id(),
    contributions: EditorContributions(),
  }
  // Marker decoration changes reach the render through the model's
  // decoration storage (`onDidChangeDecorations` → `ViewDecorationsChanged`);
  // this subscription only schedules the refresh without rebuilding the view model
  // because the model subscription already delivered the exact typed event.
  // Hosts observe marker changes on `MarkerService::on_did_change_markers`.
  viewer.add_lifetime_disposable(
    viewer.services.marker_decorations.on_did_change_marker_decorations(model => {
      if viewer.is_current_model(model) {
        viewer.schedule_render()
      }
    }),
  )
  // Editor contributions instantiate through the registry
  // (`codeEditorWidget.ts:344` `this._contributions.initialize(...)`);
  // they live until `dispose` — `set_model` does not re-create them.
  editor_registry().instantiate_enabled(viewer, contributions)
  viewer.testing_registration = Some(
    @viewer_testing.register_viewer(viewer.get_id(), set_hidden_areas=(
      ranges,
      source,
      force_update,
    ) => viewer.set_hidden_areas(ranges, source?, force_update~)),
  )
  viewer
}

///|
/// Package-private scheduler seam for deterministic hover timing tests. The
/// production constructor always installs the clearable browser timeout.
fn CodeEditorWidget::set_hover_host_for_test(
  self : CodeEditorWidget,
  schedule : (() -> Unit, Int) -> @base_common.Disposable,
  test_launch_async_task : (async () -> Unit noraise) -> Unit,
) -> Unit {
  match self.content_hover_contribution() {
    Some(state) => {
      state.schedule_timeout = schedule
      state.launch_async_task = test_launch_async_task
    }
    None => ()
  }
}

///|
/// The test seam is intentionally package-private and therefore only called
/// by a white-box test build; retain it in the ordinary library build too.
let _hover_scheduler_test_seam_anchor : Unit = ignore(
  (
    CodeEditorWidget::set_hover_host_for_test,
    CodeEditorWidget::start_showing_hover_at_range,
  ),
)

///|
fn CodeEditorWidget::on_did_detach_model_for_diagnostics(
  self : CodeEditorWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_detach_model_for_diagnostics.event(_ => listener())
}

///|
let _model_detach_diagnostics_test_seam_anchor : Unit = ignore(
  CodeEditorWidget::on_did_detach_model_for_diagnostics,
)

///|
/// Retains a CodeEditorWidget-lifetime handle, disposing immediately when registration
/// races with or follows CodeEditorWidget disposal.
fn CodeEditorWidget::add_lifetime_disposable(
  self : CodeEditorWidget,
  disposable : @base_common.Disposable,
) -> Unit {
  if self.disposed {
    disposable.dispose()
  } else {
    self.lifetime_disposables.push(disposable)
  }
}

///|
fn CodeEditorWidget::dispose_lifetime_disposables(
  self : CodeEditorWidget,
) -> Unit {
  for disposable in self.lifetime_disposables {
    disposable.dispose()
  }
  self.lifetime_disposables.clear()
}

///|
fn CodeEditorWidget::cancel_render_frame(self : CodeEditorWidget) -> Unit {
  match self.mount {
    Headless => ()
    Mounted(mounted) => mounted.cancel_render_frame()
  }
}

///|
/// Process-wide editor id counter (Monaco's per-widget editor id).
priv struct EditorIdCounter {
  mut value : Int
}

///|
let editor_id_counter : EditorIdCounter = { value: 0, }

///|
fn next_editor_id() -> Int {
  editor_id_counter.value += 1
  editor_id_counter.value
}

///|
/// Creates and attaches a viewer in one call — the `monaco.editor.create`
/// entry point. Service ownership follows `CodeEditorWidget::CodeEditorWidget`.
pub fn CodeEditorWidget::create(
  host : @rdom.Element,
  services? : CodeEditorServices,
  options? : CodeEditorOptions = CodeEditorOptions::default(),
  contributions~ : CodeEditorContributionDescriptors,
) -> CodeEditorWidget {
  // `EditorConfiguration` constructs its `ElementSizeObserver` before model
  // attachment in Monaco. Seed the same client-box fact before contributions
  // can observe this CodeEditorWidget; `attach` rechecks after publishing the mount.
  let viewer = CodeEditorWidget(
    services?,
    options~,
    initial_container=host,
    contributions~,
  )
  viewer.attach(host)
  viewer
}

///|
/// Fires when the installed model changed — Monaco's `onDidChangeModel`
/// carrying `IModelChangedEvent` (the old/new resource URIs).
pub fn CodeEditorWidget::on_did_change_model(
  self : CodeEditorWidget,
  listener : (@editor_api.ModelChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_model.event(listener)
}

///|
/// Fires when the installed model's content changed — Monaco's
/// `onDidChangeModelContent` (`cew:105`), carrying the model's public
/// `IModelContentChangedEvent` payload. Today's only producer is the
/// `set_value` flush lane, so `is_flush` is always true.
pub fn CodeEditorWidget::on_did_change_model_content(
  self : CodeEditorWidget,
  listener : (@model.ModelContentChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_model_content.event(listener)
}

///|
/// Fires when the primary cursor's model position changed — Monaco's
/// `onDidChangeCursorPosition` (`cew:117-118`, fired at `:1836-1845`).
/// Single-cursor: `secondary_positions` is always empty.
pub fn CodeEditorWidget::on_did_change_cursor_position(
  self : CodeEditorWidget,
  listener : (@editor_api.CursorPositionChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_cursor_position.event(listener)
}

///|
/// Fires when the primary cursor's model selection changed — Monaco's
/// `onDidChangeCursorSelection` (`cew:120-121`, fired at `:1846-1857`).
/// Single-cursor: the secondary arrays are always empty.
pub fn CodeEditorWidget::on_did_change_cursor_selection(
  self : CodeEditorWidget,
  listener : (@editor_api.CursorSelectionChangedEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_change_cursor_selection.event(listener)
}

///|
/// Fires after the editor scroll position or extents changed — Monaco's
/// `onDidScrollChange`, coalesced onto the render flush.
pub fn CodeEditorWidget::on_did_scroll_change(
  self : CodeEditorWidget,
  listener : (@editor_api.ScrollEvent) -> Unit,
) -> @base_common.Disposable {
  self.did_scroll.event(listener)
}

///|
/// Fires whenever the computed editor layout identity changes. The payload is
/// the same reduced layout info returned by `get_layout_info`; callers do not
/// need to infer gutter changes from outer container resize events.
pub fn CodeEditorWidget::on_did_layout_change(
  self : CodeEditorWidget,
  listener : (@config.EditorLayoutInfo) -> Unit,
) -> @base_common.Disposable {
  self.did_change_layout_info.event(listener)
}

///|
fn CodeEditorWidget::emit_layout_change_if_needed(
  self : CodeEditorWidget,
  previous : EditorLayoutIdentity,
) -> Unit {
  let current = self.configuration.event_snapshot().layout
  if !previous.same_layout_info(current) {
    self.did_change_layout_info.fire(
      self.configuration
      .snapshot()
      .layout_info(self.configuration.model_line_count),
    )
  }
}

///|
/// Fires after a successful ViewZones whitespace transaction. Internal View
/// delivery has completed before the ViewModel outgoing arm reaches this
/// emitter.
pub fn CodeEditorWidget::on_did_change_view_zones(
  self : CodeEditorWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_change_view_zones.event(_ => listener())
}

///|
pub fn CodeEditorWidget::on_did_dispose(
  self : CodeEditorWidget,
  listener : () -> Unit,
) -> @base_common.Disposable {
  self.did_dispose.event(_ => listener())
}

///|
/// Applies runtime options — `updateOptions`. Theme and placeholder apply
/// without a rebuild; the current view model is rebuilt when wrapping, tab, or
/// render settings change.
pub fn CodeEditorWidget::update_options(
  self : CodeEditorWidget,
  options : CodeEditorOptions,
) -> Unit {
  let previous_configuration = self.configuration.event_snapshot()
  let previous = previous_configuration.configuration.options
  if previous == options {
    return
  }
  let previous_fold_lane_width = self.configuration
    .snapshot()
    .layout_decorations_width()
    .to_int()
  let event_batch = self.begin_view_event_batch()
  self.configuration.replace_options(options) |> ignore
  // Existing Markdown ViewZones outlive option changes. Keep their gutter
  // chevrons on the same live decorations lane as ordinary folding icons;
  // agent feedback can widen that lane after a model has already mounted.
  if previous_fold_lane_width !=
    self.configuration.snapshot().layout_decorations_width().to_int() {
    self.sync_markdown_comment_fold_lane_width()
  }
  if previous.theme != options.theme {
    self.apply_theme()
    self.markdown_comments_on_theme_changed(options.theme)
  }
  if previous.smooth_scrolling != options.smooth_scrolling {
    match self.get_view_model() {
      Some(view_model) =>
        view_model.view_layout.set_smooth_scrolling(options.smooth_scrolling)
      None => ()
    }
  }
  // The folding half of Monaco's `onDidChangeConfiguration` subscription
  // (`folding.ts:155-180`).
  self.folding_on_configuration_changed(previous)
  if !previous.same_layout_options(options) {
    // A changed font option resolves through `FontMeasurements` immediately
    // (Monaco's synchronous `_recomputeOptions`), so the wrap column below
    // already uses the new advance width.
    self.refresh_font_info()
    self.configuration.recompute_soft_wrap_column() |> ignore
    self.on_configuration_changed(previous_options=previous)
    self.configuration.request_measure()
  }
  let current_model_line_count = match self.get_model() {
    Some(model) => model.snapshot.line_count()
    None => 0
  }
  let current_view_line_count = match self.get_view_model() {
    Some(view_model) => view_model.line_count()
    None => 0
  }
  self.configuration.set_line_counts(
    current_model_line_count, current_view_line_count,
  )
  match
    previous_configuration.changed_event(self.configuration.event_snapshot()) {
    Some(event) => self.emit_view_event(ViewConfigurationChanged(event))
    None => ()
  }
  end_view_event_batch(event_batch)
  self.emit_layout_change_if_needed(previous_configuration.layout)
  self.refresh_managed_overview_rulers()
  self.schedule_render()
}

///|
/// Mirrors the theme option onto the active presentation without replacing its
/// root or scroll state.
fn CodeEditorWidget::apply_theme(self : CodeEditorWidget) -> Unit {
  let theme = self.configuration.snapshot().options.theme
  match self.mount {
    Headless => ()
    Mounted(mounted) => mounted.apply_placeholder_theme(theme)
  }
  match self.current_code_browser_data() {
    Some(presentation) => presentation.apply_theme(theme)
    None => ()
  }
}

///|
/// Takes ownership of the host element: stores the container and mounts the
/// CodeEditorWidget-owned no-model placeholder. The per-model `View` is created by
/// `attach_model` and destroyed by `detach_model` (Monaco's `_attachModel`
/// → `_createView` / `_detachModel`). The host element must stay mounted
/// and must never receive host-rendered children.
fn CodeEditorWidget::attach(
  self : CodeEditorWidget,
  host : @rdom.Element,
) -> Unit {
  if self.disposed {
    return
  }
  match self.mount {
    Mounted(_) => return
    Headless => ()
  }
  // Construct the complete placeholder capability locally and publish the
  // mounted aggregate only after its DOM is installed. No callback can
  // observe a host, root, and text node in partially initialized states.
  let placeholder = PlaceholderDom(self.configuration.snapshot().options.theme)
  host.append_child(placeholder.root.as_node())
  self.mount = Mounted(MountedViewer(host, placeholder))
  // Public construction is synchronous: the returned CodeEditorWidget already reports
  // the host client box even when it has no model and before any animation
  // frame. The constructor supplied the same fact before contributions; this
  // second read also covers the private headless-then-attach test path.
  self.measure()
  // Untrusted readings re-measure after 5s (`FontMeasurements.onDidChange`,
  // e.g. once a web font finished loading) — Monaco's
  // `_recomputeOptions` subscription in `editorConfiguration.ts`. CodeEditorWidget-
  // level: it outlives any per-model view.
  self.add_lifetime_disposable(
    @browser_config.font_measurements().on_did_change(() => {
      if !self.disposed {
        self.configuration.request_measure()
        self.schedule_render()
      }
    }),
  )
  self.configuration.request_measure()
  self.schedule_render()
}

///|
/// Replaces the installed model's whole content in place — `setValue`
/// (`cew:487-497`): delegate to `model.setValue`. Unlike `set_model`, the
/// same `TextModel`, `ViewModel`, and `View` survive: scroll clamps instead
/// of resetting, and feature contribs re-derive their state from the
/// content-change event. No model → no-op, like the source's `_modelData`
/// guard. The `_beginUpdate`/`_endUpdate` bracket is N-A — the viewer's
/// repaint already coalesces on the scheduled render flush.
pub fn CodeEditorWidget::set_value(
  self : CodeEditorWidget,
  value : String,
) -> Unit {
  if self.disposed {
    return
  }
  guard self.model_slot.current is Some(model_data) else { return }
  model_data.model.set_value(value)
}

///|
/// Renders caller-owned immutable text model state — `setModel`. Source reads,
/// watches, reloads, and error policy belong to the host. `None` detaches the
/// current model and clears the rendered content. Like Monaco, swapping the
/// model resets the scroll position and controller state; hosts preserve or
/// restore scroll through `save_view_state`/`restore_view_state`.
pub fn CodeEditorWidget::set_model(
  self : CodeEditorWidget,
  model : @model.TextModel?,
) -> Unit {
  if self.disposed {
    return
  }
  // `setModel` (`cew:506-546`): same-model no-ops, then detach-then-attach,
  // carrying text focus across the swap.
  if self.model_slot.current is None && model is None {
    return
  }
  match (self.model_slot.current, model) {
    (Some(model_data), Some(model)) =>
      if model_data.model.same(model) {
        return
      }
    _ => ()
  }
  let old_model_url = self.model_slot.current.map(model_data => {
    model_data.model.uri
  })
  let new_model_url = model.map(model => model.uri)
  let had_text_focus = self.has_text_focus()
  let had_definition_peek_focus = self.definition_peek_contains_focus()
  let previous_layout_identity = self.configuration.event_snapshot().layout
  let detached_model = self.detach_model()
  match model {
    Some(model) => self.attach_model(model)
    // `_attachModel(null)` just nulls `_modelData` (`cew:1751-1754`); the
    // scheduled flush repaints the placeholder. View zones are owned by the
    // outgoing per-model View, so detach and every model replacement lose
    // them structurally.
    None => self.schedule_render()
  }
  if self.has_model() {
    // "we have a new model (with a new view)!" (`cew:528-532`).
    if had_text_focus || had_definition_peek_focus {
      self.focus()
    }
  } else {
    // "make sure the outside world knows we are not focused" (`cew:536`).
    match self.mount {
      Headless => ()
      Mounted(mounted) => mounted.set_editor_focus(false) |> ignore
    }
  }
  self.did_change_model.fire({ old_model_url, new_model_url, })
  // `_postDetachModelCleanup` (`cew:2008-2010`): sweep this editor's
  // decorations off the outgoing model by owner id.
  match detached_model {
    Some(detached) =>
      detached.remove_all_decorations_with_owner_id(self.editor_id)
    None => ()
  }
  self.emit_layout_change_if_needed(previous_layout_identity)
}

///|
/// Completes model setup after the host has installed the model, restored view
/// state, and applied synchronous options — Monaco's separate
/// `ICodeEditor.handleInitialized`. This is intentionally not part of
/// `set_model`. Every call republishes the current stable visible demand, which
/// also lets the model cancel a pending unstable-range debounce. A token
/// listener may synchronously replace the model, but this call retains and
/// completes only the model that was current when it began.
pub fn CodeEditorWidget::handle_initialized(self : CodeEditorWidget) -> Unit {
  if self.disposed {
    return
  }
  guard self.model_slot.current is Some(_) else { return }
  self.stabilize_active_scroll()
}

///|
/// Monaco's `_detachModel` (`cew:2012-2032`): reset the per-model feature
/// state, dispose the bundle's listeners, remove the view's DOM subtree from
/// the container (restoring the no-model placeholder), drop `data-mode-id`,
/// and hand back the outgoing model for the owner-id decoration sweep.
fn CodeEditorWidget::detach_model(self : CodeEditorWidget) -> @model.TextModel? {
  guard self.model_slot.current is Some(_) else { return None }
  self.close_definition_peek(restore_focus=false)
  guard self.model_slot.invalidate_current_for_detach() is Some(model_data) else {
    return None
  }
  self.reset_definition_requests()
  self.cancel_render_frame()
  self.cursor_delivery.reset_model_scope()
  let model = model_data.model
  // Feature state belongs to the outgoing model: the per-model resets Track
  // C moved onto the controllers, plus the widget teardown.
  self.cancel_mouse_selection()
  match self.content_hover_controller() {
    Some(hc) => {
      hc.cancel_all_timers()
      hc.cancel_request()
      hc.reset_model_state()
      hc.hover = hc.hover.cleared()
      hc.hover_keep_open = false
      hc.hover_ignore_mouse_events = false
      hc.hover_is_mouse_down = false
      hc.hover_mouse_posx = 0.0
      hc.hover_mouse_posy = 0.0
      hc.hover_last_modifiers = @hover.EventModifiers::none()
    }
    None => ()
  }
  self.sync_content_hover_widget()
  match self.agent_feedback_input_contribution() {
    Some(ic) => ic.reset_model_state()
    None => ()
  }
  match self.agent_feedback_widget_contribution() {
    Some(wc) => wc.reset_model_state()
    None => ()
  }
  self.clear_agent_feedback_widgets() |> ignore
  // Markdown-comment ViewZones retain caller DOM below the outgoing code View.
  self.clear_markdown_comment_model_state()
  let root = model_data.browser.map(browser => browser.view.root)
  // Keep Monaco's Code order: listener -> attached-view -> View -> ViewModel,
  // followed by root removal.
  model_data.dispose(() => self.did_detach_model_for_diagnostics.fire(()))
  match (self.mount, root) {
    (Mounted(mounted), Some(root)) => {
      mounted.container.remove_attribute("data-mode-id")
      mounted.remove_presentation_root(root, restore_placeholder=!self.disposed)
    }
    (Mounted(mounted), None) =>
      mounted.container.remove_attribute("data-mode-id")
    (Headless, _) => ()
  }
  self.model_slot.clear_current_after_dispose()
  self.configuration.reset_model_line_counts()
  Some(model)
}

///|
/// Returns the current model installed on the viewer.
pub fn CodeEditorWidget::get_model(
  self : CodeEditorWidget,
) -> @model.TextModel? {
  self.model_slot.current.map(model_data => model_data.model)
}

///|
/// Whether a model is installed — `hasModel`, Monaco's type-guard companion to
/// `getModel`.
fn CodeEditorWidget::has_model(self : CodeEditorWidget) -> Bool {
  self.model_slot.current is Some(_)
}

///|
/// The attached bundle's view model — Monaco's `_getViewModel()`.
fn CodeEditorWidget::get_view_model(
  self : CodeEditorWidget,
) -> @view_model.ViewModel? {
  self.model_slot.current.map(model_data => model_data.view_model)
}

///|
/// The attached bundle's view — `None` with no model, and `None` headless
/// (the `hasRealView = false` analog).
fn CodeEditorWidget::current_code_view(self : CodeEditorWidget) -> @view.View? {
  self.current_code_browser_data().map(browser => browser.view)
}

///|
/// The current options snapshot — the read side of `update_options` (Monaco's
/// `getOptions`/`getRawOptions`, collapsed onto the one options struct).
pub fn CodeEditorWidget::get_options(
  self : CodeEditorWidget,
) -> CodeEditorOptions {
  self.configuration.snapshot().options
}

///|
/// This editor's unique id, Monaco's `getId()`: the editor type plus the
/// process-wide instance counter.
pub fn CodeEditorWidget::get_id(self : CodeEditorWidget) -> String {
  "\{self.get_editor_type()}:\{self.editor_id.to_string()}"
}

///|
/// The editor's own root element — `getDomNode` (`cew:1489-1494`): the
/// view's node only while a model is attached with a real view.
pub fn CodeEditorWidget::get_dom_node(
  self : CodeEditorWidget,
) -> @rdom.Element? {
  self.active_presentation_root()
}

///|
/// The original host container element — `getContainerDomNode`. Public
/// Viewers are created with `CodeEditorWidget::create`, so the host is always present
/// and remains queryable after CodeEditorWidget disposal.
pub fn CodeEditorWidget::get_container_dom_node(
  self : CodeEditorWidget,
) -> @rdom.Element {
  match self.mount {
    Mounted(mounted) => mounted.container
    Headless => abort("CodeEditorWidget is not attached")
  }
}

///|
/// Focuses the editor's focusable surface — `focus()`. Monaco focuses the
/// hidden textarea / edit context; the viewer's focusable surface is the view
/// root itself.
pub fn CodeEditorWidget::focus(self : CodeEditorWidget) -> Unit {
  match self.current_code_browser_data() {
    Some(presentation) => presentation.focus()
    None => ()
  }
}

///|
/// Whether the editor's text surface has DOM focus — `hasTextFocus()`.
pub fn CodeEditorWidget::has_text_focus(self : CodeEditorWidget) -> Bool {
  match self.mount {
    Headless => false
    Mounted(mounted) => mounted.editor_has_focus
  }
}

///|
/// Returns the current scroll and contribution state in host-restorable form
/// — Monaco's `saveViewState` (`cew:1038-1049`). No model → `None`.
pub fn CodeEditorWidget::save_view_state(
  self : CodeEditorWidget,
) -> CodeEditorViewState? {
  guard self.active_scroll_position() is Some(position) else { return None }
  let folding_state = self
    .folding_controller()
    .bind(controller => controller.save_view_state())
  Some({
    scroll_top: position.scroll_top,
    scroll_left: position.scroll_left,
    folding_state,
  })
}

///|
/// Restores a previously captured contribution and scroll state — Monaco's
/// `restoreViewState` (`cew:1052-1071`): contribution state is applied before
/// the view state; a no-op without a model, and `None` restores nothing.
pub fn CodeEditorWidget::restore_view_state(
  self : CodeEditorWidget,
  state : CodeEditorViewState?,
) -> Unit {
  match state {
    Some(state) => {
      match (self.folding_controller(), state.folding_state) {
        (Some(controller), Some(folding_state)) =>
          controller.restore_view_state(folding_state)
        _ => ()
      }
      self.set_active_scroll_position(
        scroll_top=state.scroll_top,
        scroll_left=state.scroll_left,
      )
      // Code `View.restoreState` publishes stable priority only after both
      // scroll axes have synchronously delivered their ordinary unstable
      // update.
      self.stabilize_active_scroll()
    }
    None => ()
  }
}

///|
/// Disposes viewer-owned external resources. Like Monaco's dispose, the model
/// detaches silently (no `onDidChangeModel`).
pub fn CodeEditorWidget::dispose(self : CodeEditorWidget) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.cancel_render_frame()
  self.dispose_managed_overview_rulers()
  // `CodeEditorWidget.dispose` clears widget registries before model teardown.
  // The contribution instances and CodeEditorWidget-lifetime store remain live until
  // after `onDidDispose` fires (they are owned by the source base store).
  self.overlay_widgets.clear()
  // The model detaches silently (no `onDidChangeModel`), but the owner-id
  // sweep still runs (`_postDetachModelCleanup`).
  match self.detach_model() {
    Some(detached) =>
      detached.remove_all_decorations_with_owner_id(self.editor_id)
    None => ()
  }
  // CodeEditorWidget-owned attach DOM is removed before the dispose event. The caller's
  // original host remains mounted and retained for `get_container_dom_node`.
  match self.mount {
    Headless => ()
    Mounted(mounted) => mounted.remove_owned_placeholder_dom()
  }
  self.did_dispose.fire(())
  // Contributions dispose with the editor (`codeEditorWidget.dispose` →
  // `_onDidDispose.fire()` → `super.dispose()` → contributions/base store).
  self.contributions.dispose_behavior(self)
  self.dispose_lifetime_disposables()
  match self.mount {
    Headless => ()
    Mounted(mounted) => mounted.clear_disposed_state()
  }
  self.last_scroll_event = None
  self.overlay_widgets.clear()
  self.contributions.dispose_retained_browser_resources()
  self.pending_rendered = None
  self.configuration.clear_measure_request()
  self.scroll_dirty = false
  self.did_change_model.dispose()
  self.did_detach_model_for_diagnostics.dispose()
  self.did_change_model_content.dispose()
  self.did_change_cursor_position.dispose()
  self.did_change_cursor_selection.dispose()
  self.did_build_view_model.dispose()
  self.did_scroll.dispose()
  self.did_change_layout_info.dispose()
  self.did_change_view_zones.dispose()
  self.did_change_hidden_areas.dispose()
  self.did_render.dispose()
  self.did_dispose.dispose()
  self.did_mouse_down.dispose()
  self.did_mouse_up.dispose()
  self.did_mouse_move.dispose()
  self.did_context_menu.dispose()
  self.did_mouse_leave.dispose()
  match self.testing_registration {
    Some(registration) => {
      self.testing_registration = None
      registration.dispose()
    }
    None => ()
  }
  if self.owns_services {
    self.services.dispose()
  }
}

///|
/// Re-measures the viewer box after a host-observed layout change —
/// `layout()`. The explicit-dimension form is not ported: the viewer always
/// measures its host element.
pub fn CodeEditorWidget::layout(self : CodeEditorWidget) -> Unit {
  self.configuration.request_measure()
  self.schedule_render()
}

///|
/// Sets the vertical synthetic scroll position — `setScrollTop`
/// (`cew:1014-1017`, no model → no-op). Wheel and scrollbar input arrive
/// through the view's own listeners.
pub fn CodeEditorWidget::set_scroll_top(
  self : CodeEditorWidget,
  new_scroll_top : Double,
) -> Unit {
  self.set_active_scroll_position(scroll_top=new_scroll_top)
}

///|
/// Sets the horizontal synthetic scroll position — `setScrollLeft`
/// (`cew:1003-1006`, no model → no-op).
pub fn CodeEditorWidget::set_scroll_left(
  self : CodeEditorWidget,
  new_scroll_left : Double,
) -> Unit {
  self.set_active_scroll_position(scroll_left=new_scroll_left)
}

///|
/// Sets both synthetic scroll axes — `setScrollPosition` with Monaco's
/// `INewScrollPosition` semantics: an omitted axis keeps its position
/// (`cew:1025-1028`, no model → no-op).
pub fn CodeEditorWidget::set_scroll_position(
  self : CodeEditorWidget,
  scroll_top? : Double,
  scroll_left? : Double,
) -> Unit {
  self.set_active_scroll_position(scroll_top?, scroll_left?)
}

///|
fn CodeEditorWidget::apply_scroll_change(
  self : CodeEditorWidget,
  change : @view_layout.ScrollChange?,
) -> Unit {
  match change {
    Some(scroll_change) => {
      if scroll_change.scroll_top_changed || scroll_change.scroll_left_changed {
        self.reset_definition_link()
      }
      self.emit_view_scroll_changed(scroll_change)
      match self.current_code_browser_data() {
        Some(browser) =>
          browser.cancel_horizontal_reveal_on_scroll(scroll_change)
        None => ()
      }
      self.on_editor_scroll_changed(scroll_change)
      match self.current_code_view() {
        Some(view) => view.editor_scrollbar.scrollable().reveal_for_scroll()
        None => ()
      }
      self.scroll_dirty = true
      self.schedule_render()
    }
    None => ()
  }
}
