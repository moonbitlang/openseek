///|
priv struct DefinitionPeekRequestStamp {
  generation : Int
  model_identity : Int
  model_generation : Int
  model_version_id : Int
}

///|
/// Preview resources detached atomically from the shared References state before any
/// cancellation or disposal callback can re-enter the Viewer.
priv struct DetachedReferencesPeekPreview {
  viewer : Viewer?
  reference : @navigation_api.TextModelReference?
  decorations : EditorDecorationsCollection?
  layout_frame : @base_common.Disposable?
  resize_observer : @base_common.Disposable?
  restore_focus : Bool
}

///|
/// Local selected-preview transaction. None of these owners enter shared
/// contribution state until every synchronous child/editor callback boundary
/// has completed and the exact root session is still current.
priv struct ProvisionalReferencesPeekPreview {
  viewer : Viewer
  mut reference : @navigation_api.TextModelReference?
  mut decorations : EditorDecorationsCollection?
  mut layout_frame : @base_common.Disposable?
  mut resize_observer : @base_common.Disposable?
}

///|
fn ProvisionalReferencesPeekPreview::dispose(
  self : ProvisionalReferencesPeekPreview,
) -> Unit {
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  match self.layout_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  self.resize_observer = None
  self.layout_frame = None
  self.viewer.set_model(None)
  self.viewer.dispose()
  match self.reference {
    Some(reference) => reference.dispose()
    None => ()
  }
  self.reference = None
  match self.decorations {
    Some(decorations) => decorations.clear()
    None => ()
  }
  self.decorations = None
}

///|
fn ProvisionalReferencesPeekPreview::publish(
  self : ProvisionalReferencesPeekPreview,
  state : ReferencesContributionState,
) -> Unit {
  state.preview_viewer = Some(self.viewer)
  state.preview_reference = self.reference
  state.preview_decorations = self.decorations
  state.preview_layout_frame = self.layout_frame
  state.preview_resize_observer = self.resize_observer
  self.reference = None
  self.decorations = None
  self.layout_frame = None
  self.resize_observer = None
}

///|
fn DetachedReferencesPeekPreview::dispose_viewer(
  self : DetachedReferencesPeekPreview,
) -> Unit {
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  match self.layout_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  match self.viewer {
    Some(viewer) => {
      viewer.set_model(None)
      viewer.dispose()
    }
    None => ()
  }
}

///|
fn DetachedReferencesPeekPreview::dispose_reference(
  self : DetachedReferencesPeekPreview,
) -> Unit {
  match self.reference {
    Some(reference) => reference.dispose()
    None => ()
  }
}

///|
fn DetachedReferencesPeekPreview::dispose_decorations(
  self : DetachedReferencesPeekPreview,
) -> Unit {
  match self.decorations {
    Some(decorations) => decorations.clear()
    None => ()
  }
}

///|
fn DetachedReferencesPeekPreview::dispose(
  self : DetachedReferencesPeekPreview,
) -> Unit {
  self.dispose_viewer()
  self.dispose_reference()
  self.dispose_decorations()
}

///|
/// Group resources detached as one value before any cancellation/release
/// callback runs. Sources and leases retain their group order only to keep
/// teardown deterministic.
priv struct DetachedReferencesGroupPreviews {
  sources : Array[@language.CancellationTokenSource]
  references : Array[@navigation_api.TextModelReference]
}

///|
fn DetachedReferencesGroupPreviews::cancel_sources(
  self : DetachedReferencesGroupPreviews,
) -> Unit {
  for source in self.sources {
    source.dispose(cancel=true)
  }
}

///|
fn DetachedReferencesGroupPreviews::dispose_references(
  self : DetachedReferencesGroupPreviews,
) -> Unit {
  for reference in self.references {
    reference.dispose()
  }
}

///|
fn ReferencesContributionState::retire_preview_source(
  self : ReferencesContributionState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.preview_source {
    Some(current) if physical_equal(current, source) => {
      self.preview_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn Viewer::definition_peek_available(self : Viewer) -> Bool {
  self.references_peek_available() &&
  self.definition_action_available() &&
  self.get_model() is Some(_)
}

///|
fn Viewer::references_action_available(self : Viewer) -> Bool {
  guard self.references_peek_available() else { return false }
  match self.get_model() {
    Some(model) => self.services.languages.has_references_provider(model)
    None => false
  }
}

///|
fn Viewer::references_peek_available(self : Viewer) -> Bool {
  !self.disposed &&
  self.role == OuterViewer &&
  self.get_model() is Some(_) &&
  (
    self.current_code_browser_data() is Some(_) ||
    self.current_markdown_document() is Some(_)
  )
}

///|
fn Viewer::definition_peek_contains_focus(self : Viewer) -> Bool {
  match self.references_contribution() {
    Some(state) =>
      match state.widget {
        Some(widget) =>
          @base_browser.element_contains_active_element(widget.get_dom_node())
        None => false
      }
    None => false
  }
}

///|
fn Viewer::start_peek_definition(self : Viewer) -> Unit {
  guard self.definition_peek_available() else { return }
  guard self.definition_contribution() is Some(definition) else { return }
  guard self.references_contribution() is Some(references) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.definition_command_position() is Some(position) else { return }
  let position = model.validate_position(position)
  let session_key = @references.ReferencesSessionKey::from_model(
    model,
    self.model_slot.generation,
    position,
  )
  if self.references_peek_session_is_open(session_key, Definitions) {
    self.close_references_peek(restore_focus=true)
    return
  }
  guard self.begin_definition_peek(position, session_key) is Some(generation) else {
    return
  }
  let source = @language.CancellationTokenSource()
  definition.peek_source = Some(source)
  references.phase = PeekLoadingDefinitions(generation)
  let stamp : DefinitionPeekRequestStamp = {
    generation,
    model_identity: model.identity(),
    model_generation: self.model_slot.generation,
    model_version_id: model.get_version_id(),
  }
  let offset = model.get_offset_at(position)
  let task = definition.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    if !self.definition_peek_request_is_current(stamp, source) {
      definition.retire_peek_source(source, cancel=true)
      return
    }
    source.dispose()
    definition.peek_source = None
    self.install_definition_peek_locations(
      generation,
      position,
      @definition.normalize_definition_locations(locations),
    )
  })
}

///|
/// Populates Peek from locations already resolved by the ordinary Definition
/// action. This preserves the one-provider-query contract for the default
/// multiple-definition Peek policy.
fn Viewer::open_definition_peek_with_locations(
  self : Viewer,
  position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.definition_peek_available() else { return }
  guard self.get_model() is Some(model) else { return }
  let position = model.validate_position(position)
  let session_key = @references.ReferencesSessionKey::from_model(
    model,
    self.model_slot.generation,
    position,
  )
  if self.references_peek_session_is_open(session_key, Definitions) {
    self.close_references_peek(restore_focus=true)
    return
  }
  guard self.begin_definition_peek(position, session_key) is Some(generation) else {
    return
  }
  self.install_definition_peek_locations(generation, position, locations)
}

///|
/// Starts the provider-backed References action and immediately installs the
/// shared loading shell. Shift+F12 and the context-menu command both enter
/// here; the public `show_references` seam remains provider-free.
fn Viewer::start_peek_references(self : Viewer) -> Unit {
  guard self.references_action_available() else { return }
  guard self.references_contribution() is Some(references) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.definition_command_position() is Some(position) else { return }
  let position = model.validate_position(position)
  let session_key = @references.ReferencesSessionKey::from_model(
    model,
    self.model_slot.generation,
    position,
  )
  if self.references_peek_session_is_open(session_key, References) {
    self.close_references_peek(restore_focus=true)
    return
  }
  let expected_closed_generation = references.generation + 1
  self.close_references_peek(restore_focus=false)
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return
  }
  self.prepare_definition_intent_for_peek()
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return
  }
  guard self.begin_references_peek_session(
      position,
      session_key,
      References,
      expected_closed_generation,
    )
    is Some(generation) else {
    return
  }
  let source = @language.CancellationTokenSource()
  references.query_source = Some(source)
  references.phase = PeekLoadingReferences(generation)
  let stamp : ReferencesQueryStamp = {
    generation,
    model_identity: model.identity(),
    model_generation: self.model_slot.generation,
    model_version_id: model.get_version_id(),
  }
  let offset = model.get_offset_at(position)
  let task = references.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.references_at(
      model,
      offset,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    if !self.references_query_is_current(stamp, source) {
      references.retire_query_source(source, cancel=true)
      return
    }
    source.dispose()
    references.query_source = None
    self.install_references_peek_locations(generation, position, locations)
  })
}

