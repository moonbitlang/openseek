// The strip's view: the tab bar riding the top of the right panel, with the
// whole-panel toggle at its right edge. The dock renders identities only —
// labels and per-tab decorations come in as `TabChip` view-models computed
// by the root view from the owning subsystem's state, so the dock never
// reads document tables.

///|
/// The sidebar-right codicon for the panel toggle, from Microsoft's
/// vscode-codicons (CC BY 4.0); the path data is unmodified, transcribed
/// into `@svg` builders (an innerHTML-bearing element cannot be safely
/// morphed by the positional child diff).
fn icon_layout_sidebar_right() -> @html.Html {
  @icons.codicon(
    "M12.5 1C13.881 1 15 2.119 15 3.5V12.5C15 13.881 13.881 15 12.5 15H3.5C2.119 15 1 13.881 1 12.5V3.5C1 2.119 2.119 1 3.5 1H12.5ZM9 14V2H3.5C2.672 2 2 2.672 2 3.5V12.5C2 13.328 2.672 14 3.5 14H9Z",
  )
}

///|
/// Four outward-facing corners for expanding the panel into the whole content
/// area. The inverse glyph below points inward when the next action restores
/// the split view.
fn icon_expand_panel() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build()
      .fill("none")
      .stroke("currentColor")
      .stroke_linecap("round"),
    [@svg.path(d="M6 2.5H2.5V6M10 2.5h3.5V6M13.5 10v3.5H10M6 13.5H2.5V10")],
  )
}

///|
fn icon_restore_panel() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build()
      .fill("none")
      .stroke("currentColor")
      .stroke_linecap("round"),
    [@svg.path(d="M2.5 6H6V2.5M13.5 6H10V2.5M13.5 10H10v3.5M2.5 10H6v3.5")],
  )
}

///|
/// The add codicon (CC BY 4.0): the strip's new-tab button.
fn icon_add() -> @html.Html {
  @icons.codicon(
    "M8 1.5C8 1.22386 7.77614 1 7.5 1C7.22386 1 7 1.22386 7 1.5V7H1.5C1.22386 7 1 7.22386 1 7.5C1 7.77614 1.22386 8 1.5 8H7V13.5C7 13.7761 7.22386 14 7.5 14C7.77614 14 8 13.7761 8 13.5V8H13.5C13.7761 8 14 7.77614 14 7.5C14 7.22386 13.7761 7 13.5 7H8V1.5Z",
  )
}

///|
/// The folder codicon (CC BY 4.0): the launcher's Files row.
fn icon_folder() -> @html.Html {
  @icons.codicon(
    "M2 4.5V6H5.58579C5.71839 6 5.84557 5.94732 5.93934 5.85355L7.29289 4.5L5.93934 3.14645C5.84557 3.05268 5.71839 3 5.58579 3H3.5C2.67157 3 2 3.67157 2 4.5ZM1 4.5C1 3.11929 2.11929 2 3.5 2H5.58579C5.98361 2 6.36514 2.15804 6.64645 2.43934L8.20711 4H12.5C13.8807 4 15 5.11929 15 6.5V11.5C15 12.8807 13.8807 14 12.5 14H3.5C2.11929 14 1 12.8807 1 11.5V4.5ZM2 7V11.5C2 12.3284 2.67157 13 3.5 13H12.5C13.3284 13 14 12.3284 14 11.5V6.5C14 5.67157 13.3284 5 12.5 5H8.20711L6.64645 6.56066C6.36514 6.84197 5.98361 7 5.58579 7H2Z",
  )
}

///|
/// The search codicon (CC BY 4.0): the launcher's workspace Search row.
fn icon_search() -> @html.Html {
  @icons.codicon(
    "M10.0195 10.7266C9.06578 11.5217 7.83875 12 6.5 12C3.46243 12 1 9.53757 1 6.5C1 3.46243 3.46243 1 6.5 1C9.53757 1 12 3.46243 12 6.5C12 7.83875 11.5217 9.06578 10.7266 10.0195L13.8535 13.1464C14.0488 13.3417 14.0488 13.6583 13.8535 13.8536C13.6583 14.0488 13.3417 14.0488 13.1464 13.8536L10.0195 10.7266ZM11 6.5C11 4.01472 8.98528 2 6.5 2C4.01472 2 2 4.01472 2 6.5C2 8.98528 4.01472 11 6.5 11C8.98528 11 11 8.98528 11 6.5Z",
  )
}

///|
/// A simple globe for the launcher's Browse row (drawn here, not a
/// codicon): a circle with one meridian and the equator.
fn icon_globe() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build().fill("none").stroke("currentColor"),
    [
      @svg.circle(cx=8, cy=8, r=6),
      @svg.node(
        "ellipse",
        @svg.Attrs::build().cx("8").cy("8").rx("2.6").ry("6"),
        [],
      ),
      @svg.path(d="M2 8h12"),
    ],
  )
}

///|
/// A compact diff document for the launcher's Review row.
fn icon_review() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build()
      .fill("none")
      .stroke("currentColor")
      .stroke_linecap("round"),
    [
      @svg.path(d="M5.5 2.5h7v11h-9v-7"),
      @svg.path(d="M1 3.5h4M3 1.5v4M1 9.5h4"),
      @svg.path(d="M7 6.5h3.5M7 9.5h3.5"),
    ],
  )
}

