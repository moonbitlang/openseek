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
} derive(Eq)

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
  Content(content~ : String, absolute~ : @common.Uri, sig~ : String)
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
  TabLoaded(content~ : String, absolute~ : @common.Uri, sig~ : String)
  TabBinary
  TabOversized
  // The host could not read this file. Unlike `TabDeleted`, this keeps the
  // failure reason without guessing whether the cause was removal,
  // permissions, or a transient filesystem error.
  TabReadFailed(String)
  // Git proved that the path is not an ordinary file the editor may open
  // (currently a symlink, submodule, or directory). Keep the tab as a bookmark
  // without retaining source that belonged to an earlier regular file.
  TabUnavailable(String)
  // The file vanished from disk while open. The tab stays — its name is the
  // user's bookmark — showing a notice until the file reappears or the tab
  // is closed.
  TabDeleted
} derive(Eq)

///|
/// The Git baseline attached to a document opened from Changes. Ordinary file
/// opens carry `None`; review opens start at `ReviewLoading` and settle to one
/// of the typed `git.original_file` outcomes. Keeping this on the document
/// makes a tab switch restore the same review without another host round-trip.
pub(all) enum ReviewBaseline {
  ReviewLoading
  ReviewContent(String)
  // A legitimate empty baseline: added/untracked files and unborn HEAD.
  ReviewMissing
  ReviewBinary
  ReviewOversized
  ReviewFailed(String)
} derive(Eq)

///|
/// The per-tab review presentation. Source mode keeps the existing Viewer and
/// quick-diff gutter; unified mode shows the context-bounded full comparison.
pub(all) enum ReviewViewMode {
  ReviewSource
  ReviewUnifiedDiff
} derive(Eq)

///|
/// One changed-file review request parked on its document. Separate request
/// generations fence its HEAD reply and newest working-tree read; keeping the
/// tokens outside `ReviewBaseline` avoids repeating them in every settled
/// variant.
pub(all) struct ReviewState {
  // The HEAD-side request token. It remains stable while newer working-tree
  // reads are started for the same review.
  generation : Int
  // The newest working-tree read token. Keeping this separate from the HEAD
  // token lets watcher-driven reloads reject replies that complete out of
  // order without invalidating an in-flight baseline.
  working_generation : Int
  baseline : ReviewBaseline
  view_mode : ReviewViewMode
  // Preserve the exact Changes row that the user selected. Porcelain can
  // legitimately report two rows for one path (for example, a staged
  // deletion plus a recreated untracked file), so the document path alone
  // cannot identify which working/HEAD pair is under review.
  selected : ChangedFile
} derive(Eq)

///|
/// One open file's document record, keyed by its workspace-relative path in
/// `State.docs`. Which files are open — and in what order — is the dock
/// strip's business; this table only holds what each open file's document
/// looks like.
pub(all) struct Doc {
  name : String
  state : TabState
  // `Some` means this tab was explicitly opened from Changes. Content and a
  // missing HEAD become Viewer quick-diff baselines; the other cases remain
  // visible as precise review-status chrome.
  review : ReviewState?
  // The file changed on disk while its tab was in the background; reloaded
  // on activation rather than eagerly, so a build storm costs one read.
  stale : Bool
} derive(Eq)

///|
/// One file's decoded `fs.stat_files` result: its current mtime signature,
/// absent when the file is missing.
pub(all) struct FileStat {
  path : @pathx.Relative
  sig : String?
}

///|
/// One concrete filesystem event from the host watcher. Paths are relative
/// to the watcher's explicit root. A rename keeps both names so the file tree
/// and any open tab at either address can be reconciled.
pub(all) enum FileChange {
  Modified(@pathx.Relative)
  Created(@pathx.Relative)
  Removed(@pathx.Relative)
  Renamed(old~ : @pathx.Relative, new~ : @pathx.Relative)
} derive(Eq)

///|
/// The exact watcher configuration most recently sent to one host connection:
/// every open tab plus the root/expanded directories whose immediate children
/// the file tree needs to keep current.
pub(all) struct WatchedPaths {
  owner : @interop.ConversationKey
  root : @common.Uri
  files : Array[@pathx.Relative]
  directories : Array[@pathx.Relative]
  recursive : Bool
} derive(Eq)

