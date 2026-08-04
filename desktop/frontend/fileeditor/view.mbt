// The file subsystem's views: the viewer/tree body, the breadcrumb header,
// and the file-tree rows. The dock package renders the panel's tab strip;
// the root view assembles `div.editor` from the dock's parts and these, with
// dispatches pre-mapped to this package's `Msg`.

///|
/// The folder codicon for the tree-pane toggle, from Microsoft's
/// vscode-codicons (CC BY 4.0), embedded unmodified — mirrors the main
/// package's icon set, which is not importable from here.
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
/// The `div.editor` class list the root view wraps the panel's parts in:
/// tree visibility and the Settings-chosen dock layout are both classes, not
/// structure, so every state renders the same children in the same order and
/// the viewer host is never re-keyed. With no file open the breadcrumb row
/// hides (see `breadcrumb_view`) and takes the tree toggle with it, so the
/// tree must show regardless of the toggle's state — the panel is otherwise
/// a dead pane.
pub fn editor_classes(state : State, ctx : Ctx) -> String {
  let tree_visible = state.tree_open || ctx.active_file is None
  let mut classes = "editor"
  if tree_visible {
    classes = classes + " tree-open"
  }
  if ctx.tree_layout is RightSidebar {
    classes = classes + " tree-right"
  }
  classes
}

///|
/// A grab strip on the editor's left edge for drag-to-resize. Absolutely
/// positioned, so it is not a grid item and never disturbs the pane's
/// children; its drag is wired imperatively (see editor_resize.mbt). Always
/// rendered (CSS hides it while the panel is closed) so its position among
/// the editor's children — and thus the never-re-keyed viewer host — stays
/// stable.
pub fn resize_handle_view() -> @html.Html {
  @html.div(
    attrs=@html.Attrs::build().id(ResizeHandleId).class("editor-resize-handle"),
    ([] : Array[@html.Html]),
  )
}

///|
/// The viewer-plus-tree body under the strip and breadcrumb: the embedded
/// viewer with its notice overlay, and the workspace tree (filterable,
/// expandable, always rooted at the workspace root) as a toggleable pane on
/// the viewer's right. Always rendered so the viewer's host element
/// (`viewer-host`) stays put across renders and screen switches; CSS hides
/// the tree pane when toggled off and collapses the whole panel to zero
/// width when it is closed. The children's order is structural — rabbita
/// diffs by index, so every part renders unconditionally.
pub fn body_view(
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
  @html.div(class="editor-body", [
    @html.div(class="viewer-stack", [viewer_host, viewer_notice(state, ctx)]),
    tree_pane(dispatch, state, ctx),
  ])
}

