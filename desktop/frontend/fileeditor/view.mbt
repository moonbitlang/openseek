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
/// Git Graph chrome uses the same 16×16 Codicon geometry as VS Code's SCM
/// history view. Keep the paths local to this package, like the existing file
/// and folder icons, because the app-level icon package is not importable here.
fn git_graph_codicon(d : String) -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build().fill("currentColor"),
    [@svg.path(d~)],
  )
}

///|
fn icon_git_repository() -> @html.Html {
  git_graph_codicon(
    "M12.5 12C12.776 12 13 11.776 13 11.5V3C13 1.895 12.105 1 11 1H5C3.895 1 3 1.895 3 3V13C3 14.105 3.895 15 5 15V15.5C5 15.702 5.122 15.885 5.309 15.962C5.495 16.039 5.711 15.997 5.854 15.854L6.5 15.208L7.146 15.854C7.242 15.95 7.37 16 7.5 16C7.564 16 7.63 15.987 7.691 15.962C7.878 15.885 8 15.702 8 15.5V15H12.5C12.776 15 13 14.776 13 14.5C13 14.224 12.776 14 12.5 14H8V13.5C8 13.224 7.776 13 7.5 13H5.5C5.224 13 5 13.224 5 13.5V14C4.448 14 4 13.552 4 13V12H12.5ZM4 3C4 2.448 4.448 2 5 2H11C11.552 2 12 2.448 12 3V11H4V3Z",
  )
}

///|
fn icon_git_branch() -> @html.Html {
  git_graph_codicon(
    "M14 5.5C14 4.121 12.879 3 11.5 3C10.121 3 9 4.121 9 5.5C9 6.682 9.826 7.669 10.93 7.928C10.744 8.546 10.177 9 9.5 9H6.5C5.935 9 5.419 9.195 5 9.512V4.949C6.14 4.717 7 3.707 7 2.5C7 1.121 5.879 0 4.5 0C3.121 0 2 1.121 2 2.5C2 3.708 2.86 4.717 4 4.949V11.05C2.86 11.282 2 12.292 2 13.499C2 14.878 3.121 15.999 4.5 15.999C5.879 15.999 7 14.878 7 13.499C7 12.317 6.174 11.33 5.07 11.071C5.256 10.453 5.823 9.999 6.5 9.999H9.5C10.723 9.999 11.74 9.115 11.954 7.953C13.116 7.738 14 6.723 14 5.5ZM3 2.5C3 1.673 3.673 1 4.5 1C5.327 1 6 1.673 6 2.5C6 3.327 5.327 4 4.5 4C3.673 4 3 3.327 3 2.5ZM6 13.5C6 14.327 5.327 15 4.5 15C3.673 15 3 14.327 3 13.5C3 12.673 3.673 12 4.5 12C5.327 12 6 12.673 6 13.5ZM11.5 7C10.673 7 10 6.327 10 5.5C10 4.673 10.673 4 11.5 4C12.327 4 13 4.673 13 5.5C13 6.327 12.327 7 11.5 7Z",
  )
}

///|
fn icon_git_cloud() -> @html.Html {
  git_graph_codicon(
    "M8 4C6.34315 4 5 5.34315 5 7C5 7.27614 4.77614 7.5 4.5 7.5H4.25C3.00736 7.5 2 8.50736 2 9.75C2 10.9926 3.00736 12 4.25 12H11.75C12.9926 12 14 10.9926 14 9.75C14 8.50736 12.9926 7.5 11.75 7.5H11.5C11.2239 7.5 11 7.27614 11 7C11 5.34315 9.65685 4 8 4ZM4.03004 6.50733C4.27283 4.53062 5.95767 3 8 3C10.0423 3 11.7272 4.53063 11.97 6.50733C13.6623 6.62043 15 8.029 15 9.75C15 11.5449 13.5449 13 11.75 13H4.25C2.45507 13 1 11.5449 1 9.75C1 8.029 2.33769 6.62043 4.03004 6.50733Z",
  )
}

///|
fn icon_git_sync() -> @html.Html {
  git_graph_codicon(
    "M14 3.5V6.5C14 6.78 13.78 7 13.5 7H10.5C10.22 7 9.99999 6.78 9.99999 6.5C9.99999 6.22 10.22 6 10.5 6H12.58C11.78 4.17 10.01 3 7.99999 3C5.77999 3 3.79999 4.5 3.18999 6.64C3.12999 6.86 2.92999 7 2.70999 7C2.65999 7 2.61999 7 2.56999 6.98C2.29999 6.9 2.14999 6.63 2.22999 6.36C2.95999 3.79 5.32999 2 7.99999 2C10.05 2 11.91 3.02 13 4.69V3.5C13 3.22 13.22 3 13.5 3C13.78 3 14 3.22 14 3.5ZM13.42 9.02C13.16 8.95 12.88 9.1 12.8 9.37C12.19 11.51 10.22 13.01 7.98999 13.01C5.97999 13.01 4.20999 11.84 3.40999 10.01H5.48999C5.76999 10.01 5.98999 9.79 5.98999 9.51C5.98999 9.23 5.76999 9.01 5.48999 9.01H2.48999C2.20999 9.01 1.98999 9.23 1.98999 9.51V12.51C1.98999 12.79 2.20999 13.01 2.48999 13.01C2.76999 13.01 2.98999 12.79 2.98999 12.51V11.32C4.07999 12.98 5.93999 14.01 7.98999 14.01C10.66 14.01 13.03 12.22 13.76 9.65C13.84 9.38 13.68 9.11 13.41 9.03L13.42 9.02Z",
  )
}

///|
fn icon_git_chevron_right() -> @html.Html {
  git_graph_codicon(
    "M6.14601 3.14579C5.95101 3.34079 5.95101 3.65779 6.14601 3.85279L10.292 7.99879L6.14601 12.1448C5.95101 12.3398 5.95101 12.6568 6.14601 12.8518C6.34101 13.0468 6.65801 13.0468 6.85301 12.8518L11.353 8.35179C11.548 8.15679 11.548 7.83979 11.353 7.64478L6.85301 3.14479C6.65801 2.94979 6.34101 2.95079 6.14601 3.14579Z",
  )
}

