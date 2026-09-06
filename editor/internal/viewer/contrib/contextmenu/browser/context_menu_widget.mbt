// Behavior port of the selected HTML menu surface from
// `vscode/src/vs/platform/contextview/browser/contextMenuHandler.ts`,
// `base/browser/ui/contextview/contextview.ts`, and
// `base/browser/ui/menu/menu.ts` at the repository-pinned vscode revision.
//
// The root Viewer owns command policy and passes a concrete immutable entry
// tree. This package owns only browser DOM, focus, temporary listeners,
// submenu timers, viewport placement, and disposal.

///|
pub(all) struct ContextMenuWidgetCallbacks {
  on_action : (String) -> Unit
  on_hide : (Bool) -> Unit
}

///|
priv struct ContextMenuItemNode {
  wrapper : @rdom.Element
  action : @rdom.Element
}

///|
priv struct ContextMenuSubmenuView {
  container : @rdom.Element
  entries : Array[ContextMenuEntry]
  item_nodes : Array[ContextMenuItemNode?]
  listeners : Array[@base_common.Disposable]
  parent_entry_index : Int
  mut focused_entry_index : Int
}

///|
/// One reusable browser menu owned for a Viewer's entire contribution
/// lifetime. Each `show` replaces the transient entry DOM and listeners.
struct ContextMenuWidget {
  container : @rdom.Element
  mut menu : @rdom.Element
  callbacks : ContextMenuWidgetCallbacks
  mut entries : Array[ContextMenuEntry]
  mut item_nodes : Array[ContextMenuItemNode?]
  show_listeners : Array[@base_common.Disposable]
  mut submenu : ContextMenuSubmenuView?
  mut submenu_show_timer : @base_common.Disposable?
  mut submenu_hide_timer : @base_common.Disposable?
  mut focus_to_return : @rdom.Element?
  mut focused_entry_index : Int
  mut theme : String
  mut visible : Bool
  mut disposed : Bool
}

///|
pub fn ContextMenuWidget::ContextMenuWidget(
  callbacks : ContextMenuWidgetCallbacks,
) -> ContextMenuWidget {
  let document = @rdom.document()
  let container = document.create_element("div")
  container.set_attribute(
    "class", "context-view fixed monaco-menu-container moonbit-context-menu",
  )
  container.set_attribute("data-theme", "dark")
  container.set_attribute("tabindex", "-1")
  container.set_attribute("aria-hidden", "true")
  let menu = document.create_element("div")
  menu.set_attribute("class", "monaco-menu")
  let action_bar = document.create_element("div")
  action_bar.set_attribute("class", "monaco-action-bar vertical")
  action_bar.set_attribute("role", "menu")
  action_bar.set_attribute("aria-label", "Editor Context Menu")
  action_bar.set_attribute("tabindex", "-1")
  let actions = document.create_element("div")
  actions.set_attribute("class", "actions-container")
  action_bar.append_child(actions.as_node())
  menu.append_child(action_bar.as_node())
  container.append_child(menu.as_node())
  {
    container,
    menu,
    callbacks,
    entries: [],
    item_nodes: [],
    show_listeners: [],
    submenu: None,
    submenu_show_timer: None,
    submenu_hide_timer: None,
    focus_to_return: None,
    focused_entry_index: -1,
    theme: "dark",
    visible: false,
    disposed: false,
  }
}

///|
pub fn ContextMenuWidget::is_visible(self : ContextMenuWidget) -> Bool {
  self.visible && !self.disposed
}

