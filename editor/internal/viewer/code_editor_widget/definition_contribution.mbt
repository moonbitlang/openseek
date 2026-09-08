///|
let definition_contribution_id : String = "editor.contrib.definition"

///|
priv struct DefinitionContributionState {
  mut disposed : Bool
  mut link_generation : Int
  mut link_source : @language.CancellationTokenSource?
  mut link_state : @definition.DefinitionLinkState
  mut link_modifier_down : Bool
  mut last_pointer_target : @definition.DefinitionTargetFingerprint?
  mut definition_mouse_down_line : Int
  mut last_message : String?
  mut message_widget : @definition_browser.DefinitionMessageWidget?
  mut message_hide : @base_common.Disposable?
  link_decorations : EditorDecorationsCollection
  mut launch_async_task : (async () -> Unit noraise) -> Unit
  navigation_action : @goto_symbol.SymbolNavigationAction
  definition_action : @goto_symbol.DefinitionAction
  references_action : @goto_symbol.ReferencesAction
}

///|
fn DefinitionContributionState::DefinitionContributionState(
  viewer : CodeEditorWidget,
) -> DefinitionContributionState {
  let navigation_action = @goto_symbol.SymbolNavigationAction(
    viewer.services.languages,
    {
      prepare_navigation: () => viewer.prepare_symbol_navigation_intent(),
      is_anchor_current: anchor => {
        viewer.symbol_navigation_anchor_is_current(anchor)
      },
      open_location: (_anchor, location, mode, source) => {
        viewer.open_peek_location(location, mode, source)
      },
      open_in_peek: (anchor, mode, locations) => {
        viewer.open_symbol_navigation_peek(anchor, mode, locations)
      },
      show_message: (anchor, message) => {
        viewer.show_definition_message(message, position=anchor.position())
      },
    },
    run_async_tasks_concurrently,
  )
  {
    disposed: false,
    link_generation: 0,
    link_source: None,
    link_state: LinkIdle,
    link_modifier_down: false,
    last_pointer_target: None,
    definition_mouse_down_line: 0,
    last_message: None,
    message_widget: None,
    message_hide: None,
    link_decorations: viewer.create_decorations_collection(),
    launch_async_task,
    navigation_action,
    definition_action: DefinitionAction(navigation_action),
    references_action: ReferencesAction(navigation_action),
  }
}

///|
fn DefinitionContributionState::cancel_link(
  self : DefinitionContributionState,
) -> Unit {
  self.link_generation += 1
  let source = self.link_source
  self.link_source = None
  self.link_state = LinkIdle
  self.link_decorations.clear()
  match source {
    Some(source) => source.dispose(cancel=true)
    None => ()
  }
}

///|
fn DefinitionContributionState::retire_link_source(
  self : DefinitionContributionState,
  source : @language.CancellationTokenSource,
  cancel~ : Bool,
) -> Unit {
  match self.link_source {
    Some(current) if physical_equal(current, source) => {
      self.link_source = None
      source.dispose(cancel~)
    }
    _ => ()
  }
}

///|
fn DefinitionContributionState::reset_link_gesture(
  self : DefinitionContributionState,
) -> Unit {
  self.cancel_link_gesture()
  self.last_pointer_target = None
}

///|
/// Retires the modifier/click transaction while retaining the live pointer
/// anchor used by semantic Markdown keyboard commands.
fn DefinitionContributionState::cancel_link_gesture(
  self : DefinitionContributionState,
) -> Unit {
  self.cancel_link()
  self.link_modifier_down = false
  self.definition_mouse_down_line = 0
}

///|
fn DefinitionContributionState::dispose(
  self : DefinitionContributionState,
  viewer : CodeEditorWidget,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.navigation_action.dispose()
  self.reset_link_gesture()
  viewer.close_references_peek(restore_focus=false)
  viewer.dispose_definition_message()
}

