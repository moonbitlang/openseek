// Content regions resolve their own right-click targets. The shared menu is a
// sibling overlay, never an ancestor of application content or editable controls.

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
  scope : String
  // Whether ordinary web links have a visible in-app Browser destination on
  // the current screen. This is a screen capability, not a platform fact.
  open_web_links_in_app : Bool
  // Reveal is intentionally local-window-only. A browser or a Desktop viewing
  // a remote host must not unexpectedly open a file manager on another device.
  reveal_files : Bool
  preview_files : Bool
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
  preview_file : (String) -> @cmd.Cmd
  download_file : (String) -> @cmd.Cmd
}

///|
#derive(Eq, Debug)
pub(all) enum ContextTarget {
  NoTarget
  WebLink(String)
  EmailLink(url~ : String, address~ : String)
  FileLink(String, workspace_file~ : String?)
}

///|
#derive(Eq)
priv struct ContextOpen {
  request : ContextTarget
  open : Open
}

///|
priv enum ContextMsg {
  Requested(ContextOpen)
  Closed(ContextOpen)
}

///|
const ContentContextEvent : String = "openseek-content-context-open"

///|
fn event_element(event : @dom.Event) -> @dom.Element? {
  match event.target().to_element() {
    Some(element) => Some(element)
    None => event.target().to_node().bind(node => node.get_parent_element())
  }
}

