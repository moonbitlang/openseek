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
  github : @cmd.Cmd
  workflows : @cmd.Cmd
  jobs : @cmd.Cmd
}

///|
/// The launcher rows shared by the empty-strip pane and the `+` popup: the
/// kinds of tab the dock can open.
fn LauncherActions::rows(
  locale? : @i18n.Locale = English,
  self : LauncherActions,
  popup? : Bool = false,
) -> Array[@html.Html] {
  let entries : Array[(String, String, () -> @html.Html, @cmd.Cmd)] = []
  if self.browser is Some(open_browser) {
    entries.push(
      (
        ui(locale, BrowseLabel),
        ui(locale, BrowseHint),
        @icons.icon_globe,
        open_browser,
      ),
    )
  }
  entries.push(
    (
      ui(locale, SearchLabel),
      ui(locale, SearchHint),
      @icons.icon_search,
      self.search,
    ),
  )
  entries.push(
    (
      ui(locale, FilesLabel),
      ui(locale, FilesHint),
      @icons.icon_folder,
      self.files,
    ),
  )
  entries.push(
    (
      ui(locale, ReviewLabel),
      ui(locale, ReviewHint),
      @icons.icon_diff_multiple,
      self.review,
    ),
  )
  entries.push(
    ("GitHub", ui(locale, GithubHint), @icons.icon_github, self.github),
  )
  entries.push(
    (
      ui(locale, WorkflowsLabel),
      ui(locale, WorkflowsHint),
      @icons.icon_organization,
      self.workflows,
    ),
  )
  entries.push(
    (
      ui(locale, JobsLabel),
      ui(locale, JobsHint),
      @icons.icon_tasklist,
      self.jobs,
    ),
  )
  let rows : Array[@html.Html] = []
  for entry in entries {
    let (label, hint, image, choose) = entry
    rows.push(
      @html.button(
        class=if popup {
          "menu-option dock-menu-row"
        } else {
          "dock-launcher-row"
        },
        on_click=choose,
        attrs=if popup {
          @html.Attrs::build().role("menuitem").aria_label(label)
        } else {
          @html.Attrs::build()
        },
        [
          @icons.icon(image),
          @html.span(class="dock-launcher-name", label),
          @html.span(class="dock-launcher-hint", hint),
        ],
      ),
    )
  }
  rows
}

///|
/// The empty strip's body: a centered launcher menu of the tab kinds the
/// dock can open (Codex-style). Always rendered — CSS shows it only while
/// the strip is empty — so the panel's child order stays structural.
pub fn launcher_pane(
  locale? : @i18n.Locale = English,
  actions : LauncherActions,
) -> @html.Html {
  @html.div(class="dock-launcher", [
    @html.div(class="dock-launcher-menu", actions.rows(locale~)),
  ])
}

///|
/// The panel's top bar: the open tabs, the `+` launcher popup, and the
/// whole-panel toggle riding the right edge. Always rendered so the panel's
/// child order stays structural. Clicking a tab activates it; the `×`
/// closes it without activating (the close click must not bubble into the
/// tab's own handler).
pub fn tabs_bar(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  chips : Array[TabChip],
  actions : LauncherActions,
  menu_open~ : Bool,
  expanded~ : Bool,
  toggle_menu~ : @cmd.Cmd,
  close_menu~ : @cmd.Cmd,
  close_all_tabs~ : @cmd.Cmd,
  close_all_tabs_disabled~ : Bool,
  toggle_expanded~ : @cmd.Cmd,
) -> @html.Html {
  let menu : LauncherMenu = { toggle: toggle_menu, dismiss: close_menu, }
  let tabs : Array[@html.Html] = []
  for chip in chips {
    let mut classes = "editor-tab"
    if state.active is Some(active) && active == chip.tab {
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
            title=ui(locale, CloseLabel),
            attrs=@html.Attrs::build()
              .aria_label(ui(locale, CloseLabel))
              .on_click(event => {
                event.stop_propagation()
                dispatch(TabClosed(tab))
              }),
            @icons.icon(@icons.icon_close),
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
      title=ui(locale, CloseAllTabs),
      attrs=@html.Attrs::build()
        .aria_label(ui(locale, CloseAllTabs))
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
      title=ui(locale, NewTab),
      attrs=@html.Attrs::build()
        .id("dock-new-tab")
        .aria_haspopup("menu")
        .aria_controls("dock-new-tab-menu")
        .aria_expanded(menu_open.to_string()),
      on_click=menu.toggle(),
      @icons.icon(@icons.icon_add),
    ),
    @html.button(
      class="panel-toggle panel-expand",
      title=if expanded {
        ui(locale, RestorePanel)
      } else {
        ui(locale, ExpandPanel)
      },
      attrs=@html.Attrs::build()
        .aria_label(
          if expanded {
            ui(locale, RestorePanel)
          } else {
            ui(locale, ExpandPanel)
          },
        )
        .aria_pressed(expanded.to_string())
        .on_click(_ => toggle_expanded),
      @icons.icon(if expanded { icon_restore_panel } else { icon_expand_panel }),
    ),
  ]
  if menu_open {
    // No backdrop element: the frontend package installs a click-away
    // dismissal that does not consume the click that closes it.
    children.push(
      @html.div(
        class="menu-surface dock-menu",
        attrs=@html.Attrs::build()
          .id("dock-new-tab-menu")
          .role("menu")
          .aria_label(ui(locale, NewTab))
          .popover("manual")
          .on_keydown(event => menu.keydown(event)),
        actions.rows(locale~, popup=true),
      ),
    )
  }
  @html.div(class="editor-tabsbar", children)
}