///|
/// A lazily requested snapshot of one concrete workspace root. The Host walks
/// the root recursively, pruning churn directories and capping the result;
/// owner/root transitions reset it with the rest of the file-panel cache.
pub enum FileIndex {
  // No consumer has requested this workspace root yet.
  IndexEmpty
  // The first request is in flight.
  IndexLoading
  // The first request failed. A later EnsureFileIndex retries it.
  IndexFailed
  // `truncated` means the Host stopped at its response cap. A ready snapshot
  // remains usable while one refresh runs; watcher bursts coalesce into at
  // most one follow-up scan.
  IndexReady(
    files~ : Array[@pathx.Relative],
    truncated~ : Bool,
    refreshing~ : Bool,
    refresh_again~ : Bool
  )
} derive(Eq)

///|
/// Which inventory the explorer pane shows. This is a panel preference, so it
/// follows the user across conversation switches while each inventory's data
/// remains scoped to its owning conversation.
pub(all) enum ExplorerMode {
  ExplorerFiles
  ExplorerChanges
} derive(Eq)

///|
/// A changed path's stable presentation category. The host keeps Git's raw
/// index/worktree columns as well; this category is only for labels and color.
pub(all) enum ChangeKind {
  ChangeModified
  ChangeAdded
  ChangeDeleted
  ChangeRenamed
  ChangeCopied
  ChangeUnmerged
  ChangeTypeChanged
  ChangeUntracked
  ChangeSubmodule
  ChangeSymlink
  ChangeUnknown
} derive(Eq)

///|
/// One current path from the checkout's active review comparison. Renames and
/// copies retain their original path for explanatory UI.
pub(all) struct ChangedFile {
  path : @pathx.Relative
  original_path : @pathx.Relative?
  index_status : String
  worktree_status : String
  kind : ChangeKind
} derive(Eq)

///|
/// The lazily requested changed-file inventory. A ready snapshot remains
/// visible during a background refresh. `refreshing` limits the host to one
/// outstanding request; `refresh_again` coalesces later watcher/run signals
/// into at most one follow-up.
pub(all) enum ChangeList {
  ChangeListIdle
  ChangeListLoading(refresh_again~ : Bool)
  ChangeListFailed(String)
  ChangeListReady(
    repository~ : Bool,
    files~ : Array[ChangedFile],
    refreshing~ : Bool,
    refresh_again~ : Bool
  )
} derive(Eq)