///|
fn register_definition_contribution(
  registry : EditorContributionRegistry,
) -> Unit {
  registry.register_editor_contribution(
    definition_contribution_id,
    Definition,
    BeforeFirstInteraction,
    viewer => Definition(DefinitionContributionState(viewer)),
    viewer => viewer.hook_definition_contribution(),
  )
  let reveal = @goto_symbol.RevealDefinition
  registry.register_editor_command(
    reveal.id(),
    viewer => viewer.definition_action_available(),
    viewer => viewer.start_goto_definition(),
    [
      ("F12", false, false),
      // VS Code's web fallback is the same Current-mode action.
      ("F12", false, true),
    ],
    title=reveal.title(),
    menu_keybinding_label=reveal.keybinding_label().unwrap(),
    menu_placements=[
      { menu_id: EditorContext, group: "navigation", order: 1.1, },
    ],
  )
  let peek = @goto_symbol.PeekDefinition
  registry.register_editor_command(
    peek.id(),
    viewer => viewer.definition_peek_available(),
    viewer => viewer.start_peek_definition(),
    [("F12", true, false)],
    title=peek.title(),
    menu_keybinding_label=peek.keybinding_label().unwrap(),
    menu_placements=[
      { menu_id: EditorContext, group: "navigation", order: 1.2, },
    ],
  )
}

///|
fn CodeEditorWidget::definition_contribution(
  self : CodeEditorWidget,
) -> DefinitionContributionState? {
  match self.contributions.lookup(definition_contribution_id) {
    Some(entry) =>
      match entry.instance {
        Definition(state) => Some(state)
        _ => None
      }
    None => None
  }
}

///|
fn CodeEditorWidget::definition_action_available(
  self : CodeEditorWidget,
) -> Bool {
  guard !self.disposed else { return false }
  guard self.definition_contribution() is Some(_) else { return false }
  match self.get_model() {
    Some(model) => self.services.languages.has_definition_provider(model)
    None => false
  }
}

///|
fn CodeEditorWidget::symbol_navigation_anchor_at(
  self : CodeEditorWidget,
  position : @base_common.Position,
) -> @goto_symbol.SymbolNavigationAnchor? {
  guard !self.disposed && self.get_model() is Some(model) else { return None }
  let position = model.validate_position(position)
  let range = match model.get_word_at_position(position) {
    Some(word) =>
      @base_common.Range(
        position.line_number,
        word.start_column,
        position.line_number,
        word.end_column,
      )
    None =>
      Range(
        position.line_number,
        position.column,
        position.line_number,
        position.column,
      )
  }
  Some(
    @goto_symbol.SymbolNavigationAnchor::from_model(
      model,
      position,
      range,
      self.model_slot.generation,
    ),
  )
}

