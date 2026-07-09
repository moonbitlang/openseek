// The file-editor subsystem: the editor side-panel's state and messages,
// extracted from the main frontend package so the panel owns its own
// update/view loop. The main package wraps `Msg` in one root variant and
// delegates to `update`/`sync`/`panel_view`, passing the active
// conversation's identity in as `Ctx` — this package never sees the app
// model.

///|
/// One entry of the file panel's tree: a file or directory directly inside
/// some listed directory. `path` is relative to the conversation's workspace
/// ("" being the root), the key the host's `read_directory` / `read_file` ops
/// take.
pub(all) struct FileEntry {
  name : String
  path : @pathx.Relative
  is_dir : Bool
}

///|
/// A decoded `read_file` reply. Withheld files are their own cases — the
/// wording of their notices is this side's business — and only a real file
/// carries an address for path-routed ops (hover on a notice document has
/// nothing to ask about).
pub(all) enum FileContent {
  Binary
  Oversized
  // `sig` is the file's mtime signature, stat'ed by the host from the same
  // handle it read — the baseline `stat_files` results are compared against.
  Content(content~ : String, absolute~ : @pathx.Absolute, sig~ : String)
}

///|
/// Where one open tab's document stands. Content lives on the tab (not in
/// the viewer) so switching tabs redisplays instantly without a host
/// round-trip; the withheld and deleted cases keep their own notices.
pub(all) enum TabState {
  // A `read_file` is in flight (just opened, restored after a conversation
  // switch, or reloading after a disk change).
  TabLoading
  // `sig` is the loaded content's mtime signature; a differing `stat_files`
  // result means the file changed on disk. Withheld tabs carry no baseline
  // (their replies have none), so they only refresh on an explicit re-open —
  // but deletion still shows, since that compares against `""`, not a
  // baseline.
  TabLoaded(content~ : String, absolute~ : @pathx.Absolute, sig~ : String)
  TabBinary
  TabOversized
  // The file vanished from disk while open. The tab stays — its name is the
  // user's bookmark — showing a notice until the file reappears or the tab
  // is closed.
  TabDeleted
}

///|
/// One open file in the editor's tab strip. Identified by its
/// workspace-relative `path`; the strip's order is the order files were
/// opened.
pub(all) struct Tab {
  path : @pathx.Relative
  name : String
  state : TabState
  // The file changed on disk while the tab was in the background; reloaded
  // on activation rather than eagerly, so a build storm costs one read.
  stale : Bool
}

///|
/// A conversation's tab set, remembered across conversation switches. Only
/// identities — content would pin up to 1MiB per tab for conversations not
/// on screen — so restoring reloads the active tab and marks the rest for
/// load-on-activation.
pub(all) struct RememberedTab {
  path : @pathx.Relative
  name : String
}

///|
pub(all) struct RememberedTabs {
  entries : Array[RememberedTab]
  active : @pathx.Relative?
}

///|
/// One file's decoded `stat_files` result: its current mtime signature, or
/// `""` when the file is missing.
pub(all) struct FileStat {
  path : @pathx.Relative
  sig : String
}

///|
/// The workspace file index behind the filter's fuzzy matching: every file
/// under the workspace (the host walks it recursively, pruning churn
/// directories and capping the count). Requested lazily on the first
/// non-blank filter keystroke, refreshed on `FsChanged`, and reset by a
/// conversation switch like the rest of the tree cache.
pub(all) enum FileIndex {
  // Never requested (or the last request failed) — the next filter
  // keystroke asks for it. Until it arrives the filter falls back to
  // matching whatever directories are already listed.
  IndexEmpty
  // The first request is in flight.
  IndexLoading
  // `truncated` set means the walk hit the host's cap, so matches may be
  // missing; the filter footer says so.
  IndexReady(files~ : Array[@pathx.Relative], truncated~ : Bool)
}