///|
/// One node fanning out to three: the launcher's Workflows row.
fn icon_workflows() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build()
      .fill("none")
      .stroke("currentColor")
      .stroke_linecap("round"),
    [
      @svg.path(d="M2.5 8h4"),
      @svg.path(d="M6.5 8c2 0 2-4.5 4-4.5M6.5 8c2 0 2 4.5 4 4.5M6.5 8h4"),
      @svg.path(d="M10.5 3.5h3M10.5 8h3M10.5 12.5h3"),
    ],
  )
}

///|
/// An icon in a fixed-size span. Icons are functions, not shared constants:
/// each render site gets its own virtual-DOM value, so no Props instance is
/// ever aliased between two mounted elements.
fn icon(image : () -> @html.Html) -> @html.Html {
  @html.span(class="icon", attrs=@html.Attrs::build().aria_hidden("true"), [
    image(),
  ])
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
/// What the launcher's rows can open, as root-owned commands — opening a
/// tab allocates state in other packages, so the dock only emits. A `None`
/// browser action hides that row (a remote console has no native views to
/// host pages with).
pub(all) struct LauncherActions {
  browser : @cmd.Cmd?
  search : @cmd.Cmd
  files : @cmd.Cmd
  review : @cmd.Cmd
  workflows : @cmd.Cmd
}

///|
/// The launcher rows shared by the empty-strip pane and the `+` popup: the
/// kinds of tab the dock can open.
fn launcher_rows(actions : LauncherActions) -> Array[@html.Html] {
  let rows : Array[@html.Html] = []
  if actions.browser is Some(open_browser) {
    rows.push(
      @html.button(class="dock-launcher-row", on_click=open_browser, [
        icon(icon_globe),
        @html.span(class="dock-launcher-name", "Browse"),
        @html.span(class="dock-launcher-hint", "Open a page in a tab"),
      ]),
    )
  }
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.search, [
      icon(icon_search),
      @html.span(class="dock-launcher-name", "Search"),
      @html.span(class="dock-launcher-hint", "Search text across the workspace"),
    ]),
  )
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.files, [
      icon(icon_folder),
      @html.span(class="dock-launcher-name", "Files"),
      @html.span(class="dock-launcher-hint", "Open a file from the workspace"),
    ]),
  )
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.review, [
      icon(icon_review),
      @html.span(class="dock-launcher-name", "Review"),
      @html.span(class="dock-launcher-hint", "Review changed files and diffs"),
    ]),
  )
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.workflows, [
      icon(icon_workflows),
      @html.span(class="dock-launcher-name", "Workflows"),
      @html.span(
        class="dock-launcher-hint",
        "Subagents this conversation delegated to",
      ),
    ]),
  )
  rows
}

///|
/// The empty strip's body: a centered launcher menu of the tab kinds the
/// dock can open (Codex-style). Always rendered — CSS shows it only while
/// the strip is empty — so the panel's child order stays structural.
pub fn launcher_pane(actions : LauncherActions) -> @html.Html {
  @html.div(class="dock-launcher", [
    @html.div(class="dock-launcher-menu", launcher_rows(actions)),
  ])
}

///|
/// The panel's top bar: the open tabs, the `+` launcher popup, and the
/// whole-panel toggle riding the right edge. Always rendered so the panel's
/// child order stays structural. Clicking a tab activates it; the `×`
/// closes it without activating (the close click must not bubble into the
/// tab's own handler).
pub fn tabs_bar(
  dispatch : @cmd.Emit[Msg],
  state : State,
  chips : Array[TabChip],
  actions : LauncherActions,
  menu_open~ : Bool,
  expanded~ : Bool,
  toggle_menu~ : @cmd.Cmd,
  close_all_tabs~ : @cmd.Cmd,
  close_all_tabs_disabled~ : Bool,
  toggle_expanded~ : @cmd.Cmd,
  toggle_panel~ : @cmd.Cmd,
) -> @html.Html {
  let tabs : Array[@html.Html] = []
  for chip in chips {
    let mut classes = "editor-tab"
    if state.active == Some(chip.tab) {
      classes += " active"
    }
    if chip.missing {
      classes += " deleted"
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
  // With an empty strip the body already is the launcher, so the `+` hides
  // (by class, keeping the child order structural). The popup is conditional,
  // appended after every stable child.
  let children : Array[@html.Html] = [
    @html.div(class="editor-tabs", tabs),
    @html.button(
      class="tab-action tab-close-all",
      title="Close all tabs",
      attrs=@html.Attrs::build()
        .aria_label("Close all tabs")
        .disabled(close_all_tabs_disabled)
        .on_click(_ => close_all_tabs),
      icon(@icons.icon_close_all),
    ),
    @html.button(
      class=if chips.is_empty() {
        "tab-action tab-add hidden"
      } else {
        "tab-action tab-add"
      },
      title="New tab",
      on_click=toggle_menu,
      icon(icon_add),
    ),
    @html.button(
      class="panel-toggle panel-expand",
      title=if expanded { "Restore panel" } else { "Expand panel" },
      attrs=@html.Attrs::build()
        .aria_label(if expanded { "Restore panel" } else { "Expand panel" })
        .aria_pressed(expanded.to_string())
        .on_click(_ => toggle_expanded),
      icon(if expanded { icon_restore_panel } else { icon_expand_panel }),
    ),
    @html.button(
      class="panel-toggle",
      title="Hide panel",
      on_click=toggle_panel,
      icon(icon_layout_sidebar_right),
    ),
  ]
  if menu_open {
    // No backdrop element: the frontend package installs a click-away
    // dismissal that does not consume the click that closes it.
    children.push(@html.div(class="dock-menu", launcher_rows(actions)))
  }
  @html.div(class="editor-tabsbar", children)
}