///|
/// Shows a nonempty menu at a visual-viewport coordinate. Returns false when
/// disposed, empty, or the owner document has no body.
pub fn ContextMenuWidget::show(
  self : ContextMenuWidget,
  entries : Array[ContextMenuEntry],
  client_x : Double,
  client_y : Double,
  theme : String,
  theme_source? : @rdom.Element,
  auto_select_first? : Bool = false,
) -> Bool {
  if self.disposed {
    return false
  }
  if self.visible {
    self.hide(was_cancelled=true)
  }
  if entries.length() == 0 {
    return false
  }
  self.entries = entries.copy()
  self.focus_to_return = if context_menu_has_active_element(self.container) {
    Some(context_menu_active_element(self.container))
  } else {
    None
  }
  self.focused_entry_index = -1
  self.theme = theme
  self.container.set_attribute("data-theme", theme)
  if theme_source is Some(source) {
    copy_context_menu_theme(self.container, source)
  }
  self.rebuild_root_menu()
  self.install_show_listeners()
  self.container.set_attribute("aria-hidden", "false")
  @base_browser.set_style_property(self.container, "visibility", "hidden")
  @base_browser.set_style_property(self.container, "left", "0px")
  @base_browser.set_style_property(self.container, "top", "0px")
  if !append_context_menu_to_body(self.container) {
    self.clear_show_state()
    return false
  }
  self.visible = true
  let rect = self.container.get_bounding_client_rect()
  let viewport = context_menu_viewport_size(self.container)
  let position = fit_root_context_menu(
    { x: client_x, y: client_y, },
    { width: rect.get_width(), height: rect.get_height(), },
    viewport,
  )
  set_context_menu_position(self.container, position)
  @base_browser.set_style_property(self.container, "visibility", "visible")
  if auto_select_first {
    self.focus_relative_root(1)
  } else {
    @base_browser.focus_prevent_scroll(self.container)
  }
  true
}

///|
/// Hides the menu exactly once. `was_cancelled=false` is used for action
/// execution; all dismissal paths report cancellation.
pub fn ContextMenuWidget::hide(
  self : ContextMenuWidget,
  was_cancelled? : Bool = true,
) -> Unit {
  if !self.visible {
    return
  }
  let restore_focus = self.menu_owns_focus()
  self.visible = false
  self.cancel_submenu_timers()
  self.close_submenu(restore_parent_focus=false)
  self.dispose_show_listeners()
  @base_browser.remove_element(self.container)
  self.container.set_attribute("aria-hidden", "true")
  self.container.set_inner_html("")
  self.rebuild_menu_shell()
  self.entries = []
  self.item_nodes = []
  self.focused_entry_index = -1
  if restore_focus && self.focus_to_return is Some(element) {
    @base_browser.focus_prevent_scroll(element)
  }
  self.focus_to_return = None
  (self.callbacks.on_hide)(was_cancelled)
}

///|
pub fn ContextMenuWidget::dispose(self : ContextMenuWidget) -> Unit {
  if self.disposed {
    return
  }
  self.hide(was_cancelled=true)
  self.disposed = true
  self.cancel_submenu_timers()
  self.dispose_show_listeners()
  self.close_submenu(restore_parent_focus=false)
  @base_browser.remove_element(self.container)
  self.container.set_inner_html("")
  self.entries = []
  self.item_nodes = []
  self.focus_to_return = None
}

///|
fn ContextMenuWidget::rebuild_menu_shell(self : ContextMenuWidget) -> Unit {
  let document = @rdom.document()
  let menu = document.create_element("div")
  menu.set_attribute("class", "monaco-menu")
  let action_bar = document.create_element("div")
  action_bar.set_attribute("class", "monaco-action-bar vertical")
  action_bar.set_attribute("role", "menu")
  action_bar.set_attribute("aria-label", "Editor Context Menu")
  action_bar.set_attribute("tabindex", "-1")
  let actions = document.create_element("div")
  actions.set_attribute("class", "actions-container")
  action_bar.append_child(actions.as_node())
  menu.append_child(action_bar.as_node())
  self.container.append_child(menu.as_node())
  self.menu = menu
}

///|
fn ContextMenuWidget::root_actions_node(
  self : ContextMenuWidget,
) -> @rdom.Element {
  self.menu.get_children()[0].get_children()[0]
}

///|
fn ContextMenuWidget::rebuild_root_menu(self : ContextMenuWidget) -> Unit {
  self.root_actions_node().set_inner_html("")
  self.item_nodes = []
  for index, entry in self.entries {
    match entry {
      ContextMenuSeparator => {
        self
        .root_actions_node()
        .append_child(build_context_menu_separator().as_node())
        self.item_nodes.push(None)
      }
      ContextMenuAction(..) | ContextMenuSubmenu(..) => {
        let node = build_context_menu_item(entry)
        self.install_root_item_listeners(index, entry, node)
        self.root_actions_node().append_child(node.wrapper.as_node())
        self.item_nodes.push(Some(node))
      }
    }
  }
}

