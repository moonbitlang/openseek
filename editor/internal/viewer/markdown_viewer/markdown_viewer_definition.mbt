///|
priv struct MarkdownViewerWidgetDefinitionTarget {
  anchor : @goto_symbol.SymbolNavigationAnchor
}

///|
fn MarkdownViewerWidgetDefinitionTarget::same(
  self : MarkdownViewerWidgetDefinitionTarget,
  other : MarkdownViewerWidgetDefinitionTarget,
) -> Bool {
  self.anchor.same_snapshot(other.anchor)
}

///|
/// OpenSeek Markdown IDE bridge. DOM/projection work remains surface-owned;
/// provider policy and Peek lifecycle are delegated to the shared navigation
/// action and one attachment-local ReferencesController.
priv struct MarkdownViewerWidgetDefinitionBridge {
  viewer : MarkdownViewerWidget
  view : @markdown_document.MarkdownDocumentView
  model : @model.TextModel
  attach_generation : Int
  listeners : Array[@base_common.Disposable]
  navigation_action : @goto_symbol.SymbolNavigationAction
  definition_action : @goto_symbol.DefinitionAction
  references_action : @goto_symbol.ReferencesAction
  link_resolver : @goto_symbol.DefinitionLinkResolver
  controller : @references_browser.ReferencesController?
  mut context_menu : @contextmenu_browser.ContextMenuWidget?
  mut link_elements : Array[@rdom.Element]
  mut last_target : MarkdownViewerWidgetDefinitionTarget?
  mut mouse_down_target : MarkdownViewerWidgetDefinitionTarget?
  mut last_client_x : Double
  mut last_client_y : Double
  mut surface_generation : Int
  mut active : Bool
  mut disposed : Bool
}

///|
async fn markdown_navigation_run_provider_tasks(
  tasks : Array[async () -> Unit],
) -> Unit {
  for task in tasks {
    task()
  }
}

///|
fn MarkdownViewerWidgetDefinitionBridge::MarkdownViewerWidgetDefinitionBridge(
  viewer : MarkdownViewerWidget,
  view : @markdown_document.MarkdownDocumentView,
  model : @model.TextModel,
  attach_generation : Int,
) -> MarkdownViewerWidgetDefinitionBridge {
  let bridge_slot : Ref[MarkdownViewerWidgetDefinitionBridge?] = Ref(None)
  let anchor_is_current = anchor => {
    bridge_slot.val.map_or(false, bridge => bridge.anchor_is_current(anchor))
  }
  let navigation_action = @goto_symbol.SymbolNavigationAction(
    viewer.services.languages(),
    {
      prepare_navigation: () => {
        if bridge_slot.val is Some(bridge) {
          bridge.prepare_navigation()
        }
      },
      is_anchor_current: anchor_is_current,
      // `open_location` is async, so its body stays a match rather than moving
      // into a non-async `map_or` closure.
      open_location: (_anchor, location, mode, _source) => {
        match bridge_slot.val {
          Some(bridge) => bridge.open_location(location, mode)
          None => false
        }
      },
      open_in_peek: (anchor, mode, locations) => {
        bridge_slot.val.map_or(false, bridge => {
          bridge.open_in_peek(anchor, mode, locations)
        })
      },
      show_message: (_anchor, message) => {
        if bridge_slot.val is Some(bridge) {
          bridge.show_message(message)
        }
      },
    },
    markdown_navigation_run_provider_tasks,
  )
  let link_resolver = @goto_symbol.DefinitionLinkResolver(
    viewer.services.languages(),
    is_anchor_current=anchor_is_current,
    markdown_navigation_run_provider_tasks,
  )
  let controller = viewer.services
    .preview_factory()
    .map(preview_factory => {
      @references_browser.ReferencesController(
        {
          is_anchor_current: anchor_is_current,
          mount: (root, anchor) => {
            bridge_slot.val.bind(bridge => bridge.mount_peek(root, anchor))
          },
          reveal_anchor: anchor => {
            if bridge_slot.val is Some(bridge) {
              bridge.reveal_anchor(anchor)
            }
          },
          restore_source_focus: () => viewer.focus(),
          // `open_location` is async, so its body stays a match rather than
          // moving into a non-async `map_or` closure.
          open_location: (location, mode, _source) => {
            match bridge_slot.val {
              Some(bridge) => bridge.open_location(location, mode)
              None => false
            }
          },
          show_message: (_anchor, message) => {
            if bridge_slot.val is Some(bridge) {
              bridge.show_message(message)
            }
          },
        },
        preview_factory,
        resolver?=viewer.services.text_model_resolver(),
        task => viewer.services.launch_async_task(task),
      )
    })
  let bridge : MarkdownViewerWidgetDefinitionBridge = {
    viewer,
    view,
    model,
    attach_generation,
    listeners: [],
    navigation_action,
    definition_action: DefinitionAction(navigation_action),
    references_action: ReferencesAction(navigation_action),
    link_resolver,
    controller,
    context_menu: None,
    link_elements: [],
    last_target: None,
    mouse_down_target: None,
    last_client_x: 0.0,
    last_client_y: 0.0,
    surface_generation: attach_generation,
    active: false,
    disposed: false,
  }
  bridge_slot.val = Some(bridge)
  bridge
}

