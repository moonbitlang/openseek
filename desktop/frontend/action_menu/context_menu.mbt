// The shell is the fallback context-menu trigger. Nested controls retain first
// refusal; this adapter resolves links and selections, while RUI owns the menu.

///|
#derive(Eq)
pub(all) enum ClientPlatform {
  Web
  MacOS
  Windows
  Linux
}

///|
#derive(Eq)
pub(all) struct ContextInput {
  platform : ClientPlatform
  // Whether ordinary web links have a visible in-app Browser destination on
  // the current screen. This is a screen capability, not a platform fact.
  open_web_links_in_app : Bool
  // Reveal is intentionally local-window-only. A browser or a Desktop viewing
  // a remote host must not unexpectedly open a file manager on another device.
  reveal_files : Bool
  share_files : Bool
  download_files : Bool
  downloading : Bool
}

///|
pub(all) struct ContextActions {
  open_link : (String) -> @cmd.Cmd
  open_external_link : (String) -> @cmd.Cmd
  open_file : (String) -> @cmd.Cmd
  reveal_file : (String) -> @cmd.Cmd
  share_file : (String) -> @cmd.Cmd
  download_file : (String) -> @cmd.Cmd
}

///|
#derive(Eq)
priv enum ContextTarget {
  NoTarget
  WebLink(String)
  EmailLink(url~ : String, address~ : String)
  FileLink(String, workspace_file~ : String?)
}

///|
#derive(Eq)
priv struct ContextRequest {
  target : ContextTarget
  selected_text : String?
}

///|
#derive(Eq)
priv struct ContextState {
  request : ContextRequest?
  restore_focus_id : String?
}