///|
fn ContextMenuWidget::install_root_item_listeners(
  self : ContextMenuWidget,
  index : Int,
  entry : ContextMenuEntry,
  node : ContextMenuItemNode,
) -> Unit {
  self.listen_show(node.action, "mouseenter", _event => {
    guard self.visible else { return }
    self.focus_root_entry(index, pointer_driven=true)
    match entry {
      ContextMenuSubmenu(..) => self.schedule_open_submenu(index)
      _ => self.schedule_close_submenu()
    }
  })
  self.listen_show(node.action, "click", event => {
    event.prevent_default()
    event.stop_propagation()
    guard self.visible else { return }
    match entry {
      ContextMenuAction(id~, ..) => self.run_action(id)
      ContextMenuSubmenu(..) => self.open_submenu(index, focus_first=true)
      ContextMenuSeparator => ()
    }
  })
}

///|
fn ContextMenuWidget::install_show_listeners(self : ContextMenuWidget) -> Unit {
  self.listen_show(self.container, "contextmenu", event => {
    event.prevent_default()
    event.stop_propagation()
  })
  let listen_document = (event_type : String, listener : @rdom.Listener) => {
    @rdom.document().add_event_listener(event_type, listener)
    self.show_listeners.push(
      @base_common.Disposable::from(() => {
        @rdom.document().remove_event_listener(event_type, listener)
      }),
    )
  }
  let hide_when_outside : @rdom.Listener = event => {
    guard self.visible else { return }
    if !context_menu_event_inside(event, self.container) &&
      !self.event_inside_submenu(event) {
      self.hide(was_cancelled=true)
    }
  }
  // An eligible editor target stops propagation and replaces this menu in its
  // own handler. A native-fallback target does not, so the document event
  // closes the stale custom menu before the browser presents its own surface.
  listen_document("contextmenu", hide_when_outside)
  self.listen_show(self.container, "keydown", event => {
    self.handle_keydown(event)
  })
  listen_document("mousedown", event => {
    guard self.visible else { return }
    if event.to_mouse_event() is Some(mouse) && mouse.get_button() == 2 {
      return
    }
    hide_when_outside(event)
  })
  listen_document("focusin", hide_when_outside)
  let blur_listener = () => self.hide(was_cancelled=true)
  context_menu_add_window_blur_listener(self.container, blur_listener)
  self.show_listeners.push(
    @base_common.Disposable::from(() => {
      context_menu_remove_window_blur_listener(self.container, blur_listener)
    }),
  )
}

///|
fn ContextMenuWidget::run_focused_root_entry(self : ContextMenuWidget) -> Unit {
  guard self.focused_entry_index >= 0 &&
    self.focused_entry_index < self.entries.length() else {
    return
  }
  match self.entries[self.focused_entry_index] {
    ContextMenuAction(id~, ..) => self.run_action(id)
    ContextMenuSubmenu(..) =>
      self.open_submenu(self.focused_entry_index, focus_first=true)
    ContextMenuSeparator => ()
  }
}

///|
fn ContextMenuWidget::run_focused_submenu_entry(
  self : ContextMenuWidget,
) -> Unit {
  guard self.submenu is Some(submenu) else { return }
  let index = submenu.focused_entry_index
  guard index >= 0 && index < submenu.entries.length() else { return }
  match submenu.entries[index] {
    ContextMenuAction(id~, ..) => self.run_action(id)
    _ => ()
  }
}

///|
fn ContextMenuWidget::run_action(
  self : ContextMenuWidget,
  command_id : String,
) -> Unit {
  self.hide(was_cancelled=false)
  (self.callbacks.on_action)(command_id)
}

///|
fn ContextMenuWidget::focus_root_entry(
  self : ContextMenuWidget,
  index : Int,
  pointer_driven~ : Bool,
) -> Unit {
  guard index >= 0 && index < self.item_nodes.length() else { return }
  guard self.item_nodes[index] is Some(node) else { return }
  self.focused_entry_index = index
  update_context_menu_focus(self.item_nodes, index, pointer_driven)
  @base_browser.focus_prevent_scroll(node.action)
  if !self.root_entry_is_submenu(index) && self.submenu is Some(_) {
    self.schedule_close_submenu()
  }
}

