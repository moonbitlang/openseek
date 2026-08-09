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
const ExplorerFilesTabId = "explorer-files-tab"

///|
const ExplorerChangesTabId = "explorer-changes-tab"

///|
const ExplorerPanelId = "explorer-inventory"

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
  // The stable elements the source viewer and full-diff renderer attach their
  // imperative DOM into; they must stay empty and never be re-keyed (see
  // editor_panel.mbt).
  // `editor-shell` brings in the viewer's `--vscode-*` / `--editor-*` theme
  // variables (defined on that class in the bundled viewer.css); `data-theme`
  // picks the palette matching the app's own light/dark scheme (the shell's
  // default is dark, `light` overrides). The viewer's colors cascade from
  // this host.
  let show_unified_diff = match ctx.active_file {
    Some(path) =>
      state.docs.get(path).map(doc => doc.shows_unified_diff()).unwrap_or(false)
    None => false
  }
  let viewer_host = @html.div(
    attrs=@html.Attrs::build()
      .id(ViewerHostId)
      .class(
        if show_unified_diff {
          "viewer-host editor-shell moonbit-unified-diff-surface-hidden"
        } else {
          "viewer-host editor-shell"
        },
      )
      .data_set("theme", if ctx.dark_mode { "dark" } else { "light" }),
    ([] : Array[@html.Html]),
  )
  let unified_diff_host = @html.div(
    attrs=@html.Attrs::build()
      .id(UnifiedDiffHostId)
      .class(
        if show_unified_diff {
          "viewer-host editor-shell"
        } else {
          "viewer-host editor-shell moonbit-unified-diff-surface-hidden"
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
  let text = match ctx.active_file {
    Some(path) =>
      match state.docs.get(path) {
        Some(doc) =>
          match doc.state {
            TabDeleted =>
              match doc.review {
                Some({ baseline: ReviewLoading, .. }) =>
                  "Loading the HEAD version of \{doc.name}…"
                Some({ baseline: ReviewContent(_), .. }) => ""
                Some({ baseline: ReviewMissing, .. }) =>
                  "\{doc.name} was deleted and has no HEAD version to preview."
                Some({ baseline: ReviewBinary, .. }) =>
                  "The HEAD version of \{doc.name} is binary and cannot be previewed."
                Some({ baseline: ReviewOversized, .. }) =>
                  "The HEAD version of \{doc.name} is too large to preview."
                Some({ baseline: ReviewFailed(message), .. }) =>
                  "Could not load the HEAD version of \{doc.name}: \{message}."
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
    class=if text.is_empty() { "viewer-notice hidden" } else { "viewer-notice" },
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
  let visible_error = match state.watch_error {
    Some(message) => Some(message)
    None => state.error
  }
  let inventory = if ctx.checkout is None {
    [@html.div(class="file-panel-empty", "Waiting for workspace placement…")]
  } else if ctx.checkout is Some(@interop.MissingWorktree(_)) {
    [@html.div(class="file-panel-empty", "Worktree checkout is missing.")]
  } else if ctx.owner.session.is_empty() {
    [@html.div(class="file-panel-empty", "No conversation selected.")]
  } else {
    match state.explorer_mode {
      ExplorerFiles => file_inventory(dispatch, state, ctx)
      ExplorerChanges => change_inventory(dispatch, state, ctx)
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
        @html.button(
          class=if state.explorer_mode is ExplorerFiles {
            "explorer-tab active"
          } else {
            "explorer-tab"
          },
          on_click=dispatch(ExplorerModeSelected(ExplorerFiles)),
          attrs=@html.Attrs::build()
            .id(ExplorerFilesTabId)
            .role("tab")
            .tabindex(if state.explorer_mode is ExplorerFiles { 0 } else { -1 })
            .aria_controls(ExplorerPanelId)
            .aria_selected((state.explorer_mode is ExplorerFiles).to_string())
            .on_keydown(event => {
              match event.key() {
                "Home" => {
                  event.prevent_default()
                  focus_explorer_tab_after_render(ExplorerFilesTabId)
                }
                "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown" | "End" => {
                  event.prevent_default()
                  @cmd.batch([
                    dispatch(ExplorerModeSelected(ExplorerChanges)),
                    focus_explorer_tab_after_render(ExplorerChangesTabId),
                  ])
                }
                _ => @cmd.none
              }
            }),
          "Files",
        ),
        @html.button(
          class=if state.explorer_mode is ExplorerChanges {
            "explorer-tab active"
          } else {
            "explorer-tab"
          },
          title="Changed files (click again to refresh)",
          on_click=dispatch(ExplorerModeSelected(ExplorerChanges)),
          attrs=@html.Attrs::build()
            .id(ExplorerChangesTabId)
            .role("tab")
            .tabindex(
              if state.explorer_mode is ExplorerChanges {
                0
              } else {
                -1
              },
            )
            .aria_controls(ExplorerPanelId)
            .aria_selected((state.explorer_mode is ExplorerChanges).to_string())
            .on_keydown(event => {
              match event.key() {
                "End" => {
                  event.prevent_default()
                  focus_explorer_tab_after_render(ExplorerChangesTabId)
                }
                "ArrowLeft" | "ArrowRight" | "ArrowUp" | "ArrowDown" | "Home" => {
                  event.prevent_default()
                  @cmd.batch([
                    dispatch(ExplorerModeSelected(ExplorerFiles)),
                    focus_explorer_tab_after_render(ExplorerFilesTabId),
                  ])
                }
                _ => @cmd.none
              }
            }),
          [@html.span("Changes"), change_count(state.changes)],
        ),
      ],
    ),
    @html.div(
      class="file-tree",
      attrs=@html.Attrs::build()
        .id(ExplorerPanelId)
        .role("tabpanel")
        .aria_labelledby(
          if state.explorer_mode is ExplorerFiles {
            ExplorerFilesTabId
          } else {
            ExplorerChangesTabId
          },
        ),
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
        for change in files {
          rows.push(changed_file_row(dispatch, state, ctx, change))
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
        .data_set("path", change.path.0)
        .aria_label("View diff: " + change.status_title())
        .aria_current(if selected { "page" } else { "false" }),
      children,
    )
  } else {
    @html.div(
      class~,
      title=change.unselectable_title(),
      attrs=@html.Attrs::build()
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
      review_badge(dispatch, state, ctx),
      review_progress(dispatch, state, ctx),
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
                "View full diff", "Open the full unified diff against HEAD", true,
                false,
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
            "Deleted · HEAD", "Deleted in the working tree; showing the HEAD version",
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
            "Working unavailable · HEAD", "The working-tree file could not be read; showing the HEAD version",
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
            "Loading diff…", "Loading the HEAD version for comparison", false,
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
            "Deleted · no HEAD", "No HEAD version is available to preview", false,
            false,
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
            "Rendered · no gutter", "New Markdown has no HEAD version; its rendered preview does not expose diff decorations",
            false, false,
          )
        Some({ review: Some({ baseline: ReviewContent(_), .. }), .. }) =>
          ("Diff vs HEAD", "Quick diff against the HEAD version", false, false)
        Some({ review: Some({ baseline: ReviewMissing, .. }), .. }) =>
          (
            "New · no HEAD", "New file compared with an empty HEAD baseline", false,
            false,
          )
        Some({ review: Some({ baseline: ReviewBinary, .. }), .. }) =>
          ("Diff unavailable", "The HEAD version is binary", false, false)
        Some({ review: Some({ baseline: ReviewOversized, .. }), .. }) =>
          ("Diff unavailable", "The HEAD version is too large", false, false)
        Some({ review: Some({ baseline: ReviewFailed(message), .. }), .. }) =>
          ("Diff unavailable", "Could not load HEAD: " + message, false, false)
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
/// One visible hierarchical tree row. `depth` drives indentation.
fn tree_row(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
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
    // `data-path` is the hook `reveal_tree_row` uses to find the row in the DOM.
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
      class=if ctx.active_file == Some(entry.path) {
        "tree-row tree-file selected"
      } else {
        "tree-row tree-file"
      },
      style=[pad],
      on_click=dispatch(FileSelected(path=entry.path, name=entry.name)),
      attrs=@html.Attrs::build().data_set("path", entry.path.0),
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
