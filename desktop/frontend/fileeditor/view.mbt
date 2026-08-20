// The file subsystem's views: the viewer/tree body, the breadcrumb header,
// and the file-tree rows. The dock package renders the panel's tab strip;
// the root view assembles `div.editor` from the dock's parts and these, with
// dispatches pre-mapped to this package's `Msg`.

///|
/// The folder codicon for the tree-pane toggle, from Microsoft's
/// vscode-codicons (CC BY 4.0); the path data is unmodified, transcribed
/// into `@svg` builders (an innerHTML-bearing element cannot be safely
/// morphed by the positional child diff) — mirrors the main package's icon
/// set, which is not importable from here.
fn icon_folder() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build().fill("currentColor"),
    [
      @svg.path(
        d="M2 4.5V6H5.58579C5.71839 6 5.84557 5.94732 5.93934 5.85355L7.29289 4.5L5.93934 3.14645C5.84557 3.05268 5.71839 3 5.58579 3H3.5C2.67157 3 2 3.67157 2 4.5ZM1 4.5C1 3.11929 2.11929 2 3.5 2H5.58579C5.98361 2 6.36514 2.15804 6.64645 2.43934L8.20711 4H12.5C13.8807 4 15 5.11929 15 6.5V11.5C15 12.8807 13.8807 14 12.5 14H3.5C2.11929 14 1 12.8807 1 11.5V4.5ZM2 7V11.5C2 12.3284 2.67157 13 3.5 13H12.5C13.3284 13 14 12.3284 14 11.5V6.5C14 5.67157 13.3284 5 12.5 5H8.20711L6.64645 6.56066C6.36514 6.84197 5.98361 7 5.58579 7H2Z",
      ),
    ],
  )
}

///|
/// The file codicon used by the breadcrumb picker, from Microsoft's
/// vscode-codicons (CC BY 4.0).
fn icon_file() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build().fill("currentColor"),
    [
      @svg.path(
        d="M13.85 4.44l-3.28-3.3L10.22 1H2.5l-.5.5v13l.5.5h11l.5-.5V4.8l-.15-.36zM13 14H3V2h6v3.5l.5.5H13v8zm0-9h-3V2.1L12.9 5h.1z",
      ),
    ],
  )
}

///|
const ExplorerFilesTabId = "explorer-files-tab"

///|
const ExplorerChangesTabId = "explorer-changes-tab"

///|
const ExplorerSearchTabId = "explorer-search-tab"

///|
const ExplorerPanelId = "explorer-inventory"

///|
const BreadcrumbPickerId = "breadcrumb-directory-picker"

///|
fn breadcrumb_entry_id(index : Int) -> String {
  "breadcrumb-entry-\{index}"
}