///|
fn ContextMenuWidget::focus_relative_root(
  self : ContextMenuWidget,
  direction : Int,
) -> Unit {
  let next = next_context_menu_item_index(
    self.item_nodes,
    self.focused_entry_index,
    direction,
  )
  if next >= 0 {
    self.focus_root_entry(next, pointer_driven=false)
  }
}

///|
fn ContextMenuWidget::focus_root_boundary(
  self : ContextMenuWidget,
  first~ : Bool,
) -> Unit {
  let index = context_menu_boundary_index(self.item_nodes, first)
  if index >= 0 {
    self.focus_root_entry(index, pointer_driven=false)
  }
}

///|
fn ContextMenuWidget::root_entry_is_submenu(
  self : ContextMenuWidget,
  index : Int,
) -> Bool {
  index >= 0 &&
  index < self.entries.length() &&
  self.entries[index] is ContextMenuSubmenu(..)
}

///|
fn ContextMenuWidget::schedule_open_submenu(
  self : ContextMenuWidget,
  index : Int,
) -> Unit {
  self.cancel_submenu_show_timer()
  self.cancel_submenu_hide_timer()
  self.submenu_show_timer = Some(
    @base_browser.schedule_timeout(
      () => {
        self.submenu_show_timer = None
        if self.visible && self.focused_entry_index == index {
          self.open_submenu(index, focus_first=false)
        }
      },
      250,
    ),
  )
}

///|
fn ContextMenuWidget::schedule_close_submenu(self : ContextMenuWidget) -> Unit {
  guard self.submenu is Some(_) else { return }
  self.cancel_submenu_show_timer()
  self.cancel_submenu_hide_timer()
  self.submenu_hide_timer = Some(
    @base_browser.schedule_timeout(
      () => {
        self.submenu_hide_timer = None
        if self.visible && !self.submenu_owns_focus() {
          self.close_submenu(restore_parent_focus=false)
        }
      },
      750,
    ),
  )
}

///|
fn ContextMenuWidget::open_submenu(
  self : ContextMenuWidget,
  index : Int,
  focus_first~ : Bool,
) -> Unit {
  guard self.visible && index >= 0 && index < self.entries.length() else {
    return
  }
  guard self.entries[index] is ContextMenuSubmenu(entries~, ..) else { return }
  guard entries.length() > 0 else { return }
  self.cancel_submenu_timers()
  match self.submenu {
    Some(submenu) if submenu.parent_entry_index == index => {
      if focus_first {
        self.focus_submenu_boundary(first=true)
      }
      return
    }
    Some(_) => self.close_submenu(restore_parent_focus=false)
    None => ()
  }
  guard self.item_nodes[index] is Some(parent_node) else { return }
  parent_node.action.set_attribute("aria-expanded", "true")
  let submenu = build_context_submenu(entries, index)
  submenu.container.set_attribute("data-theme", self.theme)
  copy_context_menu_theme(submenu.container, self.container)
  self.submenu = Some(submenu)
  self.install_submenu_listeners(submenu)
  if !append_context_menu_to_body(submenu.container) {
    self.close_submenu(restore_parent_focus=false)
    return
  }
  let rect = submenu.container.get_bounding_client_rect()
  let parent = parent_node.wrapper.get_bounding_client_rect()
  let position = fit_submenu_context_menu(
    {
      left: parent.get_left(),
      top: parent.get_top(),
      right: parent.get_right(),
      bottom: parent.get_bottom(),
    },
    { width: rect.get_width(), height: rect.get_height(), },
    context_menu_viewport_size(submenu.container),
  )
  set_context_menu_position(submenu.container, position)
  if focus_first {
    self.focus_submenu_boundary(first=true)
  }
}

