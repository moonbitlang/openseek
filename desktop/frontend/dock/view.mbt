// The strip's view: the tab bar riding the top of the right panel, with the
// whole-panel toggle at its right edge. The dock renders identities only —
// labels and per-tab decorations come in as `TabChip` view-models computed
// by the root view from the owning subsystem's state, so the dock never
// reads document tables.

///|
/// The sidebar-right codicon for the panel toggle, from Microsoft's
/// vscode-codicons (CC BY 4.0), embedded unmodified.
let icon_layout_sidebar_right : String =
  #|<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M12.5 1C13.881 1 15 2.119 15 3.5V12.5C15 13.881 13.881 15 12.5 15H3.5C2.119 15 1 13.881 1 12.5V3.5C1 2.119 2.119 1 3.5 1H12.5ZM9 14V2H3.5C2.672 2 2 2.672 2 3.5V12.5C2 13.328 2.672 14 3.5 14H9Z"/></svg>

///|
/// An icon's SVG markup injected into a fixed-size span. The markup is a
/// trusted compile-time constant, never user input, so the XSS alert on
/// `inner_html` does not apply.
#warnings("-alert_xss_vulnerable")
fn icon(markup : String) -> @html.Html {
  @html.span(
    class="icon",
    attrs=@html.Attrs::build().inner_html(markup).aria_hidden("true"),
    ([] : Array[@html.Html]),
  )
}

///|
/// One strip entry as the root view presents it: the tab's identity plus the
/// decorations only the owning subsystem knows — the label text, the hover
/// title, and whether the tab's backing content is missing (a deleted file),
/// which styles the tab.
pub(all) struct TabChip {
  tab : DockTab
  label : String
  title : String
  missing : Bool
}

///|
/// The panel's top bar: the open tabs, with the whole-panel toggle riding
/// the right edge. Always rendered so the panel's child order stays
/// structural. Clicking a tab activates it; the `×` closes it without
/// activating (the close click must not bubble into the tab's own handler).
pub fn tabs_bar(
  dispatch : @cmd.Emit[Msg],
  state : State,
  chips : Array[TabChip],
) -> @html.Html {
  let tabs : Array[@html.Html] = []
  for chip in chips {
    let mut classes = "editor-tab"
    if state.active == Some(chip.tab) {
      classes = classes + " active"
    }
    if chip.missing {
      classes = classes + " deleted"
    }
    let tab = chip.tab
    tabs.push(
      @html.div(
        class=classes,
        title=chip.title,
        on_click=dispatch(TabActivated(tab)),
        [
          @html.span(class="tab-name", chip.label),
          @html.button(
            class="tab-close",
            title="Close",
            attrs=@html.Attrs::build().on_click(event => {
              event.stop_propagation()
              dispatch(TabClosed(tab))
            }),
            "×",
          ),
        ],
      ),
    )
  }
  @html.div(class="editor-tabsbar", [
    @html.div(class="editor-tabs", tabs),
    @html.button(
      class="panel-toggle",
      title="Hide panel",
      on_click=dispatch(TogglePanel),
      icon(icon_layout_sidebar_right),
    ),
  ])
}