///|
/// The file subsystem's state: a lazily-loaded file tree of the active
/// conversation's workspace and the document table behind the dock's open
/// file tabs. Keyed entirely by workspace-relative paths; `owner` records
/// which channel's conversation the cached tree and documents belong to, so
/// switching either channel or session swaps them rather than showing
/// another host's files. Strip membership, order, the active tab, and the
/// parked per-conversation strips all live in the dock package — the open
/// file list arrives through `Ctx`.
pub(all) struct State {
  owner : @interop.ConversationKey?
  // The workspace and resolved checkout incarnation last reconciled for
  // `owner`. A conversation can move from its project root into a newly
  // created worktree without changing owner or passing through a missing
  // placement; retaining both identities makes that transition a hard cache
  // and request boundary instead of letting root-checkout data survive it.
  placement_known : Bool
  placement_workspace : @common.Uri?
  placement_root : @common.Uri?
  placement_checkout : @interop.CheckoutPlacement?
  // Whether the file-tree pane (the toggleable column right of the viewer)
  // is shown. A panel preference, not per-conversation state, so it
  // survives conversation switches.
  tree_open : Bool
  // The explorer's Files/Changes selection and the Git snapshot behind the
  // latter. The selection survives a conversation switch; the snapshot does
  // not (see `sync`).
  explorer_mode : ExplorerMode
  // Source/full-diff is a reviewer preference, not a per-file decision. New
  // changed-file reviews inherit it so next/previous and tree navigation do
  // not force the reviewer to request the full diff again.
  review_view_mode : ReviewViewMode
  changes : ChangeList
  // Exact changed rows the user has marked reviewed in the current checkout.
  // Watcher events and run boundaries invalidate affected progress; a final
  // Git refresh also drops rows whose status or rename identity changed.
  reviewed_changes : Array[ChangedFile]
  // Monotonic request token retained across conversation re-roots and advanced
  // across same-owner placement changes. Owner plus this generation rejects an
  // old A→B→A reply or one from an earlier checkout incarnation.
  changes_generation : Int
  // Placement/conversation epoch carried by filesystem request replies.
  // Advancing this value on either boundary rejects reads, listings, and
  // stats that outlived the checkout they addressed.
  request_epoch : Int
  // Last settled Git comparison identity (task/branch base, or HEAD fallback).
  // The legacy field name stays internal; `changes_head_known` distinguishes
  // a first/unborn snapshot from no snapshot yet so a comparison transition
  // can refresh every surviving review baseline precisely.
  changes_head : String?
  changes_head_known : Bool
  // Monotonic token shared by changed-file baseline and working-tree reads.
  // Each side records its current token in `ReviewState`; it outlives
  // conversation re-roots for the same A→B→A reason as `changes_generation`.
  review_generation : Int
  // A missing checkout can discard either half of an in-flight review. Mark
  // that boundary explicitly so the first authoritative snapshot after
  // recovery restarts only incomplete requests once; ordinary polling must
  // never supersede a healthy slow read.
  review_recovery_pending : Bool
  // Legacy hosts cannot identify HEAD in their Changes reply. Their
  // compatibility refreshes keep a settled baseline visible while one new
  // HEAD read is in flight; recording that request by path prevents a slow
  // read from being superseded by every Changes poll.
  background_review_requests : Map[@pathx.Relative, Int]
  // Whether checkout placement is currently unresolved/missing. Kept separate
  // from review recovery because a repaired review may still be awaiting its
  // authoritative Changes snapshot when placement disappears a second time.
  placement_parked : Bool
  // Whether the explorer pane was visible on the preceding sync pass. This is
  // stricter than the enclosing dock being open: with a file active the tree
  // toggle (and narrow drill-down) can hide the explorer while the dock stays
  // open. Retaining this transition bit keeps Changes refresh behavior
  // independent from whether any file watcher remains active.
  explorer_was_visible : Bool
  // The paths the host's watcher currently follows (`None` = parked). Keeping
  // the full configuration makes opening/closing a tab or expanding/collapsing
  // a directory replace the watch even when the conversation did not change.
  watching : WatchedPaths?
  // Monotonic counter of the most recently requested watcher configuration.
  // Combined with `Ctx.watch_namespace`, it advances on every replacement or
  // park independently of root and filesystem request epochs.
  watch_generation : Int
  // A watcher can fail after `fs.watch` has already replied. Keep that
  // failure separate from directory/file requests so a later successful
  // directory listing does not hide the loss of live updates.
  watch_error : String?
  // Directory paths the user has expanded, and those with a `read_directory`
  // in flight; plain arrays since a workspace tree is small.
  expanded : Array[@pathx.Relative]
  loading : Array[@pathx.Relative]
  // Listed directories' entries, keyed by the directory's relative path.
  children : Map[@pathx.Relative, Array[FileEntry]]
  // Each open file's document, keyed by workspace-relative path. The key set
  // mirrors the dock strip's file tabs (`Ctx.open_files`): the root update
  // adds an entry when it opens a tab and drops it when the tab closes.
  docs : Map[@pathx.Relative, Doc]
  // The directory a breadcrumb click most recently revealed, flashed in the
  // tree until `HighlightCleared` fires.
  highlighted : @pathx.Relative?
  // The workspace-wide file snapshot used by completion consumers.
  index : FileIndex
  // The last directory/file failure, surfaced in the panel header;
  // `None` while nothing has failed.
  error : String?
} derive(Eq)

