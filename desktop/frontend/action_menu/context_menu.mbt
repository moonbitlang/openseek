// The application-shell context menu. Stable domain rows keep using
// `context_attrs`; this adjacent adapter owns ephemeral DOM context such as a
// text selection or a rendered link. Both paths share the same menu surface,
// focus behavior, positioning, and theme.

///|
pub(all) enum ClientPlatform {
  Web
  MacOS
  Windows
  Linux
} derive(Eq)

///|
pub(all) struct ContextInput {
  platform : ClientPlatform
  // Whether ordinary web links have a visible in-app Browser destination on
  // the current screen. This is a screen capability, not a platform fact.
  open_web_links_in_app : Bool
  // Reveal is intentionally local-window-only. A browser or a Desktop viewing
  // a remote host must not unexpectedly open a file manager on another device.
  reveal_files : Bool
} derive(Eq)

///|
pub(all) struct ContextActions {
  open_link : (String) -> @cmd.Cmd
  open_external_link : (String) -> @cmd.Cmd
  open_file : (String) -> @cmd.Cmd
  reveal_file : (String) -> @cmd.Cmd
}

///|
priv enum ContextTarget {
  NoTarget
  WebLink(String)
  EmailLink(url~ : String, address~ : String)
  FileLink(String)
} derive(Eq)

///|
priv struct ContextRequest {
  target : ContextTarget
  selected_text : String?
} derive(Eq)

///|
priv struct ContextOpen {
  request : ContextRequest
  x : Int
  y : Int
  restore_focus_id : String?
} derive(Eq)

///|
priv struct ContextState {
  open_context : ContextOpen?
} derive(Eq)

///|
priv enum ContextMsg {
  Requested(ContextRequest, Int, Int, String?)
  CloseContext
}

///|
const GlobalContextTarget : String = "app-context-menu"

///|
fn event_element(event : @dom.Event) -> @dom.Element? {
  match event.target().to_element() {
    Some(element) => Some(element)
    None => event.target().to_node().bind(node => node.get_parent_element())
  }
}

///|
fn selected_at(
  element : @dom.Element,
  x : Int,
  y : Int,
  keyboard : Bool,
) -> String? {
  guard browser_selection().to_option() is Some(selection) &&
    !selection.collapsed() &&
    selection.count() > 0 else {
    return None
  }
  let text = selection.text()
  guard !text.is_empty() else { return None }
  for index in 0..<selection.count() {
    let range = selection.range(index)
    if keyboard {
      let intersects : Bool = @js.Error_::wrap(() => {
        @js.Value::cast_from(range.intersects(element))
      }) catch {
        _ => false
      }
      if intersects {
        return Some(text)
      }
    }
    for rect in range.rects() {
      if x.to_double() >= rect.get_left() &&
        x.to_double() <= rect.get_right() &&
        y.to_double() >= rect.get_top() &&
        y.to_double() <= rect.get_bottom() {
        return Some(text)
      }
    }
  }
  None
}

///|
fn keyboard_anchor(element : @dom.Element) -> (Int, Int) {
  let rect = if browser_selection().to_option() is Some(selection) &&
    selection.count() > 0 {
    let rect = selection.range(0).bounds()
    if rect.get_width() > 0 || rect.get_height() > 0 {
      rect
    } else {
      element.get_bounding_client_rect()
    }
  } else {
    element.get_bounding_client_rect()
  }
  (
    @math.round(rect.get_left()).to_int(),
    @math.round(rect.get_bottom()).to_int(),
  )
}

///|
fn element_context(element : @dom.Element) -> ContextTarget {
  if element.closest("[data-context-file]") is Some(file) &&
    file.get_attribute("data-context-file") is Some(path) {
    return FileLink(path)
  }
  guard element.closest("a[href]") is Some(anchor) &&
    !anchor.has_attribute("download") else {
    return NoTarget
  }
  match anchor_protocol(anchor).to_lower() {
    "http:" | "https:" => WebLink(anchor_href(anchor))
    "mailto:" => {
      let href = anchor.get_attribute("href").unwrap_or(anchor_href(anchor))
      let raw = href[7:].split("?").next().unwrap_or(href[7:]).to_owned()
      let address = @js.Error_::wrap(() => {
        @js.Value::cast_from(decode_uri_component(raw))
      }) catch {
        _ => raw
      }
      EmailLink(url=anchor_href(anchor), address~)
    }
    _ => NoTarget
  }
}

///|
fn discard_temporary_focus(element : @dom.Element?) -> Unit {
  if element is Some(element) &&
    element.get_attribute("id") is Some(id) &&
    element.get_attribute(TemporaryFocusAttribute) == Some(id) {
    element.remove_attribute(TemporaryFocusAttribute)
    element.remove_attribute("id")
  }
}