///|
/// The notice covering the viewer while the active document has nothing to
/// show — a deleted, binary, or oversized file. Plain panel chrome laid
/// over the (cleared) viewer, so a notice never renders as a highlighted
/// source document. Always in the DOM; blank and hidden otherwise.
fn viewer_notice(state : State, ctx : Ctx) -> @html.Html {
  let text = match ctx.active_file {
    Some(path) =>
      match state.docs.get(path) {
        Some(doc) =>
          match doc.state {
            TabDeleted => "\{doc.name} was deleted on disk."
            TabBinary => "\{doc.name} is a binary file and cannot be previewed."
            TabOversized => "\{doc.name} is too large to preview."
            TabLoading | TabLoaded(..) => ""
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
/// The toggleable file-tree panel, docked flat under the viewer like an
/// Emacs bottom window: the tree rows, the last fs failure (blank and
/// collapsed while there is none — rendered unconditionally so the rows
/// never shift index), and the minibuffer-style filter line at the bottom
/// edge.
fn tree_pane(dispatch : @cmd.Emit[Msg], state : State, ctx : Ctx) -> @html.Html {
  let entries = visible_entries(state)
  // The filter's query, rebuilt here only to split each row's path into
  // matched/unmatched sections for highlighting — the rows themselves were
  // already ranked by `visible_entries`.
  let fuzzy = if state.filter.trim().is_empty() {
    None
  } else {
    Some(@fuzzy_match.Query::new(state.filter.trim().to_owned()))
  }
  let tree_children = if ctx.owner.session.is_empty() {
    [@html.div(class="file-panel-empty", "No conversation selected.")]
  } else if !state.children.contains("") {
    [@html.div(class="file-panel-empty", "Loading…")]
  } else if entries.is_empty() {
    if fuzzy is None {
      // The workspace exists once the conversation runs; until then (or if the
      // agent has written nothing) it is simply empty.
      [@html.div(class="file-panel-empty", "This workspace is empty.")]
    } else if state.index is IndexLoading {
      [@html.div(class="file-panel-empty", "Indexing files…")]
    } else {
      [@html.div(class="file-panel-empty", "No file matches the filter.")]
    }
  } else {
    let rows = entries.map(pair => {
      tree_row(dispatch, state, ctx, pair.0, pair.1, fuzzy~)
    })
    // Own up to a capped index: matches may simply be missing.
    if fuzzy is Some(_) && state.index is IndexReady(truncated=true, ..) {
      rows.push(
        @html.div(
          class="file-panel-empty",
          "File index truncated; some matches may be missing.",
        ),
      )
    }
    rows
  }
  @html.div(class="file-tree-pane", [
    // The grab strip on the panel's top seam for drag-to-resize; wired
    // imperatively like the editor's left-edge handle (see tree_resize.mbt).
    @html.div(
      attrs=@html.Attrs::build()
        .id(TreeResizeHandleId)
        .class("tree-resize-handle"),
      ([] : Array[@html.Html]),
    ),
    @html.div(class="file-tree", tree_children),
    // Rendered even while empty so the row's slot in the pane is stable.
    @html.div(
      class=if state.error is Some(_) {
        "file-panel-error"
      } else {
        "file-panel-error empty"
      },
      match state.error {
        Some(message) => message
        None => ""
      },
    ),
    // The filter line rides the bottom edge, minibuffer-style, and is the
    // keyboard's seat: ↑/↓ walk the rows, Enter acts on the cursor's row,
    // Escape clears the filter and then closes the panel.
    @html.div(class="file-tree-header", [
      @html.input(
        input_type=@html.InputType::Search,
        value=state.filter,
        placeholder="Filter files…",
        on_input=dispatch.map(value => FileFilterChanged(value)),
        attrs=@html.Attrs::build()
          .class("file-filter")
          .id(FilterInputId)
          .on_keydown(event => {
            match event.key() {
              "ArrowDown" => {
                event.prevent_default()
                dispatch(TreeKeyMove(delta=1))
              }
              "ArrowUp" => {
                event.prevent_default()
                dispatch(TreeKeyMove(delta=-1))
              }
              "Enter" =>
                if !event.is_composing() {
                  event.prevent_default()
                  dispatch(TreeKeyAccept)
                } else {
                  @cmd.none
                }
              "Escape" => {
                event.prevent_default()
                dispatch(TreeKeyDismiss)
              }
              _ => @cmd.none
            }
          }),
      ),
    ]),
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
/// The breadcrumb row under the tab bar: the active file's path as
/// `dir › dir › file` (the file segment emphasized) behind a leading
/// "Workspace" crumb. Every crumb but the last reveals that ancestor
/// directory in the tree pane when clicked (opening the pane if needed).
/// The tree-pane toggle rides this row's right edge, directly under the tab
/// bar's panel toggle. With no file open the whole row hides (via CSS — it
/// stays in the DOM so the editor's child order, and thus the viewer host,
/// is never re-keyed) and the tree shows unconditionally in its place.
pub fn breadcrumb_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let crumbs : Array[@html.Html] = []
  match ctx.active_file {
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
  @html.div(
    class=if ctx.active_file is None {
      "viewer-breadcrumb hidden"
    } else {
      "viewer-breadcrumb"
    },
    [
      @html.div(class="crumb-path", crumbs),
      @html.button(
        class="panel-toggle",
        title=if state.tree_open { "Hide file tree" } else { "Show file tree" },
        on_click=dispatch(ToggleTree),
        icon(icon_folder),
      ),
    ],
  )
}

///|
/// One visible tree row. The rows themselves come from `visible_entries`
/// (shared with the keyboard cursor, so the two can never disagree);
/// `depth` drives indentation. The keyboard cursor's row wears `cursor` on
/// top of whatever else applies. `fuzzy` present means filter mode: the row
/// is a ranked match, labeled with its whole relative path and the matched
/// characters highlighted.
fn tree_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  entry : FileEntry,
  depth : Int,
  fuzzy~ : @fuzzy_match.Query?,
) -> @html.Html {
  let pad = "padding-left: \{8 + depth * 14}px"
  let cursor = if state.cursor == Some(entry.path) { " cursor" } else { "" }
  if entry.is_dir {
    let chevron = if state.expanded.contains(entry.path) {
      "▾"
    } else {
      "▸"
    }
    // `data-path` is the hook `reveal_tree_row` / the keyboard cursor's
    // scroll-into-view use to find the row in the DOM.
    @html.div(
      class=(if state.highlighted == Some(entry.path) {
          "tree-row tree-dir highlighted"
        } else {
          "tree-row tree-dir"
        }) +
        cursor,
      style=[pad],
      on_click=dispatch(DirToggle(entry.path)),
      attrs=@html.Attrs::build().data_set("path", entry.path.0),
      [
        @html.span(class="tree-chevron", chevron),
        @html.span(class="tree-name", entry.name),
      ],
    )
  } else {
    let label = match fuzzy {
      Some(query) =>
        match query.split_by_matching_sections(item=entry.path.0) {
          Some(sections) =>
            @html.span(
              class="tree-name tree-path",
              sections.map(section => {
                let (matched, text) = section
                @html.span(
                  class=if matched { "tree-hit" } else { "" },
                  text.to_owned(),
                )
              }),
            )
          // Should not happen — the row is here because it matched — but a
          // plain path label beats dropping the row.
          None => @html.span(class="tree-name tree-path", entry.path.0)
        }
      None => @html.span(class="tree-name", entry.name)
    }
    @html.div(
      class=(if ctx.active_file == Some(entry.path) {
          "tree-row tree-file selected"
        } else {
          "tree-row tree-file"
        }) +
        cursor,
      style=[pad],
      on_click=dispatch(FileSelected(path=entry.path, name=entry.name)),
      attrs=@html.Attrs::build().data_set("path", entry.path.0),
      [label],
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
