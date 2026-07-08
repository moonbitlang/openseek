// The editor part's views: the panel (tree-or-file pane hosting the embedded
// viewer), its breadcrumb header, and the file-tree rows. Rendered by the
// main package's `view` through `panel_view`, with dispatches pre-mapped to
// this package's `Msg`.

///|
/// The sidebar-right codicon for the panel toggle, from Microsoft's
/// vscode-codicons (CC BY 4.0), embedded unmodified — mirrors the main
/// package's icon set, which is not importable from here.
let icon_layout_sidebar_right : String =
  #|<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M12.5 1C13.881 1 15 2.119 15 3.5V12.5C15 13.881 13.881 15 12.5 15H3.5C2.119 15 1 13.881 1 12.5V3.5C1 2.119 2.119 1 3.5 1H12.5ZM9 14V2H3.5C2.672 2 2 2.672 2 3.5V12.5C2 13.328 2.672 14 3.5 14H9Z"/></svg>

///|
/// The folder codicon for the tree-pane toggle (same provenance as above).
let icon_folder : String =
  #|<svg width="16" height="16" viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" fill="currentColor"><path d="M2 4.5V6H5.58579C5.71839 6 5.84557 5.94732 5.93934 5.85355L7.29289 4.5L5.93934 3.14645C5.84557 3.05268 5.71839 3 5.58579 3H3.5C2.67157 3 2 3.67157 2 4.5ZM1 4.5C1 3.11929 2.11929 2 3.5 2H5.58579C5.98361 2 6.36514 2.15804 6.64645 2.43934L8.20711 4H12.5C13.8807 4 15 5.11929 15 6.5V11.5C15 12.8807 13.8807 14 12.5 14H3.5C2.11929 14 1 12.8807 1 11.5V4.5ZM2 7V11.5C2 12.3284 2.67157 13 3.5 13H12.5C13.3284 13 14 12.3284 14 11.5V6.5C14 5.67157 13.3284 5 12.5 5H8.20711L6.64645 6.56066C6.36514 6.84197 5.98361 7 5.58579 7H2Z"/></svg>

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
/// The editor part: a tab strip of open files over the embedded viewer, with
/// the workspace tree (filterable, expandable, always rooted at the
/// workspace root) as a toggleable pane on the viewer's right. The whole
/// part is always rendered so the viewer's host element (`viewer-host`)
/// stays put across renders and screen switches; CSS hides the tree pane
/// when toggled off and collapses the whole pane to zero width when the
/// panel is closed. The children's order is structural — rabbita diffs by
/// index, so every part renders unconditionally.
pub fn panel_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  // The stable element the viewer attaches its imperative DOM into; it must
  // stay empty and never be re-keyed (see editor_panel.mbt).
  // `editor-shell` brings in the viewer's `--vscode-*` / `--editor-*` theme
  // variables (defined on that class in the bundled viewer.css); `data-theme`
  // picks the palette matching the app's own light/dark scheme (the shell's
  // default is dark, `light` overrides). The viewer's colors cascade from
  // this host.
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class("viewer-host editor-shell")
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  // A grab strip on the editor's left edge for drag-to-resize. Absolutely
  // positioned, so it is not a grid item and never disturbs the pane's
  // children; its drag is wired imperatively (see editor_resize.mbt). Always
  // rendered (CSS hides it while the panel is closed) so its position among
  // the editor's children — and thus the never-re-keyed viewer host — stays
  // stable.
  let resize_handle = @html.div(
    attrs=@html.Attrs::build().id(ResizeHandleId).class("editor-resize-handle"),
    ([] : Array[@html.Html]),
  )
  @html.div(class=if state.tree_open { "editor tree-open" } else { "editor" }, [
    resize_handle,
    tabs_bar(dispatch, state),
    viewer_breadcrumb(dispatch, state),
    @html.div(class="editor-body", [
      @html.div(class="viewer-stack", [viewer_host, viewer_notice(state)]),
      tree_pane(dispatch, state, ctx),
    ]),
  ])
}