///|
priv enum ContextMsg {
  Requested(ContextRequest, String?)
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
  x : Int32,
  y : Int32,
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
fn element_context(element : @dom.Element) -> ContextTarget {
  if element.closest("[data-context-file]") is Some(file) &&
    file.get_attribute("data-context-file") is Some(path) {
    return FileLink(
      path,
      workspace_file=file
        .get_attribute("data-context-workspace-file")
        .filter(path => !path.is_empty()),
    )
  }
  guard element.closest("a[href]") is Some(anchor) &&
    !anchor.has_attribute("download") else {
    return NoTarget
  }
  match anchor_protocol(anchor).to_lower() {
    "http:" | "https:" => WebLink(anchor_href(anchor))
    "mailto:" => {
      let href = anchor.get_attribute("href").unwrap_or(anchor_href(anchor))
      let raw = href[7:].split("?").next().unwrap_or(href[7:])
      let address = @uri.decode_component(raw)
      EmailLink(url=anchor_href(anchor), address~)
    }
    _ => NoTarget
  }
}

///|
fn context_keyboard_anchor(element : @dom.Element) -> (Int32, Int32) {
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
  (rect.get_left().round().to_int(), rect.get_bottom().round().to_int())
}

///|
fn context_editable(element : @dom.Element) -> Bool {
  element.closest("input, textarea, select, [contenteditable]") is Some(control) &&
  control.get_attribute("contenteditable") != Some("false")
}

///|
fn context_focus_id(next_id : Ref[Int32]) -> String? {
  guard @dom.document().get_active_element() is Some(active) &&
    active.to_html_element() is Some(_) &&
    !active.matches("body") else {
    return None
  }
  if active.get_attribute("id") is Some(id) && !id.is_empty() {
    return Some(id)
  }
  next_id.val += 1
  let id = "app-context-focus:\{next_id.val}"
  active.set_attribute("id", id)
  Some(id)
}

///|
fn context_item(
  label : String,
  title : String,
  icon : @html.Html,
  command : @cmd.Cmd,
  enabled~ : Bool = true,
) -> Entry {
  Action({
    label,
    title,
    icon: Some(icon),
    enabled,
    destructive: false,
    command,
  })
}

///|
fn copy_item(label : String, title : String, text : String) -> Entry {
  context_item(label, title, @icons.icon_copy(), @clipboard.copy(Text(text)))
}

///|
fn reveal_label(
  locale~ : @i18n.Locale = English,
  platform : ClientPlatform,
) -> String? {
  match platform {
    MacOS => Some(ui(locale, ShowFinder))
    Windows => Some(ui(locale, ShowExplorer))
    Linux => Some(ui(locale, ShowFolder))
    Web => None
  }
}

///|
fn context_definition(
  locale~ : @i18n.Locale = English,
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
            ui(locale, OpenNewTab),
            ui(locale, OpenNewTab),
            @icons.icon_link_external(),
            (actions.open_link)(url),
          ),
        )
      } else {
        if input.open_web_links_in_app {
          navigation.push(
            context_item(
              ui(locale, OpenLabel),
              ui(locale, OpenLabel),
              @icons.icon_link_external(),
              (actions.open_link)(url),
            ),
          )
        }
        navigation.push(
          context_item(
            ui(locale, OpenDefaultBrowser),
            ui(locale, OpenSystemBrowser),
            @icons.icon_link_external(),
            (actions.open_external_link)(url),
          ),
        )
      }
      clipboard.push(
        copy_item(ui(locale, CopyLink), ui(locale, CopyLinkAddress), url),
      )
    }
    EmailLink(url~, address~) => {
      navigation.push(
        context_item(
          ui(locale, OpenLabel),
          ui(locale, OpenEmail),
          @icons.icon_link_external(),
          (actions.open_link)(url),
        ),
      )
      clipboard.push(
        copy_item(ui(locale, CopyEmail), ui(locale, CopyEmailHint), address),
      )
    }
    FileLink(path, workspace_file~) => {
      navigation.push(
        context_item(
          ui(locale, OpenLabel),
          ui(locale, OpenFile),
          @icons.icon_link_external(),
          (actions.open_file)(path),
        ),
      )
      if input.reveal_files &&
        reveal_label(locale~, input.platform) is Some(label) {
        navigation.push(
          context_item(
            label,
            label,
            @icons.icon_folder_opened(),
            (actions.reveal_file)(path),
          ),
        )
      }
      if input.share_files && workspace_file is Some(path) {
        navigation.push(
          context_item(
            ui(locale, ShareFile),
            ui(locale, ShareFile),
            @icons.icon_link_external(),
            (actions.share_file)(path),
          ),
        )
      }
      if input.download_files && workspace_file is Some(path) {
        navigation.push(
          context_item(
            ui(locale, DownloadToLocal),
            ui(locale, DownloadToLocal),
            @icons.icon_arrow_down(),
            (actions.download_file)(path),
            enabled=!input.downloading,
          ),
        )
      }
      clipboard.push(
        copy_item(ui(locale, CopyPath), ui(locale, CopyFilePath), path),
      )
    }
  }
  if request.selected_text is Some(text) {
    clipboard.insert(
      0,
      copy_item(ui(locale, CopyLabel), ui(locale, CopySelected), text),
    )
  }
  guard !navigation.is_empty() || !clipboard.is_empty() else { return None }
  let entries = navigation
  if !navigation.is_empty() && !clipboard.is_empty() {
    entries.push(Separator)
  }
  for entry in clipboard {
    entries.push(entry)
  }
  Some({ label: ui(locale, ContextMenu), entries, })
}

