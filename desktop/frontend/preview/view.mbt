// The browser toolbar riding the top of the pane while a Browser tab is
// active: history buttons, the address bar, and open-in-system-browser. The
// page itself is a native web contents view the host overlays on the pane
// below — this package renders chrome only.

///|
/// The element id the root focuses when a blank tab opens.
pub const AddressInputId = "browser-address-input"

///|
/// An icon in a fixed-size span. Icons are functions, not shared constants:
/// each render site gets its own virtual-DOM value, so no Props instance is
/// ever aliased between two mounted elements.
fn icon(image : () -> @html.Html, rotate? : String) -> @html.Html {
  let class = match rotate {
    Some(direction) => "icon rotate-\{direction}"
    None => "icon"
  }
  @html.span(class~, attrs=@html.Attrs::build().aria_hidden("true"), [image()])
}

///|
/// What the toolbar can ask the app to do. Navigation and history are host
/// commands, so the root update owns them; this view only emits.
pub(all) struct ToolbarActions {
  input : @cmd.Emit[String]
  submit : @cmd.Cmd
  back : @cmd.Cmd
  forward : @cmd.Cmd
  reload : @cmd.Cmd
  open_external : @cmd.Cmd
  annotate : @html.Html
}

///|
/// The active page's toolbar. Always rendered (the panel's child order is
/// structural); CSS hides it while the active tab is not a Browser tab.
pub fn toolbar_view(
  locale~ : @i18n.Locale = English,
  page : PageState,
  actions : ToolbarActions,
) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.button(
      class="browser-nav-button",
      title=ui(locale, BackLabel),
      on_click=actions.back,
      icon(@icons.icon_arrow_up, rotate="left"),
    ),
    @html.button(
      class="browser-nav-button",
      title=ui(locale, ForwardLabel),
      on_click=actions.forward,
      icon(@icons.icon_arrow_up, rotate="right"),
    ),
    @html.button(
      class=if page.loading {
        "browser-nav-button loading"
      } else {
        "browser-nav-button"
      },
      title=ui(locale, ReloadLabel),
      on_click=actions.reload,
      icon(@icons.icon_sync),
    ),
    @html.input(
      input_type=@html.InputType::Text,
      value=page.input,
      placeholder=ui(locale, EnterUrl),
      on_input=actions.input,
      attrs=@html.Attrs::build()
        .id(AddressInputId)
        .class("browser-address field-surface")
        .data_set("focus-owner", "")
        .on_keydown(event => {
          match event.key() {
            "Enter" => actions.submit
            _ => @cmd.none
          }
        }),
    ),
    @html.button(
      class="browser-nav-button",
      title=ui(
        locale,
        if page.url is Some(url) && @uri.is_file_url(url) {
          OpenApplication
        } else {
          OpenBrowser
        },
      ),
      on_click=actions.open_external,
      icon(@icons.icon_link_external),
    ),
  ]
  children.push(actions.annotate)
  @html.div(class="browser-toolbar", children)
}

///|
/// The failure banner under the toolbar: the last load error, or nothing.
/// Always rendered so the pane below never shifts index.
pub fn failure_view(page : PageState) -> @html.Html {
  match page.failure {
    Some(text) => @html.div(class="browser-failure", text)
    None => @html.div(class="browser-failure hidden", "")
  }
}
