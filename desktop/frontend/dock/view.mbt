// The strip's view: the tab bar riding the top of the right panel, with the
// whole-panel toggle at its right edge. The dock renders identities only —
// labels and per-tab decorations come in as `TabChip` view-models computed
// by the root view from the owning subsystem's state, so the dock never
// reads document tables.

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
        @icons.icon(icon_globe),
        @html.span(class="dock-launcher-name", "Browse"),
        @html.span(class="dock-launcher-hint", "Open a page in a tab"),
      ]),
    )
  }
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.search, [
      @icons.icon(@icons.icon_search),
      @html.span(class="dock-launcher-name", "Search"),
      @html.span(class="dock-launcher-hint", "Search text across the workspace"),
    ]),
  )
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.files, [
      @icons.icon(@icons.icon_folder),
      @html.span(class="dock-launcher-name", "Files"),
      @html.span(class="dock-launcher-hint", "Open a file from the workspace"),
    ]),
  )
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.review, [
      @icons.icon(icon_review),
      @html.span(class="dock-launcher-name", "Review"),
      @html.span(class="dock-launcher-hint", "Review changed files and diffs"),
    ]),
  )
  rows.push(
    @html.button(class="dock-launcher-row", on_click=actions.workflows, [
      @icons.icon(icon_workflows),
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
      @icons.icon(@icons.icon_close_all),
    ),
    @html.button(
      class=if chips.is_empty() {
        "tab-action tab-add hidden"
      } else {
        "tab-action tab-add"
      },
      title="New tab",
      on_click=toggle_menu,
      @icons.icon(@icons.icon_add),
    ),
    @html.button(
      class="panel-toggle panel-expand",
      title=if expanded { "Restore panel" } else { "Expand panel" },
      attrs=@html.Attrs::build()
        .aria_label(if expanded { "Restore panel" } else { "Expand panel" })
        .aria_pressed(expanded.to_string())
        .on_click(_ => toggle_expanded),
      @icons.icon(if expanded { icon_restore_panel } else { icon_expand_panel }),
    ),
    @html.button(
      class="panel-toggle",
      title="Hide panel",
      on_click=toggle_panel,
      @icons.icon(@icons.icon_layout_sidebar_right),
    ),
  ]
  if menu_open {
    // No backdrop element: the frontend package installs a click-away
    // dismissal that does not consume the click that closes it.
    children.push(@html.div(class="dock-menu", launcher_rows(actions)))
  }
  @html.div(class="editor-tabsbar", children)
}