///|
fn CodeEditorWidget::symbol_navigation_anchor_is_current(
  self : CodeEditorWidget,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> Bool {
  guard !self.disposed && self.get_model() is Some(model) else { return false }
  anchor.surface_generation() == self.model_slot.generation &&
  anchor.model().same(model) &&
  anchor.model_is_current() &&
  self.get_position() == Some(anchor.position())
}

///|
/// Closes a Peek session that is still resolving its definitions or
/// references; a populated session stays open.
fn CodeEditorWidget::close_loading_references_peek(
  self : CodeEditorWidget,
) -> Unit {
  match self.references_contribution() {
    Some(references) =>
      match references.controller.phase() {
        PeekLoadingDefinitions(_) | PeekLoadingReferences(_) =>
          self.close_references_peek(restore_focus=false)
        _ => ()
      }
    None => ()
  }
}

///|
/// Surface-owned preparation shared by Definition and References actions.
/// Populated Peek sessions remain independently usable; only unresolved
/// queries are superseded by the new navigation intent.
fn CodeEditorWidget::prepare_symbol_navigation_intent(
  self : CodeEditorWidget,
) -> Unit {
  self.close_loading_references_peek()
  match self.definition_contribution() {
    Some(state) => state.reset_link_gesture()
    None => ()
  }
  self.clear_definition_message()
}

///|
fn CodeEditorWidget::open_symbol_navigation_peek(
  self : CodeEditorWidget,
  anchor : @goto_symbol.SymbolNavigationAnchor,
  mode : @references.ReferencesPeekMode,
  locations : Array[@language.Location],
) -> Bool {
  guard self.symbol_navigation_anchor_is_current(anchor) else { return false }
  match mode {
    Definitions => {
      guard self.definition_peek_available() else { return false }
      self.open_definition_peek_with_locations(anchor.position(), locations)
      true
    }
    References => {
      guard self.references_peek_available() else { return false }
      self.show_references(anchor.position(), locations)
      true
    }
  }
}

///|
fn CodeEditorWidget::hook_definition_contribution(
  self : CodeEditorWidget,
) -> Array[@base_common.Disposable] {
  [
    self.on_did_change_model(_ => self.reset_definition_requests()),
    self.on_did_change_model_content(_ => self.reset_definition_requests()),
    self.on_did_change_cursor_selection(event => {
      self.on_definition_cursor_selection_changed(event.selection.is_empty())
    }),
    self.on_mouse_move(event => self.on_definition_mouse_move(event)),
    self.on_mouse_up(event => self.on_definition_mouse_up(event)),
    self.on_mouse_leave(_ => self.reset_definition_link()),
    self.on_did_scroll_change(event => {
      if event.scroll_top_changed || event.scroll_left_changed {
        self.reset_definition_link()
      }
    }),
  ]
}

///|
/// Cursor movement invalidates an F12 action and a definition-link request.
/// A Peek that is still resolving its definitions is anchored to that same
/// source position and must close; once results are installed, ordinary
/// selection changes do not destroy the CodeEditorWidget-owned Peek session. When an
/// unresolved definition link lets a collapsed mousedown perform the ordinary
/// cursor move, that event cancels only the preview request: the independent
/// mouse-down line must survive until mouseup launches the fresh action. A
/// non-empty drag selection resets the whole gesture and must never navigate.
fn CodeEditorWidget::on_definition_cursor_selection_changed(
  self : CodeEditorWidget,
  selection_is_empty : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.navigation_action.cancel()
  if state.definition_mouse_down_line > 0 && selection_is_empty {
    state.cancel_link()
  } else {
    state.reset_link_gesture()
  }
  self.close_loading_references_peek()
  self.clear_definition_message()
}

///|
fn CodeEditorWidget::cancel_definition_link(self : CodeEditorWidget) -> Unit {
  match self.definition_contribution() {
    Some(state) => state.cancel_link_gesture()
    None => ()
  }
}

///|
fn CodeEditorWidget::reset_definition_requests(self : CodeEditorWidget) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.navigation_action.cancel()
      state.reset_link_gesture()
      self.close_references_peek(restore_focus=false)
      self.dispose_definition_message()
    }
    None => ()
  }
}

///|
fn CodeEditorWidget::reset_definition_link(self : CodeEditorWidget) -> Unit {
  match self.definition_contribution() {
    Some(state) => state.reset_link_gesture()
    None => ()
  }
}

///|
fn CodeEditorWidget::start_goto_definition(self : CodeEditorWidget) -> Unit {
  guard self.definition_command_position() is Some(position) else { return }
  self.start_goto_definition_at(position, mute_message=false)
}

///|
/// Starts the ordinary Definition action at an already validated source
/// position. Definition-link mouseup deliberately uses this entry instead of
/// consuming the preview request's cached locations.
fn CodeEditorWidget::start_goto_definition_at(
  self : CodeEditorWidget,
  position : @base_common.Position,
  mute_message~ : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard self.symbol_navigation_anchor_at(position) is Some(anchor) else {
    return
  }
  guard state.definition_action.begin(anchor) is Some(generation) else {
    return
  }
  let task = state.launch_async_task
  task(async fn() noraise {
    state.definition_action.run_reserved(
      anchor,
      { open_to_side: false, open_in_peek: false, mute_message, },
      generation,
    )
  })
}

///|
fn definition_link_modifier_is_active(
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
) -> Bool {
  guard !alt && !shift else { return false }
  if @base_common.is_macintosh {
    meta && !ctrl
  } else {
    ctrl && !meta
  }
}

///|
fn CodeEditorWidget::definition_target_from_mouse_target(
  self : CodeEditorWidget,
  target : @editor_browser.MouseTarget,
) -> @definition.DefinitionTargetFingerprint? {
  guard self.get_model() is Some(model) else { return None }
  guard !model.is_disposed() else { return None }
  match target {
    MouseTargetContentText(position~, detail~, ..) => {
      guard !detail.might_be_foreign_element else { return None }
      guard detail.injected_text is None else { return None }
      let position = model.validate_position(position)
      guard model.get_word_at_position(position) is Some(word) else {
        return None
      }
      Some(
        @definition.DefinitionTargetFingerprint::from_model(
          model,
          self.model_slot.generation,
          position,
          word,
        ),
      )
    }
    _ => None
  }
}