///|
/// The editor's top bar, aligned with the topbar: the open-file tabs, with
/// the whole-panel toggle riding the right edge (the topbar only shows the
/// open toggle while the panel is closed). Always rendered so the editor's
/// child order stays structural. Clicking a tab activates it; the `×`
/// closes it without activating (the close click must not bubble into the
/// tab's own handler).
fn tabs_bar(dispatch : @cmd.Emit[Msg], state : State) -> @html.Html {
  let tabs : Array[@html.Html] = []
  for tab in state.tabs {
    let mut classes = "editor-tab"
    if state.active == Some(tab.path) {
      classes = classes + " active"
    }
    if tab.state is TabDeleted {
      classes = classes + " deleted"
    }
    tabs.push(
      @html.div(
        class=classes,
        title=tab.path.0,
        on_click=dispatch(TabActivated(tab.path)),
        [
          @html.span(class="tab-name", tab.name),
          @html.button(
            class="tab-close",
            title="Close",
            attrs=@html.Attrs::build().on_click(event => {
              event.stop_propagation()
              dispatch(TabClosed(tab.path))
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
      on_click=dispatch(ToggleFilePanel),
      icon(icon_layout_sidebar_right),
    ),
  ])
}

///|
/// The notice covering the viewer while the active tab has no document to
/// show — a deleted, binary, or oversized file. Plain panel chrome laid
/// over the (cleared) viewer, so a notice never renders as a highlighted
/// source document. Always in the DOM; blank and hidden otherwise.
fn viewer_notice(state : State) -> @html.Html {
  let text = match state.active {
    Some(path) =>
      match state.tabs.search_by(tab => tab.path == path) {
        Some(index) => {
          let tab = state.tabs[index]
          match tab.state {
            TabDeleted => "\{tab.name} was deleted on disk."
            TabBinary => "\{tab.name} is a binary file and cannot be previewed."
            TabOversized => "\{tab.name} is too large to preview."
            TabLoading | TabLoaded(..) => ""
          }
        }
        None => ""
      }
    None => ""
  }
  @html.div(
    class=if text.is_empty() { "viewer-notice hidden" } else { "viewer-notice" },
    text,
  )
}

///|
/// The toggleable file-tree pane on the viewer's right: the filter header,
/// the last fs failure (blank and collapsed while there is none — rendered
/// unconditionally so the rows below never shift index), and the tree rows.
fn tree_pane(dispatch : @cmd.Emit[Msg], state : State, ctx : Ctx) -> @html.Html {
  let query = state.filter.trim().to_owned()
  let tree_children = if ctx.session.is_empty() {
    [@html.div(class="file-panel-empty", "No conversation selected.")]
  } else if !state.children.contains("") {
    [@html.div(class="file-panel-empty", "Loading…")]
  } else if !query.is_empty() {
    // Filtering flattens the loaded tree to the matching rows.
    let rows = []
    filtered_file_rows(dispatch, state, "", query.to_lower(), rows)
    if rows.is_empty() {
      [@html.div(class="file-panel-empty", "No file matches the filter.")]
    } else {
      rows
    }
  } else {
    let rows = file_tree_rows(dispatch, state, "", 0)
    if rows.is_empty() {
      // The workspace exists once the conversation runs; until then (or if the
      // agent has written nothing) it is simply empty.
      [@html.div(class="file-panel-empty", "This workspace is empty.")]
    } else {
      rows
    }
  }
  @html.div(class="file-tree-pane", [
    // The filter box, in a header bar matching the topbar/breadcrumb height.
    @html.div(class="file-tree-header", [
      @html.input(
        input_type=@html.InputType::Search,
        value=state.filter,
        placeholder="Filter files…",
        on_input=dispatch.map(value => FileFilterChanged(value)),
        attrs=@html.Attrs::build().class("file-filter"),
      ),
    ]),
    @html.div(
      class=if state.error.is_empty() {
        "file-panel-error empty"
      } else {
        "file-panel-error"
      },
      state.error,
    ),
    @html.div(class="file-tree", tree_children),
  ])
}

///|
/// Split a relative path into its non-empty segments, e.g.
/// `"cef/runtime.mbt"` → `["cef", "runtime.mbt"]`.
fn path_segments(path : @pathx.Relative) -> Array[String] {
  let segments : Array[String] = []
  let mut rest = path.0
  while rest.split_once("/") is Some((head, tail)) {
    if !head.is_empty() {
      segments.push(head.to_owned())
    }
    rest = tail.to_owned()
  }
  if !rest.is_empty() {
    segments.push(rest)
  }
  segments
}

///|
/// The path formed by joining `segments`' first `count` entries, e.g.
/// `segments_prefix(["cef", "runtime.mbt"], 1)` → `"cef"`. The inverse of
/// `path_segments`, used to recover an ancestor directory's path for a
/// breadcrumb click.
fn segments_prefix(segments : Array[String], count : Int) -> @pathx.Relative {
  let mut path = @pathx.Relative::root()
  for index in 0..<count {
    path = child_path(path, segments[index])
  }
  path
}

///|
/// The proper ancestors of `path`, nearest-root first, e.g.
/// `ancestor_paths("src/foo/bar.mbt")` → `["src", "src/foo"]`. Excludes the
/// workspace root and `path` itself.
fn ancestor_paths(path : @pathx.Relative) -> Array[@pathx.Relative] {
  let segments = path_segments(path)
  let paths : Array[@pathx.Relative] = []
  for count in 1..<segments.length() {
    paths.push(segments_prefix(segments, count))
  }
  paths
}

///|
/// A breadcrumb segment that reveals `path` in the tree when clicked.
fn crumb_link(
  dispatch : @cmd.Emit[Msg],
  label : String,
  path : @pathx.Relative,
) -> @html.Html {
  @html.span(
    class="crumb",
    attrs=@html.Attrs::build().on_click(_ => dispatch(RevealDirectory(path))),
    label,
  )
}

///|
/// The breadcrumb row under the tab bar: with a tab active, its path as
/// `dir › dir › file` (the file segment emphasized) behind a leading
/// "Workspace" crumb; otherwise just the "Workspace" crumb, since the tree
/// is always rooted there. Every crumb but the last reveals that ancestor
/// directory in the tree pane when clicked (opening the pane if needed).
/// The tree-pane toggle rides this row's right edge, directly under the tab
/// bar's panel toggle.
fn viewer_breadcrumb(dispatch : @cmd.Emit[Msg], state : State) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  match state.active {
    Some(path) => {
      crumbs.push(crumb_link(dispatch, "Workspace", @pathx.Relative::root()))
      let segments = path_segments(path)
      for index, segment in segments {
        crumbs.push(@html.span(class="crumb-sep", "›"))
        if index == segments.length() - 1 {
          crumbs.push(@html.span(class="crumb crumb-file", segment))
        } else {
          crumbs.push(
            crumb_link(dispatch, segment, segments_prefix(segments, index + 1)),
          )
        }
      }
    }
    None => crumbs.push(@html.span(class="crumb crumb-file", "Workspace"))
  }
  @html.div(class="viewer-breadcrumb", [
    @html.div(class="crumb-path", crumbs),
    @html.button(
      class="panel-toggle",
      title=if state.tree_open { "Hide file tree" } else { "Show file tree" },
      on_click=dispatch(ToggleTree),
      icon(icon_folder),
    ),
  ])
}

///|
/// The rows for the entries of one directory, with expanded directories'
/// children spliced in beneath them, depth-first. `depth` drives indentation.
fn file_tree_rows(
  dispatch : @cmd.Emit[Msg],
  state : State,
  dir_path : @pathx.Relative,
  depth : Int,
) -> Array[@html.Html] {
  guard state.children.get(dir_path) is Some(entries) else { return [] }
  let rows : Array[@html.Html] = []
  for entry in entries {
    rows.push(tree_row(dispatch, state, entry, depth))
    if entry.is_dir && state.expanded.contains(entry.path) {
      for child in file_tree_rows(dispatch, state, entry.path, depth + 1) {
        rows.push(child)
      }
    }
  }
  rows
}

///|
/// Filter mode: walk the already-loaded tree depth-first and append every entry
/// whose name contains `query` (already lower-cased) as a flat row. Only loaded
/// directories are descended into, so the filter spans the root listing plus
/// whatever the user has expanded.
fn filtered_file_rows(
  dispatch : @cmd.Emit[Msg],
  state : State,
  dir_path : @pathx.Relative,
  query : String,
  into : Array[@html.Html],
) -> Unit {
  guard state.children.get(dir_path) is Some(entries) else { return }
  for entry in entries {
    if entry.name.to_lower().contains(query) {
      into.push(tree_row(dispatch, state, entry, 0))
    }
    if entry.is_dir {
      filtered_file_rows(dispatch, state, entry.path, query, into)
    }
  }
}

///|
fn tree_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  entry : FileEntry,
  depth : Int,
) -> @html.Html {
  let pad = "padding-left: \{8 + depth * 14}px"
  if entry.is_dir {
    let chevron = if state.expanded.contains(entry.path) {
      "▾"
    } else {
      "▸"
    }
    // `data-path` is `reveal_tree_row`'s hook for scrolling a breadcrumb's
    // `RevealDirectory` target into view.
    @html.div(
      class=if state.highlighted == Some(entry.path) {
        "tree-row tree-dir highlighted"
      } else {
        "tree-row tree-dir"
      },
      style=[pad],
      on_click=dispatch(DirToggle(entry.path)),
      attrs=@html.Attrs::build().data_set("path", entry.path.0),
      [
        @html.span(class="tree-chevron", chevron),
        @html.span(class="tree-name", entry.name),
      ],
    )
  } else {
    @html.div(
      class=if state.active == Some(entry.path) {
        "tree-row tree-file selected"
      } else {
        "tree-row tree-file"
      },
      style=[pad],
      on_click=dispatch(FileSelected(path=entry.path, name=entry.name)),
      [@html.span(class="tree-name", entry.name)],
    )
  }
}

///|
/// Scroll a `RevealDirectory` target's tree row into view once it exists in
/// the DOM; a no-op while its ancestors are still loading (retried once they
/// finish, see `DirLoaded`).
fn reveal_row_after_render(path : @pathx.Relative) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => reveal_tree_row(path), kind=@cmd.after_render)
}

///|
fn reveal_tree_row(path : @pathx.Relative) -> Unit {
  match
    @dom.document().query_selector("[data-path=\"" + path.0 + "\"]").to_option() {
    Some(element) => element.scroll_into_view(behavior="smooth")
    None => ()
  }
}