///|
fn element_context(
  element : @dom.Element,
  region : @dom.Element,
) -> ContextTarget {
  if element.closest("[data-context-file]") is Some(file) &&
    region.contains(file.as_node()) &&
    file.get_attribute("data-context-file") is Some(path) {
    return FileLink(
      path,
      workspace_file=file
        .get_attribute("data-context-workspace-file")
        .filter(path => !path.is_empty()),
    )
  }
  guard element.closest("a[href]") is Some(anchor) &&
    region.contains(anchor.as_node()) &&
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
fn context_focus_id(region : String) -> String? {
  guard @dom.document().get_active_element() is Some(active) &&
    active.to_html_element() is Some(_) &&
    !active.matches("body") else {
    return None
  }
  if active.get_attribute("id") is Some(id) && !id.is_empty() {
    return Some(id)
  }
  let id = "content-context-focus:\{region}"
  // A previous invocation may have focused a different unnamed element.
  // Keep this region's temporary restore target unique across invocations.
  if @dom.document().get_element_by_id(id).to_option() is Some(previous) &&
    previous.get_attribute(TemporaryFocusAttribute) == Some(id) {
    previous.remove_attribute("id")
    previous.remove_attribute(TemporaryFocusAttribute)
  }
  active.set_attribute("id", id)
  active.set_attribute(TemporaryFocusAttribute, id)
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
  request : ContextTarget,
  actions : ContextActions,
) -> Definition? {
  let navigation : Array[Entry] = []
  let clipboard : Array[Entry] = []
  match request {
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
      let lower = path.to_lower()
      if input.preview_files &&
        workspace_file is Some(file) &&
        (lower.has_suffix(".html") || lower.has_suffix(".htm")) {
        navigation.push(
          context_item(
            ui(locale, PreviewFile),
            ui(locale, PreviewFile),
            @icons.icon_eye(),
            (actions.preview_file)(file),
          ),
        )
      }
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
/// Register a content region, without installing RUI's menu keyboard handler
/// on its descendants. Nested controls and editable elements retain first refusal.
pub fn content_attrs(region : String) -> @html.Attrs {
  let request = (event : @dom.Event, x, y, keyboard) => {
    guard !event.get_default_prevented() &&
      event_element(event) is Some(element) &&
      !context_editable(element) &&
      event.current_target().to_option().bind(target => target.to_element())
      is Some(container) &&
      element.closest("[data-content-context]") is Some(owner) &&
      owner.is_same_node(container.as_node()) else {
      return @cmd.none
    }
    let target = element_context(element, container)
    guard target != NoTarget else { return @cmd.none }
    event.prevent_default()
    event.stop_propagation()
    let (x, y) = if keyboard {
      context_keyboard_anchor(element)
    } else {
      (x, y)
    }
    let context : ContextOpen = {
      request: target,
      open: {
        target: "content-context:" + region,
        anchor: Pointer(x, y),
        restore_focus_id: context_focus_id(region),
      },
    }
    @cmd.custom_cmd(_ => {
      // An internal, typed in-memory event, not a JSON wire message.
      let event = @dom.CustomEvent::new(
        ContentContextEvent,
        detail=@js.Optional::from_option(Some(@js.Value::cast_from(context))),
      )
      @dom.document().as_event_target().dispatch_event(event.as_event())
    })
  }
  @html.Attrs::build()
  .data_set("content-context", region)
  .on_contextmenu(event => {
    let x = event.get_client_x().to_int()
    let y = event.get_client_y().to_int()
    request(event.as_event(), x, y, x == 0 && y == 0)
  })
  .on_keydown(event => {
    guard !event.is_composing() &&
      !event.repeat() &&
      (
        event.key() == "ContextMenu" ||
        (event.key() == "F10" && event.shift_key())
      ) else {
      return @cmd.none
    }
    request(event.as_event(), 0, 0, true)
  })
}

///|
/// Add a trigger to content with no suitable owning element of its own.
pub fn content_region(region : String, content : @html.Html) -> @html.Html {
  @html.div(style=["display:contents"], attrs=content_attrs(region), content)
}

///|
priv suberror ContextSubscription {
  ContextSubscription(@cmd.Emit[ContextOpen])
}

///|
fn context_subscription(emit : @cmd.Emit[ContextOpen]) -> @sub.Sub {
  @sub.custom_sub("content-context-open", Local, ContextSubscription(emit), (
    payload,
    scheduler,
  ) => {
    guard payload is ContextSubscription(emit) else { return None }
    let mut emit = emit
    let target = @dom.document().as_event_target()
    let listener : @dom.Listener = event => {
      if event.to_custom_event() is Some(event) {
        scheduler.add(emit(event.get_detail().cast()))
      }
    }
    target.add_event_listener(ContentContextEvent, listener)
    Some({
      unload: _ => target.remove_event_listener(ContentContextEvent, listener),
      update_tagger: payload => {
        if payload is ContextSubscription(next) {
          emit = next
        }
      },
    })
  })
}

///|
/// Only the open menu is a RUI surface. Changing conversation/workspace drops
/// its request so file actions cannot be applied to a different owner.
pub fn context_component(
  locale : @rabbita.Val[@i18n.Locale],
  input : @rabbita.Val[ContextInput],
  actions : ContextActions,
) -> @rabbita.Val[@html.Html] {
  let (state, emit) = @rabbita.create_state_with_input(
    input~,
    init=(_, _) => (None, @cmd.none),
    update=(state, input, msg, _) => {
      match msg {
        Requested(open) => (Some((input.scope, open)), @cmd.none)
        Closed(open) =>
          (
            if state is Some((_, current)) && current == open {
              None
            } else {
              state
            },
            @cmd.none,
          )
      }
    },
    subscriptions=(state, _, emit) => {
      @sub.batch(
        [
          context_subscription(emit.map(open => Requested(open))),
          ..state.map_or([], pair => {
            let (_, open) = pair
            [
              @dismiss.on_back("content-context-back", level=TopLayer, _ => {
                emit(Closed(open))
              }),
              @sub.on_resize(_ => emit(Closed(open))),
            ]
          }),
        ],
      )
    },
  )
  state.switch_by(
    current => {
      guard current is Some((scope, context)) else {
        return @rabbita.Val::constant(@html.nothing)
      }
      menu_component(
        input.map2(locale, (input, locale) => (input, locale)),
        context.open,
        pair => {
          let (input, locale) = pair
          if input.scope == scope {
            context_definition(locale~, input, context.request, actions)
          } else {
            None
          }
        },
        emit(Closed(context)),
      )
    },
    by=current => {
      current.map_or("closed", pair => {
        let (scope, context) = pair
        scope + context.open.key() + Repr::Repr(context.request).to_string()
      })
    },
  )
}

///|
pub extend ClientPlatform with Eq::{equal, not_equal}

///|
pub extend ContextInput with Eq::{equal, not_equal}