///|
fn focus_breadcrumb_entry_after_render(index : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id(breadcrumb_entry_id(index))
        .to_option()
        is Some(row) {
        let _ : @js.Value = @js.Value::cast_from(row).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn focus_explorer_tab_after_render(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(id).to_option() is Some(tab) {
        let _ : @js.Value = @js.Value::cast_from(tab).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn explorer_tab_id(mode : ExplorerMode) -> String {
  match mode {
    ExplorerFiles => ExplorerFilesTabId
    ExplorerChanges => ExplorerChangesTabId
    ExplorerSearch => ExplorerSearchTabId
  }
}

///|
fn ExplorerMode::next(self : ExplorerMode) -> ExplorerMode {
  match self {
    ExplorerFiles => ExplorerChanges
    ExplorerChanges => ExplorerSearch
    ExplorerSearch => ExplorerFiles
  }
}

///|
fn ExplorerMode::previous(self : ExplorerMode) -> ExplorerMode {
  match self {
    ExplorerFiles => ExplorerSearch
    ExplorerChanges => ExplorerFiles
    ExplorerSearch => ExplorerChanges
  }
}

///|
fn explorer_tab_key_target(mode : ExplorerMode, key : String) -> ExplorerMode? {
  match key {
    "Home" => Some(ExplorerFiles)
    "End" => Some(ExplorerSearch)
    "ArrowRight" | "ArrowDown" => Some(mode.next())
    "ArrowLeft" | "ArrowUp" => Some(mode.previous())
    _ => None
  }
}

///|
/// One entry in the Files / Changes / Search roving tablist. Arrow keys wrap,
/// while Home and End select the first and last inventories.
fn explorer_tab(
  dispatch : @cmd.Emit[Msg],
  selected : ExplorerMode,
  mode : ExplorerMode,
  title : String,
  children : Array[@html.Html],
) -> @html.Html {
  let active = selected == mode
  @html.button(
    class=if active { "explorer-tab active" } else { "explorer-tab" },
    title~,
    on_click=dispatch(ExplorerModeSelected(mode)),
    attrs=@html.Attrs::build()
      .id(explorer_tab_id(mode))
      .role("tab")
      .tabindex(if active { 0 } else { -1 })
      .aria_controls(ExplorerPanelId)
      .aria_selected(active.to_string())
      .on_keydown(event => {
        match explorer_tab_key_target(mode, event.key()) {
          Some(target) => {
            event.prevent_default()
            @cmd.batch([
              dispatch(ExplorerModeSelected(target)),
              focus_explorer_tab_after_render(explorer_tab_id(target)),
            ])
          }
          None => @cmd.none
        }
      }),
    children,
  )
}

///|
fn changed_file_row_id(index : Int) -> String {
  "changed-file-row-\{index}"
}

///|
fn focus_changed_file_after_render(index : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id(changed_file_row_id(index))
        .to_option()
        is Some(row) {
        let _ : @js.Value = @js.Value::cast_from(row).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
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
/// viewer with its notice overlay, and the workspace tree (expandable and
/// always rooted at the workspace root) as a toggleable pane on
/// the viewer's right. Always rendered so the viewer's host element
/// (`viewer-host` and `unified-diff-host`) stay put across renders and screen
/// switches; CSS hides the inactive surface and the tree pane when toggled off,
/// and collapses the whole panel to zero width when it is closed. The children's
/// order is structural — rabbita diffs by index, so every part renders
/// unconditionally.
pub fn body_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  // The stable elements the source Viewer and switchable DiffViewer attach
  // their imperative DOM into; they must stay empty and never be re-keyed
  // (see editor_panel.mbt).
  // `editor-shell` brings in the viewer's `--vscode-*` / `--editor-*` theme
  // variables (defined on that class in the bundled viewer.css); `data-theme`
  // picks the palette matching the app's own light/dark scheme (the shell's
  // default is dark, `light` overrides). The viewer's colors cascade from
  // this host.
  let use_unified_diff_surface = match ctx.active_file {
    Some(path) =>
      state.docs
      .get(path)
      .map(doc => doc.uses_unified_diff_surface())
      .unwrap_or(false)
    None => false
  }
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class(
        if use_unified_diff_surface {
          "viewer-host editor-shell moonbit-viewer-surface-hidden"
        } else {
          "viewer-host editor-shell"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  let unified_diff_host = @html.div(
    attrs=@html.Attrs::build()
      .id(DiffViewerHostId)
      .class(
        if use_unified_diff_surface {
          "viewer-host editor-shell"
        } else {
          "viewer-host editor-shell moonbit-viewer-surface-hidden"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  @html.div(class="editor-body", [
    @html.div(class="viewer-stack", [
      viewer_host,
      unified_diff_host,
      viewer_notice(state, ctx),
    ]),
    tree_pane(dispatch, state, ctx),
  ])
}

///|
/// The notice covering the viewer while the active document has nothing to
/// show — a deleted, unavailable, binary, or oversized file. Plain panel
/// chrome laid over the (cleared) viewer, so a notice never renders as a
/// highlighted source document. Always in the DOM; blank and hidden otherwise.
fn viewer_notice(state : State, ctx : Ctx) -> @html.Html {
  let diff_pending = match ctx.active_file {
    Some(path) =>
      state.docs
      .get(path)
      .map(doc => doc.unified_diff_is_pending())
      .unwrap_or(false)
    None => false
  }
  let text = match ctx.active_file {
    Some(path) =>
      match state.docs.get(path) {
        Some(doc) if state.shows_delayed_diff_loading(doc) =>
          "Loading diff for \{doc.name}…"
        Some(doc) =>
          match doc.state {
            TabDeleted =>
              match doc.review {
                Some({ baseline: ReviewLoading, .. }) =>
                  "Loading the review baseline for \{doc.name}…"
                Some({ baseline: ReviewContent(_), .. }) => ""
                Some({ baseline: ReviewMissing, .. }) =>
                  "\{doc.name} was deleted and has no review baseline to preview."
                Some({ baseline: ReviewBinary, .. }) =>
                  "The review baseline for \{doc.name} is binary and cannot be previewed."
                Some({ baseline: ReviewOversized, .. }) =>
                  "The review baseline for \{doc.name} is too large to preview."
                Some({ baseline: ReviewFailed(message), .. }) =>
                  "Could not load the review baseline for \{doc.name}: \{message}."
                None => "\{doc.name} was deleted on disk."
              }
            TabBinary => "\{doc.name} is a binary file and cannot be previewed."
            TabOversized => "\{doc.name} is too large to preview."
            TabReadFailed(message) =>
              if doc.review is Some({ baseline: ReviewContent(_), .. }) {
                ""
              } else {
                "Could not read \{doc.name}: \{message}."
              }
            TabUnavailable(message) => message
            TabLoading | TabLoaded(..) => ""
          }
        None => ""
      }
    None => ""
  }
  @html.div(
    class=if !text.is_empty() {
      "viewer-notice"
    } else if diff_pending {
      // Preserve the last complete diff for a fast replacement without
      // letting clicks or selection reach that now-stale comparison. If the
      // delay expires this same overlay becomes the opaque loading notice.
      "viewer-notice diff-transition-shield"
    } else {
      "viewer-notice hidden"
    },
    text,
  )
}

///|
/// The toggleable file-tree panel, docked flat under the viewer like an Emacs
/// bottom window: the hierarchical tree rows and the last fs failure (blank
/// and collapsed while there is none).
fn tree_pane(dispatch : @cmd.Emit[Msg], state : State, ctx : Ctx) -> @html.Html {
  // Losing the watcher is more important than a request-local failure: live
  // updates remain disabled even if a later directory request succeeds.
  let visible_error = if state.explorer_mode is ExplorerSearch {
    None
  } else {
    match state.watch_error {
      Some(message) => Some(message)
      None => state.error
    }
  }
  let inventory = if ctx.placement is None {
    [@html.div(class="file-panel-empty", "Waiting for workspace placement…")]
  } else if ctx.placement is Some(@interop.MissingWorktree(..)) {
    [@html.div(class="file-panel-empty", "Worktree checkout is missing.")]
  } else if ctx.owner.session.is_empty() {
    [@html.div(class="file-panel-empty", "No conversation selected.")]
  } else {
    match state.explorer_mode {
      ExplorerFiles => file_inventory(dispatch, state, ctx)
      ExplorerChanges => change_inventory(dispatch, state, ctx)
      ExplorerSearch =>
        [
          state.search.explorer_view(
            ctx.search_input(),
            dispatch.map(msg => Search(msg)),
            (path, range) => dispatch(SearchMatchSelected(path~, range~)),
          ),
        ]
    }
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
    @html.div(
      class="explorer-tabs",
      attrs=@html.Attrs::build().role("tablist").aria_label("Explorer views"),
      [
        explorer_tab(
          dispatch,
          state.explorer_mode,
          ExplorerFiles,
          "Workspace files",
          [@html.span("Files")],
        ),
        explorer_tab(
          dispatch,
          state.explorer_mode,
          ExplorerChanges,
          "Changed files (click again to refresh)",
          [@html.span("Changes"), change_count(state.changes)],
        ),
        explorer_tab(
          dispatch,
          state.explorer_mode,
          ExplorerSearch,
          "Search across the workspace",
          [@html.span("Search")],
        ),
      ],
    ),
    @html.div(
      class=if state.explorer_mode is ExplorerSearch {
        "file-tree search-inventory"
      } else {
        "file-tree"
      },
      attrs=@html.Attrs::build()
        .id(ExplorerPanelId)
        .role("tabpanel")
        .aria_labelledby(explorer_tab_id(state.explorer_mode)),
      inventory,
    ),
    // Rendered even while empty so the row's slot in the pane is stable.
    @html.div(
      class=if visible_error is Some(_) {
        "file-panel-error"
      } else {
        "file-panel-error empty"
      },
      match visible_error {
        Some(message) => message
        None => ""
      },
    ),
  ])
}

///|
fn change_count(changes : ChangeList) -> @html.Html {
  match changes {
    ChangeListReady(repository=true, files~, ..) =>
      @html.span(class="explorer-count", files.length().to_string())
    _ => @html.span(class="explorer-count hidden", "")
  }
}

///|
fn file_inventory(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> Array[@html.Html] {
  let entries = visible_entries(state)
  if !state.children.contains("") {
    [@html.div(class="file-panel-empty", "Loading…")]
  } else if entries.is_empty() {
    // The workspace exists once the conversation runs; until then (or if the
    // agent has written nothing) it is simply empty.
    [@html.div(class="file-panel-empty", "This workspace is empty.")]
  } else {
    entries.map(pair => tree_row(dispatch, state, ctx, pair.0, pair.1))
  }
}

///|
fn change_inventory(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> Array[@html.Html] {
  match state.changes {
    ChangeListIdle | ChangeListLoading(_) =>
      [@html.div(class="file-panel-empty", "Loading changes…")]
    ChangeListFailed(message) =>
      [
        @html.div(
          class="file-panel-empty",
          "Could not load changed files: \{message}. Click Changes to retry.",
        ),
      ]
    ChangeListReady(repository=false, ..) =>
      [
        @html.div(
          class="file-panel-empty",
          "Git is unavailable or this workspace is not a Git repository.",
        ),
      ]
    ChangeListReady(files~, ..) =>
      if files.is_empty() {
        [@html.div(class="file-panel-empty", "No changed files.")]
      } else {
        let reviewable = files.filter(change => change.selectable())
        let reviewed = reviewable
          .filter(change => state.reviewed_changes.contains(change))
          .length()
        let rows = [
          @html.div(
            class="review-progress-summary",
            if reviewable.is_empty() {
              "No reviewable text files"
            } else {
              "\{reviewed} of \{reviewable.length()} reviewable files reviewed"
            },
          ),
        ]
        for index, change in files {
          rows.push(changed_file_row(dispatch, state, ctx, change, index))
        }
        rows
      }
  }
}

///|
fn ChangedFile::kind_class(self : ChangedFile) -> String {
  if self.kind is ChangeSubmodule && self.has_unmerged_status() {
    return "unmerged"
  }
  match self.kind {
    ChangeAdded | ChangeUntracked => "added"
    ChangeDeleted => "deleted"
    ChangeRenamed | ChangeCopied => "renamed"
    ChangeUnmerged => "unmerged"
    ChangeModified
    | ChangeTypeChanged
    | ChangeSubmodule
    | ChangeSymlink
    | ChangeUnknown => "modified"
  }
}

///|
fn changed_file_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  change : ChangedFile,
  index : Int,
) -> @html.Html {
  let selected = change.is_selected(state, ctx)
  let reviewed = state.reviewed_changes.contains(change)
  let mut class = if selected { "change-row selected" } else { "change-row" }
  if reviewed {
    class = class + " reviewed"
  }
  if !change.selectable() {
    class = class + " disabled"
  }
  let children = [
    @html.span(class="change-path", change.path.0),
    @html.span(
      class="change-status " + change.kind_class(),
      change.status_label(),
    ),
    @html.span(
      class=if change.selectable() {
        "change-action"
      } else {
        "change-action unavailable"
      },
      if change.selectable() {
        if reviewed {
          "✓ Reviewed"
        } else {
          "View diff"
        }
      } else {
        "Unavailable"
      },
    ),
  ]
  if change.selectable() {
    // A native button supplies keyboard activation (Enter/Space) and focus
    // semantics without duplicating the tab strip's custom key handling.
    @html.button(
      class~,
      title="Open diff — " + change.status_title(),
      on_click=dispatch(ChangedFileSelected(change)),
      attrs=@html.Attrs::build()
        .id(changed_file_row_id(index))
        .data_set("path", change.path.0)
        .aria_label("View diff: " + change.status_title())
        .aria_current(if selected { "page" } else { "false" })
        .on_keydown(event => {
          let destination = match event.key() {
            "ArrowUp" => review_neighbor(state, change, -1)
            "ArrowDown" => review_neighbor(state, change, 1)
            "Home" => review_edge(state, change, first=true)
            "End" => review_edge(state, change, first=false)
            _ => None
          }
          match destination {
            Some(destination) => {
              event.prevent_default()
              @cmd.batch([
                dispatch(ChangedFileSelected(destination)),
                match change_row_index(state, destination) {
                  Some(index) => focus_changed_file_after_render(index)
                  None => @cmd.none
                },
              ])
            }
            None => @cmd.none
          }
        }),
      children,
    )
  } else {
    @html.div(
      class~,
      title=change.unselectable_title(),
      attrs=@html.Attrs::build()
        .id(changed_file_row_id(index))
        .data_set("path", change.path.0)
        .role("button")
        .aria_disabled("true")
        .tabindex(0)
        .aria_label(change.unselectable_title())
        .aria_current(if selected { "page" } else { "false" }),
      children,
    )
  }
}

///|
fn reviewable_changes(state : State) -> Array[ChangedFile] {
  match state.changes {
    ChangeListReady(files~, ..) => files.filter(change => change.selectable())
    _ => []
  }
}

///|
fn change_row_index(state : State, selected : ChangedFile) -> Int? {
  guard state.changes is ChangeListReady(files~, ..) else { return None }
  for index in 0..<files.length() {
    if files[index] == selected {
      return Some(index)
    }
  }
  None
}

///|
/// Adjacent reviewable row for list-keyboard navigation. Exact row equality
/// keeps staged-delete plus same-path untracked pairs independently ordered.
fn review_neighbor(
  state : State,
  selected : ChangedFile,
  delta : Int,
) -> ChangedFile? {
  let changes = reviewable_changes(state)
  for index in 0..<changes.length() {
    if changes[index] == selected {
      let destination = index + delta
      if destination >= 0 && destination < changes.length() {
        return Some(changes[destination])
      }
      return None
    }
  }
  None
}

///|
fn review_edge(
  state : State,
  selected : ChangedFile,
  first~ : Bool,
) -> ChangedFile? {
  let changes = reviewable_changes(state)
  guard !changes.is_empty() else { return None }
  let edge = changes[if first { 0 } else { changes.length() - 1 }]
  if edge == selected {
    None
  } else {
    Some(edge)
  }
}

///|
fn active_review_position(state : State, ctx : Ctx) -> (ChangedFile, Int, Int)? {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some({ review: Some(review), .. }) else {
    return None
  }
  let changes = reviewable_changes(state)
  for index in 0..<changes.length() {
    if changes[index] == review.selected {
      return Some((review.selected, index, changes.length()))
    }
  }
  None
}

///|
/// A normal file open selects its matching path in Changes. A review open is
/// more precise: porcelain can report two rows for one path (for example a
/// staged deletion plus a recreated untracked file), so only the exact row
/// parked in the document's review state is current.
fn ChangedFile::is_selected(
  self : ChangedFile,
  state : State,
  ctx : Ctx,
) -> Bool {
  guard ctx.active_file == Some(self.path) else { return false }
  match state.docs.get(self.path) {
    Some({ review: Some(review), .. }) => review.selected == self
    _ => true
  }
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
/// A breadcrumb segment that opens `path`'s immediate children in the
/// anchored picker below the breadcrumb.
fn crumb_link(
  dispatch : @cmd.Emit[Msg],
  label : String,
  path : @pathx.Relative,
  open : Bool,
) -> @html.Html {
  @html.button(
    type_="button",
    class="crumb crumb-directory",
    title="Show files in \{label}",
    on_click=dispatch(RevealDirectory(path)),
    attrs=@html.Attrs::build()
      .aria_controls(BreadcrumbPickerId)
      .aria_expanded(open.to_string())
      .on_keydown(event => {
        if open && event.key() == "Escape" {
          event.prevent_default()
          dispatch(HighlightCleared(path))
        } else {
          @cmd.none
        }
      }),
    label,
  )
}

///|
/// The breadcrumb row under the tab bar: the active file's path as
/// `dir › dir › file` (the file segment emphasized) behind a leading
/// "Workspace" crumb. Every crumb but the last opens a VS Code-style picker
/// of that directory's immediate children, without moving or hiding the
/// source viewer behind it.
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
      crumbs.push(
        crumb_link(
          dispatch,
          "Workspace",
          @pathx.Relative::root(),
          state.highlighted == Some(@pathx.Relative::root()),
        ),
      )
      let segments = path_segments(path)
      for index, segment in segments {
        crumbs.push(@html.span(class="crumb-sep", "›"))
        if index == segments.length() - 1 {
          crumbs.push(@html.span(class="crumb crumb-file", segment))
        } else {
          crumbs.push(
            crumb_link(
              dispatch,
              segment,
              segments_prefix(segments, index + 1),
              state.highlighted == Some(segments_prefix(segments, index + 1)),
            ),
          )
        }
      }
    }
    None => crumbs.push(@html.span(class="crumb crumb-file", "Workspace"))
  }
  let children : Array[@html.Html] = [
    @html.div(class="crumb-path", crumbs),
    review_navigation(dispatch, state, ctx),
    review_badge(dispatch, state, ctx),
    review_diff_layout_toggle(dispatch, state, ctx),
    review_progress(dispatch, state, ctx),
    @html.button(
      class="panel-toggle",
      title=if state.tree_open { "Hide file tree" } else { "Show file tree" },
      on_click=dispatch(ToggleTree),
      icon(icon_folder),
    ),
  ]
  if state.highlighted is Some(directory) {
    children.push(breadcrumb_picker(dispatch, state, ctx, directory))
  }
  @html.div(
    class=if ctx.active_file is None {
      "viewer-breadcrumb hidden"
    } else {
      "viewer-breadcrumb"
    },
    children,
  )
}

///|
/// The full comparison keeps its two models mounted while this compact control
/// changes only their layout. Source mode hides the control but preserves the
/// panel preference for the next full-diff reveal.
fn review_diff_layout_toggle(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some({ view_mode: ReviewUnifiedDiff, .. }) &&
    doc.unified_diff_content() is Some(_) else {
    return @html.span(class="review-badge hidden", "")
  }
  let unified = state.review_diff_layout == ReviewUnified
  @html.button(
    type_="button",
    class="review-badge review-badge-action review-layout-toggle",
    title=if unified {
      "Use side-by-side diff layout"
    } else {
      "Use unified diff layout"
    },
    on_click=dispatch(ToggleReviewDiffLayout),
    attrs=@html.Attrs::build()
      .data_set("layout", if unified { "unified" } else { "split" })
      .aria_label("Unified diff layout")
      .aria_pressed(unified.to_string()),
    @html.span(
      class=if unified {
        "review-layout-icon unified"
      } else {
        "review-layout-icon split"
      },
      "",
    ),
  )
}

///|
/// Floating one-level directory browser opened by a breadcrumb. It shares the
/// explorer's cache and filesystem messages, but not its expanded/collapsed
/// presentation, so it can stay compact over the source viewer.
fn breadcrumb_picker(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  directory : @pathx.Relative,
) -> @html.Html {
  let label = if directory.is_root() {
    "Workspace"
  } else {
    basename(directory)
  }
  let listed = state.children.get(directory)
  let rows : Array[@html.Html] = match listed {
    Some(entries) if entries.is_empty() =>
      [@html.div(class="breadcrumb-picker-empty", "This folder is empty.")]
    Some(entries) => {
      let rows : Array[@html.Html] = []
      for index, entry in entries {
        rows.push(
          breadcrumb_picker_row(
            dispatch,
            ctx,
            directory,
            entry,
            index,
            entries.length(),
          ),
        )
      }
      rows
    }
    None if state.loading.contains(directory) =>
      [@html.div(class="breadcrumb-picker-empty", "Loading…")]
    None =>
      [
        @html.div(
          class="breadcrumb-picker-empty breadcrumb-picker-failed",
          match state.error {
            Some(message) => "Could not load this folder: \{message}"
            None => "Could not load this folder."
          },
        ),
      ]
  }
  let count = match listed {
    Some(entries) => entries.length().to_string()
    None => ""
  }
  @html.div(
    class="breadcrumb-picker",
    attrs=@html.Attrs::build().id(BreadcrumbPickerId),
    [
      @html.div(class="breadcrumb-picker-heading", [
        @html.span(class="breadcrumb-picker-heading-icon", icon_folder()),
        @html.span(class="breadcrumb-picker-title", label),
        @html.span(class="breadcrumb-picker-count", count),
        @html.span(
          class=if state.loading.contains(directory) {
            "breadcrumb-picker-loading"
          } else {
            "breadcrumb-picker-loading hidden"
          },
          "Refreshing…",
        ),
      ]),
      @html.div(
        class="breadcrumb-picker-list",
        attrs=@html.Attrs::build().role("menu").aria_label("Files in \{label}"),
        rows,
      ),
    ],
  )
}

///|
fn breadcrumb_picker_row(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  directory : @pathx.Relative,
  entry : FileEntry,
  index : Int,
  total : Int,
) -> @html.Html {
  let selected = !entry.is_dir && ctx.active_file == Some(entry.path)
  @html.button(
    type_="button",
    class=if selected {
      "breadcrumb-picker-row selected"
    } else {
      "breadcrumb-picker-row"
    },
    title=entry.path.0,
    on_click=if entry.is_dir {
      dispatch(RevealDirectory(entry.path))
    } else {
      dispatch(FileSelected(path=entry.path, name=entry.name))
    },
    attrs=@html.Attrs::build()
      .id(breadcrumb_entry_id(index))
      .role("menuitem")
      .data_set("path", entry.path.0)
      .aria_current(if selected { "page" } else { "false" })
      .on_keydown(event => {
        match event.key() {
          "Escape" => {
            event.prevent_default()
            dispatch(HighlightCleared(directory))
          }
          "ArrowDown" if index + 1 < total => {
            event.prevent_default()
            focus_breadcrumb_entry_after_render(index + 1)
          }
          "ArrowUp" if index > 0 => {
            event.prevent_default()
            focus_breadcrumb_entry_after_render(index - 1)
          }
          "Home" if index > 0 => {
            event.prevent_default()
            focus_breadcrumb_entry_after_render(0)
          }
          "End" if index + 1 < total => {
            event.prevent_default()
            focus_breadcrumb_entry_after_render(total - 1)
          }
          "ArrowRight" if entry.is_dir => {
            event.prevent_default()
            dispatch(RevealDirectory(entry.path))
          }
          _ => @cmd.none
        }
      }),
    [
      @html.span(
        class=if entry.is_dir {
          "breadcrumb-picker-icon folder"
        } else {
          "breadcrumb-picker-icon file"
        },
        if entry.is_dir {
          icon_folder()
        } else {
          icon_file()
        },
      ),
      @html.span(class="breadcrumb-picker-name", entry.name),
      @html.span(
        class=if entry.is_dir {
          "breadcrumb-picker-chevron"
        } else {
          "breadcrumb-picker-chevron hidden"
        },
        "›",
      ),
    ],
  )
}

///|
/// Previous/next controls for walking the reviewable Changes queue without
/// returning to the tree between files. Native buttons remain keyboard
/// reachable; changed rows additionally support ArrowUp/Down and Home/End.
fn review_navigation(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard active_review_position(state, ctx) is Some((selected, index, total)) else {
    return @html.span(class="review-navigation hidden", "")
  }
  let previous = review_neighbor(state, selected, -1)
  let next = review_neighbor(state, selected, 1)
  @html.div(
    class="review-navigation",
    attrs=@html.Attrs::build()
      .role("group")
      .aria_label("Changed file navigation"),
    [
      @html.button(
        type_="button",
        class="review-nav-button",
        title="Previous changed file",
        disabled=previous is None,
        on_click=match previous {
          Some(previous) => dispatch(ChangedFileSelected(previous))
          None => @cmd.none
        },
        attrs=@html.Attrs::build().aria_label("Previous changed file"),
        "‹",
      ),
      @html.span(
        class="review-nav-position",
        attrs=@html.Attrs::build().aria_live("polite"),
        "\{index + 1} of \{total}",
      ),
      @html.button(
        type_="button",
        class="review-nav-button",
        title="Next changed file",
        disabled=next is None,
        on_click=match next {
          Some(next) => dispatch(ChangedFileSelected(next))
          None => @cmd.none
        },
        attrs=@html.Attrs::build().aria_label("Next changed file"),
        "›",
      ),
    ],
  )
}

///|
/// Progress control for the exact Changes row attached to the active review.
/// Keeping it beside the diff-mode badge makes completion explicit without
/// turning an ordinary file open into review state.
fn review_progress(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some({ review: Some(review), .. }) &&
    state.changes is ChangeListReady(files~, ..) &&
    files.contains(review.selected) else {
    return @html.span(class="review-badge hidden", "")
  }
  let reviewed = state.reviewed_changes.contains(review.selected)
  @html.button(
    type_="button",
    class=if reviewed {
      "review-badge review-progress reviewed"
    } else {
      "review-badge review-progress"
    },
    title=if reviewed {
      "Return this changed file to the review queue"
    } else {
      "Mark this changed file as reviewed"
    },
    on_click=dispatch(ToggleReviewProgress),
    attrs=@html.Attrs::build()
      .aria_label("Mark file reviewed")
      .aria_pressed(reviewed.to_string()),
    if reviewed {
      "✓ Reviewed"
    } else {
      "Mark reviewed"
    },
  )
}

///|
/// Compact review control beside the active path. Textual reviews toggle the
/// full diff; loading and unavailable reviews retain a non-interactive status.
fn review_badge(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let (text, title, action, pressed) = match ctx.active_file {
    Some(path) =>
      match state.docs.get(path) {
        Some(doc) if doc.unified_diff_content() is Some(_) =>
          match doc.review {
            Some({ view_mode: ReviewUnifiedDiff, .. }) =>
              (
                "View file", "Return to the source preview and quick-diff gutter",
                true, true,
              )
            Some({ view_mode: ReviewSource, .. }) =>
              (
                "View full diff", "Open the full diff against the review baseline",
                true, false,
              )
            None => ("", "", false, false)
          }
        Some(
          {
            state: TabDeleted,
            review: Some({ baseline: ReviewContent(_), .. }),
            ..,
          }
        ) =>
          (
            "Deleted · baseline", "Deleted in the working tree; showing the review baseline",
            false, false,
          )
        Some(
          {
            state: TabReadFailed(_),
            review: Some({ baseline: ReviewContent(_), .. }),
            ..,
          }
        ) =>
          (
            "Working unavailable · baseline", "The working-tree file could not be read; showing the review baseline",
            false, false,
          )
        Some({ state: TabBinary, review: Some(_), .. })
        | Some({ state: TabOversized, review: Some(_), .. })
        | Some({ state: TabReadFailed(_), review: Some(_), .. }) =>
          (
            "Diff unavailable", "The working-tree file cannot be previewed as text",
            false, false,
          )
        Some({ review: Some({ baseline: ReviewLoading, .. }), .. }) =>
          (
            "Loading diff…", "Loading the review baseline for comparison", false,
            false,
          )
        Some(
          {
            state: TabDeleted,
            review: Some({ baseline: ReviewMissing, .. }),
            ..,
          }
        ) =>
          (
            "Deleted · no baseline", "No review baseline is available to preview",
            false, false,
          )
        Some({ name, review: Some({ baseline: ReviewContent(_), .. }), .. }) if name.has_suffix(
            ".md",
          ) =>
          (
            "Rendered · no gutter", "Rendered Markdown does not expose source diff decorations",
            false, false,
          )
        Some({ name, review: Some({ baseline: ReviewMissing, .. }), .. }) if name.has_suffix(
            ".md",
          ) =>
          (
            "Rendered · no gutter", "New Markdown has no review baseline; its rendered preview does not expose diff decorations",
            false, false,
          )
        Some({ review: Some({ baseline: ReviewContent(_), .. }), .. }) =>
          (
            "Diff vs baseline", "Quick diff against the review baseline", false,
            false,
          )
        Some({ review: Some({ baseline: ReviewMissing, .. }), .. }) =>
          (
            "New · no baseline", "New file compared with an empty review baseline",
            false, false,
          )
        Some({ review: Some({ baseline: ReviewBinary, .. }), .. }) =>
          ("Diff unavailable", "The review baseline is binary", false, false)
        Some({ review: Some({ baseline: ReviewOversized, .. }), .. }) =>
          ("Diff unavailable", "The review baseline is too large", false, false)
        Some({ review: Some({ baseline: ReviewFailed(message), .. }), .. }) =>
          (
            "Diff unavailable",
            "Could not load review baseline: " + message,
            false,
            false,
          )
        _ => ("", "", false, false)
      }
    None => ("", "", false, false)
  }
  if action {
    @html.button(
      type_="button",
      class="review-badge review-badge-action",
      title~,
      on_click=dispatch(ToggleReviewDiff),
      attrs=@html.Attrs::build()
        .aria_label("Full diff")
        .aria_pressed(pressed.to_string()),
      text,
    )
  } else {
    @html.span(
      class=if text.is_empty() { "review-badge hidden" } else { "review-badge" },
      title~,
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      text,
    )
  }
}

///|
/// One visible hierarchical tree row. `depth` supplies a local CSS variable;
/// the stylesheet owns the padding property.
fn tree_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  entry : FileEntry,
  depth : Int,
) -> @html.Html {
  let indent_style = "--tree-indent: \{8 + depth * 14}px"
  if entry.is_dir {
    let chevron = if state.expanded.contains(entry.path) {
      "▾"
    } else {
      "▸"
    }
    @html.div(
      class="tree-row tree-dir",
      style=[indent_style],
      on_click=dispatch(DirToggle(entry.path)),
      attrs=@html.Attrs::build().data_set("path", entry.path.0),
      [
        @html.span(class="tree-chevron", chevron),
        @html.span(class="tree-name", entry.name),
      ],
    )
  } else {
    @html.div(
      class=if ctx.active_file == Some(entry.path) {
        "tree-row tree-file selected"
      } else {
        "tree-row tree-file"
      },
      style=[indent_style],
      on_click=dispatch(FileSelected(path=entry.path, name=entry.name)),
      attrs=@html.Attrs::build().data_set("path", entry.path.0),
      [@html.span(class="tree-name", entry.name)],
    )
  }
}
