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
/// The per-tab review presentation. Source mode keeps the selected code or
/// Markdown surface; full-diff mode shows the context-bounded source comparison
/// in the separately selected side-by-side or inline layout.
pub(all) enum ReviewViewMode {
  ReviewSource
  ReviewDiff
} derive(Eq)

///|
/// The presentation selected for an ordinary generated MoonBit interface.
/// Diff/review and positioned navigation ignore this preference and keep the
/// source surface, but a normal `.mbti` tab starts in diagram mode.
pub(all) enum MbtiViewMode {
  MbtiDiagram
  MbtiSource
} derive(Eq)

///|
/// The layout shared by Line and sectioned semantic comparison. This
/// panel-level preference is independent from `ReviewViewMode`: returning to
/// source keeps it for the next review and the next changed file.
pub(all) enum ReviewDiffLayout {
  ReviewSideBySide
  ReviewInline
} derive(Eq)

///|
/// Desktop-owned comparison algorithm preference. Line keeps the complete
/// file DiffEditor; Token and Tree select the sectioned semantic review.
/// Non-MoonBit comparisons keep using Line without overwriting this preference.
pub(all) enum ReviewDiffMode {
  ReviewDiffLine
  ReviewDiffToken
  ReviewDiffTree
} derive(Eq, Debug)

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
/// or why the host has none — the file is missing, or it could not be
/// inspected at all.
pub(all) struct FileStat {
  path : @pathx.Relative
  signature : @protocol.FileSignature
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
  // The first request is in flight. A watcher event can arrive after the
  // recursive watch starts but before that request settles; `refresh_again`
  // preserves one follow-up scan across that race.
  IndexLoading(refresh_again~ : Bool)
  // The first request failed. A later EnsureFileIndex retries it.
  IndexFailed
  // `truncated` means the Host stopped at its response cap. A ready snapshot
  // remains usable while one refresh runs; watcher bursts coalesce into at
  // most one follow-up scan. When `refreshing` is false, `refresh_again` marks
  // a failed refresh whose stale snapshot must be retried by the next
  // EnsureFileIndex consumer.
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
  // Workspace text search is the third inventory owned by this file panel.
  ExplorerSearch
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
/// The lazily loaded, snapshot-pinned Git graph. A ready page stays visible
/// while more rows are requested; `load_error` therefore does not discard the
/// history the user can still inspect.
pub(all) enum GitGraphState {
  GitGraphIdle
  GitGraphLoading
  GitGraphFailed(String)
  GitGraphReady(
    repository~ : Bool,
    snapshot~ : @protocol.GitHistorySnapshot,
    commits~ : Array[@protocol.GitHistoryCommit],
    has_more~ : Bool,
    loading_more~ : Bool,
    load_error~ : String?
  )
} derive(Eq)

///|
/// The inline file expansion for the currently selected commit.
pub(all) enum GitCommitFiles {
  GitCommitFilesIdle
  GitCommitFilesLoading(commit~ : String)
  GitCommitFilesFailed(commit~ : String, message~ : String)
  GitCommitFilesReady(
    commit~ : String,
    parent~ : String?,
    files~ : Array[@protocol.GitHistoricalChange]
  )
} derive(Eq)

///|
pub(all) enum HistoryBlob {
  HistoryBlobLoading
  HistoryBlobMissing
  HistoryBlobBinary
  HistoryBlobOversized
  HistoryBlobContent(String)
  HistoryBlobError(String)
} derive(Eq)

///|
pub(all) enum HistoryDiffSide {
  HistoryOriginal
  HistoryModified
} derive(Eq)

///|
pub(all) struct HistoryDiffDoc {
  diff : @dock.GitHistoryDiff
  generation : Int
  original : HistoryBlob
  modified : HistoryBlob
} derive(Eq)

///|
/// The checkout placement a sync pass settled on for `State::owner`.
/// Availability and identity are one value: parking keeps the identity the
/// panel had before the gap, so recovery can tell the same checkout coming
/// back from another checkout taking its place.
pub(all) enum ReconciledPlacement {
  // No owner has been claimed yet, so nothing has been reconciled.
  PlacementUnknown
  // A ready checkout. Filesystem requests may address it.
  PlacementLive(@interop.CheckoutPlacement)
  // Placement is unresolved or missing, so host-backed work stays suspended.
  // `last_known` is the identity from before the gap, and `None` only when the
  // owner was claimed while placement was already unresolved. Parking is
  // tracked here rather than folded into review recovery because a repaired
  // review may still be awaiting its authoritative Changes snapshot when
  // placement disappears a second time.
  PlacementParked(last_known~ : @interop.CheckoutPlacement?)
} derive(Eq)

///|
/// The checkout identity this panel is reconciled against, live or retained
/// across a gap. Identity comparisons and cache retirement read through this;
/// a value here does not mean the checkout is currently usable.
pub fn ReconciledPlacement::identity(
  self : ReconciledPlacement,
) -> @interop.CheckoutPlacement? {
  match self {
    PlacementUnknown => None
    PlacementLive(value) => Some(value)
    PlacementParked(last_known~) => last_known
  }
}

///|
/// Whether reconciliation has parked this panel.
pub fn ReconciledPlacement::is_parked(self : ReconciledPlacement) -> Bool {
  self is PlacementParked(_)
}

///|
/// Settle a freshly projected placement against the retained one: a ready
/// value goes live and anything else parks. An unresolved projection keeps the
/// retained identity, because a gap must not erase what recovery compares
/// against. A new incarnation reconciles from `PlacementUnknown` instead, so
/// the checkout it replaced is not carried into it.
pub fn ReconciledPlacement::reconcile(
  self : ReconciledPlacement,
  current : @interop.CheckoutPlacement?,
) -> ReconciledPlacement {
  match current {
    Some(value) if value.is_ready() => PlacementLive(value)
    Some(value) => PlacementParked(last_known=Some(value))
    None => PlacementParked(last_known=self.identity())
  }
}

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
  // The placement incarnation last reconciled for `owner`, including whether
  // it is currently parked. A conversation can move from its project root into
  // a newly-created worktree without changing owner; retaining the complete
  // value makes that transition a hard cache and request boundary without
  // storing independently drifting roots.
  placement : ReconciledPlacement
  // Whether the file-tree pane (the toggleable column right of the viewer)
  // is shown. A panel preference, not per-conversation state, so it
  // survives conversation switches.
  tree_open : Bool
  // The explorer's Files/Changes/Search selection. The selection survives a
  // conversation switch; checkout-derived inventories do not (see `sync`).
  explorer_mode : ExplorerMode
  // Workspace text search is a child inventory of this file subsystem. Its
  // reducer/request/view remain in grep_search, while this State supplies the
  // same owner/root lifecycle already used by Files and Changes.
  search : @grep_search.State
  // Source/full-diff is a reviewer preference, not a per-file decision. New
  // changed-file reviews inherit it so next/previous and tree navigation do
  // not force the reviewer to request the full diff again.
  review_view_mode : ReviewViewMode
  // Side-by-side/inline is likewise a reviewer preference rather than
  // document state. Line applies it to its retained models; Token/Tree update
  // the DiffEditor mounted inside every semantic section.
  review_diff_layout : ReviewDiffLayout
  // The requested MoonBit-aware algorithm and filtering policy are desktop
  // preferences. Other file types keep rendering the Line surface while
  // these values remain parked for the next `.mbt` comparison.
  review_diff_mode : ReviewDiffMode
  review_diff_ignore_comments : Bool
  review_diff_ignore_tests : Bool
  // Token/Tree comparisons are computed once during state reconciliation.
  // The view renders only section chrome and stable editor hosts; the
  // imperative lifecycle consumes the same plan to mount one DiffEditor per
  // top-level fragment.
  semantic_review_input : SemanticReviewInput?
  semantic_review_plan : @moon_diff_provider.SectionedSemanticReviewPlan?
  // VS Code's MultiDiffEditor keeps collapse state per document item. Our
  // semantic input is one tab-local document, so reset these section keys when
  // that input changes while preserving them across layout/theme rerenders.
  semantic_review_collapsed : Array[String]
  // Whether DiffEditor's current (possibly source-mode parked) comparison has
  // at least one completed change for cyclic previous/next navigation.
  review_diff_navigation_available : Bool
  changes : ChangeList
  // Git graph state is conversation/workspace scoped like Changes, but is
  // refreshed only at meaningful repository boundaries rather than on the
  // three-second working-tree poll.
  git_graph : GitGraphState
  git_graph_generation : Int
  git_graph_selected : String?
  git_commit_files : GitCommitFiles
  git_commit_files_generation : Int
  git_actual_head : String?
  git_actual_head_known : Bool
  // Section presentation is a page-lifetime preference and survives owner
  // switches; the drag ratio itself lives as a CSS custom property on the
  // permanent pane element.
  changes_collapsed : Bool
  git_graph_collapsed : Bool
  // Historical content is not a filesystem document and never joins the
  // watcher/LSP projections. Keys combine commit and current path.
  history_docs : Map[String, HistoryDiffDoc]
  history_generation : Int
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
  // Page-lifetime navigation token. Transcript file-link clicks capture it;
  // every competing editor navigation advances it, so a slower older click
  // cannot move the viewer after a newer user action has taken precedence.
  file_link_generation : Int
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
  // The pending comparison whose loading notice has survived the reveal
  // delay. A newer review generation does not inherit this value, so rapid
  // file changes cannot flash an older timer's notice.
  diff_loading_generation : Int?
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
  // Whether the explorer pane was visible on the preceding sync pass. This is
  // stricter than the enclosing dock being open: with a file active the tree
  // toggle (and narrow drill-down) can hide the explorer while the dock stays
  // open. Retaining this transition bit keeps Changes refresh behavior
  // independent from whether any file watcher remains active.
  explorer_was_visible : Bool
  // The effective paths most recently requested from the Host (`None` =
  // parked). Recursive selections omit ordinary paths already covered by the
  // workspace-wide watch, so equality means the native watch policy is truly
  // unchanged rather than merely producing an equivalent Host filter.
  watching : WatchedPaths?
  // Monotonic counter of the most recently requested watcher configuration.
  // Combined with `Ctx.watch_namespace`, it advances on every replacement or
  // park independently of root and filesystem request epochs.
  watch_generation : Int
  // `fs.watch` can reject activation, and an active watcher can later stop.
  // Keep either failure separate from directory/file requests so a later
  // successful listing does not hide the loss of live updates. The root app
  // owns its toast presentation; this state only prevents a retry loop.
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
  // Per-tab MBTI presentation. Absence is the normal default (`MbtiDiagram`),
  // so a closed and later reopened interface starts rendered again. Special
  // source-bearing opens record `MbtiSource` while that tab remains open.
  mbti_view_modes : Map[@pathx.Relative, MbtiViewMode]
  // The directory whose immediate children are open in the breadcrumb's
  // VS Code-style picker. The legacy field and message names remain so this
  // presentation change does not grow the package's public API.
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
    placement: PlacementUnknown,
    tree_open: true,
    explorer_mode: ExplorerFiles,
    search: @grep_search.State::empty(),
    review_view_mode: ReviewDiff,
    review_diff_layout: ReviewSideBySide,
    review_diff_mode: ReviewDiffLine,
    // Token/Tree starts from semantic production changes. Both explicit
    // toggles can restore comments/blank lines or test blocks when needed.
    review_diff_ignore_comments: true,
    review_diff_ignore_tests: true,
    semantic_review_input: None,
    semantic_review_plan: None,
    semantic_review_collapsed: [],
    review_diff_navigation_available: false,
    changes: ChangeListIdle,
    git_graph: GitGraphIdle,
    git_graph_generation: 0,
    git_graph_selected: None,
    git_commit_files: GitCommitFilesIdle,
    git_commit_files_generation: 0,
    git_actual_head: None,
    git_actual_head_known: false,
    changes_collapsed: false,
    git_graph_collapsed: false,
    history_docs: Map([]),
    history_generation: 0,
    reviewed_changes: [],
    changes_generation: 0,
    request_epoch: 0,
    file_link_generation: 0,
    changes_head: None,
    changes_head_known: false,
    review_generation: 0,
    diff_loading_generation: None,
    review_recovery_pending: false,
    background_review_requests: Map([]),
    explorer_was_visible: false,
    watching: None,
    watch_generation: 0,
    watch_error: None,
    expanded: [],
    loading: [],
    children: Map([]),
    docs: Map([]),
    mbti_view_modes: Map([]),
    highlighted: None,
    index: IndexEmpty,
    error: None,
  }
}