///|
fn CodeEditorWidget::definition_command_position(
  self : CodeEditorWidget,
) -> @base_common.Position? {
  self.get_position()
}

///|
fn CodeEditorWidget::definition_link_target_is_current(
  self : CodeEditorWidget,
  target : @definition.DefinitionTargetFingerprint,
) -> Bool {
  match self.get_model() {
    Some(model) => {
      guard target.is_current(model, self.model_slot.generation) else {
        return false
      }
      true
    }
    None => false
  }
}

///|
/// Commits a plain-click command anchor. Pointer hover alone must not cancel a
/// Markdown request, but an actual click is the projection equivalent of a Code
/// cursor change and invalidates the old action/loading Peek immediately.
fn CodeEditorWidget::commit_plain_definition_pointer_target(
  self : CodeEditorWidget,
  target : @definition.DefinitionTargetFingerprint?,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.navigation_action.cancel()
  self.close_loading_references_peek()
  state.last_pointer_target = match target {
    Some(target) if self.definition_link_target_is_current(target) =>
      Some(target)
    _ => None
  }
  state.cancel_link_gesture()
  self.clear_definition_message()
}

///|
fn CodeEditorWidget::start_definition_link_request(
  self : CodeEditorWidget,
  target : @definition.DefinitionTargetFingerprint,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  guard self.get_model() is Some(model) else { return }
  guard self.services.languages.has_definition_provider(model) else {
    state.cancel_link()
    return
  }
  match state.link_state {
    LinkResolving(stamp) | LinkResolvedEmpty(stamp) | LinkArmed(stamp, _) if stamp.target.same_word(
        target,
      ) => return
    _ => ()
  }
  state.cancel_link()
  self.clear_definition_message()
  let sequence = state.link_generation
  let stamp : @definition.DefinitionRequestStamp = { sequence, target, }
  let source = @language.CancellationTokenSource()
  state.link_source = Some(source)
  state.link_state = LinkResolving(stamp)
  let offset = model.get_offset_at(target.position())
  let task = state.launch_async_task
  task(async fn() noraise {
    let locations = self.services.languages.definition_at(
      model,
      offset,
      token=source.token(),
      run_tasks=run_async_tasks_concurrently,
    )
    if !self.definition_link_request_is_current(stamp, source) {
      state.retire_link_source(source, cancel=true)
      return
    }
    source.dispose()
    state.link_source = None
    let locations = @definition.normalize_definition_locations(locations)
    if locations.is_empty() {
      state.link_state = LinkResolvedEmpty(stamp)
      state.link_decorations.clear()
      return
    }
    state.link_state = LinkArmed(stamp, locations)
    state.link_decorations.set([
      {
        range: target.word_range(),
        options: ModelDecorationOptions(
          "",
          inline_class_name="moonbit-viewer-definition-link",
          description="definition-link",
        ),
      },
    ])
    |> ignore
  })
}

///|
fn CodeEditorWidget::definition_link_request_is_current(
  self : CodeEditorWidget,
  stamp : @definition.DefinitionRequestStamp,
  source : @language.CancellationTokenSource,
) -> Bool {
  guard !self.disposed && !source.token().is_cancellation_requested() else {
    return false
  }
  guard self.definition_contribution() is Some(state) else { return false }
  guard state.link_generation == stamp.sequence else { return false }
  guard state.link_modifier_down else { return false }
  guard state.last_pointer_target is Some(pointer_target) &&
    pointer_target.same_word(stamp.target) else {
    return false
  }
  guard self.definition_link_target_is_current(stamp.target) else {
    return false
  }
  match state.link_state {
    LinkResolving(current) => current == stamp
    _ => false
  }
}