///|
/// The editor side-panel's state: a lazily-loaded file tree of the active
/// conversation's workspace and the files open in the embedded viewer's tab
/// strip. Keyed entirely by workspace-relative paths; `session` records
/// which conversation the cached tree belongs to, so switching conversations
/// swaps it (parking the open tabs in `remembered`) rather than showing
/// another workspace's files.
pub(all) struct State {
  // Whether the panel column is expanded; the column is always rendered (so
  // the viewer host element stays put) and merely hidden by CSS when closed.
  open : Bool
  session : String
  // Whether the file-tree pane (the toggleable column right of the viewer)
  // is shown. A panel preference, not per-conversation state, so it
  // survives conversation switches.
  tree_open : Bool
  // The session whose workspace the host's file watcher currently follows
  // ("" = parked). `sync` reconciles it with what the panel needs, so the
  // watcher follows conversation switches and stops when nothing is open.
  watching : String
  // Directory paths the user has expanded, and those with a `read_directory`
  // in flight; plain arrays since a workspace tree is small.
  expanded : Array[@pathx.Relative]
  loading : Array[@pathx.Relative]
  // Listed directories' entries, keyed by the directory's relative path.
  children : Map[@pathx.Relative, Array[FileEntry]]
  // The open files, in strip order, and which of them the viewer shows.
  // `active: None` leaves the viewer on its placeholder.
  tabs : Array[Tab]
  active : @pathx.Relative?
  // Tab sets parked by conversation switches, keyed by session id, restored
  // when that conversation returns to the screen.
  remembered : Map[String, RememberedTabs]
  // The directory a breadcrumb click most recently revealed, flashed in the
  // tree until `HighlightCleared` fires.
  highlighted : @pathx.Relative?
  // The file-tree filter query. Blank lists the tree; otherwise the rows are
  // the workspace files fuzzy-matched against it (fzf-style: subsequence
  // match on the whole relative path, best score first, smart-case).
  filter : String
  // The workspace file list the fuzzy filter matches against.
  index : FileIndex
  // The keyboard cursor's row in the tree, moved from the filter input with
  // ↑/↓ and acted on with Enter. Path-keyed (not an index) so it survives
  // rows appearing and disappearing around it; None until the keyboard
  // first moves.
  cursor : @pathx.Relative?
  // The last directory/file failure, surfaced in the panel header.
  error : String
}

///|
pub fn State::empty() -> State {
  {
    open: false,
    session: "",
    tree_open: true,
    watching: "",
    expanded: [],
    loading: [],
    children: {},
    tabs: [],
    active: None,
    remembered: {},
    highlighted: None,
    filter: "",
    index: IndexEmpty,
    cursor: None,
    error: "",
  }
}

///|
/// Where the file tree docks inside the editor panel: flat along the bottom
/// (Emacs-window style) or as a column on the viewer's right. A Settings
/// choice owned by the main package and passed in through `Ctx`; the two
/// layouts share one DOM order and differ only in CSS, so switching never
/// re-keys the viewer host.
pub(all) enum TreeLayout {
  BottomPanel
  RightSidebar
}

///|
/// The stored wire name's inverse; an unknown value falls back to the
/// default right sidebar, so a missing key and a stale value read the same.
pub fn TreeLayout::parse(value : String) -> TreeLayout {
  match value {
    "bottom-panel" => BottomPanel
    _ => RightSidebar
  }
}

///|
pub fn TreeLayout::wire(self : TreeLayout) -> String {
  match self {
    BottomPanel => "bottom-panel"
    RightSidebar => "right-sidebar"
  }
}

///|
/// The active conversation's identity, passed in by the main package on every
/// `update`/`sync`/`panel_view` call: which session the panel serves, the
/// conversation's attached workspace (the hint fs ops carry), whether the
/// app is in dark mode (drives the embedded viewer's theme attribute), and
/// the Settings choice of where the file tree docks.
pub(all) struct Ctx {
  session : String
  workspace : @pathx.Absolute?
  dark_mode : Bool
  tree_layout : TreeLayout
}

