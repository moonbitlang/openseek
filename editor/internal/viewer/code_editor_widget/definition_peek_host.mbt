///|
priv struct CodeReferencesPeekMountOwner {
  viewer : CodeEditorWidget
  view : @view.View
  zone_id : String
  overlay : @editor_browser.OverlayWidget
  mut disposed : Bool
}

///|
fn CodeReferencesPeekMountOwner::is_current(
  self : CodeReferencesPeekMountOwner,
) -> Bool {
  !self.disposed &&
  !self.viewer.disposed &&
  self.viewer.current_code_browser_data() is Some(browser) &&
  physical_equal(browser.view, self.view)
}

///|
fn CodeReferencesPeekMountOwner::dispose(
  self : CodeReferencesPeekMountOwner,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.viewer.remove_overlay_widget_if_current(self.overlay) |> ignore
  self.view.change_view_zones(accessor => accessor.remove_zone(self.zone_id))
  if !self.viewer.disposed {
    self.viewer.schedule_render()
  }
}

///|
priv struct CodeReferencesPeekPreviewOwner {
  viewer : CodeEditorWidget
  decorations : EditorDecorationsCollection
  resize_observer : @base_common.Disposable?
  layout_frame : @base_common.Disposable
  mut disposed : Bool
}

///|
fn CodeReferencesPeekPreviewOwner::contains_focus(
  self : CodeReferencesPeekPreviewOwner,
) -> Bool {
  guard !self.disposed && self.viewer.get_dom_node() is Some(root) else {
    return false
  }
  @base_browser.element_contains_active_element(root)
}

///|
fn CodeReferencesPeekPreviewOwner::dispose(
  self : CodeReferencesPeekPreviewOwner,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  match self.resize_observer {
    Some(observer) => observer.dispose()
    None => ()
  }
  self.layout_frame.dispose()
  self.viewer.set_model(None)
  self.viewer.dispose()
  self.decorations.clear()
}

///|
/// CodeEditor preview creation injected into the shared ReferencesController.
/// Markdown uses the same factory while retaining an independent controller.
pub fn code_editor_references_preview_factory(
  services : CodeEditorServices,
  options : CodeEditorOptions,
) -> @references_browser.ReferencesPeekPreviewFactory {
  {
    create: (host, model, selected_range, match_ranges, mode) => {
      guard !model.is_disposed() else { return None }
      let preview = CodeEditorWidget(
        services~,
        options~,
        initial_container=host,
        contributions=CodeEditorContributionDescriptors::peek_preview(),
      )
      preview.attach(host)
      preview.set_model(Some(model))
      let decorations : Array[@model.ModelDeltaDecoration] = []
      for range in match_ranges {
        decorations.push({
          range: model.validate_range(range),
          options: ModelDecorationOptions(
            "moonbit-viewer-references-peek-reference-match",
            description="peek-reference-match",
          ),
        })
      }
      let selected_range = model.validate_range(selected_range)
      decorations.push({
        range: selected_range,
        options: ModelDecorationOptions(
          "moonbit-viewer-references-peek-reference-match-selected",
          description="peek-reference-match-selected",
        ),
      })
      let collection = preview.create_decorations_collection(decorations~)
      let start = selected_range.get_start_position()
      preview.set_position(
        start,
        source=if mode == Definitions {
          "peekDefinition"
        } else {
          "peekReferences"
        },
      )
      preview.reveal_range_in_center_if_outside_viewport(
        Range(start.line_number, start.column, start.line_number, start.column),
      )
      preview.handle_initialized()
      let mut owner_slot : CodeReferencesPeekPreviewOwner? = None
      let resize_observer = @base_browser.observe_element_resize(host, () => {
        match owner_slot {
          Some(owner) if !owner.disposed => preview.layout()
          _ => ()
        }
      })
      let layout_frame = @base_browser.schedule_at_next_animation_frame(() => {
        match owner_slot {
          Some(owner) if !owner.disposed => preview.layout()
          _ => ()
        }
      })
      let owner : CodeReferencesPeekPreviewOwner = {
        viewer: preview,
        decorations: collection,
        resize_observer,
        layout_frame,
        disposed: false,
      }
      owner_slot = Some(owner)
      Some(
        ReferencesPeekPreview(
          contains_focus=() => owner.contains_focus(),
          focus=() => preview.focus(),
          dispose=() => owner.dispose(),
        ),
      )
    },
  }
}