///|
/// Displays an already-computed reference set without invoking a language
/// provider. The caller's array is copied before the shared model normalizes
/// it, so the Peek never retains or mutates caller-owned collection state.
pub fn Viewer::show_references(
  self : Viewer,
  anchor : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.references_peek_available() else { return }
  guard self.get_model() is Some(model) else { return }
  let anchor = model.validate_position(anchor)
  let session_key = @references.ReferencesSessionKey::from_model(
    model,
    self.model_slot.generation,
    anchor,
  )
  if self.references_peek_session_is_open(session_key, References) {
    self.close_references_peek(restore_focus=true)
    return
  }
  guard self.references_contribution() is Some(references) else { return }
  let copied_locations = locations.copy()
  let expected_closed_generation = references.generation + 1
  self.close_references_peek(restore_focus=false)
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return
  }
  self.prepare_definition_intent_for_peek()
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return
  }
  guard self.begin_references_peek_session(
      anchor,
      session_key,
      References,
      expected_closed_generation,
    )
    is Some(generation) else {
    return
  }
  self.install_references_peek_locations(generation, anchor, copied_locations)
}

///|
fn Viewer::references_peek_session_is_open(
  self : Viewer,
  session_key : @references.ReferencesSessionKey,
  mode : @references.ReferencesPeekMode,
) -> Bool {
  match self.references_contribution() {
    Some(state) =>
      state.session_key == Some(session_key) &&
      state.mode == Some(mode) &&
      state.widget is Some(_)
    None => false
  }
}

///|
fn Viewer::references_peek_closed_generation_is_current(
  self : Viewer,
  generation : Int,
) -> Bool {
  guard !self.disposed else { return false }
  match self.references_contribution() {
    Some(state) =>
      state.generation == generation &&
      state.phase == PeekClosed &&
      state.query_source is None &&
      state.mode is None &&
      state.session_key is None &&
      state.model is None &&
      state.widget is None
    None => false
  }
}

///|
/// A direct locations Peek is a newer navigation intent than pending
/// Definition actions, modifier-link resolution, or opener feedback. Markdown
/// retains its pointer anchor just like Peek Definition; Code resets it.
fn Viewer::prepare_definition_intent_for_peek(self : Viewer) -> Unit {
  self.clear_definition_message()
  match self.definition_contribution() {
    Some(definition) => {
      definition.invalidate_open_feedback()
      definition.cancel_action()
      if self.current_markdown_document() is Some(_) {
        definition.cancel_link_gesture()
      } else {
        definition.reset_link_gesture()
      }
    }
    None => ()
  }
}

///|
fn Viewer::begin_definition_peek(
  self : Viewer,
  position : @base_common.Position,
  session_key : @references.ReferencesSessionKey,
) -> Int? {
  guard self.definition_contribution() is Some(_) else { return None }
  guard self.references_contribution() is Some(references) else { return None }
  let expected_closed_generation = references.generation + 1
  self.close_references_peek(restore_focus=false)
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return None
  }
  self.prepare_definition_intent_for_peek()
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return None
  }
  let attempt_generation = expected_closed_generation + 1
  match
    self.begin_references_peek_session(
      position,
      session_key,
      Definitions,
      expected_closed_generation,
    ) {
    Some(generation) => Some(generation)
    None => {
      // A ViewZone listener can replace the failed attempt synchronously.
      // Definition feedback belongs only to the still-closed attempt, never to
      // a newer Peek installed before shell construction returned.
      if self.references_peek_closed_generation_is_current(attempt_generation) {
        self.show_definition_message("No preview available", position~)
      }
      None
    }
  }
}

///|
/// Starts the shared shell after the caller has retired any previous session
/// and completed mode-specific preparation.
fn Viewer::begin_references_peek_session(
  self : Viewer,
  position : @base_common.Position,
  session_key : @references.ReferencesSessionKey,
  mode : @references.ReferencesPeekMode,
  expected_closed_generation : Int,
) -> Int? {
  guard self.references_peek_closed_generation_is_current(
    expected_closed_generation,
  ) else {
    return None
  }
  guard self.references_contribution() is Some(references) else { return None }
  references.generation += 1
  let generation = references.generation
  references.mode = Some(mode)
  references.session_key = Some(session_key)
  guard self.open_references_peek_shell(position, generation, mode) else {
    // Shell construction crosses synchronous browser-event boundaries. A
    // listener may already have installed a newer session; only retire this
    // failed attempt while its generation is still the published owner.
    if references.generation == generation {
      references.mode = None
      references.session_key = None
    }
    return None
  }
  Some(generation)
}