///|
pub(all) enum Msg {
  // Show or hide the editor side-panel. Opening it loads the active
  // conversation's workspace root if it has not been listed yet.
  ToggleFilePanel
  // A breadcrumb segment was clicked: switch back to the (always-rooted)
  // tree and reveal this directory — expanding whatever ancestors are
  // needed to show it, then scrolling to and flashing it. `""` (the leading
  // "Workspace" crumb) just returns to the plain tree with no highlight.
  RevealDirectory(@pathx.Relative)
  // A `RevealDirectory` highlight's flash delay elapsed; clears it unless a
  // newer reveal has since replaced it.
  HighlightCleared(@pathx.Relative)
  // Show or hide the file-tree pane (the column right of the viewer).
  ToggleTree
  // A tab in the strip was clicked: show that file in the viewer.
  TabActivated(@pathx.Relative)
  // A tab's close button was clicked. Closing the active tab activates its
  // right neighbor, else its left, else none (the viewer falls back to the
  // placeholder, and the tree pane is forced open so the panel is never
  // empty).
  TabClosed(@pathx.Relative)
  // Expand or collapse a directory row in the file tree; the first expansion
  // lazily lists the directory through the host.
  DirToggle(@pathx.Relative)
  // The file-tree filter query changed.
  FileFilterChanged(String)
  // ↑/↓ in the filter input: move the keyboard cursor through the visible
  // rows (`delta` is ±1); the first move enters at the top or bottom.
  TreeKeyMove(delta~ : Int)
  // Enter in the filter input: act on the cursor's row — toggle a
  // directory, open a file. With no cursor yet, the first visible row of a
  // non-blank filter is taken, so "type then Enter" opens the top match.
  TreeKeyAccept
  // Escape in the filter input: clear a non-blank filter first, then close
  // the tree panel (when a file is open to fall back to).
  TreeKeyDismiss
  // A `read_directory` reply: `session`/`path` say which request it answers so
  // a reply that lost a conversation switch can be dropped.
  DirLoaded(
    session~ : String,
    path~ : @pathx.Relative,
    entries~ : Array[FileEntry]
  )
  DirFailed(session~ : String, path~ : @pathx.Relative, message~ : String)
  // A `list_files` reply: the workspace's files for the fuzzy filter.
  // `truncated` means the host's walk stopped at its cap.
  FilesIndexed(
    session~ : String,
    files~ : Array[@pathx.Relative],
    truncated~ : Bool
  )
  // A `list_files` request failed or returned garbage; drops the index back
  // to `IndexEmpty` so the next filter keystroke retries.
  FileIndexFailed(session~ : String)
  // A file row was clicked: read it and show it in the viewer. `name` is the
  // entry's display name, kept for the viewer's title and language guess.
  FileSelected(path~ : @pathx.Relative, name~ : String)
  // `file` is the decoded reply (content + address, or a withheld-file
  // case). `range`, when present, is a jumped-to symbol's one-based range,
  // revealed in the viewer once the file loads and — unless empty —
  // selected so the code it names reads highlighted. `annotation`, when
  // present (an annotation chip's jump), is the user's comment text,
  // re-shown as an editor bubble over `range`. A plain tree click leaves
  // both `None`.
  FileLoaded(
    session~ : String,
    path~ : @pathx.Relative,
    name~ : String,
    file~ : FileContent,
    range~ : @common.Range?,
    annotation~ : String?
  )
  FileFailed(session~ : String, message~ : String)
  // The host's coarse "something changed under the watched workspace" push.
  // Carries no paths — the handler re-stats the open tabs and re-lists the
  // expanded directories to find out what moved.
  FsChanged
  // A `stat_files` reply: each open tab's current mtime signature (`""` =
  // the file is gone). `session` says which conversation it answers, like
  // every other reply.
  StatsLoaded(session~ : String, stats~ : Array[FileStat])
  // The language server's diagnostics for the file at `absolute`, either
  // returned by `lsp_open` when the file is shown or pushed later as the server
  // re-analyzes (the main package forwards the host's `diagnostics` events
  // here). `diagnostics` is the raw LSP array (0-based ranges). Applied to
  // the viewer only while it still shows that file; a stale one is dropped.
  DiagnosticsPublished(absolute~ : @pathx.Absolute, diagnostics~ : Json)
  // The user commented on a selection in the editor viewer (the
  // agent-feedback inline input). NOT handled by this package's `update`:
  // the comment becomes a chip on the main package's composer draft, so the
  // main update intercepts it there and clears the editor's bubble through
  // `remove_editor_feedback`. `resource` is the viewer model URI the comment
  // was filed under — only the key for that removal; `file` is the file as
  // the conversation names it (workspace-relative, recorded when the panel
  // opened the file). `quote` is the selected source; `feedback_id`
  // addresses the bubble to clear.
  EditorCommentAdded(
    resource~ : ModelUri,
    file~ : @pathx.Relative,
    range~ : @common.Range,
    quote~ : String,
    comment~ : String,
    feedback_id~ : String
  )
}