///|
fn icon_git_list_tree() -> @html.Html {
  git_graph_codicon(
    "M2 3.5C2 3.22386 2.22386 3 2.5 3H13.5C13.7761 3 14 3.22386 14 3.5C14 3.77614 13.7761 4 13.5 4H6V6H13.5C13.7761 6 14 6.22386 14 6.5C14 6.77614 13.7761 7 13.5 7H6V9H13.5C13.7761 9 14 9.22386 14 9.5C14 9.77614 13.7761 10 13.5 10H6V12H13.5C13.7761 12 14 12.2239 14 12.5C14 12.7761 13.7761 13 13.5 13H5.5C5.22386 13 5 12.7761 5 12.5V4H2.5C2.22386 4 2 3.77614 2 3.5Z",
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
  let tree_visible = state.tree_open ||
    (ctx.active_file is None && ctx.active_history_diff is None)
  let mut classes = "editor"
  if tree_visible {
    classes += " tree-open"
  }
  if ctx.tree_layout is RightSidebar {
    classes += " tree-right"
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
/// (`viewer-host`, `markdown-viewer-host`, `mbti-diagram-host`,
/// `diff-editor-host`, and `semantic-review-host`) stay put
/// across renders and screen
/// switches; CSS hides the inactive surface and the tree pane when toggled off,
/// and collapses the whole panel to zero width when it is closed. The children's
/// order is structural — rabbita diffs by index, so every part renders
/// unconditionally.
pub fn body_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  semantic_review? : @html.Html = @html.nothing,
) -> @html.Html {
  // The stable elements the code Viewer, MarkdownViewer, and switchable Line
  // DiffEditor attach their imperative DOM into. Semantic review owns keyed
  // empty child hosts under its stable sibling.
  // (see editor_panel.mbt).
  // `editor-shell` brings in the viewer's `--vscode-*` / `--editor-*` theme
  // variables (defined on that class in the bundled viewer.css); `data-theme`
  // picks the palette matching the app's own light/dark scheme (the shell's
  // default is dark, `light` overrides). The viewer's colors cascade from
  // this host.
  let use_diff_surface = if ctx.active_history_diff is Some(_) {
    true
  } else {
    match ctx.active_file {
      Some(path) =>
        state.docs
        .get(path)
        .map(doc => doc.uses_diff_surface())
        .unwrap_or(false)
      None => false
    }
  }
  let use_markdown_surface = !use_diff_surface &&
    (match ctx.active_file {
      Some(path) =>
        uses_markdown_presentation(
          state.docs.get(path).map(doc => doc.name).unwrap_or(path.0),
        )
      None => false
    })
  let use_mbti_surface = !use_diff_surface &&
    !use_markdown_surface &&
    uses_mbti_diagram_surface(state, ctx)
  let use_semantic_surface = use_diff_surface &&
    state.review_diff_mode != ReviewDiffLine &&
    (match ctx.active_history_diff {
      Some(diff) => supports_moon_diff(diff.path.0)
      None =>
        ctx.active_file.map(path => supports_moon_diff(path.0)).unwrap_or(false)
    })
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class(
        if use_diff_surface || use_markdown_surface || use_mbti_surface {
          "viewer-host editor-shell moonbit-viewer-surface-hidden"
        } else {
          "viewer-host editor-shell"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  let markdown_viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(MarkdownViewerHostId)
      .class(
        if use_markdown_surface {
          "viewer-host editor-shell"
        } else {
          "viewer-host editor-shell moonbit-viewer-surface-hidden"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  let mbti_diagram_host = @html.div(
    attrs=@html.Attrs::build()
      .id(MbtiDiagramHostId)
      .class(
        if use_mbti_surface {
          "viewer-host editor-shell mbti-diagram-host"
        } else {
          "viewer-host editor-shell mbti-diagram-host moonbit-viewer-surface-hidden"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  let diff_editor_host = @html.div(
    attrs=@html.Attrs::build()
      .id(DiffEditorHostId)
      .class(
        if use_diff_surface && !use_semantic_surface {
          "viewer-host editor-shell"
        } else {
          "viewer-host editor-shell moonbit-viewer-surface-hidden"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  let semantic_review_host = @html.div(
    attrs=@html.Attrs::build()
      .id(SemanticReviewHostId)
      .class(
        if use_semantic_surface {
          "viewer-host editor-shell semantic-review-host"
        } else {
          "viewer-host editor-shell semantic-review-host moonbit-viewer-surface-hidden"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" })
      .on_scroll(event => {
        guard event.target().to_element() is Some(element) else {
          return @cmd.none
        }
        sync_semantic_review_scroll_left(element.get_scroll_left())
        @cmd.none
      }),
    semantic_review,
  )
  @html.div(class="editor-body", [
    @html.div(class="viewer-stack", [
      viewer_host,
      markdown_viewer_host,
      mbti_diagram_host,
      diff_editor_host,
      semantic_review_host,
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
  if ctx.active_history_diff is Some(diff) {
    let text = history_diff_notice(state, diff)
    return @html.div(
      class=if text.is_empty() {
        "viewer-notice hidden"
      } else {
        "viewer-notice"
      },
      text,
    )
  }
  let diff_pending = match ctx.active_file {
    Some(path) =>
      state.docs.get(path).map(doc => doc.diff_is_pending()).unwrap_or(false)
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
fn history_diff_notice(state : State, diff : @dock.GitHistoryDiff) -> String {
  guard state.history_docs.get(history_diff_key(diff)) is Some(doc) else {
    return "Loading historical diff for \{basename(diff.path)}…"
  }
  match (doc.original, doc.modified) {
    (HistoryBlobLoading, _) | (_, HistoryBlobLoading) =>
      "Loading historical diff for \{basename(diff.path)}…"
    (HistoryBlobError(message), _) | (_, HistoryBlobError(message)) =>
      "Could not load historical diff for \{basename(diff.path)}: \{message}."
    (HistoryBlobBinary, _) | (_, HistoryBlobBinary) =>
      "\{basename(diff.path)} is binary at this revision and cannot be previewed."
    (HistoryBlobOversized, _) | (_, HistoryBlobOversized) =>
      "\{basename(diff.path)} is too large at this revision to preview."
    (HistoryBlobMissing, HistoryBlobMissing) =>
      "No file content exists on either side of this commit."
    _ => ""
  }
}

///|
/// The toggleable file-tree panel, docked flat under the viewer like an Emacs
/// bottom window. Request-local listing failures remain beside the inventory;
/// watcher failures use the root app's transient toast rail instead.
fn tree_pane(dispatch : @cmd.Emit[Msg], state : State, ctx : Ctx) -> @html.Html {
  let visible_error = if state.explorer_mode is ExplorerSearch {
    None
  } else {
    state.error
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
      ExplorerChanges => [review_git_layout(dispatch, state, ctx)]
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
      } else if state.explorer_mode is ExplorerChanges {
        "file-tree review-git-tree"
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
fn review_git_layout(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let split_hidden = state.changes_collapsed || state.git_graph_collapsed
  let layout_class = if state.changes_collapsed {
    "review-git-layout changes-collapsed"
  } else if state.git_graph_collapsed {
    "review-git-layout graph-collapsed"
  } else {
    "review-git-layout"
  }
  @html.div(
    attrs=@html.Attrs::build().id(GitGraphLayoutId).class(layout_class),
    [
      @html.section(
        class=if state.changes_collapsed {
          "review-section review-changes-section collapsed"
        } else {
          "review-section review-changes-section"
        },
        attrs=@html.Attrs::build().id(GitGraphChangesSectionId),
        [
          @html.button(
            class="review-section-header",
            on_click=dispatch(ToggleChangesSection),
            attrs=@html.Attrs::build()
              .aria_expanded((!state.changes_collapsed).to_string())
              .aria_controls("review-changes-body"),
            [
              @html.span(class="review-section-chevron", "›"),
              @html.span(class="review-section-title", "Changes"),
              change_count(state.changes),
            ],
          ),
          @html.div(
            class="review-section-body",
            attrs=@html.Attrs::build().id("review-changes-body"),
            change_inventory(dispatch, state, ctx),
          ),
        ],
      ),
      @html.div(
        class=if split_hidden {
          "review-split-handle hidden"
        } else {
          "review-split-handle"
        },
        title="Resize Changes and Git Graph",
        attrs=@html.Attrs::build()
          .id(GitGraphResizeHandleId)
          .role("separator")
          .tabindex(0)
          .aria_label("Resize Changes and Git Graph")
          .aria_orientation("horizontal")
          .on_keydown(event => {
            match event.key() {
              "ArrowUp" => {
                event.prevent_default()
                adjust_git_graph_split(-24)
              }
              "ArrowDown" => {
                event.prevent_default()
                adjust_git_graph_split(24)
              }
              _ => ()
            }
            @cmd.none
          }),
        ([] : Array[@html.Html]),
      ),
      @html.section(
        class=if state.git_graph_collapsed {
          "review-section git-graph-section collapsed"
        } else {
          "review-section git-graph-section"
        },
        [
          @html.div(class="review-section-header git-graph-header", [
            @html.button(
              class="git-graph-collapse",
              on_click=dispatch(ToggleGitGraphSection),
              attrs=@html.Attrs::build()
                .aria_expanded((!state.git_graph_collapsed).to_string())
                .aria_controls("git-graph-body"),
              [
                @html.span(class="git-graph-chevron", icon_git_chevron_right()),
                @html.span(
                  class="review-section-title git-graph-title",
                  "Graph",
                ),
              ],
            ),
            @html.div(class="git-graph-toolbar", [
              @html.span(
                class="git-graph-context git-graph-repository",
                title=git_graph_repository_label(ctx),
                [
                  @html.span(
                    class="git-graph-context-icon",
                    icon_git_repository(),
                  ),
                  @html.span(
                    class="git-graph-context-label",
                    git_graph_repository_label(ctx),
                  ),
                ],
              ),
              @html.span(
                class="git-graph-context git-graph-branch",
                title=git_graph_branch_label(state),
                [
                  @html.span(class="git-graph-context-icon", icon_git_branch()),
                  @html.span(
                    class="git-graph-context-label",
                    git_graph_branch_label(state),
                  ),
                ],
              ),
              @html.button(
                class="git-graph-refresh",
                title="Refresh Git Graph",
                on_click=dispatch(GitHistoryRefreshRequested),
                attrs=@html.Attrs::build().aria_label("Refresh Git Graph"),
                @html.span(class="git-graph-refresh-icon", icon_git_sync()),
              ),
            ]),
          ]),
          @html.div(
            class="review-section-body git-graph-body",
            attrs=@html.Attrs::build()
              .id("git-graph-body")
              .on_scroll(event => {
                guard event.target().to_element() is Some(element) &&
                  element.get_scroll_height() -
                  element.get_scroll_top() -
                  element.get_client_height() <=
                  120.0 else {
                  return @cmd.none
                }
                dispatch(GitHistoryLoadMoreRequested)
              }),
            git_graph_inventory(dispatch, state, ctx),
          ),
        ],
      ),
    ],
  )
}

///|
fn git_graph_repository_label(ctx : Ctx) -> String {
  ctx
  .workspace()
  .map(resource => @resource.label(resource))
  .unwrap_or("Repository")
}

///|
fn git_graph_branch_label(state : State) -> String {
  match state.git_graph {
    GitGraphReady(snapshot~, ..) =>
      snapshot.branch.unwrap_or(
        snapshot.head.map(short_commit).unwrap_or("No commits"),
      )
    _ => ""
  }
}

///|
fn git_commit_row_id(index : Int) -> String {
  "git-commit-row-\{index}"
}

///|
fn focus_git_commit_after_render(index : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document().get_element_by_id(git_commit_row_id(index)).to_option()
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
fn git_graph_inventory(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> Array[@html.Html] {
  match state.git_graph {
    GitGraphIdle | GitGraphLoading =>
      [@html.div(class="file-panel-empty", "Loading Git history…")]
    GitGraphFailed(message) =>
      [
        @html.div(class="git-graph-message", [
          @html.span("Could not load Git history: \{message}."),
          @html.button(
            class="git-graph-retry",
            on_click=dispatch(GitHistoryRefreshRequested),
            "Retry",
          ),
        ]),
      ]
    GitGraphReady(repository=false, ..) =>
      [
        @html.div(
          class="file-panel-empty",
          "Git is unavailable or this workspace is not a Git repository.",
        ),
      ]
    GitGraphReady(
      snapshot~,
      commits~,
      has_more~,
      loading_more~,
      load_error~,
      ..
    ) => {
      if commits.is_empty() {
        return [
          @html.div(class="file-panel-empty", "This branch has no commits."),
        ]
      }
      let layouts = graph_rows(commits, snapshot)
      let children : Array[@html.Html] = []
      for index, commit in commits {
        children.push(
          git_commit_row(
            dispatch,
            state,
            ctx,
            commit,
            layouts[index],
            index,
            commits.length(),
          ),
        )
      }
      if load_error is Some(message) {
        children.push(
          @html.div(
            class="git-graph-load-error",
            "Could not load more: \{message}",
          ),
        )
      }
      if has_more || loading_more {
        let continuation = layouts[layouts.length() - 1].output_swimlanes
        children.push(
          @html.button(
            class="git-graph-load-more",
            disabled=loading_more,
            on_click=dispatch(GitHistoryLoadMoreRequested),
            [
              git_graph_placeholder(continuation, None),
              @html.span(
                class="git-graph-load-more-label",
                if loading_more {
                  "Loading…"
                } else {
                  "Load more"
                },
              ),
            ],
          ),
        )
      }
      [
        @html.div(
          class="git-graph-list",
          attrs=@html.Attrs::build()
            .role("tree")
            .aria_label("Git commit history"),
          children,
        ),
      ]
    }
  }
}

///|
fn graph_color_class(color : Int) -> String {
  "git-graph-color-\{color}"
}

///|
fn graph_lane_x(lane : Int) -> Int {
  11 * (lane + 1)
}

///|
fn graph_row_index(row : GraphRow, id : String) -> Int {
  match find_graph_lane(row.input_swimlanes, id) {
    Some(index) => index
    None => row.input_swimlanes.length()
  }
}

///|
fn graph_row_width(row : GraphRow) -> Int {
  11 *
  (row.input_swimlanes.length().max(row.output_swimlanes.length()).max(1) + 1)
}

///|
fn find_last_graph_lane(lanes : Array[GraphLane], id : String) -> Int? {
  let mut index = lanes.length()
  while index > 0 {
    index -= 1
    if lanes[index].id == id {
      return Some(index)
    }
  }
  None
}

///|
fn graph_circle_color(row : GraphRow, circle_index : Int) -> Int {
  if circle_index < row.output_swimlanes.length() {
    row.output_swimlanes[circle_index].color
  } else if circle_index < row.input_swimlanes.length() {
    row.input_swimlanes[circle_index].color
  } else {
    GraphCurrentColor
  }
}

///|
fn git_graph_placeholder(
  columns : Array[GraphLane],
  highlight_index : Int?,
) -> @html.Html {
  let graph_width = 11 * (columns.length() + 1)
  let paths : Array[@svg.Svg] = []
  for lane, column in columns {
    let x = graph_lane_x(lane)
    let highlight_class = if highlight_index == Some(lane) {
      " git-graph-edge-highlight"
    } else {
      ""
    }
    let path_class = "git-graph-edge " +
      graph_color_class(column.color) +
      highlight_class
    paths.push(
      @svg.path(
        class=path_class,
        d="M\{x} 0 V22",
        attrs=@svg.Attrs::build()
          .stroke_width(if highlight_index == Some(lane) { "3" } else { "1" })
          .stroke_linecap("round"),
      ),
    )
  }
  @html.span(
    class="git-history-graph-placeholder",
    attrs=@html.Attrs::build().aria_hidden("true"),
    @svg.svg(
      class="git-graph-svg",
      width=graph_width,
      height=22,
      view_box="0 0 \{graph_width} 22",
      paths,
    ),
  )
}

///|
fn git_graph_cell(
  row : GraphRow,
  commit : @protocol.GitHistoryCommit,
  head : Bool,
) -> @html.Html {
  let children : Array[@svg.Svg] = []
  let input_index = find_graph_lane(row.input_swimlanes, commit.id)
  let circle_index = graph_row_index(row, commit.id)
  let circle_x = graph_lane_x(circle_index)
  let circle_color = graph_circle_color(row, circle_index)
  let mut output_swimlane_index = 0

  for index, node in row.input_swimlanes {
    if node.id == commit.id {
      if index != circle_index {
        children.push(
          @svg.path(
            class="git-graph-edge " + graph_color_class(node.color),
            d="M \{graph_lane_x(index)} 0 A 11 11 0 0 1 \{11 * index} 11 H \{circle_x}",
            attrs=@svg.Attrs::build().stroke_linecap("round"),
          ),
        )
      } else {
        output_swimlane_index += 1
      }
    } else if output_swimlane_index < row.output_swimlanes.length() &&
      node.id == row.output_swimlanes[output_swimlane_index].id {
      let x = graph_lane_x(index)
      let output_x = graph_lane_x(output_swimlane_index)
      let d = if index == output_swimlane_index {
        "M \{x} 0 V 22"
      } else {
        "M \{x} 0 V 6 A 5 5 0 0 1 \{x - 5} 11 H \{output_x + 5} A 5 5 0 0 0 \{output_x} 16 V 22"
      }
      children.push(
        @svg.path(
          class="git-graph-edge " + graph_color_class(node.color),
          d~,
          attrs=@svg.Attrs::build().stroke_linecap("round"),
        ),
      )
      output_swimlane_index += 1
    }
  }

  for parent_index in 1..<commit.parent_ids.length() {
    guard find_last_graph_lane(
        row.output_swimlanes,
        commit.parent_ids[parent_index],
      )
      is Some(parent_output_index) else {
      continue
    }
    let start_x = 11 * parent_output_index
    children.push(
      @svg.path(
        class="git-graph-edge " +
          graph_color_class(row.output_swimlanes[parent_output_index].color),
        d="M \{start_x} 11 A 11 11 0 0 1 \{graph_lane_x(parent_output_index)} 22 M \{start_x} 11 H \{circle_x}",
        attrs=@svg.Attrs::build().stroke_linecap("round"),
      ),
    )
  }

  if input_index is Some(index) {
    children.push(
      @svg.path(
        class="git-graph-edge " +
          graph_color_class(row.input_swimlanes[index].color),
        d="M \{circle_x} 0 V 11",
        attrs=@svg.Attrs::build().stroke_linecap("round"),
      ),
    )
  }
  if !commit.parent_ids.is_empty() {
    children.push(
      @svg.path(
        class="git-graph-edge " + graph_color_class(circle_color),
        d="M \{circle_x} 11 V 22",
        attrs=@svg.Attrs::build().stroke_linecap("round"),
      ),
    )
  }

  let node_color = graph_color_class(circle_color)
  if head {
    children.push(
      @svg.circle(
        class="git-graph-node git-graph-node-head-outer " + node_color,
        cx=circle_x,
        cy=11,
        r=7,
      ),
    )
    children.push(
      @svg.circle(
        class="git-graph-node git-graph-node-head-inner " + node_color,
        cx=circle_x,
        cy=11,
        r=2,
        attrs=@svg.Attrs::build().stroke_width("4"),
      ),
    )
  } else if commit.parent_ids.length() > 1 {
    children.push(
      @svg.circle(
        class="git-graph-node git-graph-node-merge-outer " + node_color,
        cx=circle_x,
        cy=11,
        r=6,
      ),
    )
    children.push(
      @svg.circle(
        class="git-graph-node git-graph-node-merge-inner " + node_color,
        cx=circle_x,
        cy=11,
        r=3,
      ),
    )
  } else {
    children.push(
      @svg.circle(
        class="git-graph-node git-graph-node-commit " + node_color,
        cx=circle_x,
        cy=11,
        r=5,
      ),
    )
  }
  @html.span(
    class="git-graph-cell",
    attrs=@html.Attrs::build().aria_hidden("true"),
    @svg.svg(
      class="git-graph-svg",
      width=graph_row_width(row),
      height=22,
      view_box="0 0 \{graph_row_width(row)} 22",
      children,
    ),
  )
}

///|
fn git_commit_refs(
  snapshot : @protocol.GitHistorySnapshot,
  commit : String,
) -> Array[@html.Html] {
  let visible = snapshot.refs.filter(ref_ => ref_.revision == commit)
  visible.sort_by((left, right) => {
    let rank = git_history_ref_rank(left.kind) -
      git_history_ref_rank(right.kind)
    if rank == 0 {
      left.name.lexical_compare(right.name)
    } else {
      rank
    }
  })
  let refs : Array[@html.Html] = []
  for index, ref_ in visible {
    let contents : Array[@html.Html] = [
      @html.span(
        class="git-ref-icon",
        if ["upstream", "base"].contains(ref_.kind) {
          icon_git_cloud()
        } else {
          icon_git_branch()
        },
      ),
    ]
    if index == 0 {
      contents.push(@html.span(class="git-ref-name", ref_.name))
    }
    refs.push(
      @html.span(
        class="git-ref git-ref-" + ref_.kind,
        title="\{ref_.kind}: \{ref_.name}",
        contents,
      ),
    )
  }
  refs
}

///|
fn git_commit_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  commit : @protocol.GitHistoryCommit,
  layout : GraphRow,
  index : Int,
  total : Int,
) -> @html.Html {
  let expanded = state.git_graph_selected == Some(commit.id)
  let refs : Array[@html.Html] = []
  let mut head = false
  if state.git_graph is GitGraphReady(snapshot~, ..) {
    head = snapshot.head == Some(commit.id)
    refs.push_iter(git_commit_refs(snapshot, commit.id).iter())
  }
  let mut row_class = "git-commit-row"
  if head {
    row_class += " current"
  }
  if expanded {
    row_class += " selected"
  }
  let children : Array[@html.Html] = [
    @html.button(
      class=row_class,
      title="\{commit.subject}\n\{commit.id}\n\{commit.author} · \{commit.authored_at}",
      on_click=dispatch(GitCommitSelected(commit.id)),
      attrs=@html.Attrs::build()
        .id(git_commit_row_id(index))
        .role("treeitem")
        .aria_label(
          "\{commit.subject}, \{commit.author}, \{commit.authored_at}, \{commit.id}",
        )
        .aria_expanded(expanded.to_string())
        .on_keydown(event => {
          match event.key() {
            "ArrowUp" if index > 0 => {
              event.prevent_default()
              focus_git_commit_after_render(index - 1)
            }
            "ArrowDown" if index + 1 < total => {
              event.prevent_default()
              focus_git_commit_after_render(index + 1)
            }
            "Home" => {
              event.prevent_default()
              focus_git_commit_after_render(0)
            }
            "End" => {
              event.prevent_default()
              focus_git_commit_after_render(total - 1)
            }
            "ArrowRight" if !expanded => {
              event.prevent_default()
              dispatch(GitCommitSelected(commit.id))
            }
            "ArrowLeft" if expanded => {
              event.prevent_default()
              dispatch(GitCommitSelected(commit.id))
            }
            _ => @cmd.none
          }
        }),
      [
        git_graph_cell(layout, commit, head),
        @html.span(class="git-commit-label", [
          @html.span(class="git-commit-subject", commit.subject),
          @html.span(class="git-commit-author", commit.author),
        ]),
        @html.span(class="git-ref-list", refs),
        @html.span(
          class="git-commit-actions",
          attrs=@html.Attrs::build().aria_hidden("true"),
          icon_git_list_tree(),
        ),
      ],
    ),
  ]
  if expanded {
    children.push(git_commit_files(dispatch, state, ctx, commit, layout))
  }
  @html.div(class="git-commit-entry", children)
}

///|
fn historical_status_label(status : String) -> String {
  match status {
    "added" => "A"
    "deleted" => "D"
    "renamed" => "R"
    "copied" => "C"
    "type-changed" => "T"
    _ => "M"
  }
}

///|
fn git_commit_files(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  commit : @protocol.GitHistoryCommit,
  layout : GraphRow,
) -> @html.Html {
  let columns = layout.output_swimlanes
  let highlight_index = Some(graph_row_index(layout, commit.id))
  let rows : Array[@html.Html] = match state.git_commit_files {
    GitCommitFilesLoading(commit=id) if id == commit.id =>
      [
        @html.div(class="git-commit-files-message", [
          git_graph_placeholder(columns, highlight_index),
          @html.span("Loading changed files…"),
        ]),
      ]
    GitCommitFilesFailed(commit=id, message~) if id == commit.id =>
      [
        @html.div(class="git-commit-files-message error", [
          git_graph_placeholder(columns, highlight_index),
          @html.span(class="git-commit-files-message-content", [
            @html.span("Could not load this commit: \{message}."),
            @html.button(
              class="git-history-retry",
              on_click=dispatch(GitCommitChangesRetry(commit.id)),
              "Retry",
            ),
          ]),
        ]),
      ]
    GitCommitFilesReady(commit=id, parent~, files~) if id == commit.id =>
      if files.is_empty() {
        [
          @html.div(class="git-commit-files-message", [
            git_graph_placeholder(columns, highlight_index),
            @html.span("No changes in this workspace."),
          ]),
        ]
      } else {
        files.map(file => {
          let selectable = file.kind == "file" &&
            !(["renamed", "copied"].contains(file.status) &&
            file.original_path is None)
          let diff : @dock.GitHistoryDiff = {
            commit: commit.id,
            parent,
            path: @pathx.Relative(file.path),
            original_path: file.original_path.map(path => @pathx.Relative(path)),
            status: file.status,
            kind: file.kind,
          }
          let selected = ctx.active_history_diff == Some(diff)
          let contents : Array[@html.Html] = [
            git_graph_placeholder(columns, highlight_index),
            @html.span(class="git-history-file-path", file.path),
            @html.span(
              class="git-history-file-status status-" + file.status,
              historical_status_label(file.status),
            ),
          ]
          if selectable {
            @html.button(
              class=if selected {
                "git-history-file selected"
              } else {
                "git-history-file"
              },
              title="Open historical diff for \{file.path}",
              on_click=dispatch(HistoricalFileSelected(diff)),
              attrs=@html.Attrs::build()
                .role("treeitem")
                .aria_current(if selected { "page" } else { "false" }),
              contents,
            )
          } else {
            @html.div(
              class="git-history-file unavailable",
              title=if file.kind == "submodule" {
                "Git submodule cannot be shown as a text diff"
              } else if file.kind == "symlink" {
                "Git symlink cannot be shown as a text diff"
              } else {
                "Original path is outside this workspace"
              },
              attrs=@html.Attrs::build().role("treeitem").aria_disabled("true"),
              contents,
            )
          }
        })
      }
    _ =>
      [
        @html.div(class="git-commit-files-message", [
          git_graph_placeholder(columns, highlight_index),
          @html.span("Loading changed files…"),
        ]),
      ]
  }
  @html.div(
    class="git-commit-files",
    attrs=@html.Attrs::build().role("group"),
    rows,
  )
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
          .filter(change => state.is_change_reviewed(change))
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
  let progress = state.changed_file_review_state(change)
  let mut class = if selected { "change-row selected" } else { "change-row" }
  if progress is ReviewComplete {
    class += " reviewed"
  }
  if !change.selectable() {
    class += " disabled"
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
        match progress {
          ReviewComplete => "✓ Reviewed"
          ReviewInProgress => "◐ In progress"
          ReviewUnviewed => "View diff"
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
  files.search_by(change => change == selected)
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
  guard changes.search_by(change => change == selected) is Some(index) else {
    return None
  }
  changes.get(index + delta)
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
  changes
  .search_by(change => change == review.selected)
  .map(index => (review.selected, index, changes.length()))
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
  [
    for segment in path.0.split("/") if !segment.is_empty() => {
      segment.to_owned()
    }
  ]
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
/// The breadcrumb under the tab bar: the active file's path as
/// `dir › dir › file` (the file segment emphasized) behind a leading
/// "Workspace" crumb. Every crumb but the last opens a VS Code-style picker
/// of that directory's immediate children, without moving or hiding the
/// source viewer behind it.
/// Reviews add a second, wrapping command row so the path, file navigation,
/// and completion action never compete with comparison settings. With no file
/// open the whole breadcrumb hides; it stays in the DOM so the editor's child
/// order, and thus the viewer host, is never re-keyed.
pub fn breadcrumb_view(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  if ctx.active_history_diff is Some(diff) {
    return @html.div(
      class="viewer-breadcrumb review-toolbar history-breadcrumb",
      [
        @html.div(class="viewer-breadcrumb-row", [
          @html.div(class="crumb-path", [
            @html.span(
              class="crumb history-commit-crumb",
              short_commit(diff.commit),
            ),
            @html.span(class="crumb-sep", "›"),
            @html.span(class="crumb crumb-file", diff.path.0),
          ]),
          @html.button(
            class="panel-toggle",
            title=if state.tree_open {
              "Hide file tree"
            } else {
              "Show file tree"
            },
            on_click=dispatch(ToggleTree),
            icon(icon_folder),
          ),
        ]),
        @html.div(class="review-command-row", [
          review_diff_mode_toolbar(dispatch, state, ctx),
          @html.span(
            class=if moon_diff_available(state, ctx) {
              "review-control-divider"
            } else {
              "review-control-divider hidden"
            },
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
          review_diff_layout_toggle(dispatch, state, ctx),
          review_comments_control(dispatch, state, ctx),
          review_tests_control(dispatch, state, ctx),
          review_diff_navigation(dispatch, state, ctx),
        ]),
      ],
    )
  }
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
  let review = full_diff_available(state, ctx)
  let path_row : Array[@html.Html] = [
    @html.div(class="crumb-path", crumbs),
    review_navigation(dispatch, state, ctx),
  ]
  if review {
    path_row.push(review_progress(dispatch, state, ctx))
  } else {
    path_row.push(review_badge(dispatch, state, ctx))
    path_row.push(review_progress(dispatch, state, ctx))
  }
  if mbti_view_available(state, ctx) {
    path_row.push(mbti_view_toolbar(dispatch, state, ctx))
  }
  path_row.push(
    @html.button(
      class="panel-toggle",
      title=if state.tree_open { "Hide file tree" } else { "Show file tree" },
      on_click=dispatch(ToggleTree),
      icon(icon_folder),
    ),
  )
  if review {
    let children : Array[@html.Html] = [
      @html.div(class="viewer-breadcrumb-row", path_row),
      @html.div(class="review-command-row", [
        review_mode_toolbar(dispatch, state, ctx),
        @html.span(
          class="review-control-divider",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        review_diff_layout_toggle(dispatch, state, ctx),
        review_comments_control(dispatch, state, ctx),
        review_tests_control(dispatch, state, ctx),
        review_diff_navigation(dispatch, state, ctx),
        review_hunk_toggle(dispatch, state, ctx),
      ]),
    ]
    if state.highlighted is Some(directory) {
      children.push(breadcrumb_picker(dispatch, state, ctx, directory))
    }
    @html.div(class="viewer-breadcrumb review-toolbar", children)
  } else {
    if state.highlighted is Some(directory) {
      path_row.push(breadcrumb_picker(dispatch, state, ctx, directory))
    }
    @html.div(
      class=if ctx.active_file is None {
        "viewer-breadcrumb hidden"
      } else {
        "viewer-breadcrumb"
      },
      path_row,
    )
  }
}

///|
/// Only an ordinary, loaded generated interface owns the diagram/source
/// presentation. Review and historical paths retain their code surfaces.
fn mbti_view_available(state : State, ctx : Ctx) -> Bool {
  guard ctx.active_history_diff is None && ctx.active_file is Some(path) else {
    return false
  }
  state.docs.get(path) is Some({ name, state: TabLoaded(..), review: None, .. }) &&
  uses_mbti_presentation(name)
}

///|
fn uses_mbti_diagram_surface(state : State, ctx : Ctx) -> Bool {
  guard mbti_view_available(state, ctx) && ctx.active_file is Some(path) else {
    return false
  }
  state.mbti_view_mode(path) == MbtiDiagram
}

///|
fn mbti_view_button(
  dispatch : @cmd.Emit[Msg],
  selected : MbtiViewMode,
  mode : MbtiViewMode,
  label : String,
) -> @html.Html {
  let active = selected == mode
  @html.button(
    type_="button",
    class=if active {
      "review-mode-button active"
    } else {
      "review-mode-button"
    },
    on_click=if active {
      @cmd.none
    } else {
      dispatch(MbtiViewModeSelected(mode))
    },
    attrs=@html.Attrs::build().aria_pressed(active.to_string()),
    label,
  )
}

///|
fn mbti_view_toolbar(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) else { return @html.nothing }
  let selected = state.mbti_view_mode(path)
  @html.div(
    class="review-mode-toolbar mbti-view-toolbar",
    attrs=@html.Attrs::build().role("group").aria_label("MBTI view"),
    [
      mbti_view_button(dispatch, selected, MbtiDiagram, "Diagram"),
      mbti_view_button(dispatch, selected, MbtiSource, "Source"),
    ],
  )
}

///|
fn full_diff_available(state : State, ctx : Ctx) -> Bool {
  let review_available = ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some(_) &&
    doc.diff_content() is Some(_)
  let history_available = ctx.active_history_diff is Some(diff) &&
    state.history_docs.get(history_diff_key(diff)) is Some(history) &&
    history.original.text() is Some(_) &&
    history.modified.text() is Some(_)
  review_available || history_available
}

///|
fn full_diff_ready(state : State, ctx : Ctx) -> Bool {
  let review_ready = ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some({ view_mode: ReviewDiff, .. }) &&
    doc.diff_content() is Some(_)
  let history_ready = ctx.active_history_diff is Some(diff) &&
    state.history_docs.get(history_diff_key(diff)) is Some(history) &&
    history.original.text() is Some(_) &&
    history.modified.text() is Some(_)
  review_ready || history_ready
}

///|
fn moon_diff_available(state : State, ctx : Ctx) -> Bool {
  let review_available = ctx.active_file is Some(path) &&
    supports_moon_diff(path.0) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some(_) &&
    doc.diff_content() is Some(_)
  let history_available = ctx.active_history_diff is Some(diff) &&
    supports_moon_diff(diff.path.0) &&
    state.history_docs.get(history_diff_key(diff)) is Some(history) &&
    history.original.text() is Some(_) &&
    history.modified.text() is Some(_)
  review_available || history_available
}

///|
fn moon_diff_ready(state : State, ctx : Ctx) -> Bool {
  moon_diff_available(state, ctx) && full_diff_ready(state, ctx)
}

///|
/// Whether the visible comparison is the complete Line DiffEditor. A parked
/// Token/Tree preference does not affect non-MoonBit files, which always keep
/// the Line surface.
fn line_diff_ready(state : State, ctx : Ctx) -> Bool {
  full_diff_ready(state, ctx) &&
  (state.review_diff_mode == ReviewDiffLine || !moon_diff_ready(state, ctx))
}

///|
/// Line receives availability from its mounted provider. Token/Tree plans are
/// already nonempty change documents, so their aggregate navigation is ready
/// once at least one semantic item exists.
fn review_diff_navigation_enabled(state : State, ctx : Ctx) -> Bool {
  if line_diff_ready(state, ctx) {
    state.review_diff_navigation_available
  } else {
    full_diff_ready(state, ctx) &&
    !semantic_sections(state.semantic_review_plan).is_empty()
  }
}

///|
fn ReviewDiffMode::label(self : ReviewDiffMode) -> String {
  match self {
    ReviewDiffLine => "Line"
    ReviewDiffToken => "Token"
    ReviewDiffTree => "Tree"
  }
}

///|
fn ReviewDiffMode::attribute(self : ReviewDiffMode) -> String {
  match self {
    ReviewDiffLine => "line"
    ReviewDiffToken => "token"
    ReviewDiffTree => "tree"
  }
}

///|
fn review_diff_mode_button(
  mode : ReviewDiffMode,
  active : Bool,
  on_click : @cmd.Cmd,
) -> @html.Html {
  @html.button(
    type_="button",
    class=if active {
      "review-mode-button active"
    } else {
      "review-mode-button"
    },
    title="Use " + mode.label() + " diff",
    on_click~,
    attrs=@html.Attrs::build()
      .data_set("diff-mode", mode.attribute())
      .aria_label(mode.label() + " diff")
      .aria_pressed(active.to_string()),
    mode.label(),
  )
}

///|
fn review_mode_toolbar(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some(review) &&
    doc.diff_content() is Some(_) else {
    return @html.span(class="review-mode-toolbar hidden", "")
  }
  let diff = review.view_mode == ReviewDiff
  let moon = supports_moon_diff(path.0)
  let children : Array[@html.Html] = [
    @html.button(
      type_="button",
      class=if diff {
        "review-mode-button"
      } else {
        "review-mode-button active"
      },
      title="Show file",
      on_click=if diff { dispatch(ToggleReviewDiff) } else { @cmd.none },
      attrs=@html.Attrs::build()
        .data_set("review-mode", "file")
        .aria_label("File view")
        .aria_pressed((!diff).to_string()),
      "File",
    ),
    @html.span(
      class="review-mode-divider",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
    review_diff_mode_button(
      ReviewDiffLine,
      diff && (!moon || state.review_diff_mode == ReviewDiffLine),
      if moon {
        dispatch(ReviewDiffModeSelected(ReviewDiffLine))
      } else if diff {
        @cmd.none
      } else {
        dispatch(ToggleReviewDiff)
      },
    ),
  ]
  if moon {
    children.push(
      review_diff_mode_button(
        ReviewDiffToken,
        diff && state.review_diff_mode == ReviewDiffToken,
        dispatch(ReviewDiffModeSelected(ReviewDiffToken)),
      ),
    )
    children.push(
      review_diff_mode_button(
        ReviewDiffTree,
        diff && state.review_diff_mode == ReviewDiffTree,
        dispatch(ReviewDiffModeSelected(ReviewDiffTree)),
      ),
    )
  }
  @html.div(
    class="review-mode-toolbar",
    attrs=@html.Attrs::build().role("toolbar").aria_label("Review mode"),
    children,
  )
}

///|
/// Historical comparisons have no File surface, but retain the same explicit
/// MoonBit comparison algorithms as changed-file reviews.
fn review_diff_mode_toolbar(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard moon_diff_ready(state, ctx) else {
    return @html.span(class="review-mode-toolbar hidden", "")
  }
  @html.div(
    class="review-mode-toolbar review-history-mode-toolbar",
    attrs=@html.Attrs::build()
      .role("toolbar")
      .aria_label("Comparison algorithm"),
    [
      review_diff_mode_button(
        ReviewDiffLine,
        state.review_diff_mode == ReviewDiffLine,
        dispatch(ReviewDiffModeSelected(ReviewDiffLine)),
      ),
      review_diff_mode_button(
        ReviewDiffToken,
        state.review_diff_mode == ReviewDiffToken,
        dispatch(ReviewDiffModeSelected(ReviewDiffToken)),
      ),
      review_diff_mode_button(
        ReviewDiffTree,
        state.review_diff_mode == ReviewDiffTree,
        dispatch(ReviewDiffModeSelected(ReviewDiffTree)),
      ),
    ],
  )
}

///|
fn review_comments_control(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard moon_diff_available(state, ctx) else {
    return @html.span(class="review-comments-control hidden", "")
  }
  let enabled = full_diff_ready(state, ctx) &&
    state.review_diff_mode != ReviewDiffLine
  @html.button(
    type_="button",
    class=if enabled && state.review_diff_ignore_comments {
      "review-comments-control active"
    } else {
      "review-comments-control"
    },
    title=if !full_diff_ready(state, ctx) {
      "Available in diff view"
    } else if state.review_diff_mode == ReviewDiffLine {
      "Available in Token and Tree diff"
    } else if state.review_diff_ignore_comments {
      "Include comments in the comparison"
    } else {
      "Ignore comment-only changes"
    },
    disabled=!enabled,
    on_click=dispatch(ToggleReviewDiffIgnoreComments),
    attrs=@html.Attrs::build()
      .aria_label("Ignore comments")
      .aria_pressed((enabled && state.review_diff_ignore_comments).to_string()),
    if state.review_diff_ignore_comments {
      "Comments: ignored"
    } else {
      "Comments: included"
    },
  )
}

///|
fn review_tests_control(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard moon_diff_available(state, ctx) else {
    return @html.span(class="review-tests-control hidden", "")
  }
  let enabled = full_diff_ready(state, ctx) &&
    state.review_diff_mode != ReviewDiffLine
  @html.button(
    type_="button",
    class=if enabled && state.review_diff_ignore_tests {
      "review-tests-control active"
    } else {
      "review-tests-control"
    },
    title=if !full_diff_ready(state, ctx) {
      "Available in diff view"
    } else if state.review_diff_mode == ReviewDiffLine {
      "Available in Token and Tree diff"
    } else if state.review_diff_ignore_tests {
      "Include tests in the comparison"
    } else {
      "Ignore MoonBit test blocks"
    },
    disabled=!enabled,
    on_click=dispatch(ToggleReviewDiffIgnoreTests),
    attrs=@html.Attrs::build()
      .aria_label("Ignore tests")
      .aria_pressed((enabled && state.review_diff_ignore_tests).to_string()),
    if state.review_diff_ignore_tests {
      "Tests: ignored"
    } else {
      "Tests: included"
    },
  )
}

///|
/// Previous/next controls for walking the DiffEditor's computed change groups.
/// They share the same command path as Shift+F7/F7, including wrapping at the
/// ends; the buttons therefore stay enabled at the first and last change.
fn review_diff_navigation(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard full_diff_available(state, ctx) else {
    return @html.span(class="review-diff-navigation hidden", "")
  }
  let enabled = full_diff_ready(state, ctx) &&
    review_diff_navigation_enabled(state, ctx)
  let position = state
    .active_review_hunk(ctx.active_file)
    .bind(active => active.position)
  let controls : Array[@html.Html] = [
    @html.button(
      type_="button",
      class="review-nav-button",
      title="Previous change (Shift+F7)",
      disabled=!enabled,
      on_click=dispatch(RevealPreviousReviewDiffChange),
      attrs=@html.Attrs::build()
        .data_set("action", "previous-diff-change")
        .aria_label("Previous change")
        .aria_keyshortcuts("Shift+F7"),
      @icons.icon(@icons.icon_arrow_up),
    ),
  ]
  if position is Some(position) {
    controls.push(
      @html.span(
        class="review-hunk-position",
        attrs=@html.Attrs::build()
          .aria_label("Hunk \{position.current} of \{position.total}")
          .aria_live("polite"),
        "\{position.current} of \{position.total}",
      ),
    )
  }
  controls.push(
    @html.button(
      type_="button",
      class="review-nav-button",
      title="Next change (F7)",
      disabled=!enabled,
      on_click=dispatch(RevealNextReviewDiffChange),
      attrs=@html.Attrs::build()
        .data_set("action", "next-diff-change")
        .aria_label("Next change")
        .aria_keyshortcuts("F7"),
      @icons.icon(@icons.icon_arrow_down),
    ),
  )
  @html.div(
    class="review-diff-navigation",
    attrs=@html.Attrs::build()
      .role("group")
      .aria_label("Diff change navigation"),
    controls,
  )
}

///|
fn review_hunk_toggle_button(
  dispatch : @cmd.Emit[Msg],
  hunk_state : ReviewHunkState,
  disabled : Bool,
) -> @html.Html {
  let viewed = hunk_state is ReviewHunkViewed
  @html.button(
    type_="button",
    class=if viewed {
      "review-badge review-progress reviewed"
    } else {
      "review-badge review-progress"
    },
    title=if disabled {
      "File is marked reviewed"
    } else if viewed {
      "Mark this hunk unviewed"
    } else {
      "Mark this hunk viewed"
    },
    disabled~,
    on_click=dispatch(ToggleActiveReviewHunk),
    attrs=@html.Attrs::build()
      .aria_label(
        if disabled {
          "Hunk viewed"
        } else if viewed {
          "Unmark hunk viewed"
        } else {
          "Mark hunk viewed"
        },
      )
      .aria_pressed(
        match hunk_state {
          ReviewHunkUnviewed => "false"
          ReviewHunkPartial => "mixed"
          ReviewHunkViewed => "true"
        },
      ),
    match hunk_state {
      ReviewHunkUnviewed => "Mark viewed"
      ReviewHunkPartial => "◐ Mark viewed"
      ReviewHunkViewed => "✓ Viewed"
    },
  )
}

///|
fn review_hunk_toggle(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard state.active_review_hunk(ctx.active_file) is Some(active) else {
    return @html.nothing
  }
  let hunk_state = state.review_hunk_state(active.change, active.hunk)
  review_hunk_toggle_button(
    dispatch,
    hunk_state,
    state.is_change_reviewed(active.change) && active.file_changes is None,
  )
}

///|
/// Line keeps its two models mounted while Token/Tree reuse one section plan;
/// this explicit pair changes either presentation. File mode preserves the
/// preference but disables both choices until the next review reveal.
fn review_diff_layout_toggle(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard full_diff_available(state, ctx) else {
    return @html.span(class="review-layout-control hidden", "")
  }
  let ready = full_diff_ready(state, ctx)
  let inline = state.review_diff_layout == ReviewInline
  @html.div(
    class=if ready {
      "review-layout-control"
    } else {
      "review-layout-control disabled"
    },
    attrs=@html.Attrs::build().role("group").aria_label("Diff layout"),
    [
      @html.button(
        type_="button",
        class=if ready && !inline {
          "review-layout-button active"
        } else {
          "review-layout-button"
        },
        title="Use side-by-side diff layout",
        disabled=!ready,
        on_click=if ready && inline {
          dispatch(ToggleReviewDiffLayout)
        } else {
          @cmd.none
        },
        attrs=@html.Attrs::build()
          .data_set("layout", "side-by-side")
          .aria_label("Split diff layout")
          .aria_pressed((ready && !inline).to_string()),
        "Split",
      ),
      @html.button(
        type_="button",
        class=if ready && inline {
          "review-layout-button active"
        } else {
          "review-layout-button"
        },
        title="Use unified diff layout",
        disabled=!ready,
        on_click=if ready && !inline {
          dispatch(ToggleReviewDiffLayout)
        } else {
          @cmd.none
        },
        attrs=@html.Attrs::build()
          .data_set("layout", "inline")
          .aria_label("Unified diff layout")
          .aria_pressed((ready && inline).to_string()),
        "Unified",
      ),
    ],
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
  let progress = state.changed_file_review_state(review.selected)
  let reviewed = progress is ReviewComplete
  @html.button(
    type_="button",
    class=match progress {
      ReviewComplete => "review-badge review-progress reviewed"
      ReviewInProgress => "review-badge review-progress"
      ReviewUnviewed => "review-badge review-progress"
    },
    title=if reviewed {
      "Return this changed file to the review queue"
    } else {
      "Mark this changed file as reviewed"
    },
    on_click=dispatch(ToggleReviewProgress),
    attrs=@html.Attrs::build()
      .aria_label(
        if reviewed {
          "Mark file unreviewed"
        } else {
          "Mark file reviewed"
        },
      )
      .aria_pressed(
        match progress {
          ReviewComplete => "true"
          ReviewInProgress => "mixed"
          ReviewUnviewed => "false"
        },
      ),
    match progress {
      ReviewComplete => "✓ Reviewed"
      ReviewInProgress => "◐ In progress"
      ReviewUnviewed => "Mark reviewed"
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
        Some(doc) if doc.diff_content() is Some(_) =>
          match doc.review {
            Some({ view_mode: ReviewDiff, .. }) =>
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
            ..
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
            ..
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
            ..
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