///|
fn install_context_menu_listener(
  close : () -> Unit,
  open : (ContextRequest, String?, Int, Int) -> Unit,
) -> () -> Unit {
  let document = @dom.document()
  let mut remembered_selection : (Int, Int, String?)? = None
  let mut temporary_focus : @dom.Element? = None
  let mut next_focus_id = 0
  let remember_focus = () => {
    discard_temporary_focus(temporary_focus)
    temporary_focus = None
    guard document.get_active_element() is Some(active) &&
      active.to_html_element() is Some(_) &&
      !active.matches("body") else {
      return None
    }
    if active.get_attribute("id") is Some(id) && !id.is_empty() {
      return Some(id)
    }
    next_focus_id += 1
    let id = "app-context-focus:\{next_focus_id}"
    active.set_attribute("id", id)
    active.set_attribute(TemporaryFocusAttribute, id)
    temporary_focus = Some(active)
    Some(id)
  }
  let on_mouse_down : @dom.Listener = event => {
    guard event.to_mouse_event() is Some(mouse) &&
      mouse.get_button() == 2 &&
      event_element(event) is Some(element) else {
      return
    }
    let x = mouse.get_client_x()
    let y = mouse.get_client_y()
    remembered_selection = Some((x, y, selected_at(element, x, y, false)))
  }
  // Capture closes the previous menu even when another owner stops bubbling.
  let on_context_capture : @dom.Listener = _ => {
    discard_temporary_focus(temporary_focus)
    temporary_focus = None
    close()
  }
  // Other owners get first refusal through ordinary DOM bubbling.
  let on_context_menu : @dom.Listener = event => {
    guard !event.get_default_prevented() &&
      event_element(event) is Some(element) &&
      event.to_mouse_event() is Some(mouse) else {
      return
    }
    if element.closest("input, textarea, select, [contenteditable]")
      is Some(control) &&
      control.get_attribute("contenteditable") != Some("false") {
      return
    }
    event.prevent_default()
    let x = mouse.get_client_x()
    let y = mouse.get_client_y()
    let keyboard = x == 0 && y == 0
    let mut selected_text = selected_at(element, x, y, keyboard)
    if selected_text is None &&
      remembered_selection is Some((old_x, old_y, text)) &&
      (old_x.to_double() - x.to_double()).abs() <= 2 &&
      (old_y.to_double() - y.to_double()).abs() <= 2 {
      selected_text = text
    }
    remembered_selection = None
    let (x, y) = if keyboard {
      keyboard_anchor(element)
    } else {
      (@math.round(x.to_double()).to_int(), @math.round(y.to_double()).to_int())
    }
    open(
      { target: element_context(element), selected_text, },
      remember_focus(),
      x,
      y,
    )
  }
  document.add_event_listener_with_options(
    "mousedown",
    on_mouse_down,
    capture=true,
  )
  document.add_event_listener_with_options(
    "contextmenu",
    on_context_capture,
    capture=true,
  )
  document.add_event_listener("contextmenu", on_context_menu)
  () => {
    document.remove_event_listener_with_options(
      "mousedown",
      on_mouse_down,
      capture=true,
    )
    document.remove_event_listener_with_options(
      "contextmenu",
      on_context_capture,
      capture=true,
    )
    document.remove_event_listener("contextmenu", on_context_menu)
    discard_temporary_focus(temporary_focus)
  }
}

///|
priv suberror ContextMenuSubscription {
  ContextMenuSubscription(@cmd.Emit[ContextMsg])
}

///|
fn context_menu_subscription(emit : @cmd.Emit[ContextMsg]) -> @sub.Sub {
  @sub.custom_sub("app-context-menu", Global, ContextMenuSubscription(emit), (
    payload,
    scheduler,
  ) => {
    guard payload is ContextMenuSubscription(emit) else { return None }
    let mut emit = emit
    let unload = install_context_menu_listener(
      () => scheduler.add(emit(CloseContext)),
      (request, restore, x, y) => {
        scheduler.add(emit(Requested(request, x, y, restore)))
      },
    )
    Some({
      unload: _ => unload(),
      update_tagger: payload => {
        guard payload is ContextMenuSubscription(next) else { return }
        emit = next
      },
    })
  })
}

///|
fn context_item(
  label : String,
  title : String,
  icon : @html.Html,
  command : @cmd.Cmd,
) -> Entry {
  Action({
    label,
    title,
    icon: Some(icon),
    enabled: true,
    destructive: false,
    command,
  })
}

///|
fn copy_item(label : String, title : String, text : String) -> Entry {
  context_item(label, title, @icons.icon_copy(), @clipboard.copy(Text(text)))
}