///|
fn Viewer::install_definition_peek_locations(
  self : Viewer,
  generation : Int,
  source_position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  self.install_references_peek_locations(generation, source_position, locations)
}

///|
fn Viewer::install_references_peek_locations(
  self : Viewer,
  generation : Int,
  source_position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.references_peek_session_is_current(generation) else { return }
  guard self.references_contribution() is Some(state) else { return }
  guard self.get_model() is Some(source_model) else { return }
  let result_model = @references.ReferencesModel(locations)
  state.model = Some(result_model)
  // `set_results` synchronously reports the initially expanded group. Install
  // every owner first so that callback always sees a complete session.
  let group_preview_owners : Array[ReferencesGroupPreviewOwner] = []
  for group in result_model.groups {
    group_preview_owners.push(ReferencesGroupPreviewOwner(group.group_index))
  }
  state.group_preview_owners = group_preview_owners
  if result_model.is_empty() {
    if state.mode == Some(Definitions) {
      // Definition retains its command-specific no-result feedback. The
      // precomputed References entry instead keeps this shell open.
      self.close_references_peek(restore_focus=true)
      self.show_definition_message(
        self.definition_no_result_message(source_position),
        position=source_position,
      )
    } else {
      match state.widget {
        Some(widget) => widget.show_empty()
        None => ()
      }
      state.phase = PeekShown(generation, state.preview_generation)
    }
    return
  }
  guard result_model.nearest_reference(source_model.uri, source_position)
    is Some(selected) else {
    return
  }
  let selected_index = selected.flat_index
  state.selected_index = selected_index
  match state.widget {
    Some(widget) => {
      widget.set_results(result_model, Some(selected))
      widget.show_preview_loading()
    }
    None => return
  }
  self.load_references_peek_preview(generation, selected_index)
}

///|
fn Viewer::open_references_peek_shell(
  self : Viewer,
  position : @base_common.Position,
  generation : Int,
  mode : @references.ReferencesPeekMode,
) -> Bool {
  guard self.references_contribution() is Some(state) else { return false }
  let widget = @references_browser.ReferencesPeekWidget(mode, {
    on_close: () => {
      if self.references_peek_session_is_current(generation) {
        self.close_references_peek(restore_focus=true)
      }
    },
    on_select: item => {
      if self.references_peek_session_is_current(generation) {
        self.select_references_peek_item(item)
      }
    },
    on_confirm: item => {
      if self.references_peek_session_is_current(generation) &&
        self.references_peek_item_is_current(item) {
        self.confirm_references_peek_result(item.flat_index)
      }
    },
    on_open_side: item => {
      if self.references_peek_session_is_current(generation) {
        self.confirm_references_peek_item(item, Side)
      }
    },
    on_next: () => {
      if self.references_peek_session_is_current(generation) {
        self.move_references_peek_result(1)
      }
    },
    on_previous: () => {
      if self.references_peek_session_is_current(generation) {
        self.move_references_peek_result(-1)
      }
    },
    on_expand_group: group => {
      if self.references_peek_session_is_current(generation) {
        self.load_references_peek_group(group)
      }
    },
  })
  // Publish the callback owner before the first synchronous browser mutation.
  // `change_view_zones` emits publicly before returning, so a listener may
  // close this provisional shell and install another one. The mount facts stay
  // local until each reentrant boundary has confirmed this exact owner.
  state.widget = Some(widget)
  let mounted_view : Ref[@view.View?] = Ref(None)
  let mounted_zone_id : Ref[String?] = Ref(None)
  let mounted_overlay : Ref[@editor_browser.OverlayWidget?] = Ref(None)
  let markdown_mounted = Ref(false)
  // Every abandon path below unmounts the same shell, and each reads the mount
  // facts as they stand at that point. Binding the call once keeps the reads
  // late while leaving one place to extend the resource set.
  let retire = () => {
    self.retire_provisional_references_peek_shell(
      state,
      generation,
      widget,
      mounted_view.val,
      mounted_zone_id.val,
      mounted_overlay.val,
      markdown_mounted.val,
    )
  }
  match self.current_code_browser_data() {
    Some(browser) => {
      let zone_dom_node = @rdom.document().create_element("div")
      zone_dom_node.set_attribute(
        "class", "moonbit-viewer-references-peek-zone",
      )
      let widget_dom_node = widget.get_dom_node()
      let layout = self.get_layout_info()
      @base_browser.set_style_property(widget_dom_node, "position", "absolute")
      @base_browser.set_style_property(widget_dom_node, "top", "-1000000px")
      @base_browser.set_style_property(widget_dom_node, "left", "0")
      @base_browser.set_style_property(
        widget_dom_node,
        "right",
        "\{layout.vertical_scrollbar_width.to_string()}px",
      )
      @base_browser.set_style_property(widget_dom_node, "width", "auto")
      let zone = @editor_browser.ViewZone(
        position.line_number,
        zone_dom_node,
        after_column=position.column,
        suppress_mouse_down=true,
        height_in_lines=self.references_peek_height_in_lines(),
        on_dom_node_top=top => {
          @base_browser.set_style_property(
            widget_dom_node,
            "top",
            "\{top.to_string()}px",
          )
        },
        on_computed_height=height => {
          @base_browser.set_style_property(
            widget_dom_node,
            "height",
            "\{height.to_string()}px",
          )
        },
      )
      let added_id = Ref("")
      self.change_view_zones(accessor => added_id.val = accessor.add_zone(zone))
      if added_id.val == "" {
        retire()
        return false
      }
      mounted_view.val = Some(browser.view)
      mounted_zone_id.val = Some(added_id.val)
      if !self.references_peek_shell_owner_is_current(generation, widget) {
        retire()
        return false
      }
      state.zone_id = Some(added_id.val)
      let overlay = overlay_widget(
        "moonbit.viewer.referencesPeek.\{self.get_id()}",
        widget_dom_node,
      )
      self.add_overlay_widget(overlay)
      mounted_overlay.val = Some(overlay)
      if !self.references_peek_shell_owner_is_current(generation, widget) {
        retire()
        return false
      }
      state.overlay_widget = Some(overlay)
      self.reveal_references_peek_zone(position)
      if !self.references_peek_session_is_current(generation) {
        retire()
        return false
      }
    }
    None =>
      match self.current_markdown_document() {
        Some(markdown) => {
          widget
          .get_dom_node()
          .set_attribute(
            "class", "moonbit-viewer-references-peek moonbit-viewer-references-peek-overlay",
          )
          markdown.overlay_mount().append_child(widget.get_dom_node().as_node())
          markdown_mounted.val = true
          if !self.references_peek_shell_owner_is_current(generation, widget) {
            retire()
            return false
          }
          state.markdown_projection_generation = Some(
            markdown.projection_generation(),
          )
        }
        None => {
          retire()
          return false
        }
      }
  }
  guard self.references_peek_session_is_current(generation) else {
    retire()
    return false
  }
  state.focus_frame = Some(
    @base_browser.schedule_at_next_animation_frame(
      () => {
        if state.generation == generation {
          state.focus_frame = None
        }
        if self.references_peek_session_is_current(generation) &&
          state.widget is Some(current_widget) &&
          physical_equal(current_widget, widget) {
          widget.focus()
        }
      },
      // Viewer render runs at 100; focus runs later in the same native frame,
      // after a Code ViewZone has changed from display:none to display:block.
      priority=0,
    ),
  )
  true
}