///|
pub fn State::empty() -> State {
  {
    owner: None,
    placement_known: false,
    placement_workspace: None,
    placement_root: None,
    placement_checkout: None,
    tree_open: true,
    explorer_mode: ExplorerFiles,
    review_view_mode: ReviewUnifiedDiff,
    changes: ChangeListIdle,
    reviewed_changes: [],
    changes_generation: 0,
    request_epoch: 0,
    changes_head: None,
    changes_head_known: false,
    review_generation: 0,
    review_recovery_pending: false,
    background_review_requests: Map([]),
    placement_parked: false,
    explorer_was_visible: false,
    watching: None,
    watch_generation: 0,
    watch_error: None,
    expanded: [],
    loading: [],
    children: Map([]),
    docs: Map([]),
    highlighted: None,
    index: IndexEmpty,
    error: None,
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
} derive(Eq)

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
/// `update`/`sync`/`panel_view` call: which conversation the panel serves, its
/// concrete root its file/LSP ops address, its attached workspace (still used
/// by Git operations), where that conversation is placed, whether the app is
/// in dark mode (drives the
/// embedded viewer's theme attribute), and the Settings choice of where the
/// file tree docks.
pub(all) struct Ctx {
  owner : @interop.ConversationKey
  // The current placement incarnation for filesystem request/reply fencing.
  request_epoch : Int
  // Page-unique prefix for watcher identities. The native watcher outlives a
  // page reload, so the counter alone is not enough to prevent reuse.
  watch_namespace : String
  root : @common.Uri?
  workspace : @common.Uri?
  // `None` while this connection has not loaded the conversation's placement.
  // Unknown and missing placements both block filesystem requests so neither
  // can be resolved against the registered project's main checkout.
  checkout : @interop.CheckoutPlacement?
  dark_mode : Bool
  tree_layout : TreeLayout
  // The app's phone-narrow layout flag. Narrow, the tree and the viewer
  // share one full-width pane (CSS shows exactly one), so opening a file
  // closes the tree — a drill-down — instead of showing both side by side.
  narrow : Bool
  // The dock's projection, recomputed by the root each dispatch: whether the
  // file body is actually on-screen (open on Chat with a file or picker active),
  // which files the strip holds (in strip order — the stat/watch/reload sweeps
  // run over this list), and which file tab is active (`None` while no file tab
  // is on screen).
  panel_open : Bool
  open_files : Array[@pathx.Relative]
  active_file : @pathx.Relative?
}

///|
pub(all) enum Msg {
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
  // Select the ordinary workspace tree or the checkout's changed-file list.
  // Selecting Changes also requests (or explicitly refreshes) its snapshot.
  ExplorerModeSelected(ExplorerMode)
  // Expand or collapse a directory row in the file tree; the first expansion
  // lazily lists the directory through the host.
  DirToggle(@pathx.Relative)
  // Ensure the current workspace's file snapshot exists. Loading and ready
  // states make this idempotent; a failed first request is retryable.
  EnsureFileIndex
  // A `read_directory` reply: `owner`/`path` say which request it answers so a
  // reply that lost a conversation switch can be dropped.
  DirLoaded(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    path~ : @pathx.Relative,
    entries~ : Array[FileEntry]
  )
  DirFailed(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    path~ : @pathx.Relative,
    message~ : String
  )
  // A workspace snapshot reply. The owner/epoch pair rejects a result that
  // outlived a conversation or concrete-root transition.
  FilesIndexed(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    files~ : Array[@pathx.Relative],
    truncated~ : Bool
  )
  // A request failed or was cancelled. A failed background refresh keeps the
  // previously ready snapshot; only an initial fetch becomes IndexFailed.
  FileIndexFailed(owner~ : @interop.ConversationKey, epoch~ : Int)
  // A `git.changes` reply. `head` carries the immutable comparison when the
  // host can identify one: a task or branch baseline when present, otherwise
  // resolved HEAD. `None` means no commit exists or a legacy host omitted the
  // identity. The owner fence rejects late responses.
  ChangesLoaded(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    repository~ : Bool,
    head~ : String?,
    files~ : Array[ChangedFile]
  )
  ChangesFailed(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    message~ : String
  )
  // A low-frequency fallback while Changes is visible. The selective file
  // watcher intentionally follows only open/listed paths, so polling also
  // catches nested external edits and index-only staging operations.
  ChangesPollDue(owner~ : @interop.ConversationKey, generation~ : Int)
  // A file row was clicked: read it and show it in the viewer. `name` is the
  // entry's display name, kept for the viewer's title and language guess.
  FileSelected(path~ : @pathx.Relative, name~ : String)
  // A Changes row was clicked. The full decoded row carries the original path
  // needed by renames/copies and whether a working-tree read is possible.
  ChangedFileSelected(ChangedFile)
  // Switch the active changed-file review between the ordinary source Viewer
  // and its full unified diff. Unavailable/loading reviews ignore the action.
  ToggleReviewDiff
  // Mark the active changed-file review as reviewed, or return it to the
  // unreviewed queue. Ordinary file tabs ignore the action.
  ToggleReviewProgress
  // One `git.original_file` request settled. `path` is always the current
  // changed path (the dock/document key), even when the host read its rename
  // source from `original_path`.
  GitOriginalLoaded(
    owner~ : @interop.ConversationKey,
    path~ : @pathx.Relative,
    generation~ : Int,
    background~ : Bool,
    original~ : @protocol.GitOriginalFileReply
  )
  GitOriginalFailed(
    owner~ : @interop.ConversationKey,
    path~ : @pathx.Relative,
    generation~ : Int,
    background~ : Bool,
    message~ : String
  )
  // A Definition/References result accepted by the Viewer's location opener.
  // Carry the captured owner so a conversation switch that races the async
  // request cannot open the target in the next workspace.
  OpenNavigationLocation(
    owner~ : @interop.ConversationKey,
    path~ : @pathx.Relative,
    range~ : @common.Range
  )
  // `file` is the decoded reply (content + address, or a withheld-file
  // case). `range`, when present, is a jumped-to symbol's one-based range,
  // revealed in the viewer once the file loads and — unless empty —
  // selected so the code it names reads highlighted. `annotation`, when
  // present (an annotation chip's jump), is the user's comment text,
  // re-shown as an editor bubble over `range`. A plain tree click leaves
  // both `None`. `review_generation` is present only for the working-tree
  // half of a changed-row open and fences repeated review clicks.
  FileLoaded(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    path~ : @pathx.Relative,
    name~ : String,
    file~ : FileContent,
    review_generation~ : Int?,
    range~ : @common.Range?,
    annotation~ : String?
  )
  // A read failure carries the same path/generation identity as success so a
  // stale review read cannot surface an error over a newer review or ordinary
  // open. Ordinary reads leave `review_generation=None`.
  FileFailed(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    path~ : @pathx.Relative,
    review_generation~ : Int?,
    message~ : String
  )
  // An `fs.watch` request rejection or an asynchronous watcher failure. The
  // generation identifies the exact watcher configuration that produced it.
  FileWatchFailed(
    channel~ : @interop.ChannelId,
    root~ : @common.Uri,
    generation~ : String,
    message~ : String
  )
  // A new watcher sends `changes=None` once it is attached, requesting a full
  // baseline reconciliation. Later pushes contain the exact debounced events.
  FsChanged(
    root~ : @common.Uri,
    generation~ : String,
    changes~ : Array[FileChange]?
  )
  // The conversation's agent run finished: the workspace has settled, so
  // re-check the active MoonBit file's module. The pruned watcher cannot see
  // edits outside open files and listed directories, and an agent turn
  // routinely writes files the panel never shows — the finish boundary is
  // the one cheap signal that covers them. `owner` fences a background
  // conversation's finish.
  RunSettled(owner~ : @interop.ConversationKey)
  // A `stat_files` reply: each open tab's current mtime signature (`""` =
  // the file is gone). Owner plus request epoch fence a request that outlived
  // either its conversation or checkout.
  StatsLoaded(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    stats~ : Array[FileStat]
  )
  // The language server's diagnostics returned by `lsp_open`. The full owner
  // fences a reply that lost a device/session switch while the request ran.
  DiagnosticsLoaded(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    absolute~ : @common.Uri,
    diagnostics~ : Array[@protocol.LspDiagnostic]
  )
  // A later diagnostics push from the host. The wire event is channel-scoped
  // but carries no session, so the main package first rejects background
  // channels and this handler then verifies the panel still serves it.
  DiagnosticsPublished(
    channel~ : @interop.ChannelId,
    absolute~ : @common.Uri,
    diagnostics~ : Array[@protocol.LspDiagnostic]
  )
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
  // The user submitted a comment from the standalone full-diff surface.
  // Both line domains cross the package boundary: additions/context use the
  // modified number, while an original-only deletion remains identifiable to
  // the composer without pretending it exists in the working document.
  // Like `EditorCommentAdded`, the main update intercepts this message and
  // turns it into a deduplicated annotation chip.
  UnifiedDiffCommentAdded(
    file~ : @pathx.Relative,
    original_line_number~ : Int?,
    modified_line_number~ : Int?,
    quote~ : String,
    comment~ : String
  )
}
