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
          ([] : FixedArray[@js.Value]),
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
          ([] : FixedArray[@js.Value]),
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
/// `package-diagram-host`, `diff-editor-host`, and `semantic-review-host`) stay put
/// across renders and screen
/// switches; CSS hides the inactive surface and the tree pane when toggled off,
/// and collapses the whole panel to zero width when it is closed. The children's
/// order is structural — rabbita diffs by index, so every part renders
/// unconditionally.
pub fn body_view(
  locale? : @i18n.Locale = English,
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
          state.docs.get(path).map(doc => doc.name).unwrap_or(path.path),
        )
      None => false
    })
  let use_mbti_surface = !use_diff_surface &&
    !use_markdown_surface &&
    uses_mbti_diagram_surface(state, ctx)
  let use_package_surface = !use_diff_surface &&
    !use_markdown_surface &&
    !use_mbti_surface &&
    uses_package_diagram_surface(state, ctx)
  let use_semantic_surface = use_diff_surface &&
    state.review_diff_mode != ReviewDiffLine &&
    (match ctx.active_history_diff {
      Some(diff) => supports_moon_diff(diff.path.0)
      None =>
        ctx.active_file
        .map(path => supports_moon_diff(path.path))
        .unwrap_or(false)
    })
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class(
        if use_diff_surface ||
          use_markdown_surface ||
          use_mbti_surface ||
          use_package_surface {
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
  let package_diagram_host = @html.div(
    attrs=@html.Attrs::build()
      .id(PackageDiagramHostId)
      .class(
        if use_package_surface {
          "viewer-host editor-shell package-diagram-host"
        } else {
          "viewer-host editor-shell package-diagram-host moonbit-viewer-surface-hidden"
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
        track_semantic_review_scroll(element)
        @cmd.none
      }),
    semantic_review,
  )
  @html.div(class="editor-body", [
    @html.div(class="viewer-stack", [
      viewer_host,
      markdown_viewer_host,
      mbti_diagram_host,
      package_diagram_host,
      diff_editor_host,
      semantic_review_host,
      viewer_notice(locale~, state, ctx),
      github_review_line_layer(locale~, dispatch, state, ctx),
    ]),
    tree_pane(locale~, dispatch, state, ctx),
  ])
}

///|
/// The notice covering the viewer while the active document has nothing to
/// show — a deleted, unavailable, binary, or oversized file. Plain panel
/// chrome laid over the (cleared) viewer, so a notice never renders as a
/// highlighted source document. Always in the DOM; blank and hidden otherwise.
fn viewer_notice(
  locale? : @i18n.Locale = English,
  state : State,
  ctx : Ctx,
) -> @html.Html {
  if ctx.active_history_diff is Some(diff) {
    let text = history_diff_notice(locale~, state, diff)
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
          dynamic_text(locale, DLoadingDiff(doc.name.to_string()))
        Some(doc) if doc.diff_is_pending() => ""
        Some(doc) =>
          match doc.state {
            TabDeleted =>
              match doc.review {
                Some({ baseline: ReviewLoading, .. }) =>
                  dynamic_text(locale, DLoadingBaseline(doc.name.to_string()))
                Some({ baseline: ReviewContent(_), .. }) => ""
                Some({ baseline: ReviewMissing, .. }) =>
                  "\{doc.name} was deleted and has no review baseline to preview."
                Some({ baseline: ReviewBinary, .. }) =>
                  dynamic_text(locale, DBinaryBaseline(doc.name.to_string()))
                Some({ baseline: ReviewOversized, .. }) =>
                  dynamic_text(locale, DLargeBaseline(doc.name.to_string()))
                Some({ baseline: ReviewFailed(message), .. }) =>
                  dynamic_text(
                    locale,
                    DBaselineFailed(doc.name.to_string(), message.to_string()),
                  )
                None => "\{doc.name} was deleted on disk."
              }
            TabBinary => "\{doc.name} is a binary file and cannot be previewed."
            TabOversized => "\{doc.name} is too large to preview."
            TabReadFailed(message) =>
              if doc.review is Some({ baseline: ReviewContent(_), .. }) {
                ""
              } else {
                dynamic_text(
                  locale,
                  DReadFailed(doc.name.to_string(), message.to_string()),
                )
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
fn history_diff_notice(
  locale? : @i18n.Locale = English,
  state : State,
  diff : @dock.GitHistoryDiff,
) -> String {
  guard state.history_docs.get(history_diff_key(diff)) is Some(doc) else {
    return dynamic_text(
      locale,
      DLoadingHistoryDiff(basename(diff.path).to_string()),
    )
  }
  match (doc.original, doc.modified) {
    (HistoryBlobLoading, _) | (_, HistoryBlobLoading) =>
      dynamic_text(locale, DLoadingHistoryDiff(basename(diff.path).to_string()))
    (HistoryBlobError(message), _) | (_, HistoryBlobError(message)) =>
      dynamic_text(
        locale,
        DHistoryDiffFailed(basename(diff.path).to_string(), message.to_string()),
      )
    (HistoryBlobBinary, _) | (_, HistoryBlobBinary) =>
      "\{basename(diff.path)} is binary at this revision and cannot be previewed."
    (HistoryBlobOversized, _) | (_, HistoryBlobOversized) =>
      "\{basename(diff.path)} is too large at this revision to preview."
    (HistoryBlobMissing, HistoryBlobMissing) => ui(locale, NoCommitContent)
    _ => ""
  }
}

///|
/// The toggleable file-tree panel, docked flat under the viewer like an Emacs
/// bottom window. Request-local listing failures remain beside the inventory;
/// watcher failures use the root app's transient toast rail instead.
fn tree_pane(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let visible_error = if state.explorer_mode is ExplorerSearch {
    None
  } else {
    state.error
  }
  let inventory = if ctx.placement is None {
    [@html.div(class="file-panel-empty", ui(locale, WaitingPlacement))]
  } else if ctx.placement is Some(@interop.MissingWorktree(..)) {
    [@html.div(class="file-panel-empty", ui(locale, MissingCheckout))]
  } else if ctx.owner.session.is_empty() {
    [@html.div(class="file-panel-empty", ui(locale, NoConversation))]
  } else {
    match state.explorer_mode {
      ExplorerFiles => file_inventory(locale~, dispatch, state, ctx)
      ExplorerChanges => [review_git_layout(locale~, dispatch, state, ctx)]
      ExplorerSearch =>
        [
          state.search.explorer_view(
            locale~,
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
      attrs=@html.Attrs::build()
        .role("tablist")
        .aria_label(ui(locale, ExplorerViews)),
      [
        explorer_tab(
          dispatch,
          state.explorer_mode,
          ExplorerFiles,
          ui(locale, WorkspaceFiles),
          [
            @icons.icon(@icons.icon_folder),
            @html.span(class="visually-hidden", ui(locale, FilesLabel)),
          ],
        ),
        explorer_tab(
          dispatch,
          state.explorer_mode,
          ExplorerChanges,
          ui(locale, ChangedFilesHint),
          // Keep the name and count in the accessibility tree, as before.
          [
            @icons.icon(@icons.icon_diff_multiple),
            @html.span(class="visually-hidden", ui(locale, ChangesLabel)),
            change_count(state.changes),
          ],
        ),
        explorer_tab(
          dispatch,
          state.explorer_mode,
          ExplorerSearch,
          ui(locale, SearchWorkspace),
          [
            @icons.icon(@icons.icon_search),
            @html.span(class="visually-hidden", ui(locale, SearchLabel)),
          ],
        ),
      ],
    ),
    @html.div(
      class=if state.explorer_mode is ExplorerSearch {
        "file-tree search-inventory"
      } else if state.explorer_mode is ExplorerChanges {
        "file-tree review-git-tree"
      } else {
        "file-tree workspace-file-list"
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
fn review_git_sections(
  locale? : @i18n.Locale = English,
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
              @html.span(class="review-section-title", ui(locale, ChangesLabel)),
              change_count(state.changes),
            ],
          ),
          @html.div(
            class="review-section-body",
            attrs=@html.Attrs::build().id("review-changes-body"),
            change_inventory_rows(locale~, dispatch, state, ctx),
          ),
        ],
      ),
      @html.div(
        class=if split_hidden {
          "review-split-handle hidden"
        } else {
          "review-split-handle"
        },
        title=ui(locale, ResizeGraph),
        attrs=@html.Attrs::build()
          .id(GitGraphResizeHandleId)
          .role("separator")
          .tabindex(0)
          .aria_label(ui(locale, ResizeGraph))
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
                  ui(locale, GraphLabel),
                ),
              ],
            ),
            @html.div(class="git-graph-toolbar", [
              @html.span(
                class="git-graph-context git-graph-repository",
                title=git_graph_repository_label(locale~, ctx),
                [
                  @html.span(
                    class="git-graph-context-icon",
                    icon_git_repository(),
                  ),
                  @html.span(
                    class="git-graph-context-label",
                    git_graph_repository_label(locale~, ctx),
                  ),
                ],
              ),
              @html.span(
                class="git-graph-context git-graph-branch",
                title=git_graph_branch_label(locale~, state),
                [
                  @html.span(class="git-graph-context-icon", icon_git_branch()),
                  @html.span(
                    class="git-graph-context-label",
                    git_graph_branch_label(locale~, state),
                  ),
                ],
              ),
              @html.button(
                class="git-graph-refresh",
                title=ui(locale, RefreshGraph),
                on_click=dispatch(GitHistoryRefreshRequested),
                attrs=@html.Attrs::build().aria_label(ui(locale, RefreshGraph)),
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
            git_graph_inventory(locale~, dispatch, state, ctx),
          ),
        ],
      ),
    ],
  )
}

///|
fn git_graph_repository_label(
  locale? : @i18n.Locale = English,
  ctx : Ctx,
) -> String {
  ctx
  .workspace()
  .map(resource => @resource.label(resource))
  .unwrap_or(ui(locale, RepositoryLabel))
}

///|
fn git_graph_branch_label(
  locale? : @i18n.Locale = English,
  state : State,
) -> String {
  match state.git_graph {
    GitGraphReady(snapshot~, ..) =>
      snapshot.branch.unwrap_or(
        snapshot.head.map(short_commit).unwrap_or(ui(locale, NoCommits)),
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
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn git_graph_inventory(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> Array[@html.Html] {
  match state.git_graph {
    GitGraphIdle | GitGraphLoading =>
      [@html.div(class="file-panel-empty", ui(locale, LoadingHistory))]
    GitGraphFailed(message) =>
      [
        @html.div(class="git-graph-message", [
          @html.span(dynamic_text(locale, DHistoryFailed(message.to_string()))),
          @html.button(
            class="git-graph-retry",
            on_click=dispatch(GitHistoryRefreshRequested),
            ui(locale, RetryLabel),
          ),
        ]),
      ]
    GitGraphReady(repository=false, ..) =>
      [@html.div(class="file-panel-empty", ui(locale, GitUnavailable))]
    GitGraphReady(
      snapshot~,
      commits~,
      has_more~,
      loading_more~,
      load_error~,
      ..
    ) => {
      if commits.is_empty() {
        return [@html.div(class="file-panel-empty", ui(locale, EmptyBranch))]
      }
      let layouts = graph_rows(commits, snapshot)
      let children : Array[@html.Html] = []
      for index, commit in commits {
        children.push(
          git_commit_row(
            locale~,
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
            dynamic_text(locale, DLoadMoreFailed(message.to_string())),
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
                  ui(locale, LoadingLabel)
                } else {
                  ui(locale, LoadMore)
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
            .aria_label(ui(locale, CommitHistory)),
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
    let highlight_class = if highlight_index is Some(highlight) &&
      highlight == lane {
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
          .stroke_width(
            if highlight_index is Some(highlight) && highlight == lane {
              "3"
            } else {
              "1"
            },
          )
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
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  commit : @protocol.GitHistoryCommit,
  layout : GraphRow,
  index : Int,
  total : Int,
) -> @html.Html {
  let expanded = state.git_graph_selected is Some(selected) &&
    selected == commit.id
  let refs : Array[@html.Html] = []
  let mut head = false
  if state.git_graph is GitGraphReady(snapshot~, ..) {
    head = snapshot.head is Some(selected) && selected == commit.id
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
    children.push(
      git_commit_files(locale~, dispatch, state, ctx, commit, layout),
    )
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
  locale? : @i18n.Locale = English,
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
          @html.span(ui(locale, LoadingChangedFiles)),
        ]),
      ]
    GitCommitFilesFailed(commit=id, message~) if id == commit.id =>
      [
        @html.div(class="git-commit-files-message error", [
          git_graph_placeholder(columns, highlight_index),
          @html.span(class="git-commit-files-message-content", [
            @html.span(dynamic_text(locale, DCommitFailed(message.to_string()))),
            @html.button(
              class="git-history-retry",
              on_click=dispatch(GitCommitChangesRetry(commit.id)),
              ui(locale, RetryLabel),
            ),
          ]),
        ]),
      ]
    GitCommitFilesReady(commit=id, parent~, files~) if id == commit.id =>
      if files.is_empty() {
        [
          @html.div(class="git-commit-files-message", [
            git_graph_placeholder(columns, highlight_index),
            @html.span(ui(locale, NoWorkspaceChanges)),
          ]),
        ]
      } else {
        let visible = filtered_history_changes(state, files)
        if visible.is_empty() {
          [
            @html.div(
              class="git-commit-files-message",
              ui(locale, NoFilterMatches),
            ),
          ]
        } else {
          visible.map(file => {
            let selectable = file.kind == "file" &&
              !(["renamed", "copied"].contains(file.status) &&
              file.original_path is None)
            let diff : @dock.GitHistoryDiff = {
              commit: commit.id,
              parent,
              path: @pathx.Relative(file.path),
              original_path: file.original_path.map(path => {
                @pathx.Relative(path)
              }),
              status: file.status,
              kind: file.kind,
            }
            let selected = ctx.active_history_diff is Some(active_diff) &&
              active_diff == diff
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
                title=dynamic_text(
                  locale,
                  DOpenHistoryDiff(file.path.to_string()),
                ),
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
                  ui(locale, SubmoduleDiff)
                } else if file.kind == "symlink" {
                  ui(locale, SymlinkDiff)
                } else {
                  ui(locale, PathOutsideWorkspace)
                },
                attrs=@html.Attrs::build()
                  .role("treeitem")
                  .aria_disabled("true"),
                contents,
              )
            }
          })
        }
      }
    _ =>
      [
        @html.div(class="git-commit-files-message", [
          git_graph_placeholder(columns, highlight_index),
          @html.span(ui(locale, LoadingChangedFiles)),
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
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> Array[@html.Html] {
  let entries = visible_entries(state)
  let focus = tree_focus_target(state)
  let children = if !state.children.contains("") {
    [@html.div(class="file-panel-empty", ui(locale, LoadingLabel))]
  } else if entries.is_empty() {
    [@html.div(class="file-panel-empty", ui(locale, EmptyWorkspace))]
  } else {
    entries.map(pair => tree_row(dispatch, state, ctx, pair.0, pair.1, focus))
  }
  [
    @html.div(
      attrs=@html.Attrs::build()
        .id("workspace-file-tree")
        .role("tree")
        .aria_label(ui(locale, WorkspaceFiles))
        .tabindex(if entries.is_empty() { 0 } else { -1 }),
      children,
    ),
  ]
}

///|
fn change_inventory_rows(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> Array[@html.Html] {
  match state.changes {
    ChangeListIdle | ChangeListLoading(_) =>
      [@html.div(class="file-panel-empty", ui(locale, LoadingChanges))]
    ChangeListFailed(message) =>
      [
        @html.div(
          class="file-panel-empty",
          dynamic_text(locale, DChangesFailed(message.to_string())),
        ),
      ]
    ChangeListReady(repository=false, ..) =>
      [@html.div(class="file-panel-empty", ui(locale, GitUnavailable))]
    ChangeListReady(files~, ..) =>
      if files.is_empty() {
        [@html.div(class="file-panel-empty", ui(locale, NoChangedFiles))]
      } else {
        let reviewable = files.filter(change => change.selectable())
        let reviewed = reviewable
          .filter(change => state.is_change_reviewed(change))
          .length()
        let rows = [
          @html.div(
            class="review-progress-summary",
            if reviewable.is_empty() {
              ui(locale, NoReviewableFiles)
            } else {
              dynamic_text(
                locale,
                DReviewedFiles(reviewed, reviewable.length()),
              )
            },
          ),
        ]
        let visible = filtered_changes(state)
        if visible.is_empty() {
          rows.push(
            @html.div(class="file-panel-empty", ui(locale, NoFilterMatches)),
          )
        }
        let tree_rows = change_tree_rows(state)
        let focus = change_tree_focus_target(state, tree_rows)
        rows.push(
          @html.div(
            class="change-tree",
            attrs=@html.Attrs::build()
              .id("review-file-tree")
              .role("tree")
              .aria_label(ui(locale, ChangedFiles))
              .tabindex(if tree_rows.is_empty() { 0 } else { -1 }),
            [
              for index, row in tree_rows => {
                change_tree_row(
                  locale~,
                  dispatch,
                  state,
                  ctx,
                  tree_rows,
                  row,
                  index,
                  focus,
                )
              }
            ],
          ),
        )
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
fn change_tree_row(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  rows : Array[ChangeTreeRow],
  row : ChangeTreeRow,
  index : Int,
  focus : ChangeTreeItem?,
) -> @html.Html {
  let item = row.node.item
  let selected = item is ChangeFile(change) && change.is_selected(state, ctx)
  let reviewable = row.node.changes.any(change => change.selectable())
  let progress = change_tree_review_state(state, row.node.changes)
  let mut class = match item {
    ChangeDirectory(_) => "tree-row change-directory"
    ChangeFile(change) => "tree-row change-row " + change.kind_class()
  }
  if selected {
    class += " selected"
  }
  if progress is ReviewComplete {
    class += " reviewed"
  }
  if !reviewable {
    class += " disabled"
  }
  let label = match item {
    ChangeDirectory(path) => path.0
    ChangeFile(change) => ui(locale, ViewDiffPrefix) + change.status_title()
  }
  let title = match item {
    ChangeDirectory(path) => path.0
    ChangeFile(change) if change.selectable() =>
      ui(locale, OpenDiffPrefix) + change.status_title()
    ChangeFile(change) => change.unselectable_title(locale~)
  }
  let attrs = @html.Attrs::build()
    .role("treeitem")
    .aria_label(label)
    .aria_level((row.depth + 1).to_string())
    .aria_posinset((row.position + 1).to_string())
    .aria_setsize(row.siblings.to_string())
    .aria_selected(selected.to_string())
    .aria_current(if selected { "page" } else { "false" })
    .data_set("path", item.path().0)
    .tabindex(if focus == Some(item) { 0 } else { -1 })
    .on_focus(_ => dispatch(ChangeTreeFocused(item)))
    .on_keydown(event => {
      if event.alt_key() || event.ctrl_key() || event.meta_key() {
        return @cmd.none
      }
      if [
          "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End", "Enter",
          " ",
        ].contains(event.key()) {
        event.prevent_default()
        event.stop_propagation()
        change_tree_key(dispatch, state, rows, index, event.key())
      } else {
        @cmd.none
      }
    })
  let attrs = match change_tree_row_id(state, item) {
    Some(id) => attrs.id(id)
    None => attrs
  }
  let attrs = match item {
    ChangeDirectory(_) => attrs.aria_expanded(row.expanded.to_string())
    ChangeFile(_) => attrs.aria_disabled((!reviewable).to_string())
  }
  @html.div(
    class~,
    title~,
    style=["--tree-depth: \{row.depth}"],
    attrs~,
    on_click=@cmd.batch([
      focus_change_tree_after_render(state, Some(item)),
      match item {
        ChangeDirectory(path) =>
          dispatch(ChangeDirectoryExpanded(path, !row.expanded))
        ChangeFile(change) if change.selectable() =>
          dispatch(ChangedFileSelected(change))
        _ => @cmd.none
      },
    ]),
    [
      @html.span(
        class=if row.expanded {
          "tree-twistie expanded"
        } else {
          "tree-twistie"
        },
        attrs=@html.Attrs::build().aria_hidden("true"),
        if item is ChangeDirectory(_) {
          @icons.icon_chevron_down()
        } else {
          @html.nothing
        },
      ),
      @html.button(
        class="change-review-checkbox",
        type_="button",
        disabled=!reviewable,
        title=if progress is ReviewComplete {
          ui(locale, MarkUnreviewed)
        } else {
          ui(locale, MarkReviewed)
        },
        attrs=@html.Attrs::build()
          .role("checkbox")
          .tabindex(-1)
          .aria_label(ui(locale, ReviewedPrefix) + item.path().0)
          .aria_checked(
            match progress {
              ReviewComplete => "true"
              ReviewInProgress => "mixed"
              ReviewUnviewed => "false"
            },
          )
          .on_click(event => {
            event.stop_propagation()
            @cmd.batch([
              dispatch(ChangeTreeReviewToggled(item)),
              focus_change_tree_after_render(state, Some(item)),
            ])
          })
          .on_keydown(event => {
            event.stop_propagation()
            @cmd.none
          }),
        match progress {
          ReviewComplete => @icons.icon_check()
          ReviewInProgress => @html.span(class="change-review-partial", "")
          ReviewUnviewed => @html.nothing
        },
      ),
      if item is ChangeFile(_) {
        @html.span(
          class="change-file-icon",
          attrs=@html.Attrs::build().aria_hidden("true"),
          @svg.svg(width=16, height=16, view_box="0 0 16 16", [
            @svg.path(
              d="M3 3.5h10M3 6.5h7M3 9.5h10M3 12.5h7",
              attrs=@svg.Attrs::build().stroke("currentColor").fill("none"),
            ),
          ]),
        )
      } else {
        @html.nothing
      },
      @html.span(class="change-path", row.node.label),
      match item {
        ChangeFile(change) => {
          let count = state.github_review.comment_count(change.path.0)
          if count > 0 {
            @html.span(
              class="github-review-file-count",
              title=ui(locale, UnresolvedGithubConversations),
              [@icons.icon_comment(), @html.text(count.to_string())],
            )
          } else {
            @html.nothing
          }
        }
        _ => @html.nothing
      },
      match item {
        ChangeFile(change) =>
          @html.span(
            class="change-status " + change.kind_class(),
            change.status_label(),
          )
        ChangeDirectory(_) => @html.nothing
      },
      @html.span(
        class="tree-indent-guides",
        attrs=@html.Attrs::build().aria_hidden("true"),
        @html.nothing,
      ),
    ],
  )
}

///|
fn reviewable_changes(state : State) -> Array[ChangedFile] {
  filtered_changes(state).filter(change => change.selectable())
}

///|
fn change_row_index(state : State, selected : ChangedFile) -> Int? {
  filtered_changes(state).search_by(change => change == selected)
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
  guard ctx.active_file is Some(active) &&
    ctx.relative(active) == Some(self.path) else {
    return false
  }
  match ctx.resource(self.path).bind(file => state.docs.get(file)) {
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
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  label : String,
  path : @pathx.Relative,
  open : Bool,
) -> @html.Html {
  @html.button(
    type_="button",
    class="crumb crumb-directory",
    title=dynamic_text(locale, DShowFiles(label.to_string())),
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
/// ui(locale, WorkspaceLabel) crumb. Every crumb but the last opens a VS Code-style picker
/// of that directory's immediate children, without moving or hiding the
/// source viewer behind it.
/// Reviews add a second, horizontally scrolling command row so the path,
/// file navigation, and completion action never compete with comparison settings.
/// With no file open the whole breadcrumb hides; it stays in the DOM so the
/// editor's child order, and thus the viewer host, is never re-keyed.
pub fn breadcrumb_view(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  reveal? : (String, @cmd.Cmd)? = None,
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
              ui(locale, HideFileTree)
            } else {
              ui(locale, ShowFileTree)
            },
            on_click=dispatch(ToggleTree),
            icon(icon_folder),
          ),
        ]),
        @html.div(class="review-command-row", [
          review_diff_mode_toolbar(locale~, dispatch, state, ctx),
          @html.span(
            class=if moon_diff_controls_visible(state, ctx) {
              "review-control-divider"
            } else {
              "review-control-divider hidden"
            },
            attrs=@html.Attrs::build().aria_hidden("true"),
            "",
          ),
          review_diff_layout_toggle(locale~, dispatch, state, ctx),
          review_comments_control(locale~, dispatch, state, ctx),
          review_tests_control(locale~, dispatch, state, ctx),
          review_diff_navigation(locale~, dispatch, state, ctx),
        ]),
      ],
    )
  }
  let crumbs : Array[@html.Html] = []
  match ctx.active_file {
    Some(file) =>
      if ctx.relative(file) is Some(path) {
        crumbs.push(
          crumb_link(
            locale~,
            dispatch,
            ui(locale, WorkspaceLabel),
            @pathx.Relative::root(),
            state.highlighted is Some(highlight) &&
            highlight == @pathx.Relative::root(),
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
                locale~,
                dispatch,
                segment,
                segments_prefix(segments, index + 1),
                state.highlighted is Some(highlight) &&
                highlight == segments_prefix(segments, index + 1),
              ),
            )
          }
        }
      } else {
        crumbs.push(@html.span(class="crumb crumb-file", file.path))
      }
    None =>
      crumbs.push(
        @html.span(class="crumb crumb-file", ui(locale, WorkspaceLabel)),
      )
  }
  let review = review_toolbar_visible(state, ctx)
  let path_row : Array[@html.Html] = [@html.div(class="crumb-path", crumbs)]
  if !review {
    path_row.push(review_diff_navigation(locale~, dispatch, state, ctx))
  }
  if !full_diff_available(state, ctx) {
    path_row.push(review_badge(locale~, dispatch, state, ctx))
  }
  path_row.push(review_progress(locale~, dispatch, state, ctx))
  if mbti_view_available(state, ctx) {
    path_row.push(mbti_view_toolbar(locale~, dispatch, state, ctx))
  }
  if moon_mod_view_available(state, ctx) {
    path_row.push(moon_mod_view_toolbar(locale~, dispatch, state, ctx))
  }
  if reveal is Some((label, command)) {
    path_row.push(
      @html.button(
        type_="button",
        class="file-reveal-button",
        title=label,
        on_click=command,
        attrs=@html.Attrs::build().aria_label(label),
        [icon(@icons.icon_link_external), @html.text(label)],
      ),
    )
  }
  path_row.push(
    @html.button(
      class="panel-toggle",
      title=if state.tree_open {
        ui(locale, HideFileTree)
      } else {
        ui(locale, ShowFileTree)
      },
      on_click=dispatch(ToggleTree),
      icon(icon_folder),
    ),
  )
  if review {
    let children : Array[@html.Html] = [
      @html.div(class="viewer-breadcrumb-row", path_row),
      @html.div(class="review-command-row", [
        review_mode_toolbar(locale~, dispatch, state, ctx),
        @html.span(
          class="review-control-divider",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "",
        ),
        review_diff_layout_toggle(locale~, dispatch, state, ctx),
        review_comments_control(locale~, dispatch, state, ctx),
        review_tests_control(locale~, dispatch, state, ctx),
        @github_review.toolbar(
          locale~,
          state.github_review,
          dispatch.map(msg => GithubReview(msg)),
          current=ctx.github,
        ),
        review_navigation_controls(locale~, dispatch, state, ctx),
      ]),
      github_review_status(locale~, dispatch, state, ctx),
    ]
    if state.highlighted is Some(directory) {
      children.push(breadcrumb_picker(locale~, dispatch, state, ctx, directory))
    }
    @html.div(class="viewer-breadcrumb review-toolbar", children)
  } else {
    if state.highlighted is Some(directory) {
      path_row.push(breadcrumb_picker(locale~, dispatch, state, ctx, directory))
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
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) else { return @html.nothing }
  let selected = state.mbti_view_mode(path)
  @html.div(
    class="review-mode-toolbar mbti-view-toolbar",
    attrs=@html.Attrs::build()
      .role("group")
      .aria_label(
        match locale {
          SimplifiedChinese => "MBTI 视图"
          TraditionalChinese => "MBTI 檢視"
          Japanese => "MBTI ビュー"
          English => "MBTI view"
          Spanish => "Vista MBTI"
        },
      ),
    [
      mbti_view_button(
        dispatch,
        selected,
        MbtiDiagram,
        ui(locale, DiagramLabel),
      ),
      mbti_view_button(dispatch, selected, MbtiSource, ui(locale, SourceLabel)),
    ],
  )
}

///|
/// A package dependency graph belongs only to an ordinary, loaded file whose
/// exact basename is `moon.mod`. Reviews and historical comparisons retain
/// their source/diff surfaces even if their path names a module manifest.
fn moon_mod_view_available(state : State, ctx : Ctx) -> Bool {
  guard ctx.active_history_diff is None &&
    ctx.active_file is Some(path) &&
    ctx.relative(path) is Some(_) else {
    return false
  }
  state.docs.get(path) is Some({ name, state: TabLoaded(..), review: None, .. }) &&
  uses_moon_mod_presentation(name)
}

///|
fn uses_package_diagram_surface(state : State, ctx : Ctx) -> Bool {
  guard moon_mod_view_available(state, ctx) && ctx.active_file is Some(path) else {
    return false
  }
  state.moon_mod_view_mode(path) == MoonModDependencies
}

///|
fn moon_mod_view_button(
  dispatch : @cmd.Emit[Msg],
  selected : MoonModViewMode,
  mode : MoonModViewMode,
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
    // An already-selected failed dependency view treats another click as an
    // explicit retry; the update loop leaves every other same-mode click inert.
    on_click=dispatch(MoonModViewModeSelected(mode)),
    attrs=@html.Attrs::build().aria_pressed(active.to_string()),
    label,
  )
}

///|
fn moon_mod_view_toolbar(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) else { return @html.nothing }
  let selected = state.moon_mod_view_mode(path)
  @html.div(
    class="review-mode-toolbar moon-mod-view-toolbar",
    attrs=@html.Attrs::build()
      .role("group")
      .aria_label(ui(locale, MoonModuleView)),
    [
      moon_mod_view_button(
        dispatch,
        selected,
        MoonModDependencies,
        ui(locale, DependencyGraph),
      ),
      moon_mod_view_button(
        dispatch,
        selected,
        MoonModSource,
        ui(locale, SourceLabel),
      ),
    ],
  )
}

///|
/// Toolbar placement belongs to the review context, not to asynchronously
/// loaded diff inputs. Keep the same rows and controls while either side loads.
fn review_toolbar_visible(state : State, ctx : Ctx) -> Bool {
  ctx.active_history_diff is Some(_) ||
  (
    ctx.active_file is Some(path) &&
    state.docs.get(path) is Some({ review: Some(_), .. })
  )
}

///|
fn moon_diff_controls_visible(state : State, ctx : Ctx) -> Bool {
  if ctx.active_history_diff is Some(diff) {
    supports_moon_diff(diff.path.0)
  } else {
    review_toolbar_visible(state, ctx) &&
    ctx.active_file is Some(path) &&
    supports_moon_diff(path.path)
  }
}

///|
fn review_controls_pending(state : State, ctx : Ctx) -> Bool {
  state.review_navigation_display is Some(_) &&
  ctx.active_history_diff is None &&
  ctx.active_file is Some(path) &&
  state.docs.get(path) is Some(doc) &&
  doc.diff_is_pending()
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
    supports_moon_diff(path.path) &&
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
  if active_review_position(state, ctx) is Some((_, _, total)) && total > 1 {
    return true
  }
  if line_diff_ready(state, ctx) {
    state.review_diff_navigation_available
  } else {
    full_diff_ready(state, ctx) &&
    !semantic_sections(state.semantic_review_plan).is_empty()
  }
}

///|
fn ReviewDiffMode::label(
  locale? : @i18n.Locale = English,
  self : ReviewDiffMode,
) -> String {
  match self {
    ReviewDiffLine => ui(locale, LineLabel)
    ReviewDiffToken => ui(locale, TokenLabel)
    ReviewDiffTree => ui(locale, TreeLabel)
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
  locale? : @i18n.Locale = English,
  mode : ReviewDiffMode,
  active : Bool,
  on_click : @cmd.Cmd,
  enabled~ : Bool,
) -> @html.Html {
  @html.button(
    type_="button",
    class=if active {
      "review-mode-button active"
    } else {
      "review-mode-button"
    },
    title=match locale {
      SimplifiedChinese => "使用" + mode.label(locale~) + "差异"
      TraditionalChinese => "使用" + mode.label(locale~) + "差異"
      Japanese => "使用" + mode.label(locale~) + "差分"
      English => "Use " + mode.label(locale~) + " diff"
      Spanish => "Usar diferencias de " + mode.label(locale~)
    },
    disabled=!enabled,
    on_click~,
    attrs=@html.Attrs::build()
      .data_set("diff-mode", mode.attribute())
      .aria_label(
        mode.label(locale~) +
        (match locale {
          SimplifiedChinese => "差异"
          TraditionalChinese => "差異"
          Japanese => "差分"
          English => " diff"
          Spanish => " diferencias"
        }),
      )
      .aria_pressed(active.to_string()),
    mode.label(locale~),
  )
}

///|
fn review_mode_toolbar(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some(review) else {
    return @html.span(class="review-mode-toolbar hidden", "")
  }
  let diff = review.view_mode == ReviewDiff
  let enabled = doc.diff_content() is Some(_)
  let moon = supports_moon_diff(path.path)
  let children : Array[@html.Html] = [
    @html.button(
      type_="button",
      class=if diff {
        "review-mode-button"
      } else {
        "review-mode-button active"
      },
      title=ui(locale, ShowFile),
      disabled=!enabled,
      on_click=if diff { dispatch(ToggleReviewDiff) } else { @cmd.none },
      attrs=@html.Attrs::build()
        .data_set("review-mode", "file")
        .aria_label(ui(locale, FileView))
        .aria_pressed((!diff).to_string()),
      ui(locale, FileLabel),
    ),
    @html.span(
      class="review-mode-divider",
      attrs=@html.Attrs::build().aria_hidden("true"),
      "",
    ),
    review_diff_mode_button(
      locale~,
      enabled~,
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
        locale~,
        enabled~,
        ReviewDiffToken,
        diff && state.review_diff_mode == ReviewDiffToken,
        dispatch(ReviewDiffModeSelected(ReviewDiffToken)),
      ),
    )
    children.push(
      review_diff_mode_button(
        locale~,
        enabled~,
        ReviewDiffTree,
        diff && state.review_diff_mode == ReviewDiffTree,
        dispatch(ReviewDiffModeSelected(ReviewDiffTree)),
      ),
    )
  }
  @html.div(
    class=if review_controls_pending(state, ctx) {
      "review-mode-toolbar pending"
    } else {
      "review-mode-toolbar"
    },
    attrs=@html.Attrs::build()
      .role("toolbar")
      .aria_label(ui(locale, ReviewMode)),
    children,
  )
}

///|
/// Historical comparisons have no File surface, but retain the same explicit
/// MoonBit comparison algorithms as changed-file reviews.
fn review_diff_mode_toolbar(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard moon_diff_controls_visible(state, ctx) else {
    return @html.span(class="review-mode-toolbar hidden", "")
  }
  @html.div(
    class="review-mode-toolbar review-history-mode-toolbar",
    attrs=@html.Attrs::build()
      .role("toolbar")
      .aria_label(ui(locale, ComparisonAlgorithm)),
    [
      review_diff_mode_button(
        locale~,
        enabled=moon_diff_ready(state, ctx),
        ReviewDiffLine,
        state.review_diff_mode == ReviewDiffLine,
        dispatch(ReviewDiffModeSelected(ReviewDiffLine)),
      ),
      review_diff_mode_button(
        locale~,
        enabled=moon_diff_ready(state, ctx),
        ReviewDiffToken,
        state.review_diff_mode == ReviewDiffToken,
        dispatch(ReviewDiffModeSelected(ReviewDiffToken)),
      ),
      review_diff_mode_button(
        locale~,
        enabled=moon_diff_ready(state, ctx),
        ReviewDiffTree,
        state.review_diff_mode == ReviewDiffTree,
        dispatch(ReviewDiffModeSelected(ReviewDiffTree)),
      ),
    ],
  )
}

///|
fn review_comments_control(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard moon_diff_controls_visible(state, ctx) else {
    return @html.span(class="review-comments-control hidden", "")
  }
  let enabled = full_diff_ready(state, ctx) &&
    state.review_diff_mode != ReviewDiffLine
  let pending = review_controls_pending(state, ctx) &&
    state.review_diff_mode != ReviewDiffLine
  @html.button(
    type_="button",
    class="review-comments-control" +
      (if (enabled || pending) && state.review_diff_ignore_comments {
        " active"
      } else {
        ""
      }) +
      (if pending { " pending" } else { "" }),
    title=if !full_diff_ready(state, ctx) {
      ui(locale, AvailableDiff)
    } else if state.review_diff_mode == ReviewDiffLine {
      ui(locale, AvailableTokenTree)
    } else if state.review_diff_ignore_comments {
      ui(locale, IncludeComments)
    } else {
      ui(locale, IgnoreCommentChanges)
    },
    disabled=!enabled,
    on_click=dispatch(ToggleReviewDiffIgnoreComments),
    attrs=@html.Attrs::build()
      .aria_label(ui(locale, IgnoreComments))
      .aria_pressed(
        ((enabled || pending) && state.review_diff_ignore_comments).to_string(),
      ),
    if state.review_diff_ignore_comments {
      ui(locale, CommentsIgnored)
    } else {
      ui(locale, CommentsIncluded)
    },
  )
}

///|
fn review_tests_control(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard moon_diff_controls_visible(state, ctx) else {
    return @html.span(class="review-tests-control hidden", "")
  }
  let enabled = full_diff_ready(state, ctx) &&
    state.review_diff_mode != ReviewDiffLine
  let pending = review_controls_pending(state, ctx) &&
    state.review_diff_mode != ReviewDiffLine
  @html.button(
    type_="button",
    class="review-tests-control" +
      (if (enabled || pending) && state.review_diff_ignore_tests {
        " active"
      } else {
        ""
      }) +
      (if pending { " pending" } else { "" }),
    title=if !full_diff_ready(state, ctx) {
      ui(locale, AvailableDiff)
    } else if state.review_diff_mode == ReviewDiffLine {
      ui(locale, AvailableTokenTree)
    } else if state.review_diff_ignore_tests {
      ui(locale, IncludeTests)
    } else {
      ui(locale, IgnoreTestBlocks)
    },
    disabled=!enabled,
    on_click=dispatch(ToggleReviewDiffIgnoreTests),
    attrs=@html.Attrs::build()
      .aria_label(ui(locale, IgnoreTests))
      .aria_pressed(
        ((enabled || pending) && state.review_diff_ignore_tests).to_string(),
      ),
    if state.review_diff_ignore_tests {
      ui(locale, TestsIgnored)
    } else {
      ui(locale, TestsIncluded)
    },
  )
}

///|
/// Retain the last complete navigation while a replacement is preparing.
fn review_navigation_controls(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard state.review_navigation_display is Some(display) else {
    return @html.nothing
  }
  let pending = !review_navigation_complete(state, ctx)
  @html.div(
    class="review-navigation-controls",
    attrs=@html.Attrs::build().aria_busy(pending.to_string()).inert(pending),
    [
      review_navigation_view(locale~, dispatch, display),
      match display.hunk_toggle {
        Some((hunk_state, disabled)) =>
          review_hunk_toggle_button(locale~, dispatch, hunk_state, disabled)
        None => @html.nothing
      },
    ],
  )
}

///|
/// One navigation group walks changes, then files, and wraps the review queue.
fn review_diff_navigation(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  let display = current_review_navigation_display(state, ctx)
  guard full_diff_available(state, ctx) || display.file_position is Some(_) else {
    return @html.span(class="review-diff-navigation hidden", "")
  }
  review_navigation_view(locale~, dispatch, display)
}

///|
fn review_navigation_view(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  display : ReviewNavigationDisplay,
) -> @html.Html {
  let file_position = display.file_position
  let position = display.position
  let enabled = display.enabled
  let controls : Array[@html.Html] = []
  if file_position is Some((index, total)) {
    controls.push(
      @html.span(
        class="review-nav-position",
        dynamic_text(
          locale,
          DFilePosition((index + 1).to_string(), total.to_string()),
        ),
      ),
    )
  }
  if position is Some(position) {
    controls.push(
      @html.span(
        class="review-hunk-position",
        attrs=@html.Attrs::build()
          .aria_label(
            dynamic_text(
              locale,
              DHunkPosition(
                position.current.to_string(),
                position.total.to_string(),
              ),
            ),
          )
          .aria_live("polite"),
        dynamic_text(
          locale,
          DChangePosition(
            position.current.to_string(),
            position.total.to_string(),
          ),
        ),
      ),
    )
  }
  controls.push(
    @html.button(
      type_="button",
      class="review-nav-button",
      title=ui(locale, PreviousChangeShortcut),
      disabled=!enabled,
      on_click=dispatch(RevealPreviousReviewDiffChange),
      attrs=@html.Attrs::build()
        .data_set("action", "previous-diff-change")
        .aria_label(ui(locale, PreviousChange))
        .aria_keyshortcuts("Shift+F7"),
      @icons.icon(@icons.icon_arrow_up),
    ),
  )
  controls.push(
    @html.button(
      type_="button",
      class="review-nav-button",
      title=ui(locale, NextChangeShortcut),
      disabled=!enabled,
      on_click=dispatch(RevealNextReviewDiffChange),
      attrs=@html.Attrs::build()
        .data_set("action", "next-diff-change")
        .aria_label(ui(locale, NextChange))
        .aria_keyshortcuts("F7"),
      @icons.icon(@icons.icon_arrow_down),
    ),
  )
  @html.div(
    class="review-diff-navigation",
    attrs=@html.Attrs::build()
      .id("review-change-navigation")
      .role("group")
      .aria_label(ui(locale, DiffNavigation)),
    controls,
  )
}

///|
fn review_hunk_toggle_button(
  locale? : @i18n.Locale = English,
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
      ui(locale, FileReviewed)
    } else if viewed {
      ui(locale, MarkHunkUnviewed)
    } else {
      ui(locale, MarkHunkViewed)
    },
    disabled~,
    on_click=dispatch(ToggleActiveReviewHunk),
    attrs=@html.Attrs::build()
      .aria_label(
        if disabled {
          ui(locale, HunkViewed)
        } else if viewed {
          ui(locale, UnmarkHunkViewed)
        } else {
          ui(locale, MarkHunkViewedLabel)
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
      ReviewHunkUnviewed => ui(locale, MarkViewed)
      ReviewHunkPartial => "◐ Mark viewed"
      ReviewHunkViewed => "✓ Viewed"
    },
  )
}

///|
/// Line keeps its two models mounted while Token/Tree reuse one section plan;
/// this explicit pair changes either presentation. File mode preserves the
/// preference but disables both choices until the next review reveal.
fn review_diff_layout_toggle(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  guard review_toolbar_visible(state, ctx) else {
    return @html.span(class="review-layout-control hidden", "")
  }
  let ready = full_diff_ready(state, ctx)
  let pending = review_controls_pending(state, ctx)
  let shown_ready = ready || pending
  let inline = state.review_diff_layout == ReviewInline
  @html.div(
    class=if pending {
      "review-layout-control pending"
    } else if ready {
      "review-layout-control"
    } else {
      "review-layout-control disabled"
    },
    attrs=@html.Attrs::build().role("group").aria_label(ui(locale, DiffLayout)),
    [
      @html.button(
        type_="button",
        class=if shown_ready && !inline {
          "review-layout-button active"
        } else {
          "review-layout-button"
        },
        title=ui(locale, SideBySideHint),
        disabled=!ready,
        on_click=if ready && inline {
          dispatch(ToggleReviewDiffLayout)
        } else {
          @cmd.none
        },
        attrs=@html.Attrs::build()
          .data_set("layout", "side-by-side")
          .aria_label(ui(locale, SplitDiffLayout))
          .aria_pressed((shown_ready && !inline).to_string()),
        ui(locale, SplitLabel),
      ),
      @html.button(
        type_="button",
        class=if shown_ready && inline {
          "review-layout-button active"
        } else {
          "review-layout-button"
        },
        title=ui(locale, UnifiedDiffHint),
        disabled=!ready,
        on_click=if ready && !inline {
          dispatch(ToggleReviewDiffLayout)
        } else {
          @cmd.none
        },
        attrs=@html.Attrs::build()
          .data_set("layout", "inline")
          .aria_label(ui(locale, UnifiedDiffLayout))
          .aria_pressed((shown_ready && inline).to_string()),
        ui(locale, UnifiedLabel),
      ),
    ],
  )
}

///|
/// Floating one-level directory browser opened by a breadcrumb. It shares the
/// explorer's cache and filesystem messages, but not its expanded/collapsed
/// presentation, so it can stay compact over the source viewer.
fn breadcrumb_picker(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  directory : @pathx.Relative,
) -> @html.Html {
  let label = if directory.is_root() {
    ui(locale, WorkspaceLabel)
  } else {
    basename(directory)
  }
  let listed = state.children.get(directory)
  let rows : Array[@html.Html] = match listed {
    Some(entries) if entries.is_empty() =>
      [@html.div(class="breadcrumb-picker-empty", ui(locale, EmptyFolder))]
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
      [@html.div(class="breadcrumb-picker-empty", ui(locale, LoadingLabel))]
    None =>
      [
        @html.div(
          class="breadcrumb-picker-empty breadcrumb-picker-failed",
          match state.error {
            Some(message) =>
              dynamic_text(locale, DFolderFailed(message.to_string()))
            None => ui(locale, CannotLoadFolder)
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
          ui(locale, RefreshingLabel),
        ),
      ]),
      @html.div(
        class="breadcrumb-picker-list",
        attrs=@html.Attrs::build()
          .role("menu")
          .aria_label(dynamic_text(locale, DFilesIn(label.to_string()))),
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
  let selected = !entry.is_dir &&
    ctx.active_file is Some(active) &&
    ctx.relative(active) == Some(entry.path)
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
/// Progress control for the exact Changes row attached to the active review.
/// Keeping it beside the diff-mode badge makes completion explicit without
/// turning an ordinary file open into review state.
fn review_progress(
  locale? : @i18n.Locale = English,
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
      ui(locale, ReturnReviewQueue)
    } else {
      ui(locale, MarkChangedReviewed)
    },
    on_click=dispatch(ToggleReviewProgress),
    attrs=@html.Attrs::build()
      .aria_label(
        if reviewed {
          ui(locale, MarkFileUnreviewed)
        } else {
          ui(locale, MarkFileReviewed)
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
      ReviewUnviewed => ui(locale, MarkReviewed)
    },
  )
}

///|
/// Compact review control beside the active path. Textual reviews toggle the
/// full diff; unavailable reviews retain a non-interactive status. Loading uses
/// the delayed overlay so it cannot change the breadcrumb layout.
fn review_badge(
  locale? : @i18n.Locale = English,
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
                ui(locale, ViewFile),
                ui(locale, ReturnSourcePreview),
                true,
                true,
              )
            Some({ view_mode: ReviewSource, .. }) =>
              (ui(locale, ViewFullDiff), ui(locale, FullDiffHint), true, false)
            None => return @html.nothing
          }
        Some(
          {
            state: TabDeleted,
            review: Some({ baseline: ReviewContent(_), .. }),
            ..
          }
        ) =>
          (
            ui(locale, DeletedBaseline),
            ui(locale, DeletedBaselineHint),
            false,
            false,
          )
        Some(
          {
            state: TabReadFailed(_),
            review: Some({ baseline: ReviewContent(_), .. }),
            ..
          }
        ) =>
          (
            ui(locale, WorkingUnavailable),
            ui(locale, WorkingUnavailableHint),
            false,
            false,
          )
        Some({ state: TabBinary, review: Some(_), .. })
        | Some({ state: TabOversized, review: Some(_), .. })
        | Some({ state: TabReadFailed(_), review: Some(_), .. }) =>
          (
            ui(locale, DiffUnavailable),
            ui(locale, NotTextPreview),
            false,
            false,
          )
        // Loading is presented only by the delayed, non-layout overlay.
        Some({ review: Some({ baseline: ReviewLoading, .. }), .. }) =>
          return @html.nothing
        Some(
          {
            state: TabDeleted,
            review: Some({ baseline: ReviewMissing, .. }),
            ..
          }
        ) =>
          (ui(locale, DeletedNoBaseline), ui(locale, NoBaseline), false, false)
        Some({ name, review: Some({ baseline: ReviewContent(_), .. }), .. }) if name.has_suffix(
            ".md",
          ) =>
          (
            ui(locale, RenderedNoGutter),
            ui(locale, MarkdownGutterHint),
            false,
            false,
          )
        Some({ name, review: Some({ baseline: ReviewMissing, .. }), .. }) if name.has_suffix(
            ".md",
          ) =>
          (
            ui(locale, RenderedNoGutter),
            ui(locale, NewMarkdownHint),
            false,
            false,
          )
        Some({ review: Some({ baseline: ReviewContent(_), .. }), .. }) =>
          (
            ui(locale, DiffBaseline),
            ui(locale, QuickDiffBaseline),
            false,
            false,
          )
        Some({ review: Some({ baseline: ReviewMissing, .. }), .. }) =>
          (ui(locale, NewNoBaseline), ui(locale, NewBaselineHint), false, false)
        Some({ review: Some({ baseline: ReviewBinary, .. }), .. }) =>
          (
            ui(locale, DiffUnavailable),
            ui(locale, BinaryBaseline),
            false,
            false,
          )
        Some({ review: Some({ baseline: ReviewOversized, .. }), .. }) =>
          (ui(locale, DiffUnavailable), ui(locale, LargeBaseline), false, false)
        Some({ review: Some({ baseline: ReviewFailed(message), .. }), .. }) =>
          (
            ui(locale, DiffUnavailable),
            ui(locale, BaselineFailedPrefix) + message,
            false,
            false,
          )
        _ => return @html.nothing
      }
    None => return @html.nothing
  }
  if action {
    @html.button(
      type_="button",
      class="review-badge review-badge-action",
      title~,
      on_click=dispatch(ToggleReviewDiff),
      attrs=@html.Attrs::build()
        .aria_label(ui(locale, FullDiff))
        .aria_pressed(pressed.to_string()),
      text,
    )
  } else {
    @html.span(
      class="review-badge",
      title~,
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      text,
    )
  }
}

///|
/// Every row reserves the same chevron slot, including files. Depth drives
/// both label indentation and ancestor guides, as in VS Code's tree rows.
fn tree_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  entry : FileEntry,
  depth : Int,
  focus : @pathx.Relative?,
) -> @html.Html {
  let indent_style = "--tree-depth: \{depth}"
  let expanded = state.expanded.contains(entry.path)
  let children = [
    @html.span(
      class=if entry.is_dir && expanded {
        "tree-twistie expanded"
      } else {
        "tree-twistie"
      },
      attrs=@html.Attrs::build().aria_hidden("true"),
      if entry.is_dir {
        @icons.icon_chevron_down()
      } else {
        @html.nothing
      },
    ),
    @html.span(class="tree-name", entry.name),
    // Decorative guides never intercept clicks or change the label's slot.
    @html.span(
      class="tree-indent-guides",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @html.nothing,
    ),
  ]
  let siblings = state.children
    .get(FileChange::parent(entry.path))
    .unwrap_or([])
  let position = siblings.search_by(item => item.path == entry.path)
  let selected = ctx.active_file is Some(active) &&
    ctx.relative(active) == Some(entry.path)
  let attrs = @html.Attrs::build()
    .id("workspace-tree-" + entry.path.0)
    .role("treeitem")
    .aria_label(entry.name)
    .aria_level((depth + 1).to_string())
    .aria_setsize(siblings.length().to_string())
    .aria_selected(selected.to_string())
    .data_set("path", entry.path.0)
    .data_set("context-file", entry.path.0)
    .tabindex(if focus == Some(entry.path) { 0 } else { -1 })
    .on_focus(_ => dispatch(TreeFocused(entry.path)))
    .on_keydown(event => {
      if event.alt_key() || event.ctrl_key() || event.meta_key() {
        return @cmd.none
      }
      let action = tree_key_action(state, entry, event.key())
      if action is Some(_) {
        event.prevent_default()
      }
      match action {
        Some(TreeMove(path)) => focus_tree_after_render(Some(path))
        Some(TreeToggle) => dispatch(DirToggle(entry.path))
        Some(TreeOpen) =>
          dispatch(FileSelected(path=entry.path, name=entry.name))
        Some(TreeStay) | None => @cmd.none
      }
    })
  let attrs = if position is Some(position) {
    attrs.aria_posinset((position + 1).to_string())
  } else {
    attrs
  }
  let attrs = if entry.is_dir {
    attrs.aria_expanded(expanded.to_string())
  } else {
    attrs
  }
  @html.div(
    class=if entry.is_dir {
      "tree-row tree-dir"
    } else if selected {
      "tree-row tree-file selected"
    } else {
      "tree-row tree-file"
    },
    style=[indent_style],
    attrs~,
    on_click=@cmd.batch([
      focus_tree_after_render(Some(entry.path)),
      if entry.is_dir {
        dispatch(DirToggle(entry.path))
      } else {
        dispatch(FileSelected(path=entry.path, name=entry.name))
      },
    ]),
    children,
  )
}

///|
fn review_filter_controls(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
) -> @html.Html {
  @html.div(class="review-filter-controls", [
    @html.div(
      class="review-filter-scope",
      attrs=@html.Attrs::build().id("review-filter-scope"),
      match state.git_graph_selected {
        Some(commit) => ui(locale, FilteringCommit) + short_commit(commit)
        None => ui(locale, FilteringWorkingTree)
      },
    ),
    @html.div(class="review-path-filter", [
      @html.input(
        input_type=@html.InputType::Text,
        value=state.change_path_filter,
        placeholder=ui(locale, FilterFilesPath),
        on_input=dispatch.map(value => ChangePathFilterChanged(value)),
        attrs=@html.Attrs::build()
          .id("review-path-filter-input")
          .data_set("focus-owner", "")
          .aria_describedby("review-filter-scope")
          .aria_label(ui(locale, FilterChangedPath))
          .on_keydown(event => {
            if event.key() == "Escape" && !state.change_path_filter.is_empty() {
              event.prevent_default()
              event.stop_propagation()
              dispatch(ChangePathFilterChanged(""))
            } else {
              @cmd.none
            }
          }),
      ),
      change_extension_filter(locale~, dispatch, state),
      @html.button(
        class="button secondary small",
        disabled=state.change_path_filter.is_empty() &&
          state.change_extensions is None,
        on_click=@cmd.batch([
          dispatch(ChangeFiltersCleared),
          focus_change_filter_after_render(),
        ]),
        attrs=@html.Attrs::build().aria_label(ui(locale, ClearFilters)),
        ui(locale, ClearLabel),
      ),
    ]),
    match review_filter_inventory(state) {
      Some(files) if !state.change_path_filter.is_empty() ||
        state.change_extensions is Some(_) => {
        let filter = state.review_file_filter()
        let count = files
          .filter(file => filter.matches(file.path, file.original))
          .length()
        @html.div(
          class="review-filter-count",
          attrs=@html.Attrs::build().role("status"),
          dynamic_text(
            locale,
            DShowingFiles(count.to_string(), files.length().to_string()),
          ),
        )
      }
      _ => @html.nothing
    },
  ])
}

///|
fn focus_change_filter_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id("review-path-filter-input")
        .to_option()
        is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
fn change_extension_filter(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
) -> @html.Html {
  let options = change_extension_options(state)
  let label = match state.change_extensions {
    None => ui(locale, FileTypes)
    Some(selected) if selected.is_empty() => ui(locale, NoFileTypes)
    Some(selected) =>
      selected.map(value => extension_label(locale~, value)).join(", ")
  }
  @html.div(class="review-type-filter", [
    @html.button(
      class="button secondary small review-type-trigger",
      disabled=review_filter_inventory(state) is None,
      title=label,
      attrs=@html.Attrs::build()
        .id("review-file-types-trigger")
        .aria_label(
          ui(locale, FilterExtensionPrefix) +
          (if state.change_extensions is None {
            ui(locale, AllFileTypes)
          } else {
            label
          }),
        )
        .aria_describedby("review-filter-scope")
        .aria_haspopup("dialog")
        .aria_controls("review-file-types"),
      [
        @html.span(class="review-type-label", label),
        @icons.icon(@icons.icon_chevron_down),
      ],
    ),
    @html.div(
      class="review-type-options",
      attrs=@html.Attrs::build()
        .id("review-file-types")
        .popover("auto")
        .role("dialog")
        .aria_label(ui(locale, FileTypes)),
      [
        @html.div(class="review-type-heading", ui(locale, FileTypes)),
        ..options.map(option => {
          @html.label(class="review-type-option", [
            @html.input(
              input_type=@html.InputType::Checkbox,
              checked=state.change_extensions is None ||
                (
                  state.change_extensions is Some(selected) &&
                  selected.contains(option.0)
                ),
              on_change=dispatch.map(_ => ChangeExtensionToggled(option.0)),
              attrs=@html.Attrs::build().aria_label(
                extension_label(locale~, option.0),
              ),
            ),
            @html.span(extension_label(locale~, option.0)),
            @html.span(class="review-type-count", option.1.to_string()),
          ])
        }),
        if options.is_empty() {
          @html.div(ui(locale, NoChangedTypes))
        } else {
          @html.nothing
        },
      ],
    ),
  ])
}

///|
// Rabbita does not expose the popovertarget attribute yet. Bind the native
// invoker after rendering instead of duplicating light-dismiss behavior.
extern "js" fn bind_change_types() -> Unit =
  #| () => {
  #|   if (typeof document === "undefined") return;
  #|   const trigger = document.getElementById("review-file-types-trigger");
  #|   const menu = document.getElementById("review-file-types");
  #|   if (trigger && menu) trigger.popoverTargetElement = menu;
  #| }

///|
fn review_git_layout(
  locale? : @i18n.Locale = English,
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> @html.Html {
  @html.div(class="review-filter-layout", [
    review_filter_controls(locale~, dispatch, state),
    review_git_sections(locale~, dispatch, state, ctx),
  ])
}