///|
fn reveal_label(platform : ClientPlatform) -> String? {
  match platform {
    MacOS => Some("Show in Finder")
    Windows => Some("Show in File Explorer")
    Linux => Some("Show in Folder")
    Web => None
  }
}

///|
fn context_definition(
  input : ContextInput,
  request : ContextRequest,
  actions : ContextActions,
) -> Definition? {
  let navigation : Array[Entry] = []
  let clipboard : Array[Entry] = []
  match request.target {
    NoTarget => ()
    WebLink(url) => {
      if input.platform is Web {
        navigation.push(
          context_item(
            "Open in New Tab",
            "Open in New Tab",
            @icons.icon_link_external(),
            (actions.open_link)(url),
          ),
        )
      } else {
        if input.open_web_links_in_app {
          navigation.push(
            context_item(
              "Open",
              "Open",
              @icons.icon_link_external(),
              (actions.open_link)(url),
            ),
          )
        }
        navigation.push(
          context_item(
            "Open in Default Browser",
            "Open in the system default browser",
            @icons.icon_link_external(),
            (actions.open_external_link)(url),
          ),
        )
      }
      clipboard.push(copy_item("Copy Link", "Copy link address", url))
    }
    EmailLink(url~, address~) => {
      navigation.push(
        context_item(
          "Open",
          "Open email link",
          @icons.icon_link_external(),
          (actions.open_link)(url),
        ),
      )
      clipboard.push(
        copy_item("Copy Email Address", "Copy email address", address),
      )
    }
    FileLink(path) => {
      navigation.push(
        context_item(
          "Open",
          "Open file",
          @icons.icon_link_external(),
          (actions.open_file)(path),
        ),
      )
      if input.reveal_files && reveal_label(input.platform) is Some(label) {
        navigation.push(
          context_item(
            label,
            label,
            @icons.icon_folder_opened(),
            (actions.reveal_file)(path),
          ),
        )
      }
      clipboard.push(copy_item("Copy Path", "Copy file path", path))
    }
  }
  if request.selected_text is Some(text) {
    clipboard.insert(0, copy_item("Copy", "Copy selected text", text))
  }
  guard !navigation.is_empty() || !clipboard.is_empty() else { return None }
  let entries = navigation
  if !navigation.is_empty() && !clipboard.is_empty() {
    entries.push(Separator)
  }
  for entry in clipboard {
    entries.push(entry)
  }
  Some({ label: "Context menu", entries, })
}

///|
fn ContextOpen::as_menu_open(self : ContextOpen) -> Open {
  {
    target: GlobalContextTarget,
    anchor: Pointer(self.x, self.y),
    restore_focus_id: self.restore_focus_id,
  }
}

///|
/// Own the application shell's fallback context menu. More-specific controls
/// run first through ordinary DOM bubbling; unclaimed events are either
/// converted into this themed menu or suppressed when they have no action.
pub fn context_component(
  input : @rabbita.Val[ContextInput],
  actions : ContextActions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => ({ open_context: None, }, @cmd.none),
    update=(_state, input, msg, _) => {
      match msg {
        Requested(request, x, y, restore_focus_id) => {
          guard context_definition(input, request, actions) is Some(definition) &&
            definition.enabled_indices() is [_, ..] else {
            return ({ open_context: None, }, @cmd.none)
          }
          let open : ContextOpen = { request, x, y, restore_focus_id, }
          (
            { open_context: Some(open), },
            @cmd.batch([
              position(GlobalContextTarget, Pointer(x, y)),
              focus_element(menu_id(GlobalContextTarget), true),
            ]),
          )
        }
        CloseContext => ({ open_context: None, }, @cmd.none)
      }
    },
    subscriptions=(state, input, emit) => {
      let requests = context_menu_subscription(emit)
      guard state.open_context is Some(open) else { return requests }
      let enabled = context_definition(input, open.request, actions).map(definition => {
        definition.enabled_indices()
      })
      let focus = focus_subscription(
        GlobalContextTarget,
        enabled,
        emit.map((_ : Unit) => CloseContext),
      )
      @sub.batch([
        requests,
        dismiss_subscription(
          GlobalContextTarget,
          emit.map((_ : Unit) => CloseContext),
          dismiss_on_context=false,
        ),
        focus,
      ])
    },
  )
  state.map2(input, (state, input) => {
    guard state.open_context is Some(open) &&
      context_definition(input, open.request, actions) is Some(definition) &&
      !definition.enabled_indices().is_empty() else {
      return @html.nothing
    }
    render_menu(open.as_menu_open(), definition, emit(CloseContext))
  })
}

///|
pub extend ClientPlatform with Eq::{equal, not_equal}

///|
pub extend ContextInput with Eq::{equal, not_equal}