///|
fn MarkdownViewerWidgetDefinitionBridge::is_current(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Bool {
  self.active &&
  !self.disposed &&
  !self.model.is_disposed() &&
  self.viewer.is_current_attachment(self.model, self.attach_generation) &&
  self.view.source_model_version() == self.model.get_version_id()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::anchor_is_current(
  self : MarkdownViewerWidgetDefinitionBridge,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> Bool {
  self.is_current() &&
  anchor.surface_generation() == self.surface_generation &&
  anchor.model().same(self.model) &&
  anchor.model_is_current()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::target_is_current(
  self : MarkdownViewerWidgetDefinitionBridge,
  target : MarkdownViewerWidgetDefinitionTarget,
) -> Bool {
  self.anchor_is_current(target.anchor)
}

///|
fn MarkdownViewerWidgetDefinitionBridge::target_at(
  self : MarkdownViewerWidgetDefinitionBridge,
  client_x : Double,
  client_y : Double,
) -> MarkdownViewerWidgetDefinitionTarget? {
  guard self.is_current() &&
    self.view.semantic_pointer_hit(client_x, client_y) is Some(hit) else {
    return None
  }
  let position = self.model.get_position_at(hit.source_offset)
  guard self.model.get_word_at_position(position) is Some(word) else {
    return None
  }
  let range = @base_common.Range(
    position.line_number,
    word.start_column,
    position.line_number,
    word.end_column,
  )
  Some({
    anchor: @goto_symbol.SymbolNavigationAnchor::from_model(
      self.model,
      position,
      range,
      self.surface_generation,
    ),
  })
}

///|
fn MarkdownViewerWidgetDefinitionBridge::listen(
  self : MarkdownViewerWidgetDefinitionBridge,
  element : @rdom.Element,
  event_name : String,
  listener : @rdom.Listener,
) -> Unit {
  element.add_event_listener(event_name, listener)
  self.listeners.push(
    @base_common.Disposable::from(() => {
      element.remove_event_listener(event_name, listener)
    }),
  )
}

///|
fn markdown_viewer_definition_modifier_is_active(
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
fn markdown_viewer_definition_modifier_key(key : String) -> Bool {
  if @base_common.is_macintosh {
    key == "Meta"
  } else {
    key == "Control"
  }
}

///|
fn MarkdownViewerWidgetDefinitionBridge::clear_link_elements(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  for element in self.link_elements {
    @base_browser.remove_element(element)
  }
  self.link_elements.clear()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::cancel_link_preview(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  self.link_resolver.cancel()
  self.clear_link_elements()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::reset_link(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  self.cancel_link_preview()
  self.mouse_down_target = None
  self.last_target = None
}

///|
fn MarkdownViewerWidgetDefinitionBridge::start_link_preview(
  self : MarkdownViewerWidgetDefinitionBridge,
  target : MarkdownViewerWidgetDefinitionTarget,
) -> Unit {
  guard self.target_is_current(target) &&
    self.viewer.services.languages().has_definition_provider(self.model) else {
    self.cancel_link_preview()
    return
  }
  if self.last_target is Some(last) &&
    last.same(target) &&
    !self.link_elements.is_empty() {
    return
  }
  self.cancel_link_preview()
  self.last_target = Some(target)
  guard self.link_resolver.begin(target.anchor) is Some(generation) else {
    return
  }
  self.viewer.services.launch_async_task(async fn() noraise {
    let locations = self.link_resolver.resolve_reserved(
      target.anchor,
      generation,
    )
    guard !locations.is_empty() && self.target_is_current(target) else {
      return
    }
    let source_range = self.model.snapshot.offset_range_of(
      target.anchor.range(),
    )
    self.link_elements = self.view.append_projected_range_spans(
      source_range, "moonbit-viewer-markdown-definition-link",
    )
  })
}

///|
fn MarkdownViewerWidgetDefinitionBridge::prepare_navigation(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  self.cancel_link_preview()
  self.hide_context_menu()
  self.show_message("")
}

///|
fn MarkdownViewerWidgetDefinitionBridge::run_definition(
  self : MarkdownViewerWidgetDefinitionBridge,
  target : MarkdownViewerWidgetDefinitionTarget,
  config : @goto_symbol.SymbolNavigationActionConfig,
) -> Unit {
  guard self.target_is_current(target) &&
    self.viewer.services.languages().has_definition_provider(self.model) &&
    self.definition_action.begin(target.anchor) is Some(generation) else {
    return
  }
  self.viewer.services.launch_async_task(async fn() noraise {
    self.definition_action.run_reserved(target.anchor, config, generation)
  })
}

///|
fn MarkdownViewerWidgetDefinitionBridge::run_references(
  self : MarkdownViewerWidgetDefinitionBridge,
  target : MarkdownViewerWidgetDefinitionTarget,
  config : @goto_symbol.SymbolNavigationActionConfig,
) -> Unit {
  guard self.target_is_current(target) &&
    self.viewer.services.languages().has_references_provider(self.model) &&
    self.references_action.begin(target.anchor) is Some(generation) else {
    return
  }
  self.viewer.services.launch_async_task(async fn() noraise {
    self.references_action.run_reserved(target.anchor, config, generation)
  })
}

///|
fn MarkdownViewerWidgetDefinitionBridge::run_command(
  self : MarkdownViewerWidgetDefinitionBridge,
  command_id : String,
) -> Unit {
  guard self.last_target is Some(target) && self.target_is_current(target) else {
    return
  }
  match @goto_symbol.SymbolNavigationCommand::from_id(command_id) {
    Some(RevealDefinition) =>
      self.run_definition(
        target,
        @goto_symbol.SymbolNavigationActionConfig::goto(),
      )
    Some(PeekDefinition) =>
      self.run_definition(
        target,
        @goto_symbol.SymbolNavigationActionConfig::peek(),
      )
    Some(GoToReferences) =>
      self.run_references(
        target,
        @goto_symbol.SymbolNavigationActionConfig::goto(),
      )
    Some(PeekReferences) =>
      self.run_references(
        target,
        @goto_symbol.SymbolNavigationActionConfig::peek(),
      )
    _ => ()
  }
}

///|
fn MarkdownViewerWidgetDefinitionBridge::context_menu_entries(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Array[@contextmenu_browser.ContextMenuEntry] {
  @goto_symbol.symbol_navigation_context_commands(
    self.viewer.services.languages(),
    self.model,
    self.controller is Some(_),
  ).map(command => {
    ContextMenuAction(
      id=command.id(),
      label=command.title(),
      keybinding_label=command.keybinding_label(),
    )
  })
}

///|
fn MarkdownViewerWidgetDefinitionBridge::get_or_create_context_menu(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> @contextmenu_browser.ContextMenuWidget? {
  if self.disposed {
    return None
  }
  match self.context_menu {
    Some(widget) => Some(widget)
    None => {
      let widget = @contextmenu_browser.ContextMenuWidget({
        on_action: command_id => self.run_command(command_id),
        on_hide: _cancelled => (),
      })
      self.context_menu = Some(widget)
      Some(widget)
    }
  }
}

///|
fn MarkdownViewerWidgetDefinitionBridge::hide_context_menu(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  if self.context_menu is Some(widget) {
    widget.hide(was_cancelled=true)
  }
}

///|
fn MarkdownViewerWidgetDefinitionBridge::show_context_menu(
  self : MarkdownViewerWidgetDefinitionBridge,
  target : MarkdownViewerWidgetDefinitionTarget,
  client_x : Double,
  client_y : Double,
  auto_select_first? : Bool = false,
) -> Bool {
  guard self.target_is_current(target) else { return false }
  let entries = self.context_menu_entries()
  guard !entries.is_empty() && self.get_or_create_context_menu() is Some(widget) else {
    return false
  }
  self.last_target = Some(target)
  self.last_client_x = client_x
  self.last_client_y = client_y
  self.viewer.focus()
  widget.show(
    entries,
    client_x,
    client_y,
    self.viewer.options.theme,
    theme_source=self.view.root(),
    auto_select_first~,
  )
}

///|
fn MarkdownViewerWidgetDefinitionBridge::show_keyboard_context_menu(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Bool {
  guard self.last_target is Some(target) && self.target_is_current(target) else {
    return false
  }
  let rect = self.view.root().get_bounding_client_rect()
  let x = if self.last_client_x > 0.0 {
    self.last_client_x
  } else {
    rect.get_left() + 24.0
  }
  let y = if self.last_client_y > 0.0 {
    self.last_client_y
  } else {
    rect.get_top() + 24.0
  }
  self.show_context_menu(target, x, y, auto_select_first=true)
}

///|
fn MarkdownViewerWidgetDefinitionBridge::bind_semantic_dom(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  guard self.is_current() else { return }
  self.view.listen_semantic_dom("mousemove", event => {
    guard self.is_current() && event.to_mouse_event() is Some(mouse) else {
      self.cancel_link_preview()
      return
    }
    self.last_client_x = mouse.get_client_x().to_double()
    self.last_client_y = mouse.get_client_y().to_double()
    let target = self.target_at(self.last_client_x, self.last_client_y)
    self.last_target = target
    if mouse.get_buttons() == 0 &&
      markdown_viewer_definition_modifier_is_active(
        mouse.get_ctrl_key(),
        mouse.get_meta_key(),
        mouse.get_alt_key(),
        mouse.get_shift_key(),
      ) {
      match target {
        Some(target) => self.start_link_preview(target)
        None => self.cancel_link_preview()
      }
    } else {
      self.cancel_link_preview()
    }
  })
  self.view.listen_semantic_dom("contextmenu", event => {
    guard self.is_current() &&
      event.to_mouse_event() is Some(mouse) &&
      self.target_at(
        mouse.get_client_x().to_double(),
        mouse.get_client_y().to_double(),
      )
      is Some(target) else {
      return
    }
    if self.show_context_menu(
        target,
        mouse.get_client_x().to_double(),
        mouse.get_client_y().to_double(),
      ) {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  self.view.listen_semantic_dom("mousedown", event => {
    guard self.is_current() && event.to_mouse_event() is Some(mouse) else {
      return
    }
    let standard = @base_browser.StandardMouseEvent(mouse)
    guard standard.left_button && standard.detail <= 1 else { return }
    self.viewer.focus()
    self.mouse_down_target = self.target_at(
      mouse.get_client_x().to_double(),
      mouse.get_client_y().to_double(),
    )
    self.last_target = self.mouse_down_target
  })
  self.view.listen_semantic_dom("mouseup", event => {
    guard self.is_current() && event.to_mouse_event() is Some(mouse) else {
      return
    }
    let standard = @base_browser.StandardMouseEvent(mouse)
    let target = self.target_at(
      mouse.get_client_x().to_double(),
      mouse.get_client_y().to_double(),
    )
    let down = self.mouse_down_target
    self.mouse_down_target = None
    guard standard.left_button &&
      standard.detail <= 1 &&
      markdown_viewer_definition_modifier_is_active(
        standard.ctrl_key,
        standard.meta_key,
        standard.alt_key,
        standard.shift_key,
      ) &&
      down is Some(down) &&
      target is Some(target) &&
      down.same(target) &&
      self.target_is_current(target) else {
      return
    }
    self.last_target = Some(target)
    self.run_definition(
      target,
      @goto_symbol.SymbolNavigationActionConfig::link(),
    )
    event.prevent_default()
    event.stop_propagation()
  })
}

///|
fn MarkdownViewerWidgetDefinitionBridge::activate(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  guard !self.disposed && !self.active else { return }
  self.active = true
  self.listen(self.view.root(), "keydown", event => {
    guard self.is_current() &&
      @base_browser.event_target_is(event, self.view.root()) &&
      event.to_keyboard_event() is Some(keyboard) else {
      return
    }
    if markdown_viewer_definition_modifier_key(keyboard.key()) {
      match self.last_target {
        Some(target) if markdown_viewer_definition_modifier_is_active(
            keyboard.ctrl_key(),
            keyboard.meta_key(),
            keyboard.alt_key(),
            keyboard.shift_key(),
          ) => self.start_link_preview(target)
        _ => self.cancel_link_preview()
      }
      return
    }
    let handled = if keyboard.key() == "F12" {
      if keyboard.alt_key() && !keyboard.shift_key() {
        self.run_command("editor.action.peekDefinition")
        true
      } else if keyboard.shift_key() && !keyboard.alt_key() {
        self.run_command("editor.action.goToReferences")
        true
      } else if !keyboard.alt_key() && !keyboard.shift_key() {
        self.run_command("editor.action.revealDefinition")
        true
      } else {
        false
      }
    } else if keyboard.key() == "ContextMenu" ||
      (keyboard.key() == "F10" && keyboard.shift_key()) {
      self.show_keyboard_context_menu()
    } else {
      false
    }
    if handled {
      event.prevent_default()
      event.stop_propagation()
    }
  })
  self.listen(self.view.root(), "keyup", event => {
    guard event.to_keyboard_event() is Some(keyboard) else { return }
    if markdown_viewer_definition_modifier_key(keyboard.key()) {
      self.cancel_link_preview()
    }
  })
  self.listen(self.view.root(), "mouseleave", _ => self.cancel_link_preview())
  self.listen(self.view.root(), "blur", _ => self.cancel_link_preview())
  self.listen(self.view.viewport(), "scroll", _ => {
    self.cancel_link_preview()
    self.hide_context_menu()
  })
  self.bind_semantic_dom()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::show_message(
  self : MarkdownViewerWidgetDefinitionBridge,
  message : String,
) -> Unit {
  if message.is_empty() {
    self.view.root().remove_attribute("data-navigation-message")
  } else {
    self.view.root().set_attribute("data-navigation-message", message)
  }
}

///|
async fn MarkdownViewerWidgetDefinitionBridge::open_location(
  self : MarkdownViewerWidgetDefinitionBridge,
  location : @language.Location,
  mode : @navigation_api.OpenLocationMode,
) -> Bool noraise {
  guard self.is_current() else { return false }
  if mode == Current && self.model.uri.to_string() == location.uri.to_string() {
    let range = self.model.validate_range(location.range)
    self.view.reveal_source_offset(
      self.model.get_offset_at(range.get_start_position()),
      "center",
    )
    self.viewer.focus()
    return true
  }
  match self.viewer.services.location_opener() {
    Some(opener) =>
      opener.open({ source_viewer_id: self.viewer.get_id(), location, mode, })
    None => false
  }
}

///|
fn MarkdownViewerWidgetDefinitionBridge::open_in_peek(
  self : MarkdownViewerWidgetDefinitionBridge,
  anchor : @goto_symbol.SymbolNavigationAnchor,
  mode : @references.ReferencesPeekMode,
  locations : Array[@language.Location],
) -> Bool {
  guard self.anchor_is_current(anchor) && self.controller is Some(controller) else {
    return false
  }
  controller.toggle_locations(anchor, mode, locations)
}

///|
fn MarkdownViewerWidgetDefinitionBridge::mount_peek(
  self : MarkdownViewerWidgetDefinitionBridge,
  root : @rdom.Element,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> @references_browser.ReferencesPeekMount? {
  guard self.anchor_is_current(anchor) else { return None }
  root.set_attribute(
    "class", "moonbit-viewer-references-peek moonbit-viewer-references-peek-overlay",
  )
  self.view.overlay_mount().append_child(root.as_node())
  let disposed = Ref(false)
  Some(
    ReferencesPeekMount(
      is_current=() => {
        !disposed.val &&
        self.anchor_is_current(anchor) &&
        @base_browser.element_contains(self.view.overlay_mount(), root)
      },
      dispose=() => {
        if !disposed.val {
          disposed.val = true
          @base_browser.remove_element(root)
        }
      },
    ),
  )
}

///|
fn MarkdownViewerWidgetDefinitionBridge::reveal_anchor(
  self : MarkdownViewerWidgetDefinitionBridge,
  anchor : @goto_symbol.SymbolNavigationAnchor,
) -> Unit {
  guard self.anchor_is_current(anchor) else { return }
  self.view.reveal_source_offset(
    self.model.get_offset_at(anchor.position()),
    "center",
  )
}

///|
fn MarkdownViewerWidgetDefinitionBridge::before_projection_replaced(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.surface_generation += 1
  self.navigation_action.cancel()
  self.link_resolver.cancel()
  if self.controller is Some(controller) {
    controller.close(restore_focus=false)
  }
  self.reset_link()
  self.hide_context_menu()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::after_projection_replaced(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.bind_semantic_dom()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::layout_changed(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  guard !self.disposed else { return }
  self.cancel_link_preview()
  self.hide_context_menu()
}

///|
fn MarkdownViewerWidgetDefinitionBridge::dispose(
  self : MarkdownViewerWidgetDefinitionBridge,
) -> Unit {
  if self.disposed {
    return
  }
  self.disposed = true
  self.active = false
  self.navigation_action.dispose()
  self.link_resolver.dispose()
  if self.controller is Some(controller) {
    controller.dispose()
  }
  self.reset_link()
  if self.context_menu is Some(widget) {
    widget.dispose()
  }
  self.context_menu = None
  while self.listeners.length() > 0 {
    self.listeners.remove(self.listeners.length() - 1).dispose()
  }
}