///|
/// RUI 0.5 exposes its scope through an HTML callback, rather than as an
/// incremental value. Its renderer and open notifications supply the scope
/// and root state for composing the changing shell and context actions.
pub fn context_component(
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[ContextInput],
  actions : ContextActions,
  content : @rabbita.Val[@html.Html],
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_init(
    init=_ => ({ request: None, restore_focus_id: None, }, @cmd.none),
    update=(_, msg, _) => {
      match msg {
        Requested(request, restore_focus_id) =>
          ({ request: Some(request), restore_focus_id, }, @cmd.none)
      }
    },
  )
  let remembered_selection : Ref[(Int32, Int32, String?)?] = Ref(None)
  let next_focus_id = Ref(0)
  let keyboard_request : Ref[ContextRequest?] = Ref(None)
  let visible = Ref(false)
  let render : Ref[
    (@html.Html, @i18n.Locale, ContextInput, ContextState) -> @html.Html,
  ] = Ref((content, _, _, _) => content)
  let native = @rui.context_menu(
    id=GlobalContextTarget,
    on_open_change=open => {
      visible.val = open
      @cmd.none
    },
    scope => {
      // RUI's item indices belong to this scope, not to shell-only updates.
      let rendered_menu : Ref[@html.Html?] = Ref(None)
      render.val = (content, locale, input, state) => {
        let requested = (element, x, y, keyboard) => {
          let mut selected_text = selected_at(element, x, y, keyboard)
          if selected_text is None &&
            remembered_selection.val is Some((old_x, old_y, text)) &&
            (old_x - x).abs() <= 2 &&
            (old_y - y).abs() <= 2 {
            selected_text = text
          }
          remembered_selection.val = None
          { target: element_context(element), selected_text, }
        }
        let accept = (event : @dom.Event, request) => {
          guard context_definition(locale~, input, request, actions)
            is Some(definition) &&
            definition.has_enabled_actions() else {
            event.prevent_default()
            return @rui.popover_close(GlobalContextTarget + "-content")
          }
          emit(Requested(request, context_focus_id(next_focus_id)))
        }
        // The shell is the trigger, but keyboard invocation belongs beside
        // the focused content, not at the shell's upper-left corner.
        let keyboard_open = (event : @dom.Event, element) => {
          event.prevent_default()
          keyboard_request.val = Some(requested(element, 0, 0, true))
          let (x, y) = context_keyboard_anchor(element)
          dispatch_context_at(element, x, y)
          keyboard_request.val = None
          @cmd.none
        }
        let trigger_attrs = @html.Attrs::build()
          .on_mousedown(event => {
            if event.get_button() == 2 &&
              event_element(event.as_event()) is Some(element) {
              let x = event.get_client_x().to_int()
              let y = event.get_client_y().to_int()
              remembered_selection.val = Some(
                (x, y, selected_at(element, x, y, false)),
              )
            }
            @cmd.none
          })
          .on_contextmenu(event => {
            guard !event.get_default_prevented() &&
              event_element(event.as_event()) is Some(element) else {
              return @cmd.none
            }
            if context_editable(element) {
              event.stop_immediate_propagation()
              return @cmd.none
            }
            if keyboard_request.val is Some(request) {
              return accept(event.as_event(), request)
            }
            let x = event.get_client_x().to_int()
            let y = event.get_client_y().to_int()
            if x == 0 && y == 0 {
              keyboard_open(event.as_event(), element)
            } else {
              accept(event.as_event(), requested(element, x, y, false))
            }
          })
          .on_keydown(event => {
            guard !event.get_default_prevented() &&
              (
                event.key() == "ContextMenu" ||
                (event.key() == "F10" && event.shift_key())
              ) &&
              event_element(event.as_event()) is Some(element) else {
              return @cmd.none
            }
            if context_editable(element) {
              event.stop_immediate_propagation()
              return @cmd.none
            }
            keyboard_open(event.as_event(), element)
          })
        let menu_attrs = @html.Attrs::build()
          .data_set("action-menu-surface", GlobalContextTarget)
          .on_contextmenu(event => {
            event.prevent_default()
            event.stop_propagation()
            @cmd.none
          })
        if state.restore_focus_id is Some(id) {
          ignore(menu_attrs.data_set("final-focus-id", id))
        }
        let menu = match rendered_menu.val {
          Some(menu) => menu
          None => {
            let definition = state.request.bind(request => {
              context_definition(locale~, input, request, actions)
            })
            let menu = @rui.context_menu_content(
              scope,
              aria_label=ui(locale, ContextMenu),
              class="action-menu",
              attrs=menu_attrs,
              definition.map_or([], definition => {
                definition.entries.map(entry => {
                  match entry {
                    Separator => @rui.context_menu_separator()
                    Action(item) =>
                      @rui.context_menu_item(
                        scope,
                        disabled=!item.enabled,
                        destructive=item.destructive,
                        on_select=item.command,
                        class="action-menu-item",
                        title=item.title,
                        item_children(item),
                      )
                  }
                })
              }),
            )
            rendered_menu.val = Some(menu)
            menu
          }
        }
        @html.fragment([
          @rui.context_menu_trigger(
            scope,
            tabindex=-1,
            style=["width:100%;height:100%"],
            attrs=trigger_attrs,
            content,
          ),
          menu,
        ])
      }
      @html.nothing
    },
  )
  @rabbita.Val::map5(native, content, locale, input, state, (
    _,
    content,
    locale,
    input,
    state,
  ) => {
    @rui.theme(
      style=["display:contents"],
      @html.span(
        id=GlobalContextTarget + "-root",
        style=["display:contents"],
        attrs=@html.Attrs::build()
          .data_set("slot", "context-menu")
          .data_set("state", if visible.val { "open" } else { "closed" }),
        (render.val)(content, locale, input, state),
      ),
    )
  })
}

///|
pub extend ClientPlatform with Eq::{equal, not_equal}

///|
pub extend ContextInput with Eq::{equal, not_equal}