///|
fn ContextMenuWidget::install_submenu_listeners(
  self : ContextMenuWidget,
  submenu : ContextMenuSubmenuView,
) -> Unit {
  listen_context_submenu(submenu, submenu.container, "mouseenter", _ => {
    self.cancel_submenu_hide_timer()
  })
  listen_context_submenu(submenu, submenu.container, "mouseleave", _ => {
    self.schedule_close_submenu()
  })
  listen_context_submenu(submenu, submenu.container, "contextmenu", event => {
    event.prevent_default()
    event.stop_propagation()
  })
  listen_context_submenu(submenu, submenu.container, "keydown", event => {
    self.handle_keydown(event)
  })
  for index, entry in submenu.entries {
    guard submenu.item_nodes[index] is Some(node) else { continue }
    listen_context_submenu(submenu, node.action, "mouseenter", _ => {
      guard self.visible else { return }
      self.focus_submenu_entry(index, pointer_driven=true)
    })
    listen_context_submenu(submenu, node.action, "click", event => {
      event.prevent_default()
      event.stop_propagation()
      guard self.visible else { return }
      match entry {
        ContextMenuAction(id~, ..) => self.run_action(id)
        _ => ()
      }
    })
  }
}

///|
fn ContextMenuWidget::handle_keydown(
  self : ContextMenuWidget,
  event : @rdom.Event,
) -> Unit {
  event.stop_propagation()
  guard self.visible && event.to_keyboard_event() is Some(keyboard) else {
    return
  }
  let key = keyboard.key()
  match key {
    "Escape" | "Tab" => {
      event.prevent_default()
      self.hide(was_cancelled=true)
    }
    "ArrowDown" => {
      event.prevent_default()
      if self.submenu_owns_focus() {
        self.focus_relative_submenu(1)
      } else {
        self.focus_relative_root(1)
      }
    }
    "ArrowUp" => {
      event.prevent_default()
      if self.submenu_owns_focus() {
        self.focus_relative_submenu(-1)
      } else {
        self.focus_relative_root(-1)
      }
    }
    "Home" | "PageUp" => {
      event.prevent_default()
      if self.submenu_owns_focus() {
        self.focus_submenu_boundary(first=true)
      } else {
        self.focus_root_boundary(first=true)
      }
    }
    "End" | "PageDown" => {
      event.prevent_default()
      if self.submenu_owns_focus() {
        self.focus_submenu_boundary(first=false)
      } else {
        self.focus_root_boundary(first=false)
      }
    }
    "ArrowRight" =>
      if !self.submenu_owns_focus() &&
        self.root_entry_is_submenu(self.focused_entry_index) {
        event.prevent_default()
        self.open_submenu(self.focused_entry_index, focus_first=true)
      }
    "ArrowLeft" =>
      if self.submenu is Some(_) {
        event.prevent_default()
        self.close_submenu(restore_parent_focus=true)
      }
    "Enter" | " " | "Spacebar" => {
      event.prevent_default()
      if self.submenu_owns_focus() {
        self.run_focused_submenu_entry()
      } else {
        self.run_focused_root_entry()
      }
    }
    _ => ()
  }
}

///|
fn ContextMenuWidget::focus_submenu_entry(
  self : ContextMenuWidget,
  index : Int,
  pointer_driven~ : Bool,
) -> Unit {
  guard self.submenu is Some(submenu) else { return }
  guard index >= 0 && index < submenu.item_nodes.length() else { return }
  guard submenu.item_nodes[index] is Some(node) else { return }
  submenu.focused_entry_index = index
  update_context_menu_focus(submenu.item_nodes, index, pointer_driven)
  @base_browser.focus_prevent_scroll(node.action)
}

///|
fn ContextMenuWidget::focus_relative_submenu(
  self : ContextMenuWidget,
  direction : Int,
) -> Unit {
  guard self.submenu is Some(submenu) else { return }
  let next = next_context_menu_item_index(
    submenu.item_nodes,
    submenu.focused_entry_index,
    direction,
  )
  if next >= 0 {
    self.focus_submenu_entry(next, pointer_driven=false)
  }
}

///|
fn ContextMenuWidget::focus_submenu_boundary(
  self : ContextMenuWidget,
  first~ : Bool,
) -> Unit {
  guard self.submenu is Some(submenu) else { return }
  let index = context_menu_boundary_index(submenu.item_nodes, first)
  if index >= 0 {
    self.focus_submenu_entry(index, pointer_driven=false)
  }
}