///|
fn CodeEditorWidget::on_definition_mouse_move(
  self : CodeEditorWidget,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  let target = self.definition_target_from_mouse_target(event.target)
  self.handle_definition_pointer_move(
    target,
    event.event.ctrl_key,
    event.event.meta_key,
    event.event.alt_key,
    event.event.shift_key,
    event.event.buttons,
  )
}

///|
fn CodeEditorWidget::handle_definition_pointer_move(
  self : CodeEditorWidget,
  target : @definition.DefinitionTargetFingerprint?,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
  buttons : Int,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  state.last_pointer_target = target
  let active = definition_link_modifier_is_active(ctrl, meta, alt, shift)
  if buttons != 0 {
    state.reset_link_gesture()
    return
  }
  if !active {
    state.link_modifier_down = false
    state.cancel_link()
    return
  }
  state.link_modifier_down = true
  match target {
    Some(target) => self.start_definition_link_request(target)
    None => state.cancel_link()
  }
}

///|
fn definition_link_key_is_trigger(key : String) -> Bool {
  if @base_common.is_macintosh {
    key == "Meta"
  } else {
    key == "Control"
  }
}

///|
fn CodeEditorWidget::handle_definition_modifier_key(
  self : CodeEditorWidget,
  key : String,
  key_down : Bool,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
) -> Unit {
  guard self.definition_contribution() is Some(state) else { return }
  let active = definition_link_modifier_is_active(ctrl, meta, alt, shift)
  let trigger_key = definition_link_key_is_trigger(key)
  if !key_down {
    if trigger_key {
      state.cancel_link_gesture()
    }
    return
  }
  if !active {
    if trigger_key || state.link_modifier_down {
      state.cancel_link_gesture()
    }
    return
  }
  if !trigger_key {
    // A Ctrl/Cmd chord is not a link gesture. Clearing the whole click state
    // prevents its eventual mouseup from becoming an accidental navigation.
    state.cancel_link_gesture()
    return
  }
  let became_active = !state.link_modifier_down
  state.link_modifier_down = true
  if became_active {
    match state.last_pointer_target {
      Some(target) if self.definition_link_target_is_current(target) =>
        self.start_definition_link_request(target)
      _ => ()
    }
  }
}

///|
fn CodeEditorWidget::on_definition_mouse_up(
  self : CodeEditorWidget,
  event : @editor_browser.EditorMouseEvent,
) -> Unit {
  let target = self.definition_target_from_mouse_target(event.target)
  self.handle_definition_pointer_up(
    target,
    event.event.ctrl_key,
    event.event.meta_key,
    event.event.alt_key,
    event.event.shift_key,
    left_button=event.event.left_button,
    detail=event.event.detail,
  )
  |> ignore
}

///|
fn CodeEditorWidget::handle_definition_pointer_up(
  self : CodeEditorWidget,
  target : @definition.DefinitionTargetFingerprint?,
  ctrl : Bool,
  meta : Bool,
  alt : Bool,
  shift : Bool,
  left_button? : Bool = true,
  detail? : Int = 1,
) -> Bool {
  guard self.definition_contribution() is Some(state) else { return false }
  let modifier_active = definition_link_modifier_is_active(
    ctrl, meta, alt, shift,
  )
  let mouse_down_line = state.definition_mouse_down_line
  state.definition_mouse_down_line = 0
  guard modifier_active &&
    left_button &&
    detail <= 1 &&
    state.link_modifier_down &&
    mouse_down_line > 0 &&
    target is Some(target) &&
    target.position().line_number == mouse_down_line &&
    self.definition_link_target_is_current(target) else {
    if !modifier_active && left_button && detail <= 1 {
      self.commit_plain_definition_pointer_target(target)
    }
    return false
  }
  let position = target.position()
  state.reset_link_gesture()
  self.set_position(position, source="gotoDefinitionLink")
  self.start_goto_definition_at(position, mute_message=true)
  true
}

///|
/// VS Code's `_openReference` target feedback shared by Definition and
/// References navigation: retain the full target range for 350ms, and clear it
/// only if the CodeEditorWidget still owns the exact model that received the decoration.
fn CodeEditorWidget::show_navigation_target_highlight(
  self : CodeEditorWidget,
  target_model : @model.TextModel,
  range : @base_common.Range,
) -> Unit {
  let decorations = self.create_decorations_collection(decorations=[
    {
      range,
      options: ModelDecorationOptions(
        "symbolHighlight",
        description="symbol-navigate-action-highlight",
      ),
    },
  ])
  @base_browser.schedule_timeout(
    () => {
      match self.get_model() {
        Some(current) if current.same(target_model) => decorations.clear()
        _ => ()
      }
    },
    350,
  )
  |> ignore
}