///|
fn CodeEditorWidget::references_peek_height_in_lines(
  self : CodeEditorWidget,
) -> Double {
  let snapshot = self.configuration.snapshot()
  let requested = @references_browser.references_peek_height_in_lines.to_double()
  let line_height = snapshot.font_info.line_height.to_double()
  if snapshot.height <= 0.0 || line_height <= 0.0 {
    requested
  } else {
    requested.min((snapshot.height / line_height * 0.8).max(12.0))
  }
}

///|
fn CodeEditorWidget::mount_code_references_peek(
  self : CodeEditorWidget,
  root : @rdom.Element,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> @references_browser.ReferencesPeekMount? {
  guard self.symbol_navigation_anchor_is_current(anchor) &&
    self.current_code_browser_data() is Some(browser) else {
    return None
  }
  let zone_node = @rdom.document().create_element("div")
  zone_node.set_attribute("class", "moonbit-viewer-references-peek-zone")
  let layout = self.get_layout_info()
  @base_browser.set_style_property(root, "position", "absolute")
  @base_browser.set_style_property(root, "top", "-1000000px")
  @base_browser.set_style_property(root, "left", "0")
  @base_browser.set_style_property(
    root,
    "right",
    "\{layout.vertical_scrollbar_width.to_string()}px",
  )
  @base_browser.set_style_property(root, "width", "auto")
  let position = anchor.position()
  let zone = @editor_browser.ViewZone(
    position.line_number,
    zone_node,
    after_column=position.column,
    suppress_mouse_down=true,
    height_in_lines=self.references_peek_height_in_lines(),
    on_dom_node_top=top => {
      @base_browser.set_style_property(root, "top", "\{top.to_string()}px")
    },
    on_computed_height=height => {
      @base_browser.set_style_property(
        root,
        "height",
        "\{height.to_string()}px",
      )
    },
  )
  let zone_id = Ref("")
  self.change_view_zones(accessor => zone_id.val = accessor.add_zone(zone))
  if zone_id.val == "" {
    return None
  }
  let overlay = overlay_widget(
    "moonbit.viewer.referencesPeek.\{self.get_id()}",
    root,
  )
  self.add_overlay_widget(overlay)
  let owner : CodeReferencesPeekMountOwner = {
    viewer: self,
    view: browser.view,
    zone_id: zone_id.val,
    overlay,
    disposed: false,
  }
  if !owner.is_current() || !self.symbol_navigation_anchor_is_current(anchor) {
    owner.dispose()
    return None
  }
  Some(
    ReferencesPeekMount(is_current=() => owner.is_current(), dispose=() => {
      owner.dispose()
    }),
  )
}

///|
fn CodeEditorWidget::reveal_references_peek_anchor(
  self : CodeEditorWidget,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> Unit {
  guard self.symbol_navigation_anchor_is_current(anchor) else { return }
  let line_number = anchor.position().line_number
  let end_line_number = (line_number + 1).min(anchor.model().get_line_count())
  if end_line_number == line_number {
    self.reveal_line_near_top(line_number)
  } else {
    self.reveal_lines(line_number, end_line_number)
  }
}

///|
fn CodeEditorWidget::create_references_controller(
  self : CodeEditorWidget,
) -> @references_browser.ReferencesController {
  ReferencesController(
    {
      is_anchor_current: anchor => {
        self.symbol_navigation_anchor_is_current(anchor)
      },
      mount: (root, anchor) => self.mount_code_references_peek(root, anchor),
      reveal_anchor: anchor => self.reveal_references_peek_anchor(anchor),
      restore_source_focus: () => self.focus(),
      open_location: (location, mode, source) => {
        self.open_peek_location(location, mode, source)
      },
      show_message: (anchor, message) => {
        self.show_definition_message(message, position=anchor.position())
      },
    },
    code_editor_references_preview_factory(self.services, self.get_options()),
    resolver?=self.services.text_model_resolver,
    launch_async_task,
  )
}

///|
fn CodeEditorWidget::definition_peek_available(self : CodeEditorWidget) -> Bool {
  self.references_peek_available() &&
  self.definition_action_available() &&
  self.get_model() is Some(_)
}

///|
fn CodeEditorWidget::references_action_available(
  self : CodeEditorWidget,
) -> Bool {
  guard self.references_peek_available() else { return false }
  match self.get_model() {
    Some(model) => self.services.languages.has_references_provider(model)
    None => false
  }
}

///|
fn CodeEditorWidget::references_peek_available(self : CodeEditorWidget) -> Bool {
  !self.disposed &&
  self.references_contribution() is Some(_) &&
  self.get_model() is Some(_) &&
  self.current_code_browser_data() is Some(_)
}

///|
fn CodeEditorWidget::definition_peek_contains_focus(
  self : CodeEditorWidget,
) -> Bool {
  match self.references_contribution() {
    Some(state) => state.controller.contains_focus()
    None => false
  }
}

///|
fn CodeEditorWidget::start_peek_definition(self : CodeEditorWidget) -> Unit {
  guard self.definition_peek_available() else { return }
  guard self.definition_contribution() is Some(definition) else { return }
  guard self.definition_command_position() is Some(position) &&
    self.symbol_navigation_anchor_at(position) is Some(anchor) &&
    definition.definition_action.begin(anchor) is Some(generation) else {
    return
  }
  let task = definition.launch_async_task
  task(async fn() noraise {
    definition.definition_action.run_reserved(
      anchor,
      @goto_symbol.SymbolNavigationActionConfig::peek(),
      generation,
    )
  })
}

///|
fn CodeEditorWidget::start_goto_references(self : CodeEditorWidget) -> Unit {
  self.start_references_action(
    @goto_symbol.SymbolNavigationActionConfig::goto(),
  )
}

///|
fn CodeEditorWidget::start_peek_references(self : CodeEditorWidget) -> Unit {
  self.start_references_action(
    @goto_symbol.SymbolNavigationActionConfig::peek(),
  )
}

///|
fn CodeEditorWidget::start_references_action(
  self : CodeEditorWidget,
  config : @goto_symbol.SymbolNavigationActionConfig,
) -> Unit {
  guard self.references_action_available() else { return }
  guard self.definition_contribution() is Some(definition) else { return }
  guard self.definition_command_position() is Some(position) &&
    self.symbol_navigation_anchor_at(position) is Some(anchor) &&
    definition.references_action.begin(anchor) is Some(generation) else {
    return
  }
  let task = definition.launch_async_task
  task(async fn() noraise {
    definition.references_action.run_reserved(anchor, config, generation)
  })
}

///|
fn CodeEditorWidget::open_definition_peek_with_locations(
  self : CodeEditorWidget,
  position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.symbol_navigation_anchor_at(position) is Some(anchor) &&
    self.references_contribution() is Some(state) else {
    return
  }
  state.controller.toggle_locations(anchor, Definitions, locations) |> ignore
}

///|
pub fn CodeEditorWidget::show_references(
  self : CodeEditorWidget,
  position : @base_common.Position,
  locations : Array[@language.Location],
) -> Unit {
  guard self.symbol_navigation_anchor_at(position) is Some(anchor) &&
    self.references_contribution() is Some(state) else {
    return
  }
  state.controller.toggle_locations(anchor, References, locations) |> ignore
}

///|
async fn CodeEditorWidget::open_peek_location(
  self : CodeEditorWidget,
  location : @language.Location,
  mode : @navigation_api.OpenLocationMode,
  source : String,
) -> Bool noraise {
  guard !self.disposed && self.get_model() is Some(source_model) else {
    return false
  }
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
      opener.open({ source_viewer_id: self.get_id(), location, mode, })
    None => false
  }
}

///|
fn CodeEditorWidget::close_references_peek(
  self : CodeEditorWidget,
  restore_focus~ : Bool,
) -> Unit {
  match self.references_contribution() {
    Some(state) => state.controller.close(restore_focus~)
    None => ()
  }
}

///|
fn CodeEditorWidget::close_definition_peek(
  self : CodeEditorWidget,
  restore_focus~ : Bool,
) -> Unit {
  self.close_references_peek(restore_focus~)
}

///|
fn CodeEditorWidget::definition_peek_phase_for_test(
  self : CodeEditorWidget,
) -> @references.ReferencesPeekPhase {
  match self.references_contribution() {
    Some(state) => state.controller.phase()
    None => PeekClosed
  }
}

///|
let _definition_peek_test_seam_anchor : Unit = ignore(
  CodeEditorWidget::definition_peek_phase_for_test,
)