///|
/// An open MBTI tab defaults to its rendered diagram without storing a map
/// entry. Explicit source/diagram selections then live only for that tab's
/// lifetime.
fn State::mbti_view_mode(self : State, path : @pathx.Relative) -> MbtiViewMode {
  self.mbti_view_modes.get(path).unwrap_or(MbtiDiagram)
}

///|
/// Prepare the file subsystem for a shell-driven open that must happen before
/// the ordinary post-dispatch `sync` pass. Checkout-derived inventories and
/// documents are reset here, inside their owner, while panel preferences and
/// page-lifetime request fences survive an A -> B -> A conversation switch.
pub fn State::prepare_owner(
  self : State,
  owner : @interop.ConversationKey,
  open_files : Array[@pathx.Relative],
) -> State {
  guard self.owner != Some(owner) else { return self }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  for path in open_files {
    docs[path] = {
      name: basename(path),
      state: TabLoading,
      review: None,
      stale: false,
    }
  }
  {
    ..State::empty(),
    owner: Some(owner),
    tree_open: self.tree_open,
    explorer_mode: self.explorer_mode,
    search: self.search.reset_checkout(),
    review_view_mode: self.review_view_mode,
    review_diff_layout: self.review_diff_layout,
    review_diff_mode: self.review_diff_mode,
    review_diff_ignore_comments: self.review_diff_ignore_comments,
    review_diff_ignore_tests: self.review_diff_ignore_tests,
    changes_generation: self.changes_generation,
    request_epoch: self.request_epoch + 1,
    file_link_generation: self.file_link_generation,
    review_generation: self.review_generation,
    watch_generation: self.watch_generation,
    // Preserve the old host configuration until `sync` can explicitly retire
    // or replace it against the newly resolved checkout placement.
    watching: self.watching,
    docs,
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
/// complete directory placement, whether the app is in dark mode (drives the
/// embedded viewer's theme attribute), and the Settings choice of where the
/// file tree docks.
pub(all) struct Ctx {
  owner : @interop.ConversationKey
  // The current placement incarnation for filesystem request/reply fencing.
  request_epoch : Int
  // Page-unique prefix for watcher identities. The native watcher outlives a
  // page reload, so the counter alone is not enough to prevent reuse.
  watch_namespace : String
  // `None` while this connection has not loaded the conversation's placement.
  // Unknown and missing placements both block filesystem requests so neither
  // can be resolved against the registered project's main checkout.
  placement : @interop.CheckoutPlacement?
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
  open_history_diffs : Array[@dock.GitHistoryDiff]
  active_history_diff : @dock.GitHistoryDiff?
} derive(Eq)

///|
/// The concrete root used by file and language-service requests.
fn Ctx::root(self : Ctx) -> @common.Uri? {
  self.placement.bind(value => value.checkout_root())
}

///|
fn Ctx::search_input(self : Ctx) -> @grep_search.Input {
  @grep_search.Input(owner=self.owner, root=self.root())
}

///|
/// The registered project used by Git and worktree requests.
fn Ctx::workspace(self : Ctx) -> @common.Uri? {
  self.placement.bind(value => value.project_root())
}

///|
/// Whether this context currently names a concrete checkout directory.
fn Ctx::checkout_ready(self : Ctx) -> Bool {
  self.placement is Some(value) && value.is_ready()
}

///|
pub(all) enum Msg {
  // Open the directory's immediate children under the breadcrumb. Selecting
  // the already-open directory toggles the picker closed; an uncached level
  // is listed through the same request/cache as the explorer tree.
  RevealDirectory(@pathx.Relative)
  // Click-away and Escape close the transient picker only when `path` still
  // names the open directory.
  HighlightCleared(@pathx.Relative)
  // Show or hide the file-tree pane (the column right of the viewer).
  ToggleTree
  // Select the ordinary workspace tree, changed-file list, or workspace Search.
  // Selecting Changes also requests (or explicitly refreshes) its snapshot.
  ExplorerModeSelected(ExplorerMode)
  // Search reducer events stay nested under the Explorer owner. A selected
  // result is intercepted by the application root exactly like FileSelected
  // and ChangedFileSelected because opening a dock tab is shell state.
  Search(@grep_search.Msg)
  SearchMatchSelected(path~ : String, range~ : @common.Range)
  SemanticSelectionChanged(@mention_context.SemanticSearchReference?)
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
  // The tick carries no owner or request token: `changes_poll_wanted` decides
  // from live state whether the interval exists at all, so a tick can only be
  // delivered for the conversation and snapshot that currently want one.
  ChangesPollDue
  // The actual checkout HEAD is separate from Review's possibly older
  // comparison boundary. It invalidates the graph without rebasing reviews.
  GitHeadObserved(owner~ : @interop.ConversationKey, head~ : String?)
  GitHistoryRefreshRequested
  GitHistoryLoadMoreRequested
  GitHistoryLoaded(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    append~ : Bool,
    reply~ : @protocol.GitHistoryReply
  )
  GitHistoryFailed(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    append~ : Bool,
    message~ : String
  )
  GitCommitSelected(String)
  GitCommitChangesLoaded(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    reply~ : @protocol.GitCommitChangesReply
  )
  GitCommitChangesFailed(
    owner~ : @interop.ConversationKey,
    generation~ : Int,
    commit~ : String,
    message~ : String
  )
  GitCommitChangesRetry(String)
  HistoricalFileSelected(@dock.GitHistoryDiff)
  ToggleChangesSection
  ToggleGitGraphSection
  // A file row was clicked: read it and show it in the viewer. `name` is the
  // entry's display name, kept for the viewer's title and language guess.
  FileSelected(path~ : @pathx.Relative, name~ : String)
  // A Changes row was clicked. The full decoded row carries the original path
  // needed by renames/copies and whether a working-tree read is possible.
  ChangedFileSelected(ChangedFile)
  // Reveal a still-pending full-diff notice only after its short grace period.
  // Owner, path, and request generation fence timers that outlive navigation.
  DiffLoadingDue(
    owner~ : @interop.ConversationKey,
    path~ : @pathx.Relative,
    generation~ : Int
  )
  // Switch the active changed-file review between its selected source
  // presentation and the full comparison. Unavailable/loading reviews ignore
  // the action.
  ToggleReviewDiff
  // Switch a visible comparison between side-by-side panes and inline rows.
  // Source mode and unavailable/loading comparisons ignore the action.
  ToggleReviewDiffLayout
  // Select the desktop-owned comparison mode. Token and Tree are accepted
  // only for a visible `.mbt` comparison; other files keep the preference
  // parked while rendering Line.
  ReviewDiffModeSelected(ReviewDiffMode)
  ToggleReviewDiffIgnoreComments
  ToggleReviewDiffIgnoreTests
  // Toggle one top-level entry in the Token/Tree multi-diff container.
  SemanticReviewSectionToggled(String)
  // DiffEditor's provider transaction also controls whether its existing
  // cyclic change-navigation commands have a target.
  ReviewDiffNavigationAvailabilityChanged(Bool)
  RevealPreviousReviewDiffChange
  RevealNextReviewDiffChange
  // Continue multi-diff navigation in another Token/Tree section. `true`
  // reveals the final change when moving backward; `false` reveals the first.
  RevealSemanticReviewSectionChange(String, Bool)
  // Mark the active changed-file review as reviewed, or return it to the
  // unreviewed queue. Ordinary file tabs ignore the action.
  ToggleReviewProgress
  // Select the ordinary `.mbti` tab's rendered diagram or source. Reviews,
  // history comparisons, and non-MBTI documents ignore the action.
  MbtiViewModeSelected(MbtiViewMode)
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
  HistoryBlobLoaded(
    owner~ : @interop.ConversationKey,
    key~ : String,
    generation~ : Int,
    side~ : HistoryDiffSide,
    blob~ : @protocol.GitOriginalFileReply
  )
  HistoryBlobFailed(
    owner~ : @interop.ConversationKey,
    key~ : String,
    generation~ : Int,
    side~ : HistoryDiffSide,
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
  // revealed in the viewer once the file loads. The caret stays collapsed at
  // its start while an independent exact-symbol or whole-line decoration makes
  // the destination visible without opening selection-driven Comment UI.
  // `annotation`, when present (an annotation chip's jump), is the user's
  // comment text,
  // re-shown as an editor bubble over `range`. A plain tree click leaves
  // both `None`. `file_link_generation` identifies the explicit editor
  // navigation that started this read. Positioned transcript links supply the
  // captured click generation; direct file, symbol, and mention opens use the
  // current generation. It fences the viewer navigation while still allowing
  // a late reply to settle a loading tab when no newer read owns that path.
  // `review_generation` is present only for the working-tree half of a
  // changed-row open.
  FileLoaded(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    path~ : @pathx.Relative,
    name~ : String,
    file~ : FileContent,
    file_link_generation~ : Int?,
    review_generation~ : Int?,
    range~ : @common.Range?,
    annotation~ : String?
  )
  // A read failure carries the same path/generation identities as success so
  // a stale navigation read can settle its loading tab without surfacing an
  // error, and a stale review read cannot replace its successor. Background
  // reads leave both generation fields `None`.
  FileFailed(
    owner~ : @interop.ConversationKey,
    epoch~ : Int,
    path~ : @pathx.Relative,
    file_link_generation~ : Int?,
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
  // A `stat_files` reply: each open tab's current mtime signature, or that
  // the file is gone or could not be inspected. Owner plus request epoch
  // fence a request that outlived either its conversation or checkout.
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
  // A user-invoked Definition/References request reached the host but failed.
  // The root app intercepts this message and shows its transient toast; the
  // owner prevents a late reply from surfacing over another conversation.
  LanguageRequestFailed(owner~ : @interop.ConversationKey, message~ : String)
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
  // The inline input's Apply all feedback action follows its synchronous
  // comment-added event. The application root intercepts this after attaching
  // the new annotation chip and submits the main-window composer through its
  // ordinary prompt/steer queue.
  ApplyAllFeedback
  // The user submitted a comment from a full-diff surface. Both line domains
  // cross the package boundary: additions/context use the modified number,
  // while an original-pane selection remains identifiable to the composer
  // without pretending it exists in the working document.
  // Like `EditorCommentAdded`, the main update intercepts this message and
  // turns it into a deduplicated annotation chip.
  DiffCommentAdded(
    file~ : @pathx.Relative,
    original_line_number~ : Int?,
    modified_line_number~ : Int?,
    quote~ : String,
    comment~ : String,
    // Present when the comment came from the original-side code kernel.
    resource~ : ModelUri?,
    feedback_id~ : String?
  )
}

///|
pub extend ChangeKind with Eq::{equal, not_equal}

///|
pub extend ChangeList with Eq::{equal, not_equal}

///|
pub extend ChangedFile with Eq::{equal, not_equal}

///|
pub extend Ctx with Eq::{equal, not_equal}

///|
pub extend Doc with Eq::{equal, not_equal}

///|
pub extend ExplorerMode with Eq::{equal, not_equal}

///|
pub extend FileChange with Eq::{equal, not_equal}

///|
pub extend FileEntry with Eq::{equal, not_equal}

///|
pub extend FileIndex with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend GitCommitFiles with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend GitGraphState with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend HistoryBlob with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend HistoryDiffDoc with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend HistoryDiffSide with Eq::{equal, not_equal}

///|
pub extend ReconciledPlacement with Eq::{equal, not_equal}

///|
pub extend ReviewBaseline with Eq::{equal, not_equal}

///|
pub extend MbtiViewMode with Eq::{equal, not_equal}

///|
pub extend ReviewDiffLayout with Eq::{equal, not_equal}

///|
#deprecated("Use `Debug::to_repr` via the trait or `Repr(value)` instead", skip_current_package=true)
#doc(hidden)
pub extend ReviewDiffMode with Debug::{to_repr}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ReviewDiffMode with Eq::{equal, not_equal}

///|
pub extend ReviewState with Eq::{equal, not_equal}

///|
pub extend ReviewViewMode with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}

///|
pub extend TabState with Eq::{equal, not_equal}

///|
pub extend TreeLayout with Eq::{equal, not_equal}

///|
pub extend WatchedPaths with Eq::{equal, not_equal}