///|
fn CodeEditorWidget::show_definition_message(
  self : CodeEditorWidget,
  message : String,
  position? : @base_common.Position,
) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.last_message = Some(message)
      match state.message_hide {
        Some(handle) => handle.dispose()
        None => ()
      }
      state.message_hide = None
      guard self.current_code_browser_data() is Some(_) else { return }
      guard self.get_model() is Some(model) else { return }
      let position = model.validate_position(
        match position {
          Some(position) => position
          None =>
            match self.get_position() {
              Some(position) => position
              None => Position(1, 1)
            }
        },
      )
      let widget = match state.message_widget {
        Some(widget) => widget
        None => {
          let widget = @definition_browser.DefinitionMessageWidget()
          state.message_widget = Some(widget)
          widget
        }
      }
      guard self.current_code_view() is Some(view) else { return }
      if widget.get_dom_node().get_attribute("data-content-widget") is None {
        view.content_widgets.add_widget(widget.content_widget_handle())
      }
      @base_browser.remove_style_property(widget.get_dom_node(), "top")
      @base_browser.remove_style_property(widget.get_dom_node(), "right")
      self.reveal_position_in_center_if_outside_viewport(position)
      widget.set_message(message)
      widget.show_at(position)
      self.reposition_definition_message_widget(widget)
      state.message_hide = Some(
        @base_browser.schedule_timeout(
          () => {
            if !state.disposed {
              widget.hide()
              self.reposition_definition_message_widget(widget)
              state.message_hide = None
            }
          },
          2500,
        ),
      )
    }
    None => ()
  }
}

///|
/// Re-publishes the definition message widget's position on the current view
/// and schedules the repaint; a no-op without a view.
fn CodeEditorWidget::reposition_definition_message_widget(
  self : CodeEditorWidget,
  widget : @definition_browser.DefinitionMessageWidget,
) -> Unit {
  match self.current_code_view() {
    Some(view) => {
      view.content_widgets.set_widget_position(widget.content_widget_handle())
      self.schedule_render()
    }
    None => ()
  }
}

///|
fn CodeEditorWidget::clear_definition_message(self : CodeEditorWidget) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      state.last_message = None
      match state.message_hide {
        Some(handle) => handle.dispose()
        None => ()
      }
      state.message_hide = None
      match state.message_widget {
        Some(widget) => {
          widget.hide()
          self.reposition_definition_message_widget(widget)
        }
        None => ()
      }
    }
    None => ()
  }
}

///|
fn CodeEditorWidget::dispose_definition_message(
  self : CodeEditorWidget,
) -> Unit {
  match self.definition_contribution() {
    Some(state) => {
      match state.message_hide {
        Some(handle) => handle.dispose()
        None => ()
      }
      state.message_hide = None
      match state.message_widget {
        Some(widget) => {
          @base_browser.remove_element(widget.get_dom_node())
          widget.dispose()
        }
        None => ()
      }
      state.message_widget = None
      state.last_message = None
    }
    None => ()
  }
}

///|
fn CodeEditorWidget::definition_message_for_test(
  self : CodeEditorWidget,
) -> String? {
  self.definition_contribution().bind(state => state.last_message)
}

///|
fn CodeEditorWidget::set_definition_host_for_test(
  self : CodeEditorWidget,
  launch : (async () -> Unit noraise) -> Unit,
) -> Unit {
  match self.definition_contribution() {
    Some(state) => state.launch_async_task = launch
    None => ()
  }
  match self.references_contribution() {
    Some(state) => state.controller.set_task_launcher(launch)
    None => ()
  }
}

///|
let _definition_test_seam_anchor : Unit = ignore(
  (
    CodeEditorWidget::definition_message_for_test,
    CodeEditorWidget::set_definition_host_for_test,
    CodeEditorWidget::cancel_definition_link,
  ),
)