///|
fn ContextMenuWidget::close_submenu(
  self : ContextMenuWidget,
  restore_parent_focus~ : Bool,
) -> Unit {
  guard self.submenu is Some(submenu) else { return }
  self.cancel_submenu_timers()
  if submenu.parent_entry_index >= 0 &&
    submenu.parent_entry_index < self.item_nodes.length() {
    if self.item_nodes[submenu.parent_entry_index] is Some(parent) {
      parent.action.set_attribute("aria-expanded", "false")
    }
  }
  dispose_context_submenu(submenu)
  self.submenu = None
  if restore_parent_focus {
    self.focus_root_entry(submenu.parent_entry_index, pointer_driven=false)
  }
}

///|
fn ContextMenuWidget::submenu_owns_focus(self : ContextMenuWidget) -> Bool {
  match self.submenu {
    Some(submenu) =>
      @base_browser.element_contains_active_element(submenu.container)
    None => false
  }
}

///|
fn ContextMenuWidget::menu_owns_focus(self : ContextMenuWidget) -> Bool {
  @base_browser.element_contains_active_element(self.container) ||
  self.submenu_owns_focus()
}

///|
fn ContextMenuWidget::event_inside_submenu(
  self : ContextMenuWidget,
  event : @rdom.Event,
) -> Bool {
  match self.submenu {
    Some(submenu) => context_menu_event_inside(event, submenu.container)
    None => false
  }
}

///|
fn ContextMenuWidget::cancel_submenu_show_timer(
  self : ContextMenuWidget,
) -> Unit {
  if self.submenu_show_timer is Some(timer) {
    timer.dispose()
  }
  self.submenu_show_timer = None
}

///|
fn ContextMenuWidget::cancel_submenu_hide_timer(
  self : ContextMenuWidget,
) -> Unit {
  if self.submenu_hide_timer is Some(timer) {
    timer.dispose()
  }
  self.submenu_hide_timer = None
}

///|
fn ContextMenuWidget::cancel_submenu_timers(self : ContextMenuWidget) -> Unit {
  self.cancel_submenu_show_timer()
  self.cancel_submenu_hide_timer()
}

