// The browser toolbar riding the top of the pane while a Browser tab is
// active: history buttons, the address bar, and open-in-system-browser. The
// page itself is a native web contents view the host overlays on the pane
// below — this package renders chrome only.

///|
/// The element id the root focuses when a blank tab opens.
pub const AddressInputId = "browser-address-input"

///|
/// The up arrow codicon from Microsoft's vscode-codicons (CC BY 4.0); the
/// path data is unmodified, transcribed into `@svg` builders (an
/// innerHTML-bearing element cannot be safely morphed by the positional
/// child diff). The toolbar's back/forward rotate it by CSS so the history
/// buttons keep the exact codicon geometry.
fn icon_arrow_up() -> @html.Html {
  codicon(
    "M13.854 7.14576L8.85401 2.14576C8.65901 1.95076 8.34201 1.95076 8.14701 2.14576L3.14601 7.14576C2.95101 7.34076 2.95101 7.65776 3.14601 7.85276C3.34101 8.04776 3.65801 8.04776 3.85301 7.85276L7.99901 3.70676V13.4998C7.99901 13.7758 8.22301 13.9998 8.49901 13.9998C8.77501 13.9998 8.99901 13.7758 8.99901 13.4998V3.70676L13.145 7.85276C13.243 7.95076 13.371 7.99876 13.499 7.99876C13.627 7.99876 13.755 7.94976 13.853 7.85276C14.048 7.65776 14.048 7.34076 13.853 7.14576H13.854Z",
  )
}

///|
/// The sync codicon (CC BY 4.0), the reload button.
fn icon_sync() -> @html.Html {
  codicon(
    "M14 3.5V6.5C14 6.78 13.78 7 13.5 7H10.5C10.22 7 9.99999 6.78 9.99999 6.5C9.99999 6.22 10.22 6 10.5 6H12.58C11.78 4.17 10.01 3 7.99999 3C5.77999 3 3.79999 4.5 3.18999 6.64C3.12999 6.86 2.92999 7 2.70999 7C2.65999 7 2.61999 7 2.56999 6.98C2.29999 6.9 2.14999 6.63 2.22999 6.36C2.95999 3.79 5.32999 2 7.99999 2C10.05 2 11.91 3.02 13 4.69V3.5C13 3.22 13.22 3 13.5 3C13.78 3 14 3.22 14 3.5ZM13.42 9.02C13.16 8.95 12.88 9.1 12.8 9.37C12.19 11.51 10.22 13.01 7.98999 13.01C5.97999 13.01 4.20999 11.84 3.40999 10.01H5.48999C5.76999 10.01 5.98999 9.79 5.98999 9.51C5.98999 9.23 5.76999 9.01 5.48999 9.01H2.48999C2.20999 9.01 1.98999 9.23 1.98999 9.51V12.51C1.98999 12.79 2.20999 13.01 2.48999 13.01C2.76999 13.01 2.98999 12.79 2.98999 12.51V11.32C4.07999 12.98 5.93999 14.01 7.98999 14.01C10.66 14.01 13.03 12.22 13.76 9.65C13.84 9.38 13.68 9.11 13.41 9.03L13.42 9.02Z",
  )
}

///|
/// The link-external codicon (CC BY 4.0), the open-in-system-browser button.
fn icon_link_external() -> @html.Html {
  codicon(
    "M15 9.5V12.5C15 13.879 13.879 15 12.5 15H3.5C2.121 15 1 13.879 1 12.5V3.5C1 2.121 2.121 1 3.5 1H6.5C6.776 1 7 1.224 7 1.5C7 1.776 6.776 2 6.5 2H3.5C2.673 2 2 2.673 2 3.5V12.5C2 13.327 2.673 14 3.5 14H12.5C13.327 14 14 13.327 14 12.5V9.5C14 9.224 14.224 9 14.5 9C14.776 9 15 9.224 15 9.5ZM14.5 1H9.5C9.224 1 9 1.224 9 1.5C9 1.776 9.224 2 9.5 2H13.293L9.147 6.146C8.952 6.341 8.952 6.658 9.147 6.853C9.245 6.951 9.373 6.999 9.501 6.999C9.629 6.999 9.757 6.95 9.855 6.853L14.001 2.707V6.5C14.001 6.776 14.225 7 14.501 7C14.777 7 15.001 6.776 15.001 6.5V1.5C15.001 1.224 14.777 1 14.501 1H14.5Z",
  )
}

///|
/// A 16×16 codicon: one filled path tinted by `currentColor`.
fn codicon(d : String) -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build().fill("currentColor"),
    [@svg.path(d~)],
  )
}

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
}

///|
/// The active page's toolbar. Always rendered (the panel's child order is
/// structural); CSS hides it while the active tab is not a Browser tab.
pub fn toolbar_view(page : PageState, actions : ToolbarActions) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.button(
      class="browser-nav-button",
      title="Back",
      on_click=actions.back,
      icon(icon_arrow_up, rotate="left"),
    ),
    @html.button(
      class="browser-nav-button",
      title="Forward",
      on_click=actions.forward,
      icon(icon_arrow_up, rotate="right"),
    ),
    @html.button(
      class=if page.loading {
        "browser-nav-button loading"
      } else {
        "browser-nav-button"
      },
      title="Reload",
      on_click=actions.reload,
      icon(icon_sync),
    ),
    @html.input(
      input_type=@html.InputType::Text,
      value=page.input,
      placeholder="Enter a URL",
      on_input=actions.input,
      attrs=@html.Attrs::build()
        .id(AddressInputId)
        .class("browser-address")
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
      title="Open in system browser",
      on_click=actions.open_external,
      icon(icon_link_external),
    ),
  ]
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