///|
/// Detaches only this provisional shell, then unmounts its exact local
/// resources. Cleanup can itself emit ViewZone events, so all matching state
/// is cleared before the first callback and stale transactions never touch a
/// newer generation's same-id overlay.
fn Viewer::retire_provisional_references_peek_shell(
  self : Viewer,
  state : ReferencesContributionState,
  generation : Int,
  widget : @references_browser.ReferencesPeekWidget,
  mounted_view : @view.View?,
  mounted_zone_id : String?,
  mounted_overlay : @editor_browser.OverlayWidget?,
  markdown_mounted : Bool,
) -> Unit {
  if state.generation == generation &&
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) {
    state.widget = None
    state.zone_id = None
    state.overlay_widget = None
    state.markdown_projection_generation = None
  }
  match mounted_overlay {
    Some(overlay) => self.remove_overlay_widget_if_current(overlay) |> ignore
    None => ()
  }
  if markdown_mounted {
    @base_browser.remove_element(widget.get_dom_node())
  }
  widget.dispose()
  match (mounted_view, mounted_zone_id) {
    (Some(view), Some(zone_id)) =>
      view.change_view_zones(accessor => accessor.remove_zone(zone_id))
    _ => ()
  }
}

///|
/// Mirrors `ZoneWidget.show`: reveal the anchor through the following model
/// line after installing the whitespace. The range crosses the Peek ViewZone,
/// so the scroll computation brings the whole widget into the viewport instead
/// of leaving a newly opened shell clipped below the editor.
fn Viewer::reveal_references_peek_zone(
  self : Viewer,
  position : @base_common.Position,
) -> Unit {
  guard self.get_model() is Some(model) else { return }
  let line_number = position.line_number
  let end_line_number = (line_number + 1).min(model.get_line_count())
  if end_line_number == line_number {
    self.reveal_line_near_top(line_number)
  } else {
    self.reveal_lines(line_number, end_line_number)
  }
}

///|
fn Viewer::references_peek_height_in_lines(self : Viewer) -> Double {
  let snapshot = self.configuration.snapshot()
  let requested = @references_browser.references_peek_height_in_lines.to_double()
  let line_height = snapshot.font_info.line_height.to_double()
  if snapshot.height <= 0.0 || line_height <= 0.0 {
    return requested
  }
  requested.min((snapshot.height / line_height * 0.8).max(12.0))
}

///|
fn Viewer::definition_peek_request_is_current(
  self : Viewer,
  stamp : DefinitionPeekRequestStamp,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard !self.disposed && !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.definition_contribution() is Some(definition) else { return false }
  guard self.references_contribution() is Some(references) else { return false }
  guard references.generation == stamp.generation else { return false }
  guard definition.peek_source is Some(current_source) else { return false }
  guard physical_equal(current_source, source) else { return false }
  guard self.get_model() is Some(model) else { return false }
  model.identity() == stamp.model_identity &&
  self.model_slot.generation == stamp.model_generation &&
  model.get_version_id() == stamp.model_version_id
}

///|
fn Viewer::references_query_is_current(
  self : Viewer,
  stamp : ReferencesQueryStamp,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard !self.disposed && !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.references_contribution() is Some(references) else { return false }
  guard references.generation == stamp.generation &&
    references.phase == PeekLoadingReferences(stamp.generation) &&
    references.query_source is Some(current_source) &&
    physical_equal(current_source, source) else {
    return false
  }
  guard self.get_model() is Some(model) else { return false }
  model.identity() == stamp.model_identity &&
  self.model_slot.generation == stamp.model_generation &&
  model.get_version_id() == stamp.model_version_id
}

///|
fn Viewer::references_peek_session_is_current(
  self : Viewer,
  generation : Int,
) -> Bool {
  guard self.references_contribution() is Some(state) &&
    state.widget is Some(widget) &&
    self.references_peek_shell_owner_is_current(generation, widget) else {
    return false
  }
  match
    (state.zone_id, state.overlay_widget, state.markdown_projection_generation) {
    (Some(_), Some(_), None) => self.current_code_browser_data() is Some(_)
    (None, None, Some(projection_generation)) =>
      match self.current_markdown_document() {
        Some(markdown) =>
          markdown.projection_generation() == projection_generation
        None => false
      }
    _ => false
  }
}

///|
/// Validates the provisional shell owner without requiring its ViewZone or
/// Markdown mount to have been published yet. Shell construction uses this
/// after every synchronous browser callback boundary.
fn Viewer::references_peek_shell_owner_is_current(
  self : Viewer,
  generation : Int,
  widget : @references_browser.ReferencesPeekWidget,
) -> Bool {
  guard !self.disposed else { return false }
  guard self.references_contribution() is Some(state) else { return false }
  guard state.generation == generation &&
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return false
  }
  guard state.session_key is Some(session_key) &&
    self.get_model() is Some(source_model) &&
    session_key.is_current(source_model, self.model_slot.generation) else {
    return false
  }
  state.mode is Some(_)
}