///|
fn ContextMenuWidget::listen_show(
  self : ContextMenuWidget,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  self.show_listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn ContextMenuWidget::dispose_show_listeners(self : ContextMenuWidget) -> Unit {
  while self.show_listeners.length() > 0 {
    self.show_listeners.remove(self.show_listeners.length() - 1).dispose()
  }
}

///|
fn ContextMenuWidget::clear_show_state(self : ContextMenuWidget) -> Unit {
  self.dispose_show_listeners()
  self.container.set_attribute("aria-hidden", "true")
  self.container.set_inner_html("")
  self.rebuild_menu_shell()
  self.entries = []
  self.item_nodes = []
  self.focus_to_return = None
  self.focused_entry_index = -1
}

///|
fn build_context_submenu(
  entries : Array[ContextMenuEntry],
  parent_entry_index : Int,
) -> ContextMenuSubmenuView {
  let document = @rdom.document()
  let container = document.create_element("div")
  container.set_attribute(
    "class", "context-view fixed monaco-menu-container moonbit-context-menu moonbit-context-submenu",
  )
  container.set_attribute("role", "presentation")
  let menu = document.create_element("div")
  menu.set_attribute("class", "monaco-menu")
  let action_bar = document.create_element("div")
  action_bar.set_attribute("class", "monaco-action-bar vertical")
  action_bar.set_attribute("role", "menu")
  action_bar.set_attribute("aria-label", "Peek")
  action_bar.set_attribute("tabindex", "-1")
  let actions = document.create_element("div")
  actions.set_attribute("class", "actions-container")
  let item_nodes : Array[ContextMenuItemNode?] = []
  for entry in entries {
    match entry {
      ContextMenuSeparator => {
        actions.append_child(build_context_menu_separator().as_node())
        item_nodes.push(None)
      }
      ContextMenuAction(..) | ContextMenuSubmenu(..) => {
        let node = build_context_menu_item(entry)
        actions.append_child(node.wrapper.as_node())
        item_nodes.push(Some(node))
      }
    }
  }
  action_bar.append_child(actions.as_node())
  menu.append_child(action_bar.as_node())
  container.append_child(menu.as_node())
  {
    container,
    entries: entries.copy(),
    item_nodes,
    listeners: [],
    parent_entry_index,
    focused_entry_index: -1,
  }
}

///|
fn dispose_context_submenu(submenu : ContextMenuSubmenuView) -> Unit {
  while submenu.listeners.length() > 0 {
    submenu.listeners.remove(submenu.listeners.length() - 1).dispose()
  }
  @base_browser.remove_element(submenu.container)
  submenu.container.set_inner_html("")
}

///|
fn listen_context_submenu(
  submenu : ContextMenuSubmenuView,
  target : @rdom.Element,
  event_type : String,
  listener : @rdom.Listener,
) -> Unit {
  target.add_event_listener(event_type, listener)
  submenu.listeners.push(
    @base_common.Disposable::from(() => {
      target.remove_event_listener(event_type, listener)
    }),
  )
}

///|
fn build_context_menu_item(entry : ContextMenuEntry) -> ContextMenuItemNode {
  let document = @rdom.document()
  let wrapper = document.create_element("div")
  wrapper.set_attribute("class", "action-item")
  wrapper.set_attribute("role", "presentation")
  let action = document.create_element("div")
  action.set_attribute("class", "action-menu-item")
  action.set_attribute("role", "menuitem")
  action.set_attribute("tabindex", "-1")
  let label = document.create_element("span")
  label.set_attribute("class", "action-label")
  match entry {
    ContextMenuAction(id~, label=title, keybinding_label~) => {
      action.set_attribute("data-context-menu-command", id)
      label.append_child(document.create_text_node(title).as_node())
      action.append_child(label.as_node())
      if keybinding_label is Some(binding) {
        let keybinding = document.create_element("span")
        keybinding.set_attribute("class", "keybinding")
        keybinding.set_attribute("aria-hidden", "true")
        keybinding.append_child(document.create_text_node(binding).as_node())
        action.append_child(keybinding.as_node())
      }
    }
    ContextMenuSubmenu(label=title, ..) => {
      action.set_attribute("aria-haspopup", "menu")
      action.set_attribute("aria-expanded", "false")
      label.append_child(document.create_text_node(title).as_node())
      action.append_child(label.as_node())
      let indicator = document.create_element("span")
      indicator.set_attribute(
        "class", "submenu-indicator codicon codicon-chevron-right",
      )
      indicator.set_attribute("aria-hidden", "true")
      action.append_child(indicator.as_node())
    }
    ContextMenuSeparator => ()
  }
  wrapper.append_child(action.as_node())
  { wrapper, action, }
}

///|
fn build_context_menu_separator() -> @rdom.Element {
  let document = @rdom.document()
  let wrapper = document.create_element("div")
  wrapper.set_attribute("class", "action-item disabled")
  wrapper.set_attribute("role", "separator")
  let separator = document.create_element("span")
  separator.set_attribute("class", "action-label separator")
  separator.set_attribute("aria-hidden", "true")
  wrapper.append_child(separator.as_node())
  wrapper
}

///|
fn update_context_menu_focus(
  nodes : Array[ContextMenuItemNode?],
  focused_index : Int,
  pointer_driven : Bool,
) -> Unit {
  for index, maybe_node in nodes {
    if maybe_node is Some(node) {
      let focused = index == focused_index
      node.wrapper.set_attribute(
        "class",
        if focused {
          "action-item focused"
        } else {
          "action-item"
        },
      )
      node.action.set_attribute(
        "data-pointer-focus",
        (focused && pointer_driven).to_string(),
      )
    }
  }
}

///|
fn next_context_menu_item_index(
  nodes : Array[ContextMenuItemNode?],
  current : Int,
  direction : Int,
) -> Int {
  guard nodes.length() > 0 else { return -1 }
  let step = if direction < 0 { -1 } else { 1 }
  for _ in 0..<nodes.length(); index = current {
    let index = if index + step < 0 {
      nodes.length() - 1
    } else if index + step >= nodes.length() {
      0
    } else {
      index + step
    }
    if nodes[index] is Some(_) {
      break index
    }
    continue index
  } nobreak {
    -1
  }
}

///|
fn context_menu_boundary_index(
  nodes : Array[ContextMenuItemNode?],
  first : Bool,
) -> Int {
  match [ for index, node in nodes if node is Some(_) => index ] {
    [] => -1
    [head, ..] if first => head
    [.., last] => last
  }
}

///|
fn set_context_menu_position(
  element : @rdom.Element,
  position : ContextMenuPoint,
) -> Unit {
  @base_browser.set_style_property(
    element,
    "left",
    "\{position.x.to_string()}px",
  )
  @base_browser.set_style_property(
    element,
    "top",
    "\{position.y.to_string()}px",
  )
}

///|
fn context_menu_viewport_size(element : @rdom.Element) -> ContextMenuSize {
  {
    width: context_menu_viewport_width(element),
    height: context_menu_viewport_height(element),
  }
}

///|
extern "js" fn append_context_menu_to_body(element : @rdom.Element) -> Bool =
  #| (element) => {
  #|   const body = element?.ownerDocument?.body ?? globalThis.document?.body;
  #|   if (!body) return false;
  #|   body.appendChild(element);
  #|   return true;
  #| }

///|
extern "js" fn context_menu_active_element(
  element : @rdom.Element,
) -> @rdom.Element =
  #| (element) => element?.ownerDocument?.activeElement ?? element

///|
extern "js" fn context_menu_has_active_element(element : @rdom.Element) -> Bool =
  #| (element) => Boolean(element?.ownerDocument?.activeElement)

///|
extern "js" fn context_menu_event_inside(
  event : @rdom.Event,
  element : @rdom.Element,
) -> Bool =
  #| (event, element) => {
  #|   const target = event?.target;
  #|   return Boolean(target && element?.contains?.(target));
  #| }

///|
extern "js" fn context_menu_viewport_width(element : @rdom.Element) -> Double =
  #| (element) => {
  #|   const doc = element?.ownerDocument;
  #|   const win = doc?.defaultView ?? globalThis.window;
  #|   return win?.visualViewport?.width
  #|     ?? win?.innerWidth
  #|     ?? doc?.documentElement?.clientWidth
  #|     ?? doc?.body?.clientWidth
  #|     ?? 0;
  #| }

///|
extern "js" fn context_menu_viewport_height(element : @rdom.Element) -> Double =
  #| (element) => {
  #|   const doc = element?.ownerDocument;
  #|   const win = doc?.defaultView ?? globalThis.window;
  #|   return win?.visualViewport?.height
  #|     ?? win?.innerHeight
  #|     ?? doc?.documentElement?.clientHeight
  #|     ?? doc?.body?.clientHeight
  #|     ?? 0;
  #| }

///|
extern "js" fn context_menu_add_window_blur_listener(
  element : @rdom.Element,
  listener : () -> Unit,
) -> Unit =
  #| (element, listener) => {
  #|   (element?.ownerDocument?.defaultView ?? globalThis.window)
  #|     ?.addEventListener?.('blur', listener);
  #| }

///|
extern "js" fn context_menu_remove_window_blur_listener(
  element : @rdom.Element,
  listener : () -> Unit,
) -> Unit =
  #| (element, listener) => {
  #|   (element?.ownerDocument?.defaultView ?? globalThis.window)
  #|     ?.removeEventListener?.('blur', listener);
  #| }

///|
/// Copies only the inherited theme tokens consumed by this detached body-level
/// overlay. `getComputedStyle` is the missing browser primitive; the token
/// list is presentation data, not command policy.
extern "js" fn copy_context_menu_theme(
  target : @rdom.Element,
  source : @rdom.Element,
) -> Unit =
  #| (target, source) => {
  #|   const win = source?.ownerDocument?.defaultView ?? globalThis.window;
  #|   if (!win?.getComputedStyle || !target?.style) return;
  #|   const style = win.getComputedStyle(source);
  #|   for (const name of [
  #|     '--vscode-menu-background',
  #|     '--vscode-menu-foreground',
  #|     '--vscode-menu-selectionBackground',
  #|     '--vscode-menu-selectionForeground',
  #|     '--vscode-menu-selectionBorder',
  #|     '--vscode-menu-separatorBackground',
  #|     '--vscode-menu-border',
  #|     '--vscode-shadow-lg',
  #|     '--vscode-widget-shadow',
  #|     '--vscode-cornerRadius-medium',
  #|     '--vscode-cornerRadius-large',
  #|     '--ui-font-family'
  #|   ]) {
  #|     const value = style.getPropertyValue(name);
  #|     if (value) target.style.setProperty(name, value);
  #|   }
  #| }