///|
fn ReferencesContributionState::detach_group_previews(
  self : ReferencesContributionState,
) -> DetachedReferencesGroupPreviews {
  let owners = self.group_preview_owners
  self.group_preview_owners = []
  let sources : Array[@language.CancellationTokenSource] = []
  let references : Array[@navigation_api.TextModelReference] = []
  // First clear every detached owner slot. Only after this loop returns may a
  // caller invoke cancellation or release callbacks.
  for owner in owners {
    owner.generation += 1
    match owner.source {
      Some(source) => sources.push(source)
      None => ()
    }
    match owner.reference {
      Some(reference) => references.push(reference)
      None => ()
    }
    owner.source = None
    owner.reference = None
  }
  { sources, references }
}

///|
fn ReferencesGroupPreviewOwner::retire_source(
  self : ReferencesGroupPreviewOwner,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.source {
    Some(current) if physical_equal(current, source) => {
      self.source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn reference_group_row_previews(
  group : @references.ReferenceGroup,
  model : @model.TextModel,
) -> Array[@references.ReferenceRowPreview] {
  let previews : Array[@references.ReferenceRowPreview] = []
  for item in group.references {
    previews.push(item.row_preview(Some(model)))
  }
  previews
}

///|
fn Viewer::references_peek_group_is_current(
  self : Viewer,
  generation : Int,
  group : @references.ReferenceGroup,
) -> Bool {
  guard self.references_peek_session_is_current(generation) else {
    return false
  }
  guard self.references_contribution() is Some(state) &&
    state.model is Some(model) else {
    return false
  }
  group.group_index >= 0 &&
  group.group_index < model.groups.length() &&
  model.groups[group.group_index] == group
}

///|
fn Viewer::references_peek_group_slot_is_current(
  self : Viewer,
  generation : Int,
  group : @references.ReferenceGroup,
  owner_generation : Int,
) -> Bool {
  guard self.references_peek_group_is_current(generation, group) else {
    return false
  }
  guard self.references_contribution() is Some(state) else { return false }
  guard group.group_index >= 0 &&
    group.group_index < state.group_preview_owners.length() else {
    return false
  }
  let owner = state.group_preview_owners[group.group_index]
  owner.group_index == group.group_index && owner.generation == owner_generation
}

///|
fn Viewer::references_peek_group_request_is_current(
  self : Viewer,
  generation : Int,
  group : @references.ReferenceGroup,
  owner_generation : Int,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard self.references_peek_group_slot_is_current(
      generation, group, owner_generation,
    ) &&
    !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.references_contribution() is Some(state) else { return false }
  let owner = state.group_preview_owners[group.group_index]
  match owner.source {
    Some(current_source) => physical_equal(current_source, source)
    None => false
  }
}

///|
/// Lazily resolves one expanded resource group. The initially selected group
/// reaches this path synchronously from `ReferencesPeekWidget::set_results`,
/// after `install_references_peek_locations` has installed all owner slots.
fn Viewer::load_references_peek_group(
  self : Viewer,
  group : @references.ReferenceGroup,
) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  let generation = state.generation
  guard self.references_peek_group_is_current(generation, group) else { return }
  guard group.group_index >= 0 &&
    group.group_index < state.group_preview_owners.length() else {
    return
  }
  let owner = state.group_preview_owners[group.group_index]
  guard owner.group_index == group.group_index &&
    owner.source is None &&
    owner.reference is None else {
    return
  }
  match self.get_model() {
    Some(model) if model.uri.to_string() == group.uri_string => {
      guard state.widget is Some(widget) else { return }
      widget.set_group_previews(
        group.group_index,
        reference_group_row_previews(group, model),
      )
      return
    }
    _ => ()
  }
  guard self.services.text_model_resolver is Some(resolver) else { return }
  owner.generation += 1
  let owner_generation = owner.generation
  let source = @language.CancellationTokenSource()
  owner.source = Some(source)
  let task = state.launch_async_task
  task(async fn() noraise {
    let reference = resolver.resolve(group.uri, source.token())
    if !self.references_peek_group_request_is_current(
        generation, group, owner_generation, source,
      ) {
      owner.retire_source(source, cancel=true)
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    // Detach before disposing because token listeners may synchronously close
    // or replace the session.
    owner.source = None
    source.dispose()
    if !self.references_peek_group_slot_is_current(
        generation, group, owner_generation,
      ) {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    match reference {
      None => ()
      Some(reference) => {
        let model = reference.model()
        if model.is_disposed() || model.uri.to_string() != group.uri_string {
          reference.dispose()
          return
        }
        guard self.references_peek_group_slot_is_current(
          generation, group, owner_generation,
        ) else {
          reference.dispose()
          return
        }
        owner.reference = Some(reference)
        guard self.references_contribution() is Some(current_state) &&
          current_state.widget is Some(widget) else {
          // A synchronous teardown cannot occur between the preceding guard
          // and this lookup today, but retain exact ownership if that changes.
          owner.reference = None
          reference.dispose()
          return
        }
        widget.set_group_previews(
          group.group_index,
          reference_group_row_previews(group, model),
        )
      }
    }
  })
}

///|
fn Viewer::cancel_references_peek_preview_request(self : Viewer) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  let source = state.preview_source
  state.preview_source = None
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
/// Removes every installed preview owner slot without running callbacks.
fn Viewer::detach_installed_references_peek_preview(
  self : Viewer,
) -> DetachedReferencesPeekPreview? {
  guard self.references_contribution() is Some(state) else { return None }
  let restore_focus = match state.preview_viewer {
    Some(viewer) => viewer.has_text_focus()
    None => false
  }
  let detached : DetachedReferencesPeekPreview = {
    viewer: state.preview_viewer,
    reference: state.preview_reference,
    decorations: state.preview_decorations,
    layout_frame: state.preview_layout_frame,
    resize_observer: state.preview_resize_observer,
    restore_focus,
  }
  state.preview_resize_observer = None
  state.preview_layout_frame = None
  state.preview_viewer = None
  state.preview_reference = None
  state.preview_decorations = None
  Some(detached)
}

///|
/// Releases only the installed child and lease. A replacement request keeps
/// these alive until its own result is current and ready to commit.
fn Viewer::clear_installed_references_peek_preview(self : Viewer) -> Bool {
  guard self.detach_installed_references_peek_preview() is Some(detached) else {
    return false
  }
  let restore_focus = detached.restore_focus
  detached.dispose()
  restore_focus
}

///|
fn Viewer::load_references_peek_preview(
  self : Viewer,
  generation : Int,
  index : Int,
) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  guard self.references_peek_session_is_current(generation) else { return }
  guard state.model is Some(result_model) else { return }
  guard index >= 0 && index < result_model.references.length() else { return }
  guard state.widget is Some(widget) else { return }
  let item = result_model.references[index]
  self.cancel_references_peek_preview_request()
  // Cancellation listeners are synchronous and may replace the complete Peek.
  // Revalidate the exact generation, model item, and widget before the stale
  // caller mutates selection/phase or installs a new request source.
  guard self.references_peek_preview_selection_is_current(
    generation, result_model, index, item, widget,
  ) else {
    return
  }
  state.selected_index = index
  widget.set_selected(item)
  // Expanding a previously collapsed group synchronously enters the root
  // callback, and focus movement can enter host listeners. Either path may
  // replace the whole session before `set_selected` returns.
  guard self.references_peek_preview_selection_is_current(
    generation, result_model, index, item, widget,
  ) else {
    return
  }
  widget.show_preview_loading()
  let location = item.location()
  state.preview_generation += 1
  let preview_generation = state.preview_generation
  state.phase = PeekLoadingPreview(generation, preview_generation)
  match self.get_model() {
    Some(model) if model.uri.to_string() == location.uri.to_string() => {
      self.schedule_references_peek_preview(
        generation, preview_generation, location, model,
      )
      return
    }
    _ => ()
  }
  guard self.services.text_model_resolver is Some(resolver) else {
    self.show_references_peek_preview_unavailable(
      generation, preview_generation, "No preview available",
    )
    return
  }
  let source = @language.CancellationTokenSource()
  state.preview_source = Some(source)
  let task = state.launch_async_task
  task(async fn() noraise {
    let reference = resolver.resolve(location.uri, source.token())
    if !self.references_peek_preview_request_is_current(
        generation, preview_generation, source,
      ) {
      state.retire_preview_source(source, cancel=true)
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    state.preview_source = None
    source.dispose()
    if !self.references_peek_session_is_current(generation) ||
      state.preview_generation != preview_generation {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    match reference {
      None =>
        self.show_references_peek_preview_unavailable(
          generation, preview_generation, "No preview available",
        )
      Some(reference) => {
        let model = reference.model()
        if model.is_disposed() ||
          model.uri.to_string() != location.uri.to_string() {
          reference.dispose()
          self.show_references_peek_preview_unavailable(
            generation, preview_generation, "No preview available",
          )
          return
        }
        self.schedule_references_peek_preview(
          generation,
          preview_generation,
          location,
          model,
          reference~,
        )
      }
    }
  })
}

///|
/// Exact selected-preview owner check shared by both synchronous boundaries in
/// `load_references_peek_preview`.
fn Viewer::references_peek_preview_selection_is_current(
  self : Viewer,
  generation : Int,
  result_model : @references.ReferencesModel,
  index : Int,
  item : @references.ReferenceItem,
  widget : @references_browser.ReferencesPeekWidget,
) -> Bool {
  guard self.references_peek_session_is_current(generation) else {
    return false
  }
  guard self.references_contribution() is Some(state) &&
    state.model is Some(current_model) &&
    physical_equal(current_model, result_model) &&
    index >= 0 &&
    index < current_model.references.length() &&
    current_model.references[index] == item &&
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return false
  }
  true
}

///|
fn Viewer::references_peek_preview_request_is_current(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard self.references_peek_session_is_current(generation) else {
    return false
  }
  guard !source.token().is_cancellation_requested() else { return false }
  guard self.references_contribution() is Some(state) else { return false }
  guard state.preview_generation == preview_generation else { return false }
  match state.preview_source {
    Some(current_source) => physical_equal(current_source, source)
    None => false
  }
}

///|
/// Defers the final child swap through the same Viewer-owned task host as
/// provider and resolver work. That keeps stale reference disposal ordered
/// with cancellation and prevents an unowned browser microtask from outliving
/// the Viewer's DOM realm.
#warnings("-unused_async")
fn Viewer::schedule_references_peek_preview(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  location : @language.Location,
  model : @model.TextModel,
  reference? : @navigation_api.TextModelReference,
) -> Unit {
  guard self.references_contribution() is Some(state) else {
    match reference {
      Some(reference) => reference.dispose()
      None => ()
    }
    return
  }
  let task = state.launch_async_task
  task(async fn() noraise {
    if !self.references_peek_preview_is_current(
        generation,
        preview_generation,
        location.uri.to_string(),
        model,
      ) {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    guard state.widget is Some(widget) else {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    let restore_preview_focus = self.clear_installed_references_peek_preview()
    guard state.model is Some(result_model) &&
      self.references_peek_preview_commit_is_current(
        generation,
        preview_generation,
        location.uri.to_string(),
        model,
        result_model,
        widget,
      ) else {
      match reference {
        Some(reference) => reference.dispose()
        None => ()
      }
      return
    }
    // Each step below can hand control to a listener that supersedes this
    // preview, so every step is followed by the same currency re-check against
    // the owners captured here. Binding it once keeps the interleaved
    // browser work readable.
    let still_current = () => {
      self.references_peek_preview_commit_is_current(
        generation,
        preview_generation,
        location.uri.to_string(),
        model,
        result_model,
        widget,
      )
    }
    let preview_host = widget.get_preview_host()
    let preview = Viewer(
      services=self.services,
      options=self.get_options(),
      initial_container=preview_host,
      role=PeekPreviewViewer,
    )
    let provisional : ProvisionalReferencesPeekPreview = {
      viewer: preview,
      reference,
      decorations: None,
      layout_frame: None,
      resize_observer: None,
    }
    preview.attach(preview_host)
    guard still_current() else {
      provisional.dispose()
      return
    }
    preview.set_model(Some(model))
    guard still_current() else {
      provisional.dispose()
      return
    }
    let range = model.validate_range(location.range)
    let decorations : Array[@model.ModelDeltaDecoration] = []
    let preview_uri = model.uri.to_string()
    for item in result_model.references {
      if item.uri_string == preview_uri {
        decorations.push({
          range: model.validate_range(item.range),
          options: ModelDecorationOptions(
            "moonbit-viewer-references-peek-reference-match",
            description="peek-reference-match",
          ),
        })
      }
    }
    // The selected match is intentionally an additional final decoration,
    // including when its range already received the all-reference class.
    decorations.push({
      range,
      options: ModelDecorationOptions(
        "moonbit-viewer-references-peek-reference-match-selected",
        description="peek-reference-match-selected",
      ),
    })
    provisional.decorations = Some(
      preview.create_decorations_collection(decorations~),
    )
    guard still_current() else {
      provisional.dispose()
      return
    }
    let start = range.get_start_position()
    preview.set_position(
      start,
      source=if state.mode == Some(Definitions) {
        "peekDefinition"
      } else {
        "peekReferences"
      },
    )
    guard still_current() else {
      provisional.dispose()
      return
    }
    preview.reveal_range_in_center_if_outside_viewport(
      Range(start.line_number, start.column, start.line_number, start.column),
    )
    guard still_current() else {
      provisional.dispose()
      return
    }
    preview.handle_initialized()
    guard still_current() else {
      provisional.dispose()
      return
    }
    provisional.resize_observer = @base_browser.observe_element_resize(
      preview_host,
      () => {
        if still_current() &&
          state.preview_viewer is Some(current_preview) &&
          physical_equal(current_preview, preview) {
          preview.layout()
        }
      },
    )
    guard still_current() else {
      provisional.dispose()
      return
    }
    provisional.layout_frame = Some(
      @base_browser.schedule_at_next_animation_frame(() => {
        if still_current() &&
          state.preview_viewer is Some(current_preview) &&
          physical_equal(current_preview, preview) {
          preview.layout()
        }
      }),
    )
    guard still_current() else {
      provisional.dispose()
      return
    }
    widget.show_preview_ready()
    guard still_current() else {
      provisional.dispose()
      return
    }
    if restore_preview_focus {
      preview.focus()
    }
    guard still_current() else {
      provisional.dispose()
      return
    }
    // No callback boundary remains between these assignments. Publish the
    // complete owner set atomically from the root controller's perspective.
    provisional.publish(state)
    state.phase = PeekShown(generation, preview_generation)
  })
}

///|
fn Viewer::references_peek_preview_commit_is_current(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  expected_uri : String,
  model : @model.TextModel,
  result_model : @references.ReferencesModel,
  widget : @references_browser.ReferencesPeekWidget,
) -> Bool {
  guard self.references_peek_preview_is_current(
    generation, preview_generation, expected_uri, model,
  ) else {
    return false
  }
  guard self.references_contribution() is Some(state) &&
    state.model is Some(current_model) &&
    physical_equal(current_model, result_model) &&
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return false
  }
  true
}

///|
fn Viewer::references_peek_preview_is_current(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  expected_uri : String,
  model : @model.TextModel,
) -> Bool {
  guard self.references_peek_session_is_current(generation) else {
    return false
  }
  guard !model.is_disposed() && model.uri.to_string() == expected_uri else {
    return false
  }
  guard self.references_contribution() is Some(state) else { return false }
  state.preview_generation == preview_generation
}

///|
fn Viewer::show_references_peek_preview_unavailable(
  self : Viewer,
  generation : Int,
  preview_generation : Int,
  message : String,
) -> Unit {
  guard self.references_peek_session_is_current(generation) else { return }
  guard self.references_contribution() is Some(state) else { return }
  guard state.preview_generation == preview_generation else { return }
  guard state.widget is Some(widget) else { return }
  let had_preview_focus = self.clear_installed_references_peek_preview()
  guard self.references_peek_session_is_current(generation) &&
    state.preview_generation == preview_generation &&
    state.widget is Some(current_widget) &&
    physical_equal(current_widget, widget) else {
    return
  }
  state.phase = PeekUnavailable(generation, preview_generation)
  widget.show_preview_unavailable(message)
  if had_preview_focus {
    widget.focus()
  }
}

///|
fn Viewer::references_peek_item_is_current(
  self : Viewer,
  item : @references.ReferenceItem,
) -> Bool {
  match self.references_contribution() {
    Some(state) =>
      match state.model {
        Some(model) =>
          item.flat_index >= 0 &&
          item.flat_index < model.references.length() &&
          model.references[item.flat_index] == item
        None => false
      }
    None => false
  }
}

///|
fn Viewer::select_references_peek_item(
  self : Viewer,
  item : @references.ReferenceItem,
) -> Unit {
  if self.references_peek_item_is_current(item) {
    self.select_references_peek_result(item.flat_index)
  }
}

///|
fn Viewer::select_references_peek_result(self : Viewer, index : Int) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  guard state.model is Some(result_model) else { return }
  let generation = state.generation
  guard index >= 0 && index < result_model.references.length() else { return }
  if index == state.selected_index &&
    (state.preview_viewer is Some(_) || state.preview_source is Some(_)) {
    return
  }
  self.load_references_peek_preview(generation, index)
}

///|
fn Viewer::move_references_peek_result(self : Viewer, delta : Int) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  guard state.model is Some(result_model) else { return }
  guard result_model.references.length() > 0 else { return }
  let current = if state.selected_index >= 0 &&
    state.selected_index < result_model.references.length() {
    result_model.references[state.selected_index]
  } else {
    result_model.references[0]
  }
  let next = if delta < 0 {
    result_model.previous_reference(current)
  } else {
    result_model.next_reference(current)
  }
  match next {
    Some(item) => self.select_references_peek_item(item)
    None => ()
  }
}

///|
fn Viewer::confirm_references_peek_result(self : Viewer, index : Int) -> Unit {
  guard self.references_contribution() is Some(references) else { return }
  guard references.model is Some(result_model) else { return }
  guard index >= 0 && index < result_model.references.length() else { return }
  self.confirm_references_peek_item(result_model.references[index], Current)
}

///|
/// Shared current-model/opener path for Definition and References results.
/// Mode-specific feedback remains with the Definition wrapper.
async fn Viewer::open_peek_location(
  self : Viewer,
  location : @language.Location,
  mode : @navigation_api.OpenLocationMode,
  source : String,
) -> Bool noraise {
  guard !self.disposed else { return false }
  guard self.get_model() is Some(source_model) else { return false }
  if mode == Current && source_model.uri.to_string() == location.uri.to_string() {
    let range = source_model.validate_range(location.range)
    let start = range.get_start_position()
    self.set_position(start, source~)
    self.reveal_range_in_center_if_outside_viewport(
      Range(start.line_number, start.column, start.line_number, start.column),
    )
    self.focus()
    self.show_navigation_target_highlight(source_model, range)
    return true
  }
  match self.services.location_opener {
    Some(opener) =>
      opener.open({ source_viewer_id: self.get_id(), location, mode })
    None => false
  }
}

///|
fn Viewer::confirm_references_peek_item(
  self : Viewer,
  item : @references.ReferenceItem,
  mode : @navigation_api.OpenLocationMode,
) -> Unit {
  guard self.references_peek_item_is_current(item) else { return }
  guard self.references_contribution() is Some(references) &&
    references.mode is Some(peek_mode) else {
    return
  }
  guard self.get_model() is Some(model) else { return }
  let location = item.location()
  let model_identity = model.identity()
  let model_generation = self.model_slot.generation
  let model_version_id = model.get_version_id()
  let task = references.launch_async_task
  let definition_open_generation = match peek_mode {
    Definitions =>
      match self.definition_contribution() {
        Some(definition) => {
          definition.invalidate_open_feedback()
          definition.open_generation
        }
        None => return
      }
    References => -1
  }
  let closed_generation = references.generation + 1
  self.close_references_peek(restore_focus=true)
  task(async fn() noraise {
    guard !self.disposed &&
      references.generation == closed_generation &&
      self.get_model() is Some(current_model) &&
      current_model.identity() == model_identity &&
      self.model_slot.generation == model_generation &&
      current_model.get_version_id() == model_version_id else {
      return
    }
    match peek_mode {
      Definitions => {
        guard self.definition_contribution() is Some(definition) &&
          definition.open_generation == definition_open_generation else {
          return
        }
        self.open_definition_location(location, mode) |> ignore
      }
      References =>
        self.open_peek_location(location, mode, "showReferences") |> ignore
    }
  })
}

///|
/// Compatibility seams retained for the Definition regression suite while
/// production callbacks use the shared References names.
fn Viewer::cancel_definition_peek_preview_request(self : Viewer) -> Unit {
  self.cancel_references_peek_preview_request()
}

///|
fn Viewer::move_definition_peek_result(self : Viewer, delta : Int) -> Unit {
  self.move_references_peek_result(delta)
}

///|
fn Viewer::confirm_definition_peek_result(self : Viewer, index : Int) -> Unit {
  self.confirm_references_peek_result(index)
}

///|
fn Viewer::close_references_peek(self : Viewer, restore_focus~ : Bool) -> Unit {
  guard self.references_contribution() is Some(state) else { return }
  state.generation += 1
  let closing_generation = state.generation
  state.preview_generation += 1
  state.phase = PeekClosed

  // Detach the complete old session before the first cancellation/disposal
  // callback. Any callback may synchronously open a new Peek; teardown below
  // must then touch only these captured old resources.
  let definition_source = match self.definition_contribution() {
    Some(definition) => {
      let source = definition.peek_source
      definition.peek_source = None
      source
    }
    None => None
  }
  let query_source = state.query_source
  state.query_source = None
  let preview_source = state.preview_source
  state.preview_source = None
  let focus_frame = state.focus_frame
  state.focus_frame = None
  let widget = state.widget
  state.widget = None
  let zone_id = state.zone_id
  state.zone_id = None
  // ViewZone ids are model-scoped and may collide after a reentrant model
  // replacement. Retain the exact owning View before any cancellation or
  // lease-release callback can swap the root presentation.
  let zone_view = match zone_id {
    Some(_) =>
      match self.current_code_browser_data() {
        Some(browser) => Some(browser.view)
        None => None
      }
    None => None
  }
  let overlay_widget = state.overlay_widget
  state.overlay_widget = None
  let markdown_projection_generation = state.markdown_projection_generation
  state.markdown_projection_generation = None
  let detached_preview = self.detach_installed_references_peek_preview()
  let detached_groups = state.detach_group_previews()
  state.model = None
  state.selected_index = -1
  state.mode = None
  state.session_key = None

  match definition_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  match query_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  match preview_source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
  detached_groups.cancel_sources()
  match focus_frame {
    Some(frame) => frame.dispose()
    None => ()
  }
  // The nested Viewer and selected lease are children of the shell. Then
  // release group leases and the explicit decoration owner in the locked D6
  // order, while the shell listeners and host node are still alive.
  match detached_preview {
    Some(detached) => detached.dispose_viewer()
    None => ()
  }
  match detached_preview {
    Some(detached) => detached.dispose_reference()
    None => ()
  }
  detached_groups.dispose_references()
  match detached_preview {
    Some(detached) => detached.dispose_decorations()
    None => ()
  }
  match overlay_widget {
    Some(overlay_widget) =>
      self.remove_overlay_widget_if_current(overlay_widget) |> ignore
    None => ()
  }
  match markdown_projection_generation {
    Some(_) =>
      match widget {
        Some(widget) => @base_browser.remove_element(widget.get_dom_node())
        None => ()
      }
    None => ()
  }
  match widget {
    Some(widget) => widget.dispose()
    None => ()
  }
  match (zone_view, zone_id) {
    (Some(view), Some(zone_id)) => {
      view.change_view_zones(accessor => accessor.remove_zone(zone_id))
      if !self.disposed {
        // The root wrapper normally owns this render schedule. Teardown uses
        // the captured model-scoped View directly for identity safety.
        self.schedule_render()
      }
    }
    _ => ()
  }
  if restore_focus &&
    !self.disposed &&
    state.generation == closing_generation &&
    state.phase == PeekClosed &&
    state.widget is None {
    self.focus()
  }
}

///|
fn Viewer::close_definition_peek(self : Viewer, restore_focus~ : Bool) -> Unit {
  self.close_references_peek(restore_focus~)
}

///|
fn Viewer::definition_peek_phase_for_test(
  self : Viewer,
) -> @references.ReferencesPeekPhase {
  match self.references_contribution() {
    Some(state) => state.phase
    None => PeekClosed
  }
}

///|
let _definition_peek_test_seam_anchor : Unit = ignore(
  (
    Viewer::definition_peek_phase_for_test,
    Viewer::cancel_definition_peek_preview_request,
    Viewer::move_definition_peek_result,
    Viewer::confirm_definition_peek_result,
  ),
)
