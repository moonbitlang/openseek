// The panel's message handlers and post-dispatch reconciliation, extracted
// from the main package's update loop. `update` is pure: effects go out as
// commands, and every host reply carries the conversation owner it answers so
// a reply that lost a device/session switch is dropped against `ctx`/`state`.

///|
/// Attach the viewer the first time the panel has real width, install the
/// resize-drag handle, and re-measure on every width change. Idempotent, so
/// every panel-opening path batches it in front of its own work.
pub fn mount_cmds(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.batch([
    request_viewer_mount(dispatch),
    request_resize_handle_mount(),
    request_tree_resize_mount(),
    request_git_graph_resize_mount(),
    request_viewer_remeasure(),
  ])
}

///|
/// Whether host-backed editor work may address this conversation's checkout.
/// Public entry points are called directly by the dock/root package as well as
/// through `update`, so each one must enforce the same placement boundary as
/// the message dispatcher.
fn Ctx::placement_ready(self : Ctx) -> Bool {
  self.checkout_ready()
}

///|
/// The baseline the Viewer quick-diff service consumes. `ReviewMissing` is an
/// intentional empty original so every working-tree line renders as added;
/// unavailable/error cases clear the gutter rather than drawing a false diff.
fn ReviewBaseline::quick_diff_original(self : ReviewBaseline) -> String? {
  match self {
    ReviewContent(content) => Some(content)
    ReviewMissing => Some("")
    ReviewLoading | ReviewBinary | ReviewOversized | ReviewFailed(_) => None
  }
}

///|
fn Doc::quick_diff_original(self : Doc) -> String? {
  match self.review {
    Some(review) => review.baseline.quick_diff_original()
    None => None
  }
}

///|
/// The two textual sides available to the switchable DiffEditor.
/// Added files use an empty HEAD side and deleted files use an empty working
/// side. Loading, binary, oversized, and failed reads do not invent text.
fn Doc::diff_content(self : Doc) -> (String, String)? {
  guard self.review is Some(review) else { return None }
  let original = match review.baseline {
    ReviewContent(content) => content
    ReviewMissing => ""
    ReviewLoading | ReviewBinary | ReviewOversized | ReviewFailed(_) =>
      return None
  }
  let modified = match self.state {
    TabLoaded(content~, ..) => content
    TabDeleted => ""
    TabLoading
    | TabBinary
    | TabOversized
    | TabReadFailed(_)
    | TabUnavailable(_) => return None
  }
  Some((original, modified))
}

///|
/// Diff inputs only enter the comparison while this tab's cached copy of the
/// panel preference is full-diff mode. Keeping the copy on its review state also
/// preserves it through generation-fenced source/baseline refreshes.
fn Doc::visible_diff(self : Doc) -> (String, String)? {
  guard self.review is Some({ view_mode: ReviewDiff, .. }) else { return None }
  self.diff_content()
}

///|
fn Doc::shows_diff(self : Doc) -> Bool {
  self.visible_diff() is Some(_)
}

///|
/// VS Code enables workspace-search model decorations only while its Search
/// view is active. OpenSeek uses the Explorer inventory selection as the same
/// logical boundary; narrow drill-down deliberately retains Search mode so the
/// editor preview keeps its matches while the inventory is temporarily hidden.
fn State::editor_search_highlights(
  self : State,
  path : @pathx.Relative,
) -> @grep_search.EditorHighlights? {
  guard self.explorer_mode is ExplorerSearch else { return None }
  self.search.editor_highlights(path.0)
}

///|
/// Whether a requested full diff is still waiting for one textual side. Keep
/// this distinct from `shows_diff`: the comparison has no model yet,
/// but revealing the source Viewer while either read settles produces a
/// source-to-diff flash.
fn Doc::diff_is_pending(self : Doc) -> Bool {
  guard self.review is Some(review) && review.view_mode is ReviewDiff else {
    return false
  }
  match (review.baseline, self.state) {
    (ReviewLoading, TabLoading | TabLoaded(..) | TabDeleted) => true
    (ReviewContent(_) | ReviewMissing, TabLoading) => true
    _ => false
  }
}

///|
/// The surface selected for the current render. A full comparison owns the
/// diff host from the moment it is requested, including its loading interval;
/// a settled unavailable comparison falls back to the ordinary file surface.
fn Doc::uses_diff_surface(self : Doc) -> Bool {
  self.shows_diff() || self.diff_is_pending()
}

///|
fn ReviewState::diff_loading_generation(self : ReviewState) -> Int {
  if self.generation >= self.working_generation {
    self.generation
  } else {
    self.working_generation
  }
}

///|
fn Doc::diff_pending_generation(self : Doc) -> Int? {
  guard self.diff_is_pending() && self.review is Some(review) else {
    return None
  }
  Some(review.diff_loading_generation())
}

///|
fn State::shows_delayed_diff_loading(self : State, doc : Doc) -> Bool {
  guard doc.diff_pending_generation() is Some(generation) else { return false }
  self.diff_loading_generation == Some(generation)
}

///|
const DiffLoadingDelayMilliseconds = 200

///|
fn delayed_diff_loading(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  doc : Doc,
) -> @cmd.Cmd {
  guard doc.diff_pending_generation() is Some(generation) else {
    return @cmd.none
  }
  @cmd.delay(
    dispatch(DiffLoadingDue(owner~, path~, generation~)),
    DiffLoadingDelayMilliseconds,
  )
}

///|
/// The newest working-tree request that owns an auxiliary review reload.
/// Ordinary documents carry no token; each review reload advances this token
/// independently of its HEAD request so out-of-order file replies are fenced.
fn Doc::review_generation(self : Doc) -> Int? {
  match self.review {
    Some(review) => Some(review.working_generation)
    None => None
  }
}

///|
/// The command that puts `path`'s document on screen: its content (scroll
/// restored to where the tab was left), a withheld/deleted notice, or — for
/// a document whose content is not loaded yet — a fresh read, whose
/// `FileLoaded` does the showing. A MoonBit file also re-syncs diagnostics,
/// matching what its first load did, unless the caller is only settling the
/// review baseline for the document that is already on screen.
fn show_tab_impl(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  search_highlights : @grep_search.EditorHighlights?,
  path : @pathx.Relative,
  doc : Doc,
  reload_stale : Bool,
  sync_diagnostics : Bool,
) -> @cmd.Cmd {
  let show = match doc.state {
    // A review-loading document always has the paired read started by
    // `open_changed_document`; activation must not create an untagged
    // duplicate that could outlive a later review generation. Clear the
    // outgoing document immediately so its text and gutter cannot remain
    // under the newly active tab while the paired request settles.
    TabLoading if doc.review is Some(_) => clear_document()
    TabLoading =>
      // Covers both "a read is already in flight" (a duplicate reply is
      // folded idempotently) and "parked since a conversation restore, never
      // read" — the read is the only way to tell the viewer has something to
      // show.
      @cmd.batch([
        clear_document(),
        read_file(
          dispatch,
          ctx.owner,
          ctx.request_epoch,
          path,
          doc.name,
          range=None,
          root=ctx.root(),
        ),
      ])
    TabLoaded(content~, absolute~, ..) => {
      let show = show_file_in_viewer(
        ctx.owner,
        root=ctx.root(),
        doc.name,
        content,
        absolute~,
        relative=path,
        restore_scroll=true,
        review_original?=doc.quick_diff_original(),
        diff?=doc.visible_diff(),
        search_highlights?,
      )
      if sync_diagnostics &&
        language_id(doc.name) == "moonbit" &&
        ctx.root() is Some(root) {
        @cmd.batch([
          show,
          request_diagnostics(
            dispatch,
            ctx.owner,
            ctx.request_epoch,
            root,
            path,
            absolute,
          ),
        ])
      } else {
        show
      }
    }
    // A deleted change, or a transiently unreadable working file, can still
    // have a useful textual HEAD side. Show that baseline under explicit
    // review chrome; other unavailable cases use the panel notice overlay.
    TabDeleted | TabReadFailed(_) =>
      match doc.review {
        Some({ baseline: ReviewContent(content), .. }) =>
          show_file_in_viewer(
            ctx.owner,
            root=ctx.root(),
            doc.name,
            content,
            relative=path,
            restore_scroll=true,
            diff?=doc.visible_diff(),
            search_highlights?,
          )
        _ => clear_document()
      }
    TabBinary | TabOversized | TabUnavailable(_) => clear_document()
  }
  // A document that went stale in the background (or was deleted and
  // reappeared) shows what it has and reloads in the same breath; the reply
  // lands with the scroll kept in place.
  if reload_stale &&
    doc.stale &&
    !(doc.state is TabLoading) &&
    doc.review is None {
    @cmd.batch([
      show,
      read_file(
        dispatch,
        ctx.owner,
        ctx.request_epoch,
        path,
        doc.name,
        review_generation?=doc.review_generation(),
        range=None,
        root=ctx.root(),
      ),
    ])
  } else {
    show
  }
}

///|
fn show_tab(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  search_highlights : @grep_search.EditorHighlights?,
  path : @pathx.Relative,
  doc : Doc,
) -> @cmd.Cmd {
  show_tab_impl(dispatch, ctx, search_highlights, path, doc, true, true)
}

///|
/// Publish a newly settled HEAD side without treating it as another document
/// activation. The working file was already shown (and its diagnostics were
/// already requested) when its read settled; this pass only updates the
/// quick-diff baseline or the deleted/unavailable preview.
fn show_settled_review(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  search_highlights : @grep_search.EditorHighlights?,
  path : @pathx.Relative,
  doc : Doc,
) -> @cmd.Cmd {
  show_tab_impl(dispatch, ctx, search_highlights, path, doc, true, false)
}

///|
/// Keep cached working text visible while a paired review reload owns the next
/// content and diagnostics refresh. This pass only clears the previous gutter;
/// it must neither start a duplicate file read nor another full `moon check`.
fn show_pending_review(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  search_highlights : @grep_search.EditorHighlights?,
  path : @pathx.Relative,
  doc : Doc,
) -> @cmd.Cmd {
  show_tab_impl(dispatch, ctx, search_highlights, path, doc, false, false)
}

///|
/// Show an activated document and, for a stale review, start a uniquely
/// fenced working-tree reload. `show_tab` intentionally reloads stale ordinary
/// documents only: review callers must also persist the advanced token that
/// makes an older in-flight reply harmless.
fn show_activated_tab(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  search_highlights : @grep_search.EditorHighlights?,
  path : @pathx.Relative,
  doc : Doc,
  generation : Int,
) -> (@cmd.Cmd, Doc, Int) {
  guard doc.stale &&
    !(doc.state is TabLoading) &&
    doc.review is Some(review) &&
    review.selected.has_working_tree_file() else {
    return (
      show_tab(dispatch, ctx, search_highlights, path, doc),
      doc,
      generation,
    )
  }
  let working_generation = generation + 1
  let next_doc = { ..doc, review: Some({ ..review, working_generation, }), }
  (
    @cmd.batch([
      show_pending_review(dispatch, ctx, search_highlights, path, next_doc),
      read_file(
        dispatch,
        ctx.owner,
        ctx.request_epoch,
        path,
        doc.name,
        review_generation=working_generation,
        range=None,
        root=ctx.root(),
      ),
    ]),
    next_doc,
    working_generation,
  )
}

///|
/// Open `path`'s document — the file half of a tree click, a chip jump, or
/// a dock activation of a not-yet-open file. The dock half (which tab is in
/// the strip and active) has already happened in the root update, so
/// `ctx.active_file` names this path; `had_active` says whether a file tab
/// was on screen before the transition (gaining the first one reveals the
/// breadcrumb row, which needs a viewer remeasure). A plain re-open of an
/// already-loaded document shows what the table has, exactly like a
/// tab-strip click; everything else reads the file — so a jump's
/// `range`/`annotation` ride the reply to be revealed on arrival. A positioned
/// Every explicit navigation is echoed through `file_link_generation` so only
/// the newest one can apply its position to the Viewer. A transcript link
/// supplies the generation captured before its host lookup; direct file,
/// symbol, and mention opens use the current generation. An older reply may
/// still finish a loading document, but without its position.
pub fn open_document(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  name~ : String,
  file_link_generation? : Int,
  range~ : @common.Range?,
  annotation? : String,
  had_active~ : Bool,
) -> (@cmd.Cmd, State) {
  guard ctx.placement_ready() else { return (@cmd.none, state) }
  let state = { ..state, highlighted: None, }
  // Opening the path from Files, Quick Open, navigation, or a mention leaves
  // review mode. If the same Viewer model stays attached, the show below
  // clears its resource-keyed quick-diff baseline without replacing content.
  let state = match state.docs.get(path) {
    Some({ review: Some(_), .. }) => {
      let docs = state.docs.copy()
      let doc = docs[path]
      docs[path] = { ..doc, review: None, }
      { ..state, docs, }
    }
    _ => state
  }
  // A position-bearing open (Search, go-to-definition, or an annotation
  // jump) needs a visible text model so its range can be revealed. Plain file
  // and tab opens retain this tab's explicit selection, with Diagram as the
  // default for a newly opened `.mbti`.
  let state = if uses_mbti_presentation(name) &&
    (range is Some(_) || annotation is Some(_)) {
    let mbti_view_modes = state.mbti_view_modes.copy()
    mbti_view_modes[path] = MbtiSource
    { ..state, mbti_view_modes, }
  } else {
    state
  }
  let clear_review = if ctx.active_file == Some(path) {
    // Always clear the displayed resource, even when this path has no cached
    // `Doc`: a reviewed tab can be closed while another dock kind is active,
    // leaving its hidden Viewer model alive until the next file opens. Do not
    // wait for the ordinary read below, which can fail and deliberately leave
    // that model on screen.
    clear_quick_diff_baseline()
  } else {
    @cmd.none
  }
  // The plain-activation case must not rely on the read's reply to switch
  // the document: `FileLoaded`'s identical-content dedup assumes the reply's
  // document is the one on screen, so a re-read of an unchanged file would
  // skip the redraw and leave the previous tab's document showing. Withheld,
  // unavailable, and deleted documents still fall through to the read — a
  // tree click is the explicit re-open that refreshes them (see `TabState`).
  if range is None &&
    annotation is None &&
    state.docs.get(path) is Some(doc) &&
    !(doc.state
    is (TabBinary
    | TabOversized
    | TabReadFailed(_)
    | TabUnavailable(_)
    | TabDeleted)) {
    let show = show_tab(
      dispatch,
      ctx,
      state.editor_search_highlights(path),
      path,
      doc,
    )
    // Gaining the first active tab reveals the breadcrumb row, and the
    // narrow drill-down closing the tree reveals a viewer that was last
    // measured while hidden — both need a remeasure alongside the show.
    let cmd = if !had_active || (state.tree_open && ctx.narrow) {
      @cmd.batch([clear_review, show, request_viewer_remeasure()])
    } else {
      @cmd.batch([clear_review, show])
    }
    return (
      cmd,
      { ..state, error: None, tree_open: state.tree_open && !ctx.narrow, },
    )
  }
  let docs = state.docs.copy()
  match docs.get(path) {
    None =>
      docs[path] = { name, state: TabLoading, review: None, stale: false, }
    Some(doc) if doc.state is TabUnavailable(_) =>
      // An explicit ordinary open is the retry boundary for a path Git had
      // classified as a non-file entry. Leave that sentinel before starting
      // the read so its reply is distinguishable from an older in-flight read.
      docs[path] = { name, state: TabLoading, review: None, stale: false, }
    _ => ()
  }
  // Direct file/symbol/mention opens arrive without a captured transcript
  // generation, but root already advanced the same navigation token before
  // calling us. Tag their reads too: a newer ordinary failure must remain
  // authoritative over an older positioned success for this path.
  let read_generation = Some(
    file_link_generation.unwrap_or(state.file_link_generation),
  )
  let read = read_file(
    dispatch,
    ctx.owner,
    ctx.request_epoch,
    path,
    name,
    file_link_generation?=read_generation,
    range~,
    annotation?,
    root=ctx.root(),
  )
  // Gaining the first active tab reveals the breadcrumb row, and the narrow
  // drill-down closing the tree reveals a hidden-measured viewer — either
  // way the viewer must remeasure before the reply's document lands.
  let cmd = if !had_active || (state.tree_open && ctx.narrow) {
    @cmd.batch([clear_review, read, request_viewer_remeasure()])
  } else {
    @cmd.batch([clear_review, read])
  }
  (
    cmd,
    { ..state, docs, error: None, tree_open: state.tree_open && !ctx.narrow, },
  )
}

///|
/// Open one row from Changes as a review. Existing working-tree files load
/// through the ordinary reader while HEAD loads independently; whichever
/// reply wins is parked on the same document and the late side completes the
/// Viewer in place. Deleted paths skip the guaranteed-failing filesystem read
/// and show their textual HEAD blob when it arrives.
pub fn open_changed_document(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  change : ChangedFile,
  had_active~ : Bool,
) -> (@cmd.Cmd, State) {
  guard ctx.placement_ready() && change.selectable() else {
    return (@cmd.none, state)
  }
  let state = { ..state, highlighted: None, }
  let path = change.path
  // Selecting a Changes row is activation, not a manual reload. Reuse the
  // exact cached review (including one whose paired reads are still pending)
  // so repeated clicks cannot replace its generation, clear its DiffEditor
  // models, and briefly paint an empty comparison. Exact row identity matters:
  // Git can legitimately expose two different reviews for the same path.
  if state.docs.get(path) is Some(doc) &&
    doc.review is Some({ selected, .. }) &&
    selected == change {
    let (show, next_doc, review_generation) = show_activated_tab(
      dispatch,
      ctx,
      state.editor_search_highlights(path),
      path,
      doc,
      state.review_generation,
    )
    let docs = state.docs.copy()
    docs[path] = next_doc
    let cmds = [show, delayed_diff_loading(dispatch, ctx.owner, path, next_doc)]
    if !had_active || (state.tree_open && ctx.narrow) {
      cmds.push(request_viewer_remeasure())
    }
    return (
      @cmd.batch(cmds),
      {
        ..state,
        docs,
        review_generation,
        error: None,
        tree_open: state.tree_open && !ctx.narrow,
      },
    )
  }
  let name = basename(path)
  let generation = state.review_generation + 1
  let docs = state.docs.copy()
  let doc_state = if change.has_working_tree_file() {
    // Keep a real document on screen while both refreshes run. Besides
    // avoiding a blank/loading flash, `FileLoaded` then recognizes a reload
    // and restores the tab's scroll position. Other states need the fresh
    // read before they can become a working document.
    match docs.get(path) {
      Some({ state: TabLoaded(content~, absolute~, sig~), .. }) =>
        TabLoaded(content~, absolute~, sig~)
      _ => TabLoading
    }
  } else {
    TabDeleted
  }
  let missing_rename_source = change.kind is (ChangeRenamed | ChangeCopied) &&
    change.original_path is None
  let baseline = if missing_rename_source {
    ReviewFailed("the original path is outside this workspace")
  } else {
    ReviewLoading
  }
  let review_doc = {
    name,
    state: doc_state,
    review: Some({
      generation,
      working_generation: generation,
      baseline,
      view_mode: state.review_view_mode,
      selected: change,
    }),
    // A cached document can already be behind the filesystem when the row is
    // selected. Keep that fact until the tagged working-tree read settles: if
    // an ordinary open cancels this review first, `show_tab` must still issue
    // its own untagged refresh instead of blessing the cached text as current.
    stale: if change.has_working_tree_file() {
      docs.get(path).map(doc => doc.stale).unwrap_or(false)
    } else {
      false
    },
  }
  docs[path] = review_doc
  let cmds = []
  if !missing_rename_source {
    let source = change.original_path.unwrap_or(path)
    cmds.push(
      read_git_original(
        dispatch,
        ctx.owner,
        path,
        source,
        generation,
        revision=state.changes_head,
        workspace=ctx.workspace(),
      ),
    )
  }
  if change.has_working_tree_file() {
    if doc_state is TabLoaded(..) {
      // Clear a previous review baseline immediately while keeping the cached
      // working document and view state; the new HEAD side fills in later.
      // The tagged read below is the sole refresh owner, so this command only
      // displays the cached document instead of scheduling a duplicate reload.
      cmds.push(
        show_pending_review(
          dispatch,
          ctx,
          state.editor_search_highlights(path),
          path,
          review_doc,
        ),
      )
    } else {
      // The Viewer can still contain the previously active reviewed document.
      // The dock has already switched to this uncached path, so clear the
      // outgoing document while its tagged working-tree read is pending. Use
      // the same review-loading presentation path as later activations so the
      // old source, navigation context, and gutter all disappear together.
      cmds.push(
        show_pending_review(
          dispatch,
          ctx,
          state.editor_search_highlights(path),
          path,
          review_doc,
        ),
      )
    }
    cmds.push(
      read_file(
        dispatch,
        ctx.owner,
        ctx.request_epoch,
        path,
        name,
        review_generation=generation,
        range=None,
        root=ctx.root(),
      ),
    )
  } else {
    // Remove an earlier working document immediately; the notice covers the
    // Viewer until the HEAD side settles.
    cmds.push(clear_document())
  }
  cmds.push(delayed_diff_loading(dispatch, ctx.owner, path, review_doc))
  if !had_active || (state.tree_open && ctx.narrow) {
    cmds.push(request_viewer_remeasure())
  }
  (
    @cmd.batch(cmds),
    {
      ..state,
      docs,
      review_generation: generation,
      error: None,
      tree_open: state.tree_open && !ctx.narrow,
    },
  )
}

///|
/// Find the refreshed form of the exact Changes row that opened a review.
/// Git may emit multiple rows with the same destination path, so prefer the
/// original porcelain identity, then progressively weaker *unique* matches.
/// An ambiguous result exits review mode instead of silently switching sides.
fn selected_review_change(
  files : Array[ChangedFile],
  previous_files : Array[ChangedFile],
  selected : ChangedFile,
) -> ChangedFile? {
  let candidates = files.filter(change => change.path == selected.path)
  for change in candidates {
    if change == selected {
      return Some(change)
    }
  }
  let mut status_match : ChangedFile? = None
  let mut status_matches = 0
  for change in candidates {
    if change.original_path == selected.original_path &&
      change.index_status == selected.index_status &&
      change.worktree_status == selected.worktree_status {
      status_match = Some(change)
      status_matches += 1
    }
  }
  if status_matches == 1 {
    return status_match
  }
  let selected_source = if selected.kind is (ChangeRenamed | ChangeCopied) {
    selected.original_path
  } else {
    Some(selected.path)
  }
  let mut input_match : ChangedFile? = None
  let mut input_matches = 0
  for change in candidates {
    let source = if change.kind is (ChangeRenamed | ChangeCopied) {
      change.original_path
    } else {
      Some(change.path)
    }
    if source == selected_source &&
      change.has_working_tree_file() == selected.has_working_tree_file() {
      input_match = Some(change)
      input_matches += 1
    }
  }
  if input_matches == 1 {
    return input_match
  }
  let mut availability_match : ChangedFile? = None
  let mut availability_matches = 0
  for change in candidates {
    if change.has_working_tree_file() == selected.has_working_tree_file() {
      availability_match = Some(change)
      availability_matches += 1
    }
  }
  if availability_matches == 1 {
    return availability_match
  }
  if candidates.length() == 1 &&
    previous_files.filter(change => change.path == selected.path).length() <= 1 {
    // A sole row can legitimately cross the working-file boundary (modified
    // to deleted, or deleted back to modified). It is only safe to infer that
    // transition when the previous authoritative inventory did not contain a
    // competing same-path row whose disappearance made the identity ambiguous.
    Some(candidates[0])
  } else {
    None
  }
}

///|
/// A baseline may be cached before its paired working-tree read settles. Do
/// not publish it against a document already known to be stale: the tagged
/// `FileLoaded` reply clears that marker and performs the first safe render.
fn working_side_ready_for_review(doc : Doc) -> Bool {
  !(doc.state is TabLoading) && !doc.stale
}

///|
/// Reconcile parked reviews only against a final changed-file snapshot. Rows
/// that disappeared (or became non-textual) leave review mode. When HEAD, the
/// rename source, or working-file availability changed, surviving rows receive
/// a new generation and fresh HEAD read. The first authoritative snapshot
/// after a missing-checkout recovery also restarts an incomplete side once so
/// a reply discarded at that boundary cannot strand the document in loading.
/// Every vanished row gets one post-review stat: without a working watcher, a
/// commit can otherwise leave cached source visible after the file disappeared
/// or changed, while an earlier ignored same-path signature can strand a clean
/// restoration as deleted. A loading side also receives an ordinary read so
/// its now-superseded tagged review reply cannot strand the tab in loading.
fn reconcile_reviews_after_changes(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  previous_files : Array[ChangedFile],
  files : Array[ChangedFile],
  head~ : String?,
  head_changed~ : Bool,
  restart_incomplete~ : Bool,
) -> (Array[@cmd.Cmd], Map[@pathx.Relative, Doc], Int) {
  let docs = state.docs.copy()
  let cmds : Array[@cmd.Cmd] = []
  let restat_paths : Array[@pathx.Relative] = []
  let mut review_generation = state.review_generation
  for path, doc in state.docs {
    guard doc.review is Some(review) else { continue }
    let current_change = selected_review_change(
      files,
      previous_files,
      review.selected,
    )
    match current_change {
      None => {
        let ordinary = { ..doc, review: None, }
        docs[path] = ordinary
        // Git polling is also the fallback when the filesystem watcher is not
        // available. Re-stat every vanished review before trusting its cached
        // ordinary state. A review-loading document additionally needs an
        // untagged replacement read: its tagged reply is fenced out as soon as
        // review mode is cleared.
        restat_paths.push(path)
        if doc.state is TabLoading && ctx.active_file != Some(path) {
          cmds.push(
            read_file(
              dispatch,
              ctx.owner,
              ctx.request_epoch,
              path,
              doc.name,
              range=None,
              root=ctx.root(),
            ),
          )
        }
        if ctx.active_file == Some(path) {
          cmds.push(
            show_tab(
              dispatch,
              ctx,
              state.editor_search_highlights(path),
              path,
              ordinary,
            ),
          )
        }
      }
      Some(change) if !change.selectable() => {
        // The cached text belongs to an earlier regular file. Git now proves
        // the path is something the file reader deliberately will not follow,
        // so clear that text and retain an explicit notice until the user
        // reopens the path after it changes back.
        let ordinary = {
          ..doc,
          state: TabUnavailable(change.unselectable_title()),
          review: None,
          stale: false,
        }
        docs[path] = ordinary
        if ctx.active_file == Some(path) {
          cmds.push(
            show_tab(
              dispatch,
              ctx,
              state.editor_search_highlights(path),
              path,
              ordinary,
            ),
          )
        }
      }
      Some(change) => {
        // Only an explicit missing-checkout recovery may invalidate a healthy
        // in-flight read without changing HEAD or row metadata. Ordinary
        // three-second polls leave slow requests alone instead of repeatedly
        // superseding their generation.
        let review_incomplete = restart_incomplete &&
          (
            doc.state is TabLoading ||
            doc.review is Some({ baseline: ReviewLoading, .. })
          )
        let review_inputs_changed = review_incomplete ||
          head_changed ||
          ({
            let previous_source = if review.selected.kind
              is (ChangeRenamed | ChangeCopied) {
              review.selected.original_path
            } else {
              Some(review.selected.path)
            }
            let source = if change.kind is (ChangeRenamed | ChangeCopied) {
              change.original_path
            } else {
              Some(change.path)
            }
            previous_source != source ||
            review.selected.has_working_tree_file() !=
            change.has_working_tree_file()
          })
        if !review_inputs_changed {
          if review.selected != change {
            docs[path] = {
              ..doc,
              review: Some({ ..review, selected: change, }),
            }
          }
          continue
        }
        review_generation += 1
        let generation = review_generation
        let has_working_file = change.has_working_tree_file()
        let missing_rename_source = change.kind
          is (ChangeRenamed | ChangeCopied) &&
          change.original_path is None
        let baseline = if missing_rename_source {
          ReviewFailed("the original path is outside this workspace")
        } else {
          ReviewLoading
        }
        // Every new baseline generation owns a new working-tree read too.
        // Keeping a loaded state here would let the older tagged read be
        // rejected while the refreshed HEAD side settles against stale text.
        let refreshed_state = if has_working_file {
          TabLoading
        } else {
          TabDeleted
        }
        let refreshed = {
          ..doc,
          state: refreshed_state,
          review: Some({
            generation,
            working_generation: generation,
            baseline,
            view_mode: review.view_mode,
            selected: change,
          }),
          stale: if has_working_file {
            doc.stale
          } else {
            false
          },
        }
        docs[path] = refreshed
        if !missing_rename_source {
          let source = change.original_path.unwrap_or(path)
          cmds.push(
            read_git_original(
              dispatch,
              ctx.owner,
              path,
              source,
              generation,
              revision=head,
              workspace=ctx.workspace(),
            ),
          )
        }
        if has_working_file {
          if ctx.active_file == Some(path) && !(doc.state is TabLoading) {
            // Keep the previous working text visible while its replacement is
            // in flight, but clear the old gutter until both new sides settle.
            cmds.push(
              show_pending_review(
                dispatch,
                ctx,
                state.editor_search_highlights(path),
                path,
                { ..refreshed, state: doc.state, },
              ),
            )
          }
          cmds.push(
            read_file(
              dispatch,
              ctx.owner,
              ctx.request_epoch,
              path,
              doc.name,
              review_generation=generation,
              range=None,
              root=ctx.root(),
            ),
          )
        } else if ctx.active_file == Some(path) {
          // Clear the old gutter immediately while the new HEAD side loads;
          // deleted previews switch back to their precise loading notice.
          cmds.push(
            show_tab(
              dispatch,
              ctx,
              state.editor_search_highlights(path),
              path,
              refreshed,
            ),
          )
        }
      }
    }
  }
  if !restat_paths.is_empty() {
    cmds.push(
      stat_files(
        dispatch,
        ctx.owner,
        state.request_epoch,
        restat_paths,
        root=ctx.root(),
      ),
    )
  }
  (cmds, docs, review_generation)
}

///|
/// Open (or refocus) `path`'s document for a composer chip's or transcript
/// chip's jump, after the main package has relativized the raw path and
/// opened the dock tab. Ensures the viewer is mounted, since the jump may be
/// what opens the panel.
pub fn open_file(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  file_link_generation? : Int,
  range~ : @common.Range?,
  annotation? : String,
  had_active~ : Bool,
) -> (@cmd.Cmd, State) {
  let (cmd, state) = open_document(
    dispatch,
    state,
    ctx,
    path,
    name=basename(path),
    file_link_generation?,
    range~,
    annotation?,
    had_active~,
  )
  (@cmd.batch([mount_cmds(dispatch), cmd]), state)
}

///|
/// Show `path`'s document after the dock switched its active tab to it — a
/// tab-strip click. The document is expected in the table; a missing entry
/// (a stale click racing a close) is a no-op.
pub fn activate(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
) -> (@cmd.Cmd, State) {
  guard ctx.placement_ready() && state.docs.get(path) is Some(doc) else {
    return (@cmd.none, state)
  }
  let state = { ..state, highlighted: None, }
  let (show, doc, review_generation) = show_activated_tab(
    dispatch,
    ctx,
    state.editor_search_highlights(path),
    path,
    doc,
    state.review_generation,
  )
  let docs = state.docs.copy()
  docs[path] = doc
  // The narrow drill-down closing the tree reveals a viewer that was last
  // measured while hidden; it must remeasure with the show.
  let cmd = if state.tree_open && ctx.narrow {
    @cmd.batch([show, request_viewer_remeasure()])
  } else {
    show
  }
  (
    cmd,
    {
      ..state,
      docs,
      review_generation,
      error: None,
      tree_open: state.tree_open && !ctx.narrow,
    },
  )
}

///|
/// Drop `path`'s document after its dock tab closed. `next`, when the closed
/// tab owned the screen, is the file the dock promoted (`None` when the
/// strip emptied — the viewer falls back to the placeholder, and the tree is
/// forced open so the panel is never a dead pane). The closed document's
/// parked scroll is forgotten after the neighbor's show re-parks the
/// outgoing document.
pub fn close_document(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  next~ : @pathx.Relative?,
  was_active~ : Bool,
) -> (@cmd.Cmd, State) {
  let docs = state.docs.copy()
  docs.remove(path)
  let mbti_view_modes = state.mbti_view_modes.copy()
  mbti_view_modes.remove(path)
  let state = { ..state, mbti_view_modes, }
  // Closing a tab is useful local state even while placement is parked, but
  // promoting its neighbor must not address the missing checkout. Recovery's
  // sync pass restores whichever surviving tab the dock made active.
  if !ctx.placement_ready() {
    let state = {
      ..state,
      docs,
      tree_open: if was_active && next is None {
        true
      } else {
        state.tree_open
      },
    }
    let cmd = if was_active && next is None {
      @cmd.batch([
        clear_document(),
        forget_view_state(path),
        request_viewer_remeasure(),
      ])
    } else {
      forget_view_state(path)
    }
    return (cmd, state)
  }
  guard was_active else { return (forget_view_state(path), { ..state, docs, }) }
  match next {
    Some(next_path) =>
      if docs.get(next_path) is Some(doc) {
        let (show, doc, review_generation) = show_activated_tab(
          dispatch,
          ctx,
          state.editor_search_highlights(next_path),
          next_path,
          doc,
          state.review_generation,
        )
        docs[next_path] = doc
        (
          @cmd.batch([show, forget_view_state(path)]),
          { ..state, docs, review_generation, },
        )
      } else {
        (forget_view_state(path), { ..state, docs, })
      }
    // The last tab: fall back to the placeholder and force the tree open so
    // the panel is never a dead pane. Losing the active tab also hides the
    // breadcrumb row, so the viewer must remeasure.
    None =>
      (
        @cmd.batch([
          clear_document(),
          forget_view_state(path),
          request_viewer_remeasure(),
        ]),
        { ..state, docs, tree_open: true, },
      )
  }
}

///|
/// Reattach and show the active document when the panel opens. The Viewer can
/// have been cleared while the dock was hidden (notably when a missing checkout
/// was repaired), so every open activation restores it rather than assuming a
/// loaded cached document is still attached. `activate` also advances a stale
/// review's working-side token before starting its replacement read.
pub fn panel_toggle_cmds(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  opening~ : Bool,
) -> (@cmd.Cmd, State) {
  let cmds = [mount_cmds(dispatch)]
  let state = if opening && ctx.active_file is Some(path) {
    let (show, state) = activate(dispatch, state, ctx, path)
    cmds.push(show)
    state
  } else {
    state
  }
  (@cmd.batch(cmds), state)
}

///|
/// Whether this event can change the file currently addressed by `path`.
/// Structural directory events cover every descendant; a content modification
/// applies only to the exact file returned by the watcher.
fn FileChange::touches(self : FileChange, path : @pathx.Relative) -> Bool {
  match self {
    Modified(changed) => changed == path
    Created(changed) | Removed(changed) => changed.contains(path)
    Renamed(old~, new~) => old.contains(path) || new.contains(path)
  }
}

///|
/// The directory containing `path`; a root-level entry belongs to `""`.
fn FileChange::parent(path : @pathx.Relative) -> @pathx.Relative {
  let segments = [..path.0.split("/")]
  ignore(segments.pop())
  Relative(segments.join("/"))
}

///|
/// Listed directories whose immediate rows may have changed. A created or
/// renamed destination is included too so a directory that disappeared and
/// later returned does not reuse stale cached children.
fn FileChange::relist_candidates(self : FileChange) -> Array[@pathx.Relative] {
  match self {
    Modified(_) => []
    Created(path) => [FileChange::parent(path), path]
    Removed(path) => [FileChange::parent(path)]
    Renamed(old~, new~) =>
      [FileChange::parent(old), FileChange::parent(new), new]
  }
}

///|
/// Content-only edits preserve the workspace path set. Structural changes
/// below a directory excluded by file discovery cannot affect its snapshot;
/// a rename still matters when either side crosses that policy boundary.
fn FileChange::changes_file_list(self : FileChange) -> Bool {
  match self {
    Modified(_) => false
    Created(path) | Removed(path) =>
      !@file_search_policy.excludes_descendant(path.0)
    Renamed(old~, new~) =>
      !@file_search_policy.excludes_descendant(old.0) ||
      !@file_search_policy.excludes_descendant(new.0)
  }
}

///|
/// Whether the change involves a path that feeds `moon check` — a source or
/// interface file, or a module/package manifest. Only these can move the
/// module's diagnostics.
fn FileChange::moonbit_relevant(self : FileChange) -> Bool {
  match self {
    Modified(path) | Created(path) | Removed(path) => moonbit_check_input(path)
    Renamed(old~, new~) => moonbit_check_input(old) || moonbit_check_input(new)
  }
}

///|
/// The diagnostics request for the active file when it is a loaded MoonBit
/// document, or `None` when it is anything else — the shared trigger behind
/// the stats, watcher, and run-finish re-check paths.
fn active_moonbit_diagnostics(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  epoch : Int,
  root : @common.Uri?,
  docs : Map[@pathx.Relative, Doc],
  active : @pathx.Relative?,
) -> @cmd.Cmd? {
  guard root is Some(root) &&
    active is Some(active) &&
    docs.get(active) is Some({ name, state: TabLoaded(absolute~, ..), .. }) &&
    language_id(name) == "moonbit" else {
    return None
  }
  Some(request_diagnostics(dispatch, owner, epoch, root, active, absolute))
}

///|
fn moonbit_check_input(path : @pathx.Relative) -> Bool {
  let text = path.0
  if text.has_suffix(".mbt") ||
    text.has_suffix(".mbti") ||
    text.has_suffix(".mbt.md") {
    return true
  }
  for
    name in [
      "moon.pkg", "moon.mod", "moon.work", "moon.pkg.json", "moon.mod.json",
    ] {
    if text == name || text.has_suffix("/" + name) {
      return true
    }
  }
  false
}

///|
/// Mark a ready snapshot stale after a structural watcher event. The Bool
/// tells the caller to start the single allowed refresh; later events only
/// latch one follow-up while that request is in flight.
fn FileIndex::invalidate(self : FileIndex) -> (FileIndex, Bool) {
  match self {
    IndexLoading(refresh_again=false) =>
      (IndexLoading(refresh_again=true), false)
    IndexLoading(refresh_again=true) => (self, false)
    IndexReady(files~, truncated~, refreshing=false, ..) =>
      (
        IndexReady(files~, truncated~, refreshing=true, refresh_again=false),
        true,
      )
    IndexReady(files~, truncated~, refreshing=true, ..) =>
      (
        IndexReady(files~, truncated~, refreshing=true, refresh_again=true),
        false,
      )
    _ => (self, false)
  }
}

///|
/// Settle a successful Host scan. The Bool asks the caller to spend a watcher
/// event that arrived while the completed request was running.
fn FileIndex::loaded(
  self : FileIndex,
  files : Array[@pathx.Relative],
  truncated : Bool,
) -> (FileIndex, Bool) {
  match self {
    IndexLoading(refresh_again~) =>
      (
        IndexReady(
          files~,
          truncated~,
          refreshing=refresh_again,
          refresh_again=false,
        ),
        refresh_again,
      )
    IndexReady(refreshing=true, refresh_again~, ..) =>
      (
        IndexReady(
          files~,
          truncated~,
          refreshing=refresh_again,
          refresh_again=false,
        ),
        refresh_again,
      )
    _ => (self, false)
  }
}

///|
/// Settle a failed Host scan. Initial failure is retryable from empty; a
/// background failure retains the previous snapshot and any coalesced retry.
/// If its one immediate retry was already spent, keep a stale latch for the
/// next consumer instead of retrying forever or making the snapshot permanent.
fn FileIndex::failed(self : FileIndex) -> (FileIndex, Bool) {
  match self {
    IndexLoading(..) => (IndexFailed, false)
    IndexReady(files~, truncated~, refreshing=true, refresh_again~) =>
      (
        IndexReady(
          files~,
          truncated~,
          refreshing=refresh_again,
          refresh_again=!refresh_again,
        ),
        refresh_again,
      )
    _ => (self, false)
  }
}

///|
/// Reconcile the Host watcher with the panel, open tabs, and the workspace
/// snapshot. A live index asks the Host to retain non-ignored descendants even
/// while the panel is hidden, so empty directories and paths beyond the
/// bounded result can still invalidate the cached path set.
fn State::watched_paths(self : State, ctx : Ctx) -> WatchedPaths? {
  guard ctx.root() is Some(root) else { return None }
  let index_live = self.index is IndexLoading(..) ||
    self.index is IndexReady(..)
  if ctx.placement is None ||
    ctx.placement is Some(@interop.MissingWorktree(..)) ||
    (!ctx.panel_open && ctx.open_files.is_empty() && !index_live) ||
    ctx.owner.session.is_empty() {
    return None
  }
  let files = ctx.open_files.copy()
  files.sort_by((left, right) => left.0.lexical_compare(right.0))
  let recursive = index_live
  let files = if recursive {
    files.filter(path => @file_search_policy.excludes_directory(path.0))
  } else {
    files
  }
  let directories = if ctx.panel_open {
    let directories = []
    if !directories.contains(@pathx.Relative::root()) {
      directories.push(@pathx.Relative::root())
    }
    for directory in self.expanded {
      if !directories.contains(directory) {
        directories.push(directory)
      }
    }
    if self.highlighted is Some(directory) && !directories.contains(directory) {
      directories.push(directory)
    }
    directories.sort_by((left, right) => left.0.lexical_compare(right.0))
    if recursive {
      directories.filter(path => @file_search_policy.excludes_directory(path.0))
    } else {
      directories
    }
  } else {
    []
  }
  Some({ owner: ctx.owner, root, files, directories, recursive, })
}

///|
/// The opaque token echoed by host watcher notifications. The namespace keeps
/// the counter unique across frontend reloads.
fn Ctx::watch_identity(self : Ctx, generation : Int) -> String {
  self.watch_namespace + ":" + generation.to_string()
}

///|
fn with_watch(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  cmd : @cmd.Cmd,
) -> (State, @cmd.Cmd) {
  let want = state.watched_paths(ctx)
  if state.watching == want {
    (state, cmd)
  } else {
    let commands = [cmd]
    // Every effective configuration gets one identity for both baseline/change
    // events and later watcher failures. Recursive selections are normalized
    // by `watched_paths`, so an equivalent Host watcher is never renamed while
    // it is active. A real replacement emits a full baseline before its
    // request succeeds, closing the old-to-new observation gap.
    let watch_generation = state.watch_generation + 1
    let watch_identity = ctx.watch_identity(watch_generation)
    // A watcher is host-local. Moving across channels must explicitly retire
    // the old host; placing a new watch on another socket cannot replace it.
    if state.watching is Some(current) &&
      (
        want is None ||
        (want is Some(next) && current.owner.channel != next.owner.channel)
      ) {
      commands.push(
        watch_workspace(
          dispatch,
          channel=current.owner.channel,
          generation=watch_identity,
          None,
        ),
      )
    }
    if want is Some(next) {
      commands.push(
        watch_workspace(
          dispatch,
          channel=next.owner.channel,
          generation=watch_identity,
          Some(next),
        ),
      )
    }
    (
      { ..state, watching: want, watch_generation, watch_error: None, },
      @cmd.batch(commands),
    )
  }
}

///|
/// Park this panel's watcher on its current Host connection before another
/// device takes focus. Keeping the old owner/root state intact lets the normal
/// sync pass retire its file-index cache at the same boundary.
pub fn State::retire_watcher(
  self : State,
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  guard self.watching is Some(current) else { return (self, @cmd.none) }
  let watch_generation = self.watch_generation + 1
  let watch_identity = ctx.watch_identity(watch_generation)
  (
    { ..self, watching: None, watch_generation, watch_error: None, },
    watch_workspace(
      dispatch,
      channel=current.owner.channel,
      generation=watch_identity,
      None,
    ),
  )
}

///|
const ChangesPollIntervalMilliseconds = 3000

///|
fn explorer_visible(state : State, ctx : Ctx) -> Bool {
  ctx.panel_open &&
  (
    state.tree_open ||
    (ctx.active_file is None && ctx.active_history_diff is None)
  )
}

///|
fn changes_visible(state : State, ctx : Ctx) -> Bool {
  explorer_visible(state, ctx) && state.explorer_mode is ExplorerChanges
}

///|
/// A hidden explorer normally parks its Git inventory, but an open review is
/// still rendering against that inventory's comparison identity. Keep the
/// low-rate refresh alive until every reviewed document is closed or ordinarily
/// reopened.
fn changes_live(state : State, ctx : Ctx) -> Bool {
  if changes_visible(state, ctx) {
    return true
  }
  for _, doc in state.docs {
    if doc.review is Some(_) {
      return true
    }
  }
  false
}

///|
/// Whether the fallback poll should be running: a settled repository inventory
/// of the current conversation, addressing a checkout that still exists, that
/// something on screen still consumes. This is the sole staleness rule for the
/// poll — it decides both whether the interval exists and whether a tick
/// already in the queue may still act.
///
/// A parked checkout keeps its snapshot and its open reviews on screen so the
/// user can read them until Repair, which is exactly why availability has to be
/// asked separately: a retained inventory is not permission to keep addressing
/// the host that lost it.
fn changes_poll_wanted(state : State, ctx : Ctx) -> Bool {
  ctx.checkout_ready() &&
  state.owner == Some(ctx.owner) &&
  !ctx.owner.session.is_empty() &&
  changes_live(state, ctx) &&
  state.changes is ChangeListReady(repository=true, refreshing=false, ..)
}

///|
/// The low-rate fallback refresh of the changed-file inventory, declared rather
/// than chained. A request issued by a tick flips the snapshot to `refreshing`,
/// which retires this subscription until the reply settles — so the interval
/// restarts from each settle exactly as the old per-settle timer did, and a
/// conversation switch, a hidden explorer, or a superseded request cannot leave
/// a timer running behind the state that armed it.
fn changes_poll_subscription(
  state : State,
  ctx : Ctx,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  guard changes_poll_wanted(state, ctx) else { return @sub.none }
  @sub.every(ChangesPollIntervalMilliseconds, dispatch(ChangesPollDue))
}

///|
/// Declare every subscription owned by the file editor's Explorer. The root
/// supplies one state/context projection; individual inventories decide their
/// own request cadence without re-deriving visibility or checkout identity.
pub fn subscriptions(
  state : State,
  ctx : Ctx,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  @sub.batch([
    changes_poll_subscription(state, ctx, dispatch),
    semantic_review_navigation_subscription(state, ctx, dispatch),
    state.search.subscription(
      ctx.search_input(),
      dispatch.map(msg => Search(msg)),
    ),
  ])
}

///|
/// Whether one concrete watcher batch may have changed either side of this
/// changed-file identity. Rename/copy reviews retain their original path, so
/// edits on that side invalidate progress too.
fn ChangedFile::touched_by(
  self : ChangedFile,
  changes : Array[FileChange],
) -> Bool {
  for change in changes {
    if change.touches(self.path) {
      return true
    }
    if self.original_path is Some(original) && change.touches(original) {
      return true
    }
  }
  false
}

///|
/// A baseline-bearing review cannot trust repeated `head=None` snapshots.
/// New hosts only return that shape for an unborn repository, whose rows are
/// additions/untracked files; an older host also returns it after real commits
/// because it does not know the optional HEAD field. Keep those version-skewed
/// reviews correct by conservatively refreshing them on each settled poll.
fn review_needs_unknown_head_refresh(
  review : ReviewState,
  files : Array[ChangedFile],
) -> Bool {
  match review.baseline {
    // Do not supersede a healthy in-flight baseline solely because an old
    // host cannot identify HEAD; its settled result drives the next poll.
    ReviewLoading => false
    // A genuinely unborn repository gives additions/untracked rows an
    // empty baseline. Old hosts can give the same row real HEAD content,
    // which must be refreshed after a commit removes that baseline.
    ReviewMissing if review.selected.kind is (ChangeAdded | ChangeUntracked) => {
      // A genuinely unborn repository can only expose added/untracked rows.
      // On a legacy host, a transition can retain the exact untracked row
      // while a same-path tracked/deleted row proves that HEAD now owns a
      // baseline. Refresh that case without polling unborn files forever.
      for change in files {
        if change.path == review.selected.path &&
          !(change.kind is (ChangeAdded | ChangeUntracked)) {
          return true
        }
      }
      false
    }
    _ => true
  }
}

///|
/// Older hosts cannot attach an immutable HEAD identity to Changes snapshots.
/// Revalidate only the HEAD side in the background: keep the settled baseline
/// and working document visible, and advance its request token so overlapping
/// polls cannot apply out of order. This retains compatibility correctness
/// without rereading the working file or flashing the gutter every poll.
fn refresh_unknown_head_reviews(
  dispatch : @cmd.Emit[Msg],
  docs : Map[@pathx.Relative, Doc],
  review_generation : Int,
  background_review_requests : Map[@pathx.Relative, Int],
  ctx : Ctx,
  files : Array[ChangedFile],
) -> (
  Array[@cmd.Cmd],
  Map[@pathx.Relative, Doc],
  Int,
  Map[@pathx.Relative, Int],
) {
  let docs = docs.copy()
  let background_review_requests = background_review_requests.copy()
  let cmds = []
  let mut review_generation = review_generation
  for path, doc in docs {
    guard doc.review is Some(review) &&
      review_needs_unknown_head_refresh(review, files) &&
      background_review_requests.get(path) != Some(review.generation) else {
      continue
    }
    let source = if review.selected.kind is (ChangeRenamed | ChangeCopied) {
      match review.selected.original_path {
        Some(source) => source
        None => continue
      }
    } else {
      path
    }
    review_generation += 1
    let generation = review_generation
    docs[path] = { ..doc, review: Some({ ..review, generation, }), }
    background_review_requests[path] = generation
    cmds.push(
      read_git_original(
        dispatch,
        ctx.owner,
        path,
        source,
        generation,
        background=true,
        revision=None,
        workspace=ctx.workspace(),
      ),
    )
  }
  (cmds, docs, review_generation, background_review_requests)
}

///|
/// Start the first changed-file request or refresh an existing snapshot.
/// `refresh_again` latches a watcher/run signal that arrives while a request
/// is in flight. Its reply starts one follow-up request, so bursts coalesce
/// without losing the final workspace state.
fn refresh_changes(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  guard state.owner == Some(ctx.owner) && !ctx.owner.session.is_empty() else {
    return (@cmd.none, state)
  }
  match state.changes {
    ChangeListLoading(refresh_again~) =>
      if refresh_again {
        (@cmd.none, state)
      } else {
        (
          @cmd.none,
          { ..state, changes: ChangeListLoading(refresh_again=true), },
        )
      }
    ChangeListReady(repository~, files~, refreshing~, refresh_again~) =>
      if refreshing {
        if refresh_again {
          (@cmd.none, state)
        } else {
          (
            @cmd.none,
            {
              ..state,
              changes: ChangeListReady(
                repository~,
                files~,
                refreshing~,
                refresh_again=true,
              ),
            },
          )
        }
      } else {
        let generation = state.changes_generation + 1
        (
          list_changes(
            dispatch,
            ctx.owner,
            generation,
            workspace=ctx.workspace(),
          ),
          {
            ..state,
            changes_generation: generation,
            changes: ChangeListReady(
              repository~,
              files~,
              refreshing=true,
              refresh_again=false,
            ),
          },
        )
      }
    ChangeListIdle | ChangeListFailed(_) => {
      let generation = state.changes_generation + 1
      (
        list_changes(dispatch, ctx.owner, generation, workspace=ctx.workspace()),
        {
          ..state,
          changes: ChangeListLoading(refresh_again=false),
          changes_generation: generation,
        },
      )
    }
  }
}

///|
/// Reconcile the file subsystem with the active conversation after every
/// message: rebuild the document table and drop the tree cache when the
/// conversation changed (the dock parks/restores strip identities; this side
/// re-seeds documents from the fresh `Ctx` projection), list the concrete
/// root once its path is known, and keep the host's file watcher pointed at
/// that root. The main update runs this post-dispatch — after the
/// dock's own sync, so the projection is already the new conversation's.
/// The re-root happens whether the panel is open or closed — hidden
/// documents and the watcher must always agree on the root — while
/// listing the tree waits for an open panel. A no-op unless something is
/// actually due, so it never re-fires while a request is in flight or the
/// tree is already current.
pub fn sync(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  let checkout_ready = ctx.checkout_ready()
  let owner_changed = state.owner != Some(ctx.owner)
  // The first owner claim has no previous conversation request to fence and
  // may happen after that owner's initial transcript click. Every later owner
  // replacement is a real navigation boundary.
  let owner_replaced = state.owner is Some(_) && owner_changed
  let same_owner = state.owner == Some(ctx.owner)
  // Missing/unresolved are availability changes, not automatically a new
  // checkout. A live managed worktree and its missing form share the same
  // project/name identity so reviews and dock documents can park and recover;
  // two live values with different roots still force a hard reroot. The
  // comparison reads the retained identity, which a gap keeps (see
  // `ReconciledPlacement`), so a conversation that comes back as a different
  // checkout — another client unbound its worktree while this connection was
  // down — reroots instead of restoring the previous checkout's documents.
  let placement_identity_changed = same_owner &&
    (match (state.placement.identity(), ctx.placement) {
      (Some(previous), Some(current)) => !previous.same_identity(current)
      (None, _) | (Some(_), None) => false
    })
  let parking_existing_owner = !checkout_ready &&
    same_owner &&
    !placement_identity_changed &&
    !state.placement.is_parked()
  let restoring_existing_owner = checkout_ready &&
    same_owner &&
    state.placement.is_parked() &&
    !placement_identity_changed
  // The Host file-search service retains complete snapshots by cache key.
  // Clear the outgoing key exactly when this panel retires its index; keeping
  // it while BridgeReady merely replaces the connection is harmless because
  // that new HostConnection starts with an empty service.
  let retire_index_cmd = if (
      owner_changed || placement_identity_changed || parking_existing_owner
    ) &&
    !(state.index is IndexEmpty) &&
    state.owner is Some(old_owner) &&
    state.placement.identity().bind(value => value.checkout_root())
    is Some(old_root) {
    @files.Request(old_owner.channel, old_owner.session, Some(old_root)).retire()
  } else {
    @cmd.none
  }
  // Every filesystem request in this reconciliation carries the incarnation
  // it addresses. Compute a boundary's next epoch before scheduling any work;
  // the root projection catches up from the returned state on the next pass.
  let request_epoch = if owner_changed ||
    parking_existing_owner ||
    placement_identity_changed {
    state.request_epoch + 1
  } else {
    state.request_epoch
  }
  let ctx = { ..ctx, request_epoch, }
  // A placement-driven explicit unwatch can be the final desired state. Spend
  // its watcher generation here rather than relying on `with_watch` to place
  // a successor, which may legitimately have nothing to watch.
  let reroot_watch_generation = if placement_identity_changed &&
    state.watching is Some(_) {
    state.watch_generation + 1
  } else {
    state.watch_generation
  }
  let reroot_watch_identity = ctx.watch_identity(reroot_watch_generation)
  // When the active conversation changes, drop the cached tree *and* the
  // viewer's open document — the viewer is imperative state outside the
  // model, so it would otherwise keep showing the previous conversation's
  // file. The dock has already parked the outgoing strip and restored this
  // conversation's; the document table is rebuilt from the projection —
  // identities only, every entry `TabLoading` until a read lands. This runs
  // even while the panel is closed: `with_watch` follows `ctx.owner`
  // whenever open files remain, so leaving the documents rooted in the
  // previous conversation would have the next fs_changed stat their paths
  // against the new conversation's root — marking hidden documents
  // deleted/stale for files that never moved.
  let (state, reroot_cmd) = if same_owner && !placement_identity_changed {
    // The real owner remains stable across an unresolved/missing checkout so
    // its review selection survives. Clear the imperative Viewer exactly once
    // at that boundary; the update guard and watcher reconciliation below keep
    // every host-backed action parked until placement is healthy again.
    (state, if parking_existing_owner { clear_viewer() } else { @cmd.none })
  } else {
    let docs : Map[@pathx.Relative, Doc] = Map([])
    for path in ctx.open_files {
      docs[path] = {
        name: basename(path),
        state: TabLoading,
        review: None,
        stale: false,
      }
    }
    let cmds = [clear_viewer()]
    // A workspace or resolved root/worktree transition can leave an otherwise
    // identical watch configuration attached to the old checkout. Explicitly
    // retire it; `with_watch` installs the desired watcher after this reroot.
    if placement_identity_changed && state.watching is Some(current) {
      cmds.push(
        watch_workspace(
          dispatch,
          channel=current.owner.channel,
          generation=reroot_watch_identity,
          None,
        ),
      )
    }
    // A hidden panel's restored active document is not worth a read yet; it
    // stays TabLoading and the panel-open toggle reads it on reopen.
    if checkout_ready &&
      ctx.panel_open &&
      ctx.active_file is Some(path) &&
      docs.contains(path) {
      cmds.push(
        read_file(
          dispatch,
          ctx.owner,
          ctx.request_epoch,
          path,
          basename(path),
          range=None,
          root=ctx.root(),
        ),
      )
    }
    (
      {
        ..State::empty(),
        owner: Some(ctx.owner),
        // A new incarnation must not inherit the identity it replaced, so this
        // reconciles from `PlacementUnknown` rather than the outgoing value.
        placement: PlacementUnknown.reconcile(ctx.placement),
        tree_open: state.tree_open,
        explorer_mode: state.explorer_mode,
        search: state.search.reset_checkout(),
        review_view_mode: state.review_view_mode,
        review_diff_layout: state.review_diff_layout,
        review_diff_mode: state.review_diff_mode,
        review_diff_ignore_comments: state.review_diff_ignore_comments,
        review_diff_ignore_tests: state.review_diff_ignore_tests,
        changes_collapsed: state.changes_collapsed,
        git_graph_collapsed: state.git_graph_collapsed,
        // Request tokens must outlive the per-conversation cache. Resetting
        // here would let a late A reply collide after switching A→B→A.
        changes_generation: if placement_identity_changed {
          state.changes_generation + 1
        } else {
          state.changes_generation
        },
        request_epoch,
        // A late positioned-link reply carries only its owner and this token.
        // Spend a generation on owner replacement and same-owner placement
        // changes so an A→B→A cycle cannot make the old pair current again.
        file_link_generation: if owner_replaced || placement_identity_changed {
          state.file_link_generation + 1
        } else {
          state.file_link_generation
        },
        review_generation: state.review_generation,
        git_graph_generation: if owner_changed || placement_identity_changed {
          state.git_graph_generation + 1
        } else {
          state.git_graph_generation
        },
        git_commit_files_generation: state.git_commit_files_generation,
        history_generation: state.history_generation,
        // Like filesystem request epochs, watcher identities must outlive the
        // per-conversation cache or an A→B→A cycle could reuse one.
        watch_generation: reroot_watch_generation,
        review_recovery_pending: false,
        background_review_requests: Map([]),
        // Preserve the last host configuration long enough for `with_watch`
        // to retire or replace it on the way out.
        watching: if placement_identity_changed {
          None
        } else {
          state.watching
        },
        docs,
      },
      @cmd.batch(cmds),
    )
  }
  // A checkout can disappear while a Git request is in flight. The parked
  // update path correctly refuses its late host reply; clear the in-flight
  // bit here as well so restoring the same owner starts a fresh generation
  // instead of leaving Changes wedged in Loading/refreshing forever. A failed
  // inventory also returns to Idle at this meaningful placement boundary,
  // granting review recovery one retry without making every sync retry it.
  let state = if checkout_ready {
    state
  } else if parking_existing_owner {
    // Placement is an incarnation boundary even when the conversation owner
    // is unchanged. Drop checkout-derived caches and invalidate every host
    // request whose reply could otherwise arrive after Repair and look current.
    let docs = state.docs.copy()
    let mut review_generation = state.review_generation
    let mut review_recovery_pending = false
    for path, doc in docs {
      if doc.review is Some(review) {
        if doc.state is TabLoading || review.baseline is ReviewLoading {
          review_recovery_pending = true
        }
        // Git baseline replies do not carry the filesystem epoch. Advance
        // every review token so a background legacy refresh is fenced too.
        review_generation += 1
        docs[path] = {
          ..doc,
          review: Some({ ..review, generation: review_generation, }),
        }
      }
    }
    let state = {
      ..state,
      docs,
      children: Map([]),
      loading: [],
      index: IndexEmpty,
      error: None,
      search: state.search.park(),
      changes_generation: state.changes_generation + 1,
      review_generation,
      review_recovery_pending,
      background_review_requests: Map([]),
      git_graph: GitGraphIdle,
      git_graph_generation: state.git_graph_generation + 1,
      git_graph_selected: None,
      git_commit_files: GitCommitFilesIdle,
      history_docs: Map([]),
      history_generation: state.history_generation + 1,
      placement: state.placement.reconcile(ctx.placement),
      request_epoch,
    }
    match state.changes {
      ChangeListLoading(_) | ChangeListFailed(_) =>
        { ..state, changes: ChangeListIdle, }
      ChangeListReady(repository~, files~, refreshing=true, ..) =>
        {
          ..state,
          changes: ChangeListReady(
            repository~,
            files~,
            refreshing=false,
            refresh_again=false,
          ),
        }
      _ => state
    }
  } else {
    { ..state, placement: state.placement.reconcile(ctx.placement), }
  }
  // `clear_viewer` ran when the checkout disappeared. Once the same owner is
  // repaired, put its active tab back on screen and revalidate every cached
  // working side against the new checkout incarnation. Background tabs defer
  // their read until activation; incomplete reviews restart from the first
  // authoritative Changes snapshot below.
  let (state, restore_cmd) = if restoring_existing_owner {
    let docs = state.docs.copy()
    for path, doc in docs {
      let has_working_side = match doc.review {
        Some(review) => review.selected.has_working_tree_file()
        None => true
      }
      if has_working_side {
        docs[path] = { ..doc, stale: true, }
      }
    }
    let mut review_generation = state.review_generation
    let restore_cmd = if ctx.panel_open &&
      ctx.active_file is Some(path) &&
      docs.get(path) is Some(doc) {
      let (cmd, doc, generation) = show_activated_tab(
        dispatch,
        ctx,
        state.editor_search_highlights(path),
        path,
        doc,
        review_generation,
      )
      docs[path] = doc
      review_generation = generation
      cmd
    } else {
      @cmd.none
    }
    (
      {
        ..state,
        docs,
        review_generation,
        placement: state.placement.reconcile(ctx.placement),
      },
      restore_cmd,
    )
  } else if checkout_ready {
    (
      { ..state, placement: state.placement.reconcile(ctx.placement), },
      @cmd.none,
    )
  } else {
    (state, @cmd.none)
  }
  // A hidden explorer can miss nested edits even when Quick Open keeps its
  // shallow root-directory watch alive. The actual hide/show transition
  // therefore invalidates a ready Changes snapshot; watcher ownership and
  // workspace gaps cover the remaining reroot cases.
  let explorer_is_visible = explorer_visible(state, ctx)
  let explorer_reopened = explorer_is_visible && !state.explorer_was_visible
  let changes_are_live = changes_live(state, ctx)
  let changes_may_be_stale = changes_are_live &&
    (match state.watching {
      Some(watching) =>
        explorer_reopened ||
        watching.owner != ctx.owner ||
        ctx.root() != Some(watching.root) ||
        (
          explorer_is_visible &&
          !watching.directories.contains(@pathx.Relative::root())
        )
      None => true
    })
  let state = { ..state, explorer_was_visible: explorer_is_visible, }
  // The mode selection survives re-rooting, but its inventory does not. Load
  // it when Changes is visible, and refresh a ready snapshot when reopening
  // after its root watch was parked. Failed requests only retry on an explicit
  // selection or a settled run, not on every unrelated sync pass.
  let (changes_cmd, state) = if checkout_ready &&
    changes_are_live &&
    (
      state.changes is ChangeListIdle ||
      (
        changes_may_be_stale &&
        (
          state.changes is ChangeListLoading(_) ||
          state.changes is ChangeListReady(..)
        )
      )
    ) {
    refresh_changes(dispatch, state, ctx)
  } else {
    (@cmd.none, state)
  }
  let (graph_cmd, state) = if checkout_ready &&
    changes_visible(state, ctx) &&
    (
      state.git_graph is GitGraphIdle ||
      (
        explorer_reopened &&
        state.git_graph is (GitGraphReady(..) | GitGraphFailed(_))
      )
    ) {
    refresh_git_graph(dispatch, state, ctx)
  } else {
    (@cmd.none, state)
  }
  // Parked strips restore historical tab identities without content. Load
  // only the active immutable comparison; inactive tabs stay cheap until the
  // user returns to them.
  let (history_cmd, state) = if checkout_ready &&
    ctx.panel_open &&
    ctx.active_history_diff is Some(diff) &&
    !state.history_docs.contains(history_diff_key(diff)) {
    open_history_diff(dispatch, state, ctx, diff)
  } else {
    (@cmd.none, state)
  }
  let state = state.sync_semantic_review(ctx)
  let pending_cmd = @cmd.batch([
    retire_index_cmd,
    reroot_cmd,
    restore_cmd,
    changes_cmd,
    graph_cmd,
    history_cmd,
    sync_semantic_review_editors(state),
  ])
  // A closed panel re-roots (above) and keeps the watcher placed, but the tree
  // itself can wait for the reopen. Unresolved placement takes the same early
  // exit even if the dock is visible: no host path may fall back to root.
  guard checkout_ready && ctx.root() is Some(_) && ctx.panel_open else {
    return with_watch(dispatch, state, ctx, pending_cmd)
  }
  // Load as soon as the conversation has a concrete root: registered
  // projects and known worktrees can both load before a run.
  if ctx.owner.session.is_empty() ||
    state.children.contains("") ||
    state.loading.contains("") {
    return with_watch(dispatch, state, ctx, pending_cmd)
  }
  let loading = state.loading.copy()
  loading.push("")
  with_watch(
    dispatch,
    { ..state, loading, },
    ctx,
    @cmd.batch([
      pending_cmd,
      read_directory(
        dispatch,
        ctx.owner,
        ctx.request_epoch,
        @pathx.Relative::root(),
        root=ctx.root(),
      ),
    ]),
  )
}

///|
/// Select one review surface while keeping every parked changed-file tab
/// aligned with the panel preference. Algorithm buttons use this same
/// transition when they open a diff directly from File view.
fn select_review_view_mode(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  view_mode : ReviewViewMode,
) -> (@cmd.Cmd, State) {
  guard ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.review is Some(_) &&
    doc.diff_content() is Some(_) else {
    return (@cmd.none, state)
  }
  let docs = state.docs.copy()
  // Reopening an older tab must not resurrect a stale per-document surface.
  for review_path, review_doc in state.docs {
    match review_doc.review {
      Some(parked) =>
        docs[review_path] = {
          ..review_doc,
          review: Some({ ..parked, view_mode, }),
        }
      None => ()
    }
  }
  let next_doc = docs.get(path).unwrap()
  let show = show_pending_review(
    dispatch,
    ctx,
    state.editor_search_highlights(path),
    path,
    next_doc,
  )
  let command = match view_mode {
    // A window/tree resize can measure the display:none source host at the
    // Viewer's 5px minimum while the diff is visible. Measure again only after
    // File mode has restored the source host's real box.
    ReviewSource => @cmd.batch([show, request_viewer_remeasure()])
    ReviewDiff => show
  }
  (command, { ..state, docs, review_view_mode: view_mode, })
}

///|
pub fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  // `sync` parks the old owner while placement is unresolved or its checkout
  // is missing. Refuse file-editor actions until there is a concrete root to
  // put into their absolute filesystem or root-relative language addresses.
  if !ctx.checkout_ready() {
    // The explorer selection is a local panel preference and remains useful
    // while placement is broken; only the host-backed refresh must wait.
    return match msg {
      ExplorerModeSelected(mode) =>
        (@cmd.none, { ..state, explorer_mode: mode, })
      ToggleChangesSection =>
        (@cmd.none, { ..state, changes_collapsed: !state.changes_collapsed, })
      ToggleGitGraphSection =>
        (
          @cmd.none,
          { ..state, git_graph_collapsed: !state.git_graph_collapsed, },
        )
      _ => (@cmd.none, state)
    }
  }
  match msg {
    ToggleTree => {
      // The docked panel takes its height from the viewer, and the viewer
      // cannot see a CSS change on its own.
      let opening = !state.tree_open
      (request_viewer_remeasure(), { ..state, tree_open: opening, })
    }
    MbtiViewModeSelected(mode) => {
      guard ctx.active_history_diff is None &&
        ctx.active_file is Some(path) &&
        state.docs.get(path)
        is Some({ name, state: TabLoaded(..), review: None, .. }) &&
        uses_mbti_presentation(name) else {
        return (@cmd.none, state)
      }
      if state.mbti_view_mode(path) == mode {
        return (@cmd.none, state)
      }
      let mbti_view_modes = state.mbti_view_modes.copy()
      mbti_view_modes[path] = mode
      (
        // A Viewer measured while hidden reports its minimum box. Switching
        // back to Source must remeasure after the host becomes visible;
        // Diagram is static SVG, so the same no-op-safe command is sufficient.
        request_viewer_remeasure(),
        { ..state, mbti_view_modes, },
      )
    }
    DiffLoadingDue(owner~, path~, generation~) =>
      if state.owner == Some(owner) &&
        ctx.active_file == Some(path) &&
        state.docs.get(path) is Some(doc) &&
        doc.diff_pending_generation() == Some(generation) {
        (@cmd.none, { ..state, diff_loading_generation: Some(generation), })
      } else {
        (@cmd.none, state)
      }
    ToggleReviewDiff => {
      let view_mode = match state.review_view_mode {
        ReviewSource => ReviewDiff
        ReviewDiff => ReviewSource
      }
      select_review_view_mode(dispatch, state, ctx, view_mode)
    }
    ToggleReviewDiffLayout => {
      let review_ready = ctx.active_file is Some(path) &&
        state.docs.get(path) is Some(doc) &&
        doc.review is Some({ view_mode: ReviewDiff, .. }) &&
        doc.diff_content() is Some(_)
      let history_ready = ctx.active_history_diff is Some(diff) &&
        state.history_docs.get(history_diff_key(diff)) is Some(history) &&
        history.original.text() is Some(_) &&
        history.modified.text() is Some(_)
      guard review_ready || history_ready else { return (@cmd.none, state) }
      let review_diff_layout = match state.review_diff_layout {
        ReviewSideBySide => ReviewInline
        ReviewInline => ReviewSideBySide
      }
      (
        apply_review_diff_layout(review_diff_layout),
        { ..state, review_diff_layout, },
      )
    }
    ReviewDiffModeSelected(mode) => {
      guard moon_diff_available(state, ctx) else { return (@cmd.none, state) }
      let selected = { ..state, review_diff_mode: mode, }
      if ctx.active_file is Some(path) &&
        state.docs.get(path)
        is Some({ review: Some({ view_mode: ReviewSource, .. }), .. }) {
        let (show, diff) = select_review_view_mode(
          dispatch,
          selected,
          ctx,
          ReviewDiff,
        )
        (@cmd.batch([show, request_viewer_remeasure()]), diff)
      } else {
        (request_viewer_remeasure(), selected)
      }
    }
    ToggleReviewDiffIgnoreComments => {
      guard moon_diff_ready(state, ctx) &&
        state.review_diff_mode != ReviewDiffLine else {
        return (@cmd.none, state)
      }
      let ignore_comments = !state.review_diff_ignore_comments
      (@cmd.none, { ..state, review_diff_ignore_comments: ignore_comments, })
    }
    ToggleReviewDiffIgnoreTests => {
      guard moon_diff_ready(state, ctx) &&
        state.review_diff_mode != ReviewDiffLine else {
        return (@cmd.none, state)
      }
      let ignore_tests = !state.review_diff_ignore_tests
      (@cmd.none, { ..state, review_diff_ignore_tests: ignore_tests, })
    }
    SemanticReviewSectionToggled(key) => {
      guard semantic_sections(state.semantic_review_plan).any(section => {
        section.key == key
      }) else {
        return (@cmd.none, state)
      }
      let semantic_review_collapsed = if state.semantic_review_collapsed.contains(
          key,
        ) {
        state.semantic_review_collapsed.filter(item => item != key)
      } else {
        let collapsed = state.semantic_review_collapsed.copy()
        collapsed.push(key)
        collapsed
      }
      (@cmd.none, { ..state, semantic_review_collapsed, })
    }
    ReviewDiffNavigationAvailabilityChanged(available) =>
      (@cmd.none, { ..state, review_diff_navigation_available: available, })
    RevealPreviousReviewDiffChange => {
      guard review_diff_navigation_enabled(state, ctx) else {
        return (@cmd.none, state)
      }
      if line_diff_ready(state, ctx) {
        (reveal_previous_review_diff_change(), state)
      } else {
        (
          navigate_semantic_review_change(
            dispatch,
            state.semantic_review_collapsed,
            SemanticReviewPrevious,
          ),
          state,
        )
      }
    }
    RevealNextReviewDiffChange => {
      guard review_diff_navigation_enabled(state, ctx) else {
        return (@cmd.none, state)
      }
      if line_diff_ready(state, ctx) {
        (reveal_next_review_diff_change(), state)
      } else {
        (
          navigate_semantic_review_change(
            dispatch,
            state.semantic_review_collapsed,
            SemanticReviewNext,
          ),
          state,
        )
      }
    }
    RevealSemanticReviewSectionChange(key, reveal_last) => {
      guard !line_diff_ready(state, ctx) &&
        semantic_sections(state.semantic_review_plan).any(section => {
          section.key == key
        }) else {
        return (@cmd.none, state)
      }
      let semantic_review_collapsed = state.semantic_review_collapsed.filter(collapsed => {
        collapsed != key
      })
      (
        reveal_semantic_review_section_change(key, reveal_last),
        { ..state, semantic_review_collapsed, },
      )
    }
    ToggleReviewProgress => {
      guard ctx.active_file is Some(path) &&
        state.docs.get(path) is Some({ review: Some(review), .. }) &&
        state.changes is ChangeListReady(files~, ..) &&
        files.contains(review.selected) else {
        return (@cmd.none, state)
      }
      let reviewed_changes = if state.reviewed_changes.contains(review.selected) {
        state.reviewed_changes.filter(change => change != review.selected)
      } else {
        let reviewed_changes = state.reviewed_changes.copy()
        reviewed_changes.push(review.selected)
        reviewed_changes
      }
      (@cmd.none, { ..state, reviewed_changes, })
    }
    Search(msg) => {
      let search = state.search.handle(msg, ctx.search_input())
      let next = { ..state, search, }
      let highlights = ctx.active_file.bind(path => {
        next.editor_search_highlights(path)
      })
      let selection_changed = next.search.selected_semantic_hits() !=
        state.search.selected_semantic_hits()
      let selection_command = if selection_changed && next.search.is_semantic() {
        @cmd.custom_cmd(scheduler => {
          scheduler.add(
            dispatch(
              SemanticSelectionChanged(
                next.search.selected_semantic_reference(
                  ctx.root().map(root => root.path).unwrap_or(""),
                ),
              ),
            ),
          )
        })
      } else {
        @cmd.none
      }
      (
        @cmd.batch([
          update_search_match_highlights(highlights),
          selection_command,
        ]),
        next,
      )
    }
    SemanticSelectionChanged(_) => (@cmd.none, state)
    ExplorerModeSelected(mode) => {
      let already_selected = state.explorer_mode == mode
      let selected = { ..state, explorer_mode: mode, }
      let search_highlights = if mode is ExplorerSearch {
        ctx.active_file.bind(path => selected.search.editor_highlights(path.0))
      } else {
        None
      }
      let search_highlight_cmd = update_search_match_highlights(
        search_highlights,
      )
      match mode {
        ExplorerFiles => (search_highlight_cmd, selected)
        ExplorerSearch =>
          (
            @cmd.batch([
              search_highlight_cmd,
              @grep_search.focus_query_after_render(),
            ]),
            selected,
          )
        ExplorerChanges => {
          let (changes_cmd, selected) = if already_selected ||
            selected.changes is ChangeListIdle ||
            selected.changes is ChangeListFailed(_) {
            // Clicking the already-selected Changes tab is a manual refresh.
            // The first visit also has to obtain an inventory. Moving focus
            // back to a ready Changes tab keeps its watcher-fed snapshot and
            // lets the normal fallback poll catch index-only changes.
            refresh_changes(dispatch, selected, ctx)
          } else {
            // A ready snapshot needs nothing here: selecting Changes makes the
            // inventory live again, which is what declares the fallback poll.
            (@cmd.none, selected)
          }
          let (history_cmd, selected) = if already_selected ||
            selected.git_graph is GitGraphIdle ||
            selected.git_graph is GitGraphFailed(_) {
            refresh_git_graph(dispatch, selected, ctx)
          } else {
            (@cmd.none, selected)
          }
          (
            @cmd.batch([search_highlight_cmd, changes_cmd, history_cmd]),
            selected,
          )
        }
      }
    }
    ToggleChangesSection =>
      (@cmd.none, { ..state, changes_collapsed: !state.changes_collapsed, })
    ToggleGitGraphSection =>
      (@cmd.none, { ..state, git_graph_collapsed: !state.git_graph_collapsed, })
    RevealDirectory(path) =>
      if state.highlighted == Some(path) {
        (@cmd.none, { ..state, highlighted: None, })
      } else {
        let selected = { ..state, highlighted: Some(path), }
        if state.children.contains(path) {
          (focus_breadcrumb_entry_after_render(0), selected)
        } else if state.loading.contains(path) {
          (@cmd.none, selected)
        } else {
          let loading = state.loading.copy()
          loading.push(path)
          (
            read_directory(
              dispatch,
              ctx.owner,
              ctx.request_epoch,
              path,
              root=ctx.root(),
            ),
            { ..selected, loading, error: None, },
          )
        }
      }
    HighlightCleared(path) =>
      if state.highlighted == Some(path) {
        (@cmd.none, { ..state, highlighted: None, })
      } else {
        (@cmd.none, state)
      }
    DirToggle(path) =>
      if state.expanded.contains(path) {
        (
          @cmd.none,
          { ..state, expanded: state.expanded.filter(entry => entry != path), },
        )
      } else {
        let expanded = state.expanded.copy()
        expanded.push(path)
        // A directory listed once stays cached, so re-expanding is instant.
        if state.children.contains(path) || state.loading.contains(path) {
          (@cmd.none, { ..state, expanded, })
        } else {
          let loading = state.loading.copy()
          loading.push(path)
          (
            read_directory(
              dispatch,
              ctx.owner,
              ctx.request_epoch,
              path,
              root=ctx.root(),
            ),
            { ..state, expanded, loading, },
          )
        }
      }
    EnsureFileIndex =>
      if state.owner != Some(ctx.owner) ||
        state.placement.is_parked() ||
        ctx.root() is None ||
        !ctx.checkout_ready() ||
        ctx.owner.session.is_empty() {
        (@cmd.none, state)
      } else if state.index is IndexEmpty || state.index is IndexFailed {
        (
          list_files(dispatch, ctx.owner, ctx.request_epoch, root=ctx.root()),
          { ..state, index: IndexLoading(refresh_again=false), },
        )
      } else if state.index
        is IndexReady(files~, truncated~, refreshing=false, refresh_again=true) {
        (
          list_files(dispatch, ctx.owner, ctx.request_epoch, root=ctx.root()),
          {
            ..state,
            index: IndexReady(
              files~,
              truncated~,
              refreshing=true,
              refresh_again=false,
            ),
          },
        )
      } else {
        (@cmd.none, state)
      }
    DirLoaded(owner~, epoch~, path~, entries~) =>
      // Drop a reply whose conversation is no longer the panel's.
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else {
        let children = state.children.copy()
        children[path] = entries
        let breadcrumb_cmd = if state.highlighted == Some(path) {
          focus_breadcrumb_entry_after_render(0)
        } else {
          @cmd.none
        }
        (
          breadcrumb_cmd,
          {
            ..state,
            children,
            loading: state.loading.filter(entry => entry != path),
            error: None,
          },
        )
      }
    DirFailed(owner~, epoch~, path~, message~) =>
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else {
        (
          @cmd.none,
          {
            ..state,
            loading: state.loading.filter(entry => entry != path),
            error: Some(message),
          },
        )
      }
    FilesIndexed(owner~, epoch~, files~, truncated~) =>
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else {
        let (index, retry) = state.index.loaded(files, truncated)
        let cmd = if retry {
          list_files(dispatch, owner, epoch, root=ctx.root())
        } else {
          @cmd.none
        }
        (cmd, { ..state, index, })
      }
    FileIndexFailed(owner~, epoch~) =>
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else {
        let (index, retry) = state.index.failed()
        let cmd = if retry {
          list_files(dispatch, owner, epoch, root=ctx.root())
        } else {
          @cmd.none
        }
        (cmd, { ..state, index, })
      }
    // The subscription is only re-derived when a message is processed, so a
    // tick can still be waiting in the queue behind the message that retired
    // it. Re-check the same predicate rather than latch a redundant follow-up
    // onto a request that started meanwhile.
    ChangesPollDue =>
      if changes_poll_wanted(state, ctx) {
        refresh_changes(dispatch, state, ctx)
      } else {
        (@cmd.none, state)
      }
    GitHeadObserved(owner~, head~) =>
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        let changed = state.git_actual_head_known &&
          state.git_actual_head != head
        let observed = {
          ..state,
          git_actual_head: head,
          git_actual_head_known: true,
        }
        if changed &&
          !(observed.git_graph is (GitGraphIdle | GitGraphLoading)) &&
          changes_visible(observed, ctx) {
          refresh_git_graph(dispatch, observed, ctx)
        } else {
          (@cmd.none, observed)
        }
      }
    GitHistoryRefreshRequested => refresh_git_graph(dispatch, state, ctx)
    GitHistoryLoadMoreRequested => load_more_git_history(dispatch, state, ctx)
    GitHistoryLoaded(owner~, generation~, append~, reply~) =>
      if state.owner != Some(owner) || state.git_graph_generation != generation {
        (@cmd.none, state)
      } else if append {
        match state.git_graph {
          GitGraphReady(repository~, commits~, loading_more=true, ..) => {
            let combined = commits.copy()
            for commit in reply.commits {
              if !combined.any(existing => existing.id == commit.id) {
                combined.push(commit)
              }
            }
            (
              @cmd.none,
              {
                ..state,
                git_graph: GitGraphReady(
                  repository~,
                  snapshot=reply.snapshot,
                  commits=combined,
                  has_more=reply.has_more,
                  loading_more=false,
                  load_error=None,
                ),
              },
            )
          }
          _ => (@cmd.none, state)
        }
      } else {
        (
          @cmd.none,
          {
            ..state,
            git_graph: GitGraphReady(
              repository=reply.repository,
              snapshot=reply.snapshot,
              commits=reply.commits,
              has_more=reply.has_more,
              loading_more=false,
              load_error=None,
            ),
            git_graph_selected: None,
            git_commit_files: GitCommitFilesIdle,
          },
        )
      }
    GitHistoryFailed(owner~, generation~, append~, message~) =>
      if state.owner != Some(owner) || state.git_graph_generation != generation {
        (@cmd.none, state)
      } else if append {
        match state.git_graph {
          GitGraphReady(repository~, snapshot~, commits~, has_more~, ..) =>
            (
              @cmd.none,
              {
                ..state,
                git_graph: GitGraphReady(
                  repository~,
                  snapshot~,
                  commits~,
                  has_more~,
                  loading_more=false,
                  load_error=Some(message),
                ),
              },
            )
          _ => (@cmd.none, state)
        }
      } else {
        (@cmd.none, { ..state, git_graph: GitGraphFailed(message), })
      }
    GitCommitSelected(commit) => select_git_commit(dispatch, state, ctx, commit)
    GitCommitChangesLoaded(owner~, generation~, reply~) =>
      if state.owner == Some(owner) &&
        state.git_commit_files_generation == generation &&
        state.git_graph_selected == Some(reply.commit) &&
        state.git_commit_files is GitCommitFilesLoading(commit=loading_commit) &&
        loading_commit == reply.commit {
        let commit = reply.commit
        let parent = reply.parent
        let files = reply.changes
        (
          @cmd.none,
          {
            ..state,
            git_commit_files: GitCommitFilesReady(commit~, parent~, files~),
          },
        )
      } else {
        (@cmd.none, state)
      }
    GitCommitChangesFailed(owner~, generation~, commit~, message~) =>
      if state.owner == Some(owner) &&
        state.git_commit_files_generation == generation &&
        state.git_graph_selected == Some(commit) {
        (
          @cmd.none,
          {
            ..state,
            git_commit_files: GitCommitFilesFailed(commit~, message~),
          },
        )
      } else {
        (@cmd.none, state)
      }
    GitCommitChangesRetry(commit) =>
      retry_git_commit_changes(dispatch, state, ctx, commit)
    ChangesLoaded(owner~, generation~, repository~, head~, files~) =>
      if state.owner != Some(owner) || state.changes_generation != generation {
        (@cmd.none, state)
      } else {
        let refresh_again = match state.changes {
          ChangeListLoading(refresh_again~) => refresh_again
          ChangeListReady(refreshing=true, refresh_again~, ..) => refresh_again
          // The matching generation has already settled. Ignore a duplicate
          // callback instead of replacing the current inventory.
          _ => return (@cmd.none, state)
        }
        let previous_files = match state.changes {
          ChangeListReady(files~, ..) => files
          _ => []
        }
        // A watcher/run signal may have latched while this request was in
        // flight, then the user hid the explorer before its reply. Reopening
        // performs a fresh full refresh, so do not spend the latch off-screen.
        let follow_up = refresh_again &&
          (explorer_visible(state, ctx) || changes_live(state, ctx))
        let next_generation = if follow_up {
          generation + 1
        } else {
          generation
        }
        // An intermediate coalesced snapshot is not authoritative: a path can
        // disappear briefly and return in the already-scheduled follow-up. On
        // the final reply, clear vanished reviews and refresh every surviving
        // baseline when the comparison revision differs, or a legacy host
        // cannot report its identity and the selected row proves that a
        // baseline can exist.
        // `head` is the message's legacy field name. New clients place the task
        // baseline there when present; modern root conversations use resolved
        // HEAD. An unborn root or legacy host can leave `None`; rows that make
        // the latter ambiguous trigger live-HEAD revalidation below.
        let head_changed = state.changes_head_known &&
          state.changes_head != head
        let (review_cmds, docs, review_generation) = if follow_up {
          ([], state.docs, state.review_generation)
        } else {
          reconcile_reviews_after_changes(
            dispatch,
            state,
            ctx,
            previous_files,
            files,
            head~,
            head_changed~,
            restart_incomplete=state.review_recovery_pending,
          )
        }
        let (legacy_cmds, docs, review_generation, background_review_requests) = if !follow_up &&
          state.changes_head_known &&
          head is None {
          refresh_unknown_head_reviews(
            dispatch,
            docs,
            review_generation,
            state.background_review_requests,
            ctx,
            files,
          )
        } else {
          ([], docs, review_generation, state.background_review_requests)
        }
        for cmd in legacy_cmds {
          review_cmds.push(cmd)
        }
        let settle = if follow_up {
          list_changes(
            dispatch,
            owner,
            next_generation,
            workspace=ctx.workspace(),
          )
        } else {
          @cmd.none
        }
        review_cmds.push(settle)
        let reviewed_changes = if follow_up {
          state.reviewed_changes
        } else if head_changed {
          []
        } else {
          state.reviewed_changes.filter(change => files.contains(change))
        }
        (
          @cmd.batch(review_cmds),
          {
            ..state,
            docs,
            changes_head: if follow_up {
              state.changes_head
            } else {
              head
            },
            changes_head_known: if follow_up {
              state.changes_head_known
            } else {
              true
            },
            changes_generation: next_generation,
            review_generation,
            reviewed_changes,
            background_review_requests,
            review_recovery_pending: if follow_up {
              state.review_recovery_pending
            } else {
              false
            },
            changes: ChangeListReady(
              repository~,
              files=if follow_up { previous_files } else { files },
              refreshing=follow_up,
              refresh_again=false,
            ),
          },
        )
      }
    ChangesFailed(owner~, generation~, message~) =>
      if state.owner != Some(owner) || state.changes_generation != generation {
        (@cmd.none, state)
      } else {
        match state.changes {
          // An event arrived while the initial request was in flight. Give it
          // one final attempt before surfacing the failure, unless every
          // consumer hid meanwhile (reopening starts a fresh request).
          ChangeListLoading(refresh_again=true) =>
            if explorer_visible(state, ctx) || changes_live(state, ctx) {
              let next_generation = generation + 1
              (
                list_changes(
                  dispatch,
                  owner,
                  next_generation,
                  workspace=ctx.workspace(),
                ),
                {
                  ..state,
                  changes: ChangeListLoading(refresh_again=false),
                  changes_generation: next_generation,
                },
              )
            } else {
              (@cmd.none, { ..state, changes: ChangeListIdle, })
            }
          // A background refresh failure leaves the last usable inventory on
          // screen. If an event arrived meanwhile, spend its one coalesced
          // retry before clearing the in-flight bit.
          ChangeListReady(repository~, files~, refreshing=true, refresh_again~) =>
            if refresh_again &&
              (explorer_visible(state, ctx) || changes_live(state, ctx)) {
              let next_generation = generation + 1
              (
                list_changes(
                  dispatch,
                  owner,
                  next_generation,
                  workspace=ctx.workspace(),
                ),
                {
                  ..state,
                  changes_generation: next_generation,
                  changes: ChangeListReady(
                    repository~,
                    files~,
                    refreshing=true,
                    refresh_again=false,
                  ),
                },
              )
            } else {
              // Clearing the in-flight bit restores the settled shape that
              // declares the fallback poll, so a transient bridge/Git error
              // resumes polling while retaining the last usable snapshot.
              (
                @cmd.none,
                {
                  ..state,
                  changes: ChangeListReady(
                    repository~,
                    files~,
                    refreshing=false,
                    refresh_again=false,
                  ),
                },
              )
            }
          // A failure from an already superseded request cannot invalidate a
          // usable snapshot.
          ChangeListReady(..) => (@cmd.none, state)
          ChangeListLoading(refresh_again=false) =>
            if explorer_visible(state, ctx) || changes_live(state, ctx) {
              (@cmd.none, { ..state, changes: ChangeListFailed(message), })
            } else {
              // No explorer or review consumes this inventory. Reopening has a
              // stronger fresh signal than this failed snapshot, so return to
              // Idle and let that transition start the next request.
              (@cmd.none, { ..state, changes: ChangeListIdle, })
            }
          // An Idle/Failed state has no active request. This can be a late
          // same-owner reply after an A→B→A re-root whose generation has not
          // yet advanced because Changes is hidden; ignore it.
          _ => (@cmd.none, state)
        }
      }
    // Owned by the main package's update: which dock tab a tree click opens
    // is the strip's business, so the root intercepts this (the
    // `EditorCommentAdded` pattern), opens/activates the dock tab, and calls
    // `open_document`. Reaching this arm means the root didn't intercept it;
    // changing nothing is the safe answer.
    FileSelected(..) | SearchMatchSelected(..) => (@cmd.none, state)
    // Intercepted by the root so the dock can open/activate the file tab
    // before this package starts the paired working-tree + HEAD reads.
    ChangedFileSelected(_) => (@cmd.none, state)
    HistoricalFileSelected(_) => (@cmd.none, state)
    // Intercepted by the root for the same reason: a navigation jump opens
    // a dock tab before the document loads.
    OpenNavigationLocation(..) => (@cmd.none, state)
    GitOriginalLoaded(owner~, path~, generation~, background~, original~) => {
      let background_review_requests = if background &&
        state.background_review_requests.get(path) == Some(generation) {
        let requests = state.background_review_requests.copy()
        requests.remove(path)
        requests
      } else {
        state.background_review_requests
      }
      guard state.owner == Some(owner) &&
        state.docs.get(path) is Some(doc) &&
        doc.review is Some(current_review) &&
        current_review.generation == generation &&
        (background || current_review.baseline is ReviewLoading) else {
        return (@cmd.none, { ..state, background_review_requests, })
      }
      let review = match original {
        @protocol.OriginalContent(content) => ReviewContent(content)
        @protocol.Missing => ReviewMissing
        @protocol.BinaryOriginal => ReviewBinary
        @protocol.OversizedOriginal => ReviewOversized
      }
      let docs = state.docs.copy()
      let next_doc = {
        ..doc,
        review: Some({ ..current_review, baseline: review, }),
      }
      docs[path] = next_doc
      // A working-tree read may still be in flight. It will consume the
      // parked baseline when `FileLoaded` arrives; every settled document can
      // update immediately (including a deleted-file HEAD preview).
      let cmd = if ctx.active_file == Some(path) &&
        working_side_ready_for_review(next_doc) {
        show_settled_review(
          dispatch,
          ctx,
          state.editor_search_highlights(path),
          path,
          next_doc,
        )
      } else {
        @cmd.none
      }
      (cmd, { ..state, docs, background_review_requests, })
    }
    GitOriginalFailed(owner~, path~, generation~, background~, message~) => {
      let background_review_requests = if background &&
        state.background_review_requests.get(path) == Some(generation) {
        let requests = state.background_review_requests.copy()
        requests.remove(path)
        requests
      } else {
        state.background_review_requests
      }
      guard state.owner == Some(owner) &&
        state.docs.get(path) is Some(doc) &&
        doc.review is Some(current_review) &&
        current_review.generation == generation else {
        return (@cmd.none, { ..state, background_review_requests, })
      }
      // A compatibility refresh keeps the last usable baseline through a
      // transient failure. Foreground loads still surface their precise error.
      if background {
        return (@cmd.none, { ..state, background_review_requests, })
      }
      guard current_review.baseline is ReviewLoading else {
        return (@cmd.none, state)
      }
      let docs = state.docs.copy()
      let next_doc = {
        ..doc,
        review: Some({ ..current_review, baseline: ReviewFailed(message), }),
      }
      docs[path] = next_doc
      let cmd = if ctx.active_file == Some(path) &&
        !(next_doc.state is TabLoading) {
        show_settled_review(
          dispatch,
          ctx,
          state.editor_search_highlights(path),
          path,
          next_doc,
        )
      } else {
        @cmd.none
      }
      (cmd, { ..state, docs, background_review_requests, })
    }
    HistoryBlobLoaded(owner~, key~, generation~, side~, blob~) => {
      guard state.owner == Some(owner) &&
        state.history_docs.get(key) is Some(doc) &&
        doc.generation == generation else {
        return (@cmd.none, state)
      }
      let settled = match blob {
        @protocol.OriginalContent(content) => HistoryBlobContent(content)
        @protocol.Missing => HistoryBlobMissing
        @protocol.BinaryOriginal => HistoryBlobBinary
        @protocol.OversizedOriginal => HistoryBlobOversized
      }
      let doc = match side {
        HistoryOriginal => { ..doc, original: settled, }
        HistoryModified => { ..doc, modified: settled, }
      }
      let history_docs = state.history_docs.copy()
      history_docs[key] = doc
      let cmd = if ctx.active_history_diff is Some(active) &&
        history_diff_key(active) == key {
        show_history_doc(owner, doc)
      } else {
        @cmd.none
      }
      (cmd, { ..state, history_docs, })
    }
    HistoryBlobFailed(owner~, key~, generation~, side~, message~) => {
      guard state.owner == Some(owner) &&
        state.history_docs.get(key) is Some(doc) &&
        doc.generation == generation else {
        return (@cmd.none, state)
      }
      let failed = HistoryBlobError(message)
      let doc = match side {
        HistoryOriginal => { ..doc, original: failed, }
        HistoryModified => { ..doc, modified: failed, }
      }
      let history_docs = state.history_docs.copy()
      history_docs[key] = doc
      (@cmd.none, { ..state, history_docs, })
    }
    FileLoaded(
      owner~,
      epoch~,
      path~,
      name~,
      file~,
      file_link_generation~,
      review_generation~,
      range~,
      annotation~
    ) => {
      let stale_file_link = match file_link_generation {
        Some(generation) => state.file_link_generation != generation
        None => false
      }
      // An owner/placement mismatch means the addressed document no longer
      // belongs to this table. A stale positioned reply may finish only the
      // loading document; a newer settled snapshot always wins.
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else if state.docs.get(path) is Some(doc) {
        if stale_file_link && !(doc.state is TabLoading) {
          return (@cmd.none, state)
        }
        // A Git non-file classification invalidates every read started while
        // this path was still an ordinary file. Only an explicit reopen moves
        // the document back to `TabLoading`, where a new reply may settle.
        if doc.state is TabUnavailable(_) {
          return (@cmd.none, state)
        }
        // A repeated changed-row click starts a new working-tree read as well
        // as a new HEAD read. Fence the older working reply against the
        // generation still parked on this document. An untagged ordinary read
        // is accepted only when no review has since claimed the document.
        if review_generation is Some(generation) &&
          !(doc.review is Some({ working_generation: current, .. }) &&
          current == generation) {
          return (@cmd.none, state)
        }
        // An ordinary read may already have been in flight when the user
        // clicked Changes. It has no review token and must not overwrite the
        // paired working snapshot or inherit the newly-fetched HEAD baseline.
        if review_generation is None && doc.review is Some(_) {
          return (@cmd.none, state)
        }
        let previous = doc.state
        let doc_state = match file {
          Content(content~, absolute~, sig~) =>
            TabState::TabLoaded(content~, absolute~, sig~)
          Binary => TabBinary
          Oversized => TabOversized
        }
        let docs = state.docs.copy()
        let next_doc = {
          name,
          state: doc_state,
          review: doc.review,
          stale: false,
        }
        docs[path] = next_doc
        // Only the tab on screen touches the viewer; a background load just
        // settles into its tab for the next activation. A stale positioned
        // read may still own this path when the newer click went to the system
        // opener and left the same loading tab active. Show its content, but
        // discard the stale range and annotation so it cannot perform the old
        // navigation. No content comparison happens here: that remains the
        // show command's decision against what the Viewer actually displays.
        let reveal_range = if stale_file_link { None } else { range }
        let reveal_annotation = if stale_file_link { None } else { annotation }
        let cmd = if ctx.active_file == Some(path) {
          match file {
            // A real MoonBit file also gets a diagnostics request: the host
            // runs `moon check` over the file's module and returns its
            // current diagnostics, and future re-analysis arrives as
            // `diagnostics` events. Other files have nothing behind
            // `lsp_open` — moon has no diagnostics for a README or JSON file
            // — so only the viewer shows.
            Content(content~, absolute~, ..) => {
              let show = show_file_in_viewer(
                ctx.owner,
                root=ctx.root(),
                name,
                content,
                absolute~,
                relative=path,
                range=reveal_range,
                annotation?=reveal_annotation,
                // A reload of a document already on screen keeps the reading
                // position; only a genuinely fresh document opens at the top.
                restore_scroll=previous is TabLoaded(..),
                review_original?=doc.quick_diff_original(),
                diff?=next_doc.visible_diff(),
                search_highlights?=state.editor_search_highlights(path),
              )
              if language_id(name) == "moonbit" && ctx.root() is Some(root) {
                @cmd.batch([
                  show,
                  request_diagnostics(
                    dispatch,
                    ctx.owner,
                    ctx.request_epoch,
                    root,
                    path,
                    absolute,
                  ),
                ])
              } else {
                show
              }
            }
            // The notice overlay (rendered from the tab's new state) covers
            // the viewer; drop whatever document it was showing.
            Binary | Oversized => clear_document()
          }
        } else {
          @cmd.none
        }
        (cmd, { ..state, docs, })
      } else {
        (@cmd.none, state)
      }
    }
    RunSettled(owner~) =>
      if state.owner == Some(owner) {
        // A completed agent run can write files outside the pruned watcher.
        // Git status alone cannot prove their content or path set is unchanged,
        // so review progress and a ready file index are conservatively
        // invalidated at this authoritative boundary. FileIndex coalesces a
        // second settled run while its refresh is still in flight.
        let (index, start_index_refresh) = state.index.invalidate()
        // A missing worktree root rejects watcher activation immediately. The
        // run-settled boundary is authoritative evidence that setup may now
        // have created it, so permit exactly one new attempt here. Ordinary
        // sync messages retain the failed desired configuration and cannot
        // spin an unbounded request/failure loop.
        let watching = if state.watch_error is Some(_) {
          None
        } else {
          state.watching
        }
        let state = { ..state, reviewed_changes: [], index, watching, }
        let index_cmd = if start_index_refresh {
          list_files(dispatch, owner, state.request_epoch, root=ctx.root())
        } else {
          @cmd.none
        }
        let diagnostics = match
          active_moonbit_diagnostics(
            dispatch,
            owner,
            state.request_epoch,
            ctx.root(),
            state.docs,
            ctx.active_file,
          ) {
          Some(recheck) => recheck
          None => @cmd.none
        }
        // While the explorer is on-screen—or a review still consumes its HEAD
        // baseline—keep the inventory current even when the user is looking
        // at Files, including retrying a previous failure. An idle Changes
        // tab also loads at this workspace-settled boundary.
        let (changes_cmd, next) = if (
            explorer_visible(state, ctx) || changes_live(state, ctx)
          ) &&
          (
            !(state.changes is ChangeListIdle) ||
            state.explorer_mode is ExplorerChanges
          ) {
          refresh_changes(dispatch, state, ctx)
        } else {
          (@cmd.none, state)
        }
        let (graph_cmd, next) = if changes_visible(next, ctx) &&
          !(next.git_graph is GitGraphIdle) {
          refresh_git_graph(dispatch, next, ctx)
        } else {
          (@cmd.none, next)
        }
        (@cmd.batch([diagnostics, changes_cmd, graph_cmd, index_cmd]), next)
      } else {
        (@cmd.none, state)
      }
    FsChanged(root~, generation~, changes~) =>
      if state.owner is Some(owner) &&
        owner.channel == ctx.owner.channel &&
        ctx.root() == Some(root) &&
        generation == ctx.watch_identity(state.watch_generation) {
        let reviewed_changes = match changes {
          Some(changes) =>
            state.reviewed_changes.filter(change => !change.touched_by(changes))
          None => state.reviewed_changes
        }
        // A baseline checks the whole selection after watcher replacement.
        // Concrete batches stat only affected open files (the dock strip's
        // projection) and re-list only directories whose immediate children
        // changed.
        let cmds = []
        let stat_paths : Array[@pathx.Relative] = []
        let relist : Array[@pathx.Relative] = []
        let mut refresh_index = false
        let mut moonbit_changed = false
        if changes is Some(changes) {
          for change in changes {
            if change.moonbit_relevant() {
              moonbit_changed = true
            }
            for path in ctx.open_files {
              if change.touches(path) && !stat_paths.contains(path) {
                stat_paths.push(path)
              }
            }
            for directory in change.relist_candidates() {
              if !relist.contains(directory) &&
                state.children.contains(directory) &&
                (
                  directory.is_root() ||
                  state.expanded.contains(directory) ||
                  state.highlighted == Some(directory)
                ) &&
                !state.loading.contains(directory) {
                relist.push(directory)
              }
            }
            if change.changes_file_list() {
              refresh_index = true
            }
          }
        } else {
          for path in ctx.open_files {
            stat_paths.push(path)
          }
          if state.children.contains("") && !state.loading.contains("") {
            relist.push(@pathx.Relative::root())
          }
          for directory in state.expanded {
            if state.children.contains(directory) &&
              !state.loading.contains(directory) {
              relist.push(directory)
            }
          }
          if state.highlighted is Some(directory) &&
            state.children.contains(directory) &&
            !state.loading.contains(directory) &&
            !relist.contains(directory) {
            relist.push(directory)
          }
          // Recursive selections omit shallow explorer paths already covered
          // by the workspace-wide watcher, so those transitions issue no new
          // request. A received baseline therefore marks an initial attach or
          // an actual watcher replacement and must close that replacement gap.
          refresh_index = state.index is IndexLoading(..) ||
            state.index is IndexReady(..)
        }
        if !stat_paths.is_empty() {
          cmds.push(
            stat_files(
              dispatch,
              owner,
              state.request_epoch,
              stat_paths,
              root=ctx.root(),
            ),
          )
        } else if moonbit_changed &&
          active_moonbit_diagnostics(
            dispatch,
            owner,
            state.request_epoch,
            ctx.root(),
            state.docs,
            ctx.active_file,
          )
          is Some(recheck) {
          // A MoonBit change that touched no open tab still moves the
          // module's diagnostics (a sibling file's edit can break or fix the
          // active file), and without a stat round there is no `StatsLoaded`
          // to carry the usual re-check — ask directly. The check's pushes
          // refresh the other open tabs too.
          cmds.push(recheck)
        }
        let loading = state.loading.copy()
        for directory in relist {
          loading.push(directory)
          cmds.push(
            read_directory(
              dispatch,
              owner,
              state.request_epoch,
              directory,
              root=ctx.root(),
            ),
          )
        }
        // Structural events change the path set. Watcher baselines latch a
        // follow-up during the initial scan or refresh a ready snapshot after
        // a real replacement; normalized equivalent recursive selections do
        // not issue replacement requests. A ready snapshot stays usable during
        // one refresh, and later structural bursts coalesce once.
        let (index, start_refresh) = if refresh_index {
          state.index.invalidate()
        } else {
          (state.index, false)
        }
        if start_refresh {
          cmds.push(
            list_files(dispatch, owner, state.request_epoch, root=ctx.root()),
          )
        }
        let next = { ..state, loading, reviewed_changes, index, }
        // Any content event can change Git status, not just a structural one.
        // Refresh only after Changes has been requested and while its explorer
        // or a review is live; reopening performs its own full refresh. The
        // in-flight flag inside `refresh_changes` coalesces watcher bursts.
        let (changes_cmd, next) = if (
            explorer_visible(state, ctx) || changes_live(state, ctx)
          ) &&
          (
            state.changes is ChangeListLoading(_) ||
            state.changes is ChangeListReady(..)
          ) {
          refresh_changes(dispatch, next, ctx)
        } else {
          (@cmd.none, next)
        }
        cmds.push(changes_cmd)
        (@cmd.batch(cmds), next)
      } else {
        (@cmd.none, state)
      }
    StatsLoaded(owner~, epoch~, stats~) =>
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else {
        let docs = state.docs.copy()
        let cmds = []
        let mut review_generation = state.review_generation
        // Whether the loop below already reloads the active tab — that path
        // re-requests diagnostics on its own.
        let mut active_reloading = false
        for stat in stats {
          guard docs.get(stat.path) is Some(doc) else { continue }
          let current_sig = match stat.signature {
            Missing => {
              // The file is gone. The tab stays as the user's bookmark; the
              // notice replaces the document if it is the one on screen. A
              // tab already reviewing a textual HEAD side instead switches
              // to that deleted-file preview.
              if !(doc.state is (TabDeleted | TabUnavailable(_))) {
                let review = match doc.review {
                  Some(review) if review.selected.has_working_tree_file() => {
                    // The missing signature is newer than any tagged read
                    // that was already in flight. Advance its token so an
                    // older successful read cannot resurrect deleted working
                    // text.
                    review_generation += 1
                    Some({ ..review, working_generation: review_generation, })
                  }
                  _ => doc.review
                }
                let deleted = {
                  ..doc,
                  state: TabDeleted,
                  review,
                  stale: false,
                }
                docs[stat.path] = deleted
                if ctx.active_file == Some(stat.path) {
                  cmds.push(
                    show_tab(
                      dispatch,
                      ctx,
                      state.editor_search_highlights(stat.path),
                      stat.path,
                      deleted,
                    ),
                  )
                }
              }
              continue
            }
            Failed(message) => {
              // The host could not inspect the file — permissions, a sharing
              // violation, a path it could not resolve. That is not a
              // deletion, but the text on screen is now of unknown
              // freshness, so the tab keeps its place and shows the failure
              // exactly as a failed read would, until a later stat proves
              // the path readable and the ordinary retry reloads it. A read
              // still in flight settles the document by itself, withheld
              // documents have no baseline to invalidate, and a selected
              // deletion row reviews HEAD rather than whatever now sits at
              // its path.
              let affected = match doc.state {
                TabLoaded(..) | TabReadFailed(_) => true
                TabDeleted =>
                  doc.review
                  .map(review => review.selected.has_working_tree_file())
                  .unwrap_or(true)
                TabLoading | TabBinary | TabOversized | TabUnavailable(_) =>
                  false
              }
              if affected {
                let review = match doc.review {
                  Some(review) if review.selected.has_working_tree_file() => {
                    // Like a deletion, the failure is newer than any tagged
                    // read still in flight: an older success must not settle
                    // text the host can no longer vouch for.
                    review_generation += 1
                    Some({ ..review, working_generation: review_generation, })
                  }
                  _ => doc.review
                }
                let failed = {
                  ..doc,
                  state: TabReadFailed(message),
                  review,
                  stale: false,
                }
                docs[stat.path] = failed
                if ctx.active_file == Some(stat.path) {
                  cmds.push(
                    show_tab(
                      dispatch,
                      ctx,
                      state.editor_search_highlights(stat.path),
                      stat.path,
                      failed,
                    ),
                  )
                }
              }
              continue
            }
            Present(current_sig) => current_sig
          }
          let changed = match doc.state {
            // The loaded baseline says whether the disk moved on.
            TabLoaded(sig~, ..) => sig != current_sig
            // A deleted file whose signature came back ordinarily reappeared.
            // A selected deletion row is different: porcelain can also carry
            // a same-path untracked row, so the current filesystem object is
            // not the working side of this review and must not replace HEAD.
            TabDeleted =>
              doc.review
              .map(review => review.selected.has_working_tree_file())
              .unwrap_or(true)
            // A read is already in flight; its reply carries a fresh
            // signature anyway.
            TabLoading => false
            // Withheld documents carry no baseline to compare against (see
            // `TabState`); they refresh on explicit re-open instead. A
            // previous read failure does retry once the watcher proves the
            // path exists.
            TabBinary | TabOversized | TabUnavailable(_) => false
            TabReadFailed(_) => true
          }
          if changed {
            if ctx.active_file == Some(stat.path) {
              // The document on screen reloads eagerly (scroll kept —
              // `FileLoaded` sees the previous content). The document keeps
              // its loaded state so that restore has its baseline.
              active_reloading = true
              let working_generation = match doc.review {
                Some(review) => {
                  review_generation += 1
                  // A tagged review read can be fenced out if its Git row
                  // disappears first. Preserve a stale marker so leaving review
                  // mode hands the active tab to a replacement ordinary read.
                  docs[stat.path] = {
                    ..doc,
                    review: Some({
                      ..review,
                      working_generation: review_generation,
                    }),
                    stale: true,
                  }
                  Some(review_generation)
                }
                None => None
              }
              cmds.push(
                read_file(
                  dispatch,
                  owner,
                  state.request_epoch,
                  stat.path,
                  doc.name,
                  review_generation?=working_generation,
                  range=None,
                  root=ctx.root(),
                ),
              )
            } else {
              // Background documents just remember they are behind;
              // activation reloads them. A build storm therefore costs one
              // read, not one per open tab.
              docs[stat.path] = { ..doc, stale: true, }
            }
          }
        }
        // A change elsewhere in the module can add or remove the active
        // file's diagnostics without touching its own mtime — the one-shot
        // `moon check` behind `lsp_open` only runs when asked, unlike the
        // resident server it replaced. One re-check per (debounced) change
        // burst covers that: the reload above brings its own request, so
        // only an active file the stats left untouched needs the explicit
        // refresh. Its check's pushes update the other open tabs too.
        if !active_reloading &&
          active_moonbit_diagnostics(
            dispatch,
            owner,
            state.request_epoch,
            ctx.root(),
            docs,
            ctx.active_file,
          )
          is Some(recheck) {
          cmds.push(recheck)
        }
        (@cmd.batch(cmds), { ..state, docs, review_generation, })
      }
    DiagnosticsLoaded(owner~, epoch~, absolute~, diagnostics~) =>
      if state.owner == Some(owner) && state.request_epoch == epoch {
        (apply_diagnostics(owner.channel, absolute, diagnostics), state)
      } else {
        (@cmd.none, state)
      }
    DiagnosticsPublished(channel~, absolute~, diagnostics~) =>
      if state.owner is Some(owner) && owner.channel == channel {
        (apply_diagnostics(channel, absolute, diagnostics), state)
      } else {
        (@cmd.none, state)
      }
    // The root app owns the toast rail and intercepts this message. If an
    // embedding delegates it here instead, leaving panel state unchanged is
    // safer than persisting an error that a later successful request cannot
    // explicitly clear.
    LanguageRequestFailed(..) => (@cmd.none, state)
    FileFailed(
      owner~,
      epoch~,
      path~,
      file_link_generation~,
      review_generation~,
      message~
    ) => {
      let stale_file_link = match file_link_generation {
        Some(generation) => state.file_link_generation != generation
        None => false
      }
      if state.owner != Some(owner) || state.request_epoch != epoch {
        (@cmd.none, state)
      } else if file_link_generation is Some(_) {
        // A stale positioned failure may finish only the loading document. A
        // current failure is authoritative even if an older success filled
        // the cache first, so it replaces that snapshot with a retryable tab.
        match state.docs.get(path) {
          Some({ state: TabUnavailable(_), review: None, .. }) =>
            (@cmd.none, state)
          Some({ review: None, .. } as doc) => {
            if stale_file_link && !(doc.state is TabLoading) {
              return (@cmd.none, state)
            }
            let docs = state.docs.copy()
            let failed = { ..doc, state: TabReadFailed(message), stale: false, }
            docs[path] = failed
            let cmd = if !stale_file_link && ctx.active_file == Some(path) {
              show_tab(
                dispatch,
                ctx,
                state.editor_search_highlights(path),
                path,
                failed,
              )
            } else {
              @cmd.none
            }
            (cmd, { ..state, docs, error: None, })
          }
          Some({ review: Some(_), .. }) | None if stale_file_link =>
            (@cmd.none, state)
          _ => (@cmd.none, { ..state, error: Some(message), })
        }
      } else if review_generation is Some(generation) {
        // Review reads are generation-fenced just like successful replies.
        // Preserve a current working-side failure without guessing that every
        // host error means deletion; a superseded read remains invisible.
        guard state.docs.get(path) is Some(doc) &&
          doc.review is Some({ working_generation: current, .. }) &&
          current == generation else {
          return (@cmd.none, state)
        }
        let docs = state.docs.copy()
        let failed = { ..doc, state: TabReadFailed(message), stale: false, }
        docs[path] = failed
        let cmd = if ctx.active_file == Some(path) {
          show_tab(
            dispatch,
            ctx,
            state.editor_search_highlights(path),
            path,
            failed,
          )
        } else {
          @cmd.none
        }
        (cmd, { ..state, docs, error: None, })
      } else if state.docs.get(path) is Some({ review: Some(_), .. }) {
        // Like an untagged success, this failure belongs to an ordinary read
        // that predates the review click and is no longer user-visible.
        (@cmd.none, state)
      } else if state.docs.get(path) is Some({ state: TabUnavailable(_), .. }) {
        // A stat reply already established that this path is intentionally
        // unavailable. Its older untagged read failure must not replace that
        // precise tab notice with a generic panel-wide error banner.
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, error: Some(message), })
      }
    }
    FileWatchFailed(channel~, root~, generation~, message~) =>
      if state.owner is Some(owner) &&
        owner.channel == channel &&
        ctx.root() == Some(root) &&
        generation == ctx.watch_identity(state.watch_generation) {
        // The Host reports request-time activation failures through the
        // `fs.watch` reply and reserves this event for a watcher that stopped
        // after it was active. Keep the failed configuration recorded so the
        // ordinary sync pass cannot create an unbounded retry loop. A later
        // effective configuration change starts a fresh generation.
        // Refresh the current snapshot once because the stopped watcher opens
        // an observation gap even though it remains useful for reads.
        let (index, start_index_refresh) = state.index.invalidate()
        let cmd = if start_index_refresh {
          list_files(dispatch, owner, state.request_epoch, root=ctx.root())
        } else {
          @cmd.none
        }
        (cmd, { ..state, index, watch_error: Some(message), })
      } else {
        (@cmd.none, state)
      }
    // Owned by the main package's update: the comment becomes a composer
    // chip there, which then clears the editor bubble through
    // `remove_editor_feedback`. Reaching this arm means the main update
    // didn't intercept it; changing nothing is the safe answer.
    EditorCommentAdded(..) | DiffCommentAdded(..) | ApplyAllFeedback =>
      (@cmd.none, state)
  }
}

// State-transition tests for the document table: opening documents, how
// replies settle into the table, disk-change sweeps, and how a conversation
// switch re-roots the table from the dock's projection. Commands are opaque,
// so the tests assert on the returned state only.

///|
fn test_emit() -> @cmd.Emit[Msg] {
  Emit(_ => @cmd.none)
}

///|
fn test_ctx() -> Ctx {
  {
    owner: { channel: @interop.ChannelId::Local, session: "desktop-test", },
    request_epoch: 0,
    watch_namespace: "test-page",
    placement: @resource.of_path(@interop.ChannelId::Local, "/work").map(root => {
      @interop.WorkspaceRoot(root~)
    }),
    dark_mode: false,
    tree_layout: BottomPanel,
    narrow: false,
    panel_open: true,
    open_files: [],
    active_file: None,
    open_history_diffs: [],
    active_history_diff: None,
  }
}

///|
fn Ctx::test_root(self : Ctx) -> @common.Uri raise {
  guard self.root() is Some(root) else {
    fail("test context must carry a concrete root")
  }
  root
}

///|
fn Ctx::test_resource(self : Ctx, path : String) -> @common.Uri raise {
  guard @resource.of_path(self.owner.channel, path) is Some(resource) else {
    fail("test resource path must be absolute")
  }
  resource
}

///|
/// Put a test context in a live managed worktree whose project and checkout
/// share the fixture root. Tests that park it as missing then change only
/// availability, matching the production registry transition.
fn Ctx::test_worktree(self : Ctx, name : String) -> Ctx raise {
  let root = self.test_root()
  { ..self, placement: Some(@interop.Worktree(project=root, name~, root~)), }
}

///|
fn owned_state() -> State {
  owned_state_at(test_ctx())
}

///|
/// A state the shared test owner has already reconciled against `ctx`.
fn owned_state_at(ctx : Ctx) -> State {
  {
    ..State::empty(),
    owner: Some(test_ctx().owner),
    placement: PlacementUnknown.reconcile(ctx.placement),
    explorer_was_visible: true,
  }
}

///|
fn loaded_doc(path : String) -> Doc raise {
  guard @resource.of_path(@interop.ChannelId::Local, "/work/" + path)
    is Some(absolute) else {
    fail("test document resource was not absolute")
  }
  {
    name: basename(Relative(path)),
    state: TabLoaded(content="", absolute~, sig="1:0"),
    review: None,
    stale: false,
  }
}

///|
fn test_modified_change(path : @pathx.Relative) -> ChangedFile {
  {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
}

///|
test "file index requests retry failures and fence stale replies" {
  let emit = test_emit()
  let ctx = test_ctx()
  let state = owned_state()
  let (_, loading) = update(emit, EnsureFileIndex, state, ctx)
  assert_true(loading.index is IndexLoading(refresh_again=false))
  let (_, duplicate) = update(emit, EnsureFileIndex, loading, ctx)
  assert_true(duplicate == loading)
  let (_, stale) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=ctx.request_epoch + 1,
      files=[Relative("stale.mbt")],
      truncated=false,
    ),
    loading,
    ctx,
  )
  assert_true(stale == loading)
  let (_, failed) = update(
    emit,
    FileIndexFailed(owner=ctx.owner, epoch=ctx.request_epoch),
    loading,
    ctx,
  )
  assert_true(failed.index is IndexFailed)
  let (_, retrying) = update(emit, EnsureFileIndex, failed, ctx)
  assert_true(retrying.index is IndexLoading(refresh_again=false))
  let (_, ready) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      files=[Relative("src/main.mbt")],
      truncated=true,
    ),
    retrying,
    ctx,
  )
  assert_true(
    ready.index
    is IndexReady(
      files=[Relative("src/main.mbt")],
      truncated=true,
      refreshing=false,
      refresh_again=false
    ),
  )
  let (_, refresh_failed) = update(
    emit,
    FileIndexFailed(owner=ctx.owner, epoch=ctx.request_epoch),
    ready,
    ctx,
  )
  assert_true(refresh_failed == ready)
  let refreshing = {
    ..ready,
    index: IndexReady(
      files=[Relative("src/main.mbt")],
      truncated=true,
      refreshing=true,
      refresh_again=false,
    ),
  }
  let (_, stale) = update(
    emit,
    FileIndexFailed(owner=ctx.owner, epoch=ctx.request_epoch),
    refreshing,
    ctx,
  )
  assert_true(
    stale.index is IndexReady(refreshing=false, refresh_again=true, ..),
  )
  let (_, retrying_stale) = update(emit, EnsureFileIndex, stale, ctx)
  assert_true(
    retrying_stale.index is IndexReady(refreshing=true, refresh_again=false, ..),
  )
}

///|
test "watcher changes during the initial file index scan schedule one follow-up" {
  let emit = test_emit()
  let ctx = test_ctx()
  let (_, loading) = update(emit, EnsureFileIndex, owned_state(), ctx)
  let changed = FsChanged(
    root=ctx.test_root(),
    generation=ctx.watch_identity(loading.watch_generation),
    changes=Some([Created(Relative("src/new.mbt"))]),
  )
  let (_, latched) = update(emit, changed, loading, ctx)
  assert_true(latched.index is IndexLoading(refresh_again=true))
  let (_, following_up) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      files=[Relative("src/old.mbt")],
      truncated=false,
    ),
    latched,
    ctx,
  )
  assert_true(
    following_up.index is IndexReady(refreshing=true, refresh_again=false, ..),
  )
  let (_, settled) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      files=[Relative("src/old.mbt"), Relative("src/new.mbt")],
      truncated=false,
    ),
    following_up,
    ctx,
  )
  assert_true(
    settled.index
    is IndexReady(
      files=[Relative("src/old.mbt"), Relative("src/new.mbt")],
      refreshing=false,
      refresh_again=false,
      ..
    ),
  )
}

///|
test "structural watcher bursts coalesce file index refreshes" {
  let emit = test_emit()
  let ctx = test_ctx()
  let ready = {
    ..owned_state(),
    index: IndexReady(
      files=[Relative("src/old.mbt")],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
  }
  let changed = FsChanged(
    root=ctx.test_root(),
    generation=ctx.watch_identity(ready.watch_generation),
    changes=Some([Created(Relative("src/new.mbt"))]),
  )
  let (_, refreshing) = update(emit, changed, ready, ctx)
  assert_true(
    refreshing.index is IndexReady(refreshing=true, refresh_again=false, ..),
  )
  let (_, coalesced) = update(emit, changed, refreshing, ctx)
  assert_true(
    coalesced.index is IndexReady(refreshing=true, refresh_again=true, ..),
  )
  let (_, following_up) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      files=[Relative("src/new.mbt")],
      truncated=false,
    ),
    coalesced,
    ctx,
  )
  assert_true(
    following_up.index
    is IndexReady(
      files=[Relative("src/new.mbt")],
      refreshing=true,
      refresh_again=false,
      ..
    ),
  )
  let (_, settled) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      files=[Relative("src/new.mbt"), Relative("src/last.mbt")],
      truncated=false,
    ),
    following_up,
    ctx,
  )
  assert_true(
    settled.index
    is IndexReady(
      files=[Relative("src/new.mbt"), Relative("src/last.mbt")],
      refreshing=false,
      refresh_again=false,
      ..
    ),
  )
}

///|
test "settled agent runs refresh the file index beyond watcher coverage" {
  let emit = test_emit()
  let ctx = { ..test_ctx(), panel_open: false, }
  let ready = {
    ..owned_state(),
    index: IndexReady(
      files=[Relative("src/old.mbt")],
      truncated=true,
      refreshing=false,
      refresh_again=false,
    ),
  }
  let settled = RunSettled(owner=ctx.owner)
  let (_, refreshing) = update(emit, settled, ready, ctx)
  assert_true(
    refreshing.index is IndexReady(refreshing=true, refresh_again=false, ..),
  )
  // The same input has the same result; the update performs no direct effect.
  let (_, repeated_from_ready) = update(emit, settled, ready, ctx)
  assert_true(repeated_from_ready == refreshing)
  let (_, coalesced) = update(emit, settled, refreshing, ctx)
  assert_true(
    coalesced.index is IndexReady(refreshing=true, refresh_again=true, ..),
  )
}

///|
test "only structural watcher events change the file index path set" {
  assert_false(Modified(Relative("src/main.mbt")).changes_file_list())
  assert_true(Created(Relative("src/new.mbt")).changes_file_list())
  assert_true(Removed(Relative("src/old.mbt")).changes_file_list())
  assert_true(
    Renamed(old=Relative("src/old.mbt"), new=Relative("src/new.mbt")).changes_file_list(),
  )
  assert_false(Created(Relative("node_modules/pkg/new.js")).changes_file_list())
  assert_false(Removed(Relative("target/cache/output")).changes_file_list())
  assert_true(Created(Relative("node_modules")).changes_file_list())
  assert_true(
    Renamed(
      old=Relative("node_modules/pkg/hidden.js"),
      new=Relative("src/visible.js"),
    ).changes_file_list(),
  )
}

///|
test "language request failures remain a pure no-op below the root toast owner" {
  let emit = test_emit()
  let state = owned_state()
  let msg = LanguageRequestFailed(
    owner=test_ctx().owner,
    message="definition failed",
  )
  let (_, first) = update(emit, msg, state, test_ctx())
  let (_, second) = update(emit, msg, state, test_ctx())
  assert_true(first == state)
  assert_true(second == state)
}

///|
test "open_document seeds a loading entry and re-open keeps cached content" {
  let emit = test_emit()
  let (_, one) = open_document(
    emit,
    owned_state(),
    {
      ..test_ctx(),
      open_files: [Relative("a.mbt")],
      active_file: Some(Relative("a.mbt")),
    },
    Relative("a.mbt"),
    name="a.mbt",
    range=None,
    had_active=false,
  )
  assert_true(
    one.docs.get(Relative("a.mbt")) is Some({ state: TabLoading, .. }),
  )
  // A plain re-open of a loaded document keeps the cached state — the show
  // command redraws from the table, never waiting on a re-read's reply.
  let docs = one.docs.copy()
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  let (_, again) = open_document(
    emit,
    { ..one, docs, },
    {
      ..test_ctx(),
      open_files: [Relative("a.mbt")],
      active_file: Some(Relative("a.mbt")),
    },
    Relative("a.mbt"),
    name="a.mbt",
    range=None,
    had_active=true,
  )
  assert_true(
    again.docs.get(Relative("a.mbt")) is Some({ state: TabLoaded(..), .. }),
  )
}

///|
test "changed-file review fences paired replies and ordinary opens leave review" {
  let emit = test_emit()
  let path = @pathx.Relative("a.mbt")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let change : ChangedFile = {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let (_, first) = open_changed_document(
    emit,
    owned_state(),
    ctx,
    change,
    had_active=false,
  )
  assert_eq(first.review_generation, 1)
  // With no cached document, this loading transition also clears any outgoing
  // quick-diff baseline while the paired working-tree read owns the next show.
  assert_true(
    first.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 1, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
  // Re-selecting the exact active row is idempotent: it keeps the in-flight
  // pair and does not let click cadence continuously supersede its reads.
  let (_, repeated) = open_changed_document(
    emit,
    first,
    ctx,
    change,
    had_active=true,
  )
  assert_true(repeated == first)
  // A genuinely different Git row for the same path still owns a new pair;
  // its predecessor cannot replace the baseline even though owner/path match.
  let different_row = { ..change, index_status: "M", worktree_status: " ", }
  let (_, second) = open_changed_document(
    emit,
    repeated,
    ctx,
    different_row,
    had_active=true,
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/a.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  // An ordinary read that began before the first review click carries no
  // token. It must not inherit the newer baseline if it settles afterward.
  let (_, pre_review_working) = update(
    emit,
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="a.mbt",
      file=Content(content="pre-review working", absolute~, sig="0:18"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    second,
    ctx,
  )
  assert_true(
    pre_review_working.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 2, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
  let (_, old_working) = update(
    emit,
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="a.mbt",
      file=Content(content="stale working", absolute~, sig="1:13"),
      file_link_generation=None,
      review_generation=Some(1),
      range=None,
      annotation=None,
    ),
    pre_review_working,
    ctx,
  )
  assert_true(
    old_working.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 2, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
  let (_, ignored) = update(
    emit,
    GitOriginalLoaded(
      owner=ctx.owner,
      background=false,
      path~,
      generation=1,
      original=@protocol.OriginalContent("old one"),
    ),
    old_working,
    ctx,
  )
  assert_true(
    ignored.docs.get(path)
    is Some(
      { review: Some({ generation: 2, baseline: ReviewLoading, .. }), .. }
    ),
  )
  let (_, reviewed) = update(
    emit,
    GitOriginalLoaded(
      owner=ctx.owner,
      background=false,
      path~,
      generation=2,
      original=@protocol.OriginalContent("old two"),
    ),
    ignored,
    ctx,
  )
  assert_true(
    reviewed.docs.get(path)
    is Some(
      {
        review: Some({ generation: 2, baseline: ReviewContent("old two"), .. }),
        ..
      }
    ),
  )
  let docs = reviewed.docs.copy()
  docs[path] = {
    ..loaded_doc("a.mbt"),
    review: Some({
      generation: 2,
      working_generation: 2,
      baseline: ReviewContent("old two"),
      view_mode: ReviewSource,
      selected: different_row,
    }),
  }
  // A symbol/annotation jump starts a fresh ordinary read instead of taking
  // the cached fast path. It still leaves review synchronously; the paired
  // command clears the displayed baseline before that read can fail.
  let (_, ranged_ordinary) = open_document(
    emit,
    { ..reviewed, docs, },
    ctx,
    path,
    name="a.mbt",
    range=Some(@common.Range(2, 1, 2, 4)),
    had_active=true,
  )
  assert_true(
    ranged_ordinary.docs.get(path)
    is Some({ state: TabLoaded(..), review: None, .. }),
  )
  let (_, ordinary) = open_document(
    emit,
    { ..reviewed, docs, },
    ctx,
    path,
    name="a.mbt",
    range=None,
    had_active=true,
  )
  assert_true(ordinary.docs.get(path) is Some({ review: None, .. }))
  let (_, review_after_ordinary) = update(
    emit,
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="a.mbt",
      file=Content(content="late review", absolute~, sig="3:11"),
      file_link_generation=None,
      review_generation=Some(2),
      range=None,
      annotation=None,
    ),
    ordinary,
    ctx,
  )
  assert_true(review_after_ordinary == ordinary)
}

///|
test "reselecting a settled review keeps its cached comparison generation" {
  let path = @pathx.Relative("settled.mbt")
  let change = test_modified_change(path)
  let doc = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 7,
      working_generation: 7,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewDiff,
      selected: change,
    }),
  }
  let docs = owned_state().docs.copy()
  docs[path] = doc
  let state = { ..owned_state(), review_generation: 7, docs, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, reselected) = open_changed_document(
    test_emit(),
    state,
    ctx,
    change,
    had_active=true,
  )
  assert_true(reselected == state)
  assert_true(
    reselected.docs.get(path)
    is Some(
      {
        state: TabLoaded(..),
        review: Some(
          {
            generation: 7,
            working_generation: 7,
            baseline: ReviewContent("HEAD source"),
            ..
          }
        ),
        ..
      }
    ),
  )
}

///|
test "changed-file review preserves a stale cached working document until reload" {
  let emit = test_emit()
  let path = @pathx.Relative("stale.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = { ..loaded_doc("stale.mbt"), stale: true, }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let change : ChangedFile = {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let (_, reviewing) = open_changed_document(
    emit,
    { ..owned_state(), docs, },
    ctx,
    change,
    had_active=true,
  )
  assert_true(
    reviewing.docs.get(path)
    is Some({ state: TabLoaded(..), review: Some(_), stale: true, .. }),
  )
  guard reviewing.docs.get(path) is Some(reviewing_doc) else {
    fail("reviewing document was not retained")
  }
  assert_false(working_side_ready_for_review(reviewing_doc))
  // The HEAD side can win the race, but it remains parked while the cached
  // working text is explicitly stale.
  let (_, baseline_first) = update(
    emit,
    GitOriginalLoaded(
      owner=ctx.owner,
      background=false,
      path~,
      generation=1,
      original=@protocol.OriginalContent("HEAD source"),
    ),
    reviewing,
    ctx,
  )
  guard baseline_first.docs.get(path) is Some(baseline_doc) else {
    fail("baseline document was not retained")
  }
  assert_true(
    baseline_doc.review
    is Some({ generation: 1, baseline: ReviewContent("HEAD source"), .. }),
  )
  assert_false(working_side_ready_for_review(baseline_doc))
  // Canceling the tagged review read through an ordinary open retains the
  // staleness marker, so `show_tab` schedules its own untagged refresh.
  let (_, ordinary) = open_document(
    emit,
    baseline_first,
    ctx,
    path,
    name="stale.mbt",
    range=None,
    had_active=true,
  )
  assert_true(
    ordinary.docs.get(path)
    is Some({ state: TabLoaded(..), review: None, stale: true, .. }),
  )
}

///|
test "review failures settle precisely and missing rename sources stay unavailable" {
  let emit = test_emit()
  let path = @pathx.Relative("new.mbt")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let rename : ChangedFile = {
    path,
    original_path: None,
    index_status: "R",
    worktree_status: " ",
    kind: ChangeRenamed,
  }
  let (_, unavailable) = open_changed_document(
    emit,
    owned_state(),
    ctx,
    rename,
    had_active=false,
  )
  assert_true(
    unavailable.docs.get(path)
    is Some(
      {
        review: Some(
          {
            generation: 1,
            baseline: ReviewFailed(
              "the original path is outside this workspace"
            ),
            ..
          }
        ),
        ..
      }
    ),
  )

  let modified = {
    ..rename,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let (_, loading) = open_changed_document(
    emit,
    owned_state(),
    ctx,
    modified,
    had_active=false,
  )
  let (_, failed) = update(
    emit,
    GitOriginalFailed(
      owner=ctx.owner,
      background=false,
      path~,
      generation=1,
      message="Git baseline failed",
    ),
    loading,
    ctx,
  )
  assert_true(
    failed.docs.get(path)
    is Some(
      {
        review: Some(
          { generation: 1, baseline: ReviewFailed("Git baseline failed"), .. }
        ),
        ..
      }
    ),
  )
  let (_, read_failed) = update(
    emit,
    FileFailed(
      owner=ctx.owner,
      epoch=0,
      path~,
      file_link_generation=None,
      review_generation=Some(1),
      message="file disappeared",
    ),
    failed,
    ctx,
  )
  assert_true(
    read_failed.docs.get(path)
    is Some({ state: TabReadFailed("file disappeared"), .. }),
  )
  assert_true(read_failed.error is None)
}

///|
test "deleted changes preview HEAD and working-file loads retain early baselines" {
  let emit = test_emit()
  let deleted_path = @pathx.Relative("gone.mbt")
  let ctx = {
    ..test_ctx(),
    open_files: [deleted_path],
    active_file: Some(deleted_path),
  }
  let deleted : ChangedFile = {
    path: deleted_path,
    original_path: None,
    index_status: " ",
    worktree_status: "D",
    kind: ChangeDeleted,
  }
  let (_, loading) = open_changed_document(
    emit,
    owned_state(),
    ctx,
    deleted,
    had_active=false,
  )
  assert_true(
    loading.docs.get(deleted_path)
    is Some(
      {
        state: TabDeleted,
        review: Some({ generation: 1, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
  let (_, preview) = update(
    emit,
    GitOriginalLoaded(
      owner=ctx.owner,
      background=false,
      path=deleted_path,
      generation=1,
      original=@protocol.OriginalContent("removed source"),
    ),
    loading,
    ctx,
  )
  assert_true(
    preview.docs.get(deleted_path)
    is Some(
      {
        state: TabDeleted,
        review: Some(
          { generation: 1, baseline: ReviewContent("removed source"), .. }
        ),
        ..
      }
    ),
  )
  guard preview.docs.get(deleted_path) is Some(deleted_preview) else {
    fail("deleted review was missing")
  }
  assert_eq(deleted_preview.diff_content(), Some(("removed source", "")))
  assert_true(deleted_preview.review is Some({ view_mode: ReviewDiff, .. }))
  let (_, source) = update(emit, ToggleReviewDiff, preview, ctx)
  assert_true(
    source.docs.get(deleted_path)
    is Some({ review: Some({ view_mode: ReviewSource, .. }), .. }),
  )
  let (_, full_diff_again) = update(emit, ToggleReviewDiff, source, ctx)
  assert_true(
    full_diff_again.docs.get(deleted_path)
    is Some({ review: Some({ view_mode: ReviewDiff, .. }), .. }),
  )

  // The HEAD request may beat the ordinary filesystem read. Its result stays
  // on the loading document and is preserved when `FileLoaded` settles it.
  let live_path = @pathx.Relative("live.mbt")
  let live_ctx = {
    ..ctx,
    open_files: [live_path],
    active_file: Some(live_path),
  }
  let live = {
    ..deleted,
    path: live_path,
    worktree_status: "M",
    kind: ChangeModified,
  }
  let (_, live_loading) = open_changed_document(
    emit,
    owned_state(),
    live_ctx,
    live,
    had_active=false,
  )
  let (_, baseline_first) = update(
    emit,
    GitOriginalLoaded(
      owner=live_ctx.owner,
      background=false,
      path=live_path,
      generation=1,
      original=@protocol.Missing,
    ),
    live_loading,
    live_ctx,
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/live.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, loaded) = update(
    emit,
    FileLoaded(
      owner=live_ctx.owner,
      epoch=0,
      path=live_path,
      name="live.mbt",
      file=Content(content="new", absolute~, sig="2:3"),
      file_link_generation=None,
      review_generation=Some(1),
      range=None,
      annotation=None,
    ),
    baseline_first,
    live_ctx,
  )
  assert_true(
    loaded.docs.get(live_path)
    is Some(
      {
        state: TabLoaded(content="new", ..),
        review: Some({ generation: 1, baseline: ReviewMissing, .. }),
        ..
      }
    ),
  )
  guard loaded.docs.get(live_path) is Some(added_preview) else {
    fail("added review was missing")
  }
  assert_eq(added_preview.diff_content(), Some(("", "new")))
}

///|
test "narrow ctx: opening or activating a document closes the tree pane" {
  let emit = test_emit()
  let narrow : Ctx = {
    ..test_ctx(),
    narrow: true,
    open_files: [Relative("a.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let start = { ..owned_state(), tree_open: true, }
  // A fresh open drills down into the viewer.
  let (_, opened) = open_document(
    emit,
    start,
    narrow,
    Relative("a.mbt"),
    name="a.mbt",
    range=None,
    had_active=false,
  )
  assert_false(opened.tree_open)
  // Back to the tree, then activating an open document drills down again.
  let (_, tree) = update(emit, ToggleTree, opened, narrow)
  assert_true(tree.tree_open)
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  let (_, activated) = activate(
    emit,
    { ..tree, docs, },
    narrow,
    Relative("a.mbt"),
  )
  assert_false(activated.tree_open)
  // The wide layout keeps the pane open alongside the viewer.
  let (_, wide) = open_document(
    emit,
    start,
    {
      ..test_ctx(),
      open_files: [Relative("b.mbt")],
      active_file: Some(Relative("b.mbt")),
    },
    Relative("b.mbt"),
    name="b.mbt",
    range=None,
    had_active=false,
  )
  assert_true(wide.tree_open)
}

///|
test "activate without a document entry is a no-op" {
  let emit = test_emit()
  let (_, same) = activate(
    emit,
    owned_state(),
    test_ctx(),
    Relative("gone.mbt"),
  )
  assert_true(same == owned_state())
}

///|
test "close_document drops the entry and forces the tree open on the last one" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  docs[Relative("b.mbt")] = loaded_doc("b.mbt")
  let state = { ..owned_state(), docs, tree_open: false, }
  // Closing the active document with a neighbor left: the entry goes, the
  // tree stays as it was.
  let (_, one) = close_document(
    emit,
    state,
    test_ctx(),
    Relative("a.mbt"),
    next=Some(Relative("b.mbt")),
    was_active=true,
  )
  assert_false(one.docs.contains(Relative("a.mbt")))
  assert_true(one.docs.contains(Relative("b.mbt")))
  assert_false(one.tree_open)
  // Closing the last document: the viewer falls back to the placeholder and
  // the tree is forced open so the panel is never a dead pane.
  let (_, last) = close_document(
    emit,
    one,
    test_ctx(),
    Relative("b.mbt"),
    next=None,
    was_active=true,
  )
  assert_true(last.docs.is_empty())
  assert_true(last.tree_open)
}

///|
test "FileLoaded settles content into its document, active or not" {
  let emit = test_emit()
  guard @resource.of_path(@interop.ChannelId::Local, "/work/a.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = {
    name: "a.mbt",
    state: TabLoading,
    review: None,
    stale: false,
  }
  docs[Relative("b.mbt")] = loaded_doc("b.mbt")
  let state = { ..owned_state(), docs, }
  let ctx = {
    ..test_ctx(),
    open_files: [Relative("a.mbt"), Relative("b.mbt")],
    active_file: Some(Relative("b.mbt")),
  }
  let (_, next) = update(
    emit,
    FileLoaded(
      owner=test_ctx().owner,
      epoch=0,
      path=Relative("a.mbt"),
      name="a.mbt",
      file=Content(content="fn main {}", absolute~, sig="2:0"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    state,
    ctx,
  )
  assert_true(
    next.docs.get(Relative("a.mbt"))
    is Some({ state: TabLoaded(content="fn main {}", ..), .. }),
  )
  // A reply for a closed document (or another conversation) is dropped.
  guard @resource.of_path(@interop.ChannelId::Local, "/work/gone.mbt")
    is Some(gone_absolute) else {
    fail("test closed file resource was not absolute")
  }
  let (_, stray) = update(
    emit,
    FileLoaded(
      owner=test_ctx().owner,
      epoch=0,
      path=Relative("gone.mbt"),
      name="gone.mbt",
      file=Content(content="", absolute=gone_absolute, sig="2:0"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    next,
    ctx,
  )
  assert_true(stray.docs.length() == 2)
  let (_, other) = update(
    emit,
    FileLoaded(
      owner={
        channel: @interop.ChannelId::Remote("other"),
        session: "desktop-test",
      },
      epoch=0,
      path=Relative("a.mbt"),
      name="a.mbt",
      file=Binary,
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    stray,
    ctx,
  )
  assert_true(
    other.docs.get(Relative("a.mbt")) is Some({ state: TabLoaded(..), .. }),
  )
  // A stat issued before a placement/reroot boundary is stale even when the
  // same conversation is active again. It cannot invalidate a newer live doc.
  let epoch_state = { ..state, request_epoch: 2, }
  let (_, old_epoch) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=1, stats=[
      { path: Relative("a.mbt"), signature: Missing, },
    ]),
    epoch_state,
    ctx,
  )
  assert_true(old_epoch == epoch_state)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/a.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, old_read) = update(
    emit,
    FileLoaded(
      owner=test_ctx().owner,
      epoch=1,
      path=Relative("a.mbt"),
      name="a.mbt",
      file=Content(content="stale", absolute~, sig="9:0"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    epoch_state,
    ctx,
  )
  assert_true(old_read == epoch_state)
  let (_, old_listing) = update(
    emit,
    DirLoaded(owner=test_ctx().owner, epoch=1, path=@pathx.Relative::root(), entries=[]),
    epoch_state,
    ctx,
  )
  assert_true(old_listing == epoch_state)
  let (_, old_index) = update(
    emit,
    FilesIndexed(
      owner=test_ctx().owner,
      epoch=1,
      files=[Relative("stale.mbt")],
      truncated=false,
    ),
    epoch_state,
    ctx,
  )
  assert_true(old_index == epoch_state)
  let (_, old_watch_failure) = update(
    emit,
    FileWatchFailed(
      channel=test_ctx().owner.channel,
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(1),
      message="stale watcher",
    ),
    epoch_state,
    ctx,
  )
  assert_true(old_watch_failure == epoch_state)
}

///|
test "sync re-roots the document table from the dock's projection" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("old.mbt")] = loaded_doc("old.mbt")
  let state = { ..owned_state(), docs, tree_open: false, }
  // Switch conversations: the dock restored a two-file strip for the new
  // one; the table re-seeds from it, identities only.
  let other : Ctx = {
    ..test_ctx(),
    owner: {
      channel: @interop.ChannelId::Remote("other"),
      session: "desktop-test",
    },
    open_files: [Relative("a.mbt"), Relative("b.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let (rerooted, _) = sync(emit, state, other)
  assert_true(rerooted.owner is Some({ channel: Remote("other"), .. }))
  assert_false(rerooted.docs.contains(Relative("old.mbt")))
  assert_true(
    rerooted.docs.get(Relative("a.mbt")) is Some({ state: TabLoading, .. }),
  )
  assert_true(
    rerooted.docs.get(Relative("b.mbt")) is Some({ state: TabLoading, .. }),
  )
  // The pane-visibility preference follows the panel, not the conversation.
  assert_false(rerooted.tree_open)
}

///|
/// The bug this guards against: with the panel closed but files remaining
/// open, switching conversations used to skip the re-root while the watcher
/// followed the new session — the next fs_changed then stat'ed the old
/// conversation's paths against the new workspace, marking hidden documents
/// deleted or stale for files that never moved.
test "a closed panel still re-roots when the conversation switches" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  let state = {
    ..owned_state(),
    docs,
    children: Map([
      (
        @pathx.Relative::root(),
        [{ name: "a.mbt", path: Relative("a.mbt"), is_dir: false, }],
      ),
    ]),
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [Relative("a.mbt")],
      directories: [],
      recursive: false,
    }),
    file_link_generation: 4,
  }
  // The new conversation has nothing open and the panel is closed.
  let other : Ctx = {
    ..test_ctx(),
    owner: {
      channel: @interop.ChannelId::Remote("other"),
      session: "desktop-test",
    },
    panel_open: false,
  }
  let (parked, _) = sync(emit, state, other)
  assert_true(parked.owner is Some({ channel: Remote("other"), .. }))
  assert_eq(parked.file_link_generation, 5)
  assert_true(parked.docs.is_empty())
  // Nothing left to track in the new conversation, so the watcher parks.
  assert_true(parked.watching is None)
  // Switching back (still closed) re-seeds the table and the watcher
  // follows the open files again.
  let back : Ctx = {
    ..test_ctx(),
    panel_open: false,
    open_files: [Relative("a.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let (restored, _) = sync(emit, parked, back)
  assert_eq(restored.file_link_generation, 6)
  assert_true(
    restored.docs.get(Relative("a.mbt")) is Some({ state: TabLoading, .. }),
  )
  assert_true(
    restored.watching
    is Some(
      {
        owner: { channel: Local, session: "desktop-test", },
        root: _,
        files: [Relative("a.mbt")],
        directories: [],
        recursive: false,
      }
    ),
  )
}

///|
test "a resolved placement change reroots documents and fences old replies" {
  let emit = test_emit()
  let path = @pathx.Relative("reviewed.mbt")
  guard @resource.of_path(@interop.ChannelId::Local, "/project-a")
    is Some(old_workspace) else {
    fail("test workspace resource was not absolute")
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc("reviewed.mbt"),
    review: Some({
      generation: 4,
      working_generation: 4,
      baseline: ReviewContent("root version\n"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let state = {
    ..owned_state(),
    placement: PlacementLive(@interop.WorkspaceRoot(root=old_workspace)),
    changes: ChangeListReady(
      repository=true,
      files=[test_modified_change(path)],
      refreshing=false,
      refresh_again=false,
    ),
    changes_head: Some("root-head"),
    changes_head_known: true,
    changes_generation: 2,
    file_link_generation: 6,
    review_generation: 4,
    docs,
    children: Map([
      (
        @pathx.Relative::root(),
        [{ name: "reviewed.mbt", path, is_dir: false, }],
      ),
    ]),
    index: IndexReady(
      files=[path],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
    watching: Some({
      owner: test_ctx().owner,
      root: old_workspace,
      files: [path],
      directories: [@pathx.Relative::root()],
      recursive: true,
    }),
  }
  let worktree_ctx : Ctx = {
    ..test_ctx(),
    placement: Some(
      @interop.Worktree(
        project=old_workspace,
        name="wt-1",
        root=test_ctx().test_resource("/project-a/.worktrees/wt-1"),
      ),
    ),
    open_files: [path],
    active_file: Some(path),
  }
  let (moved, _) = sync(emit, state, worktree_ctx)
  assert_eq(moved.request_epoch, state.request_epoch + 1)
  assert_eq(moved.changes_generation, state.changes_generation + 1)
  assert_eq(moved.file_link_generation, state.file_link_generation + 1)
  assert_true(
    moved.placement.identity() is Some(@interop.Worktree(name="wt-1", ..)),
  )
  assert_eq(
    moved.placement.identity().bind(value => value.project_root()),
    Some(old_workspace),
  )
  assert_true(
    moved.docs.get(path)
    is Some({ state: TabLoading, review: None, stale: false, .. }),
  )
  assert_true(moved.children.is_empty())
  assert_true(moved.index is IndexEmpty)
  assert_true(moved.changes is ChangeListIdle)
  assert_false(moved.changes_head_known)
  assert_true(
    moved.watching
    is Some(
      {
        owner: { channel: Local, session: "desktop-test", },
        root: _,
        files: [@pathx.Relative("reviewed.mbt")],
        directories: [@pathx.Relative("")],
        recursive: false,
      }
    ),
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/project-a/reviewed.mbt")
    is Some(old_absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, after_old_reply) = update(
    emit,
    FileLoaded(
      owner=worktree_ctx.owner,
      epoch=state.request_epoch,
      path~,
      name="reviewed.mbt",
      file=Content(content="old root reply", absolute=old_absolute, sig="1:1"),
      file_link_generation=None,
      review_generation=Some(4),
      range=None,
      annotation=None,
    ),
    moved,
    { ..worktree_ctx, request_epoch: moved.request_epoch, },
  )
  assert_true(after_old_reply == moved)
  let (_, after_old_changes) = update(
    emit,
    ChangesLoaded(
      owner=worktree_ctx.owner,
      generation=state.changes_generation,
      repository=true,
      head=Some("root-head"),
      files=[test_modified_change(path)],
    ),
    moved,
    { ..worktree_ctx, request_epoch: moved.request_epoch, },
  )
  assert_true(after_old_changes == moved)

  // A workspace reassignment for the same conversation is the same hard
  // boundary even when both sides resolve to the ordinary project root.
  guard @resource.of_path(@interop.ChannelId::Local, "/project-b")
    is Some(new_workspace) else {
    fail("test workspace resource was not absolute")
  }
  let (reassigned, _) = sync(emit, state, {
    ..worktree_ctx,
    placement: Some(@interop.WorkspaceRoot(root=new_workspace)),
  })
  assert_eq(reassigned.request_epoch, state.request_epoch + 1)
  assert_eq(reassigned.file_link_generation, state.file_link_generation + 1)
  assert_true(
    reassigned.placement.identity() is Some(@interop.WorkspaceRoot(..)),
  )
  assert_eq(
    reassigned.placement.identity().bind(value => value.checkout_root()),
    Some(new_workspace),
  )
  assert_true(
    reassigned.docs.get(path)
    is Some({ state: TabLoading, review: None, stale: false, .. }),
  )
}

///|
test "a missing checkout parks files and refuses editor actions until repair" {
  let emit = test_emit()
  let present = test_ctx().test_worktree("wt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  docs[Relative("b.mbt")] = {
    ..loaded_doc("b.mbt"),
    review: Some({
      generation: 4,
      working_generation: 4,
      baseline: ReviewContent("before\n"),
      view_mode: ReviewSource,
      selected: test_modified_change(Relative("b.mbt")),
    }),
    stale: true,
  }
  let state = {
    ..owned_state_at(present),
    docs,
    review_generation: 4,
    index: IndexReady(
      files=[Relative("a.mbt")],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
    watching: Some({
      owner: present.owner,
      root: present.test_root(),
      files: [Relative("a.mbt")],
      directories: [@pathx.Relative::root()],
      recursive: true,
    }),
  }
  let missing : Ctx = {
    ..present,
    placement: Some(
      @interop.MissingWorktree(project=present.test_root(), name="wt"),
    ),
    open_files: [Relative("a.mbt"), Relative("b.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let (parked, _) = sync(emit, state, missing)
  assert_true(parked.owner == Some(present.owner))
  assert_true(
    parked.docs.get(Relative("a.mbt")) is Some({ state: TabLoaded(..), .. }),
  )
  assert_true(parked.children.is_empty())
  assert_true(parked.index is IndexEmpty)
  assert_true(parked.watching is None)
  assert_true(parked.placement.is_parked())
  assert_eq(parked.request_epoch, state.request_epoch + 1)
  let (_, refused_index) = update(emit, EnsureFileIndex, parked, missing)
  assert_true(refused_index == parked)
  // Root/dock callers also use these public entry points directly, bypassing
  // the guarded message dispatcher. They enforce the same placement boundary.
  let (_, direct_open) = open_document(
    emit,
    parked,
    missing,
    Relative("new.mbt"),
    name="new.mbt",
    range=None,
    had_active=true,
  )
  assert_true(direct_open == parked)
  let (_, direct_review) = open_changed_document(
    emit,
    parked,
    missing,
    test_modified_change(Relative("a.mbt")),
    had_active=true,
  )
  assert_true(direct_review == parked)
  let (_, direct_activation) = activate(
    emit,
    parked,
    missing,
    Relative("a.mbt"),
  )
  assert_true(direct_activation == parked)
  let (_, direct_toggle) = panel_toggle_cmds(
    emit,
    parked,
    missing,
    opening=true,
  )
  assert_true(direct_toggle == parked)
  // A close still updates the local strip mirror, but cannot activate and
  // reload the promoted review until placement is repaired.
  let (_, direct_close) = close_document(
    emit,
    parked,
    missing,
    Relative("a.mbt"),
    next=Some(Relative("b.mbt")),
    was_active=true,
  )
  assert_false(direct_close.docs.contains(Relative("a.mbt")))
  assert_true(
    direct_close.docs.get(Relative("b.mbt")) ==
    parked.docs.get(Relative("b.mbt")),
  )
  assert_eq(direct_close.review_generation, parked.review_generation)
  let (_, selected) = update(
    emit,
    ExplorerModeSelected(ExplorerChanges),
    parked,
    missing,
  )
  assert_true(selected.explorer_mode is ExplorerChanges)
  // Repeated reconciliation is pure while the checkout remains missing.
  let (still_parked, _) = sync(emit, parked, missing)
  assert_true(still_parked == parked)
  let restored_ctx = {
    ..present,
    open_files: [Relative("a.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let (restored, _) = sync(emit, parked, restored_ctx)
  assert_true(
    restored.docs.get(Relative("a.mbt"))
    is Some({ state: TabLoaded(..), stale: true, .. }),
  )
  assert_false(restored.placement.is_parked())
  assert_eq(restored.request_epoch, parked.request_epoch)
}

///|
test "opening after a hidden checkout repair restores a stale reviewed tab" {
  let emit = test_emit()
  let path = @pathx.Relative("reviewed.mbt")
  let change = test_modified_change(path)
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc("reviewed.mbt"),
    review: Some({
      generation: 4,
      working_generation: 4,
      baseline: ReviewContent("before\n"),
      view_mode: ReviewSource,
      selected: change,
    }),
  }
  let present : Ctx = {
    ..test_ctx(),
    panel_open: false,
    open_files: [path],
    active_file: Some(path),
  }
  let present = present.test_worktree("wt")
  let state = { ..owned_state_at(present), docs, review_generation: 4, }
  let missing : Ctx = {
    ..present,
    placement: Some(
      @interop.MissingWorktree(project=present.test_root(), name="wt"),
    ),
  }
  let (parked, _) = sync(emit, state, missing)
  let (restored, _) = sync(emit, parked, present)
  assert_true(
    restored.docs.get(path)
    is Some({ review: Some({ working_generation: 4, .. }), stale: true, .. }),
  )
  let (_, reopened) = panel_toggle_cmds(
    emit,
    restored,
    { ..present, panel_open: true, },
    opening=true,
  )
  assert_true(reopened.review_generation == 6)
  assert_true(
    reopened.docs.get(path)
    is Some({ review: Some({ working_generation: 6, .. }), stale: true, .. }),
  )
}

///|
test "an unresolved gap retains identity so same-checkout recovery restores" {
  let emit = test_emit()
  let path = @pathx.Relative("reviewed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc("reviewed.mbt"),
    review: Some({
      generation: 4,
      working_generation: 4,
      baseline: ReviewContent("before\n"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let present : Ctx = {
    ..test_ctx(),
    panel_open: false,
    open_files: [path],
    active_file: Some(path),
  }
  let present = present.test_worktree("wt")
  let state = { ..owned_state_at(present), docs, review_generation: 4, }
  // BridgeReady clears the registry: the projection is unresolved, not moved.
  let unresolved : Ctx = { ..present, placement: None, }
  let (parked, _) = sync(emit, state, unresolved)
  // The gap must not erase the last known identity.
  assert_true(
    parked.placement
    is PlacementParked(last_known=Some(@interop.Worktree(name="wt", ..))),
  )
  // The refreshed registry reports the same worktree: an availability change,
  // so the review survives for revalidation instead of a hard reroot.
  let (restored, _) = sync(emit, parked, present)
  assert_false(restored.placement.is_parked())
  assert_eq(restored.request_epoch, parked.request_epoch)
  assert_true(
    restored.docs.get(path)
    is Some({ review: Some({ working_generation: 4, .. }), stale: true, .. }),
  )
}

///|
test "recovery from an unresolved gap into another checkout reroots" {
  let emit = test_emit()
  let path = @pathx.Relative("reviewed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc("reviewed.mbt"),
    review: Some({
      generation: 4,
      working_generation: 4,
      baseline: ReviewContent("before\n"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let present : Ctx = {
    ..test_ctx(),
    open_files: [path],
    active_file: Some(path),
  }
  let present = present.test_worktree("wt")
  let state = { ..owned_state_at(present), docs, review_generation: 4, }
  let (parked, _) = sync(emit, state, { ..present, placement: None, })
  assert_true(
    parked.placement
    is PlacementParked(last_known=Some(@interop.Worktree(name="wt", ..))),
  )
  // Another client unbound the worktree during the gap; the conversation now
  // resolves to the project's main checkout. The retained identity exposes
  // the move, so the old checkout's documents and baselines must not be
  // restored against files read from the new root.
  let recovered : Ctx = {
    ..present,
    placement: Some(@interop.WorkspaceRoot(root=present.test_root())),
  }
  let (rerooted, _) = sync(emit, parked, recovered)
  assert_true(rerooted.placement is PlacementLive(@interop.WorkspaceRoot(..)))
  assert_eq(rerooted.request_epoch, parked.request_epoch + 1)
  assert_true(
    rerooted.docs.get(path)
    is Some({ state: TabLoading, review: None, stale: false, .. }),
  )
}

///|
test "a missing checkout settles an in-flight Changes request for retry" {
  let emit = test_emit()
  let present = test_ctx().test_worktree("wt")
  let state = {
    ..owned_state_at(present),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=true),
    changes_generation: 1,
    watching: Some({
      owner: present.owner,
      root: present.test_root(),
      files: [],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let missing : Ctx = {
    ..present,
    placement: Some(
      @interop.MissingWorktree(project=present.test_root(), name="wt"),
    ),
  }
  let (parked, _) = sync(emit, state, missing)
  assert_true(parked.changes is ChangeListIdle)
  assert_true(parked.changes_generation == 2)
  assert_true(parked.watching is None)
  // The host reply is local state only, but the parked update boundary drops
  // it. The sync above has already removed the liveness hazard.
  let (_, after_reply) = update(
    emit,
    ChangesLoaded(
      owner=present.owner,
      generation=1,
      repository=true,
      head=None,
      files=[],
    ),
    parked,
    missing,
  )
  assert_true(after_reply == parked)
  let (restored, _) = sync(emit, after_reply, present)
  assert_true(restored.changes is ChangeListLoading(refresh_again=false))
  assert_true(restored.changes_generation == 3)
}

///|
test "checkout recovery restarts a review whose paired replies were parked" {
  let emit = test_emit()
  let present = test_ctx().test_worktree("wt")
  let path = @pathx.Relative("reviewed.mbt")
  let change : ChangedFile = {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    name: "reviewed.mbt",
    state: TabLoading,
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewLoading,
      view_mode: ReviewSource,
      selected: change,
    }),
    stale: false,
  }
  let state = {
    ..owned_state_at(present),
    changes: ChangeListReady(
      repository=true,
      files=[change],
      refreshing=true,
      refresh_again=false,
    ),
    changes_generation: 1,
    changes_head: Some("same-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
    watching: Some({
      owner: present.owner,
      root: present.test_root(),
      files: [path],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let missing : Ctx = {
    ..present,
    placement: Some(
      @interop.MissingWorktree(project=present.test_root(), name="wt"),
    ),
    open_files: [path],
    active_file: Some(path),
  }
  let (parked, _) = sync(emit, state, missing)
  assert_true(
    parked.changes is ChangeListReady(refreshing=false, refresh_again=false, ..),
  )
  assert_true(parked.review_recovery_pending)
  assert_true(parked.placement.is_parked())
  assert_eq(parked.request_epoch, state.request_epoch + 1)
  assert_eq(parked.review_generation, 4)
  let (restored, _) = sync(emit, parked, {
    ..present,
    open_files: [path],
    active_file: Some(path),
  })
  assert_true(
    restored.changes
    is ChangeListReady(refreshing=true, refresh_again=false, ..),
  )
  assert_true(restored.changes_generation == 3)
  assert_true(restored.review_recovery_pending)
  assert_false(restored.placement.is_parked())
  assert_eq(restored.request_epoch, parked.request_epoch)
  // A second disappearance before the recovery snapshot settles is still a
  // fresh placement boundary: pending review recovery is not the parked flag.
  let (parked_again, _) = sync(emit, restored, missing)
  assert_true(parked_again.placement.is_parked())
  assert_eq(parked_again.request_epoch, restored.request_epoch + 1)
  let (_, restarted) = update(
    emit,
    ChangesLoaded(
      owner=present.owner,
      generation=3,
      repository=true,
      head=Some("same-head"),
      files=[change],
    ),
    restored,
    { ..present, open_files: [path], active_file: Some(path), },
  )
  assert_true(restarted.review_generation == 5)
  assert_false(restarted.review_recovery_pending)
  assert_true(
    restarted.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 5, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
}

///|
test "hidden checkout recovery retries failed Changes once before parking" {
  let emit = test_emit()
  let present = test_ctx().test_worktree("wt")
  let path = @pathx.Relative("reviewed.mbt")
  let change : ChangedFile = {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    name: "reviewed.mbt",
    state: TabLoading,
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewLoading,
      view_mode: ReviewSource,
      selected: change,
    }),
    stale: false,
  }
  let state = {
    ..owned_state_at(present),
    tree_open: false,
    changes: ChangeListFailed("transient Git failure"),
    changes_generation: 1,
    changes_head: Some("same-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let missing : Ctx = {
    ..present,
    placement: Some(
      @interop.MissingWorktree(project=present.test_root(), name="wt"),
    ),
    open_files: [path],
    active_file: Some(path),
  }
  let (parked, _) = sync(emit, state, missing)
  assert_true(parked.changes is ChangeListIdle)
  assert_true(parked.review_recovery_pending)
  let restored_ctx = { ..present, open_files: [path], active_file: Some(path), }
  let (restored, _) = sync(emit, parked, restored_ctx)
  assert_true(restored.changes is ChangeListLoading(refresh_again=false))
  assert_true(restored.changes_generation == 3)
  assert_true(restored.review_recovery_pending)
  assert_false(explorer_visible(restored, restored_ctx))
  // The placement transition grants exactly one automatic attempt. If it
  // fails too, ordinary sync leaves the failure parked at the same generation.
  let (_, failed_again) = update(
    emit,
    ChangesFailed(
      owner=present.owner,
      generation=3,
      message="Git still unavailable",
    ),
    restored,
    restored_ctx,
  )
  let (still_failed, _) = sync(emit, failed_again, restored_ctx)
  assert_true(still_failed.changes is ChangeListFailed("Git still unavailable"))
  assert_true(still_failed.changes_generation == 3)
  let (_, restarted) = update(
    emit,
    ChangesLoaded(
      owner=present.owner,
      generation=3,
      repository=true,
      head=Some("same-head"),
      files=[change],
    ),
    restored,
    restored_ctx,
  )
  assert_true(restarted.review_generation == 5)
  assert_false(restarted.review_recovery_pending)
}

///|
test "ordinary Changes polls do not supersede healthy in-flight reviews" {
  let emit = test_emit()
  let present = test_ctx()
  let path = @pathx.Relative("slow.mbt")
  let change : ChangedFile = {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    name: "slow.mbt",
    state: TabLoading,
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewLoading,
      view_mode: ReviewSource,
      selected: change,
    }),
    stale: false,
  }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[change],
      refreshing=true,
      refresh_again=false,
    ),
    changes_generation: 1,
    changes_head: Some("same-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let (_, polled) = update(
    emit,
    ChangesLoaded(
      owner=present.owner,
      generation=1,
      repository=true,
      head=Some("same-head"),
      files=[change],
    ),
    state,
    { ..present, open_files: [path], active_file: Some(path), },
  )
  assert_true(polled.review_generation == 3)
  assert_true(
    polled.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 3, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
}

///|
test "an unresolved placement parks files and refuses editor actions" {
  let emit = test_emit()
  let present = test_ctx()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  let state = {
    ..owned_state(),
    docs,
    watching: Some({
      owner: present.owner,
      root: present.test_root(),
      files: [Relative("a.mbt")],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let unresolved : Ctx = {
    ..present,
    owner: { ..present.owner, session: "", },
    placement: None,
    open_files: [],
    active_file: None,
  }
  let (parked, _) = sync(emit, state, unresolved)
  assert_true(parked.owner is Some({ session: "", .. }))
  assert_true(parked.docs.is_empty())
  assert_true(parked.watching is None)
  let (_, refused_index) = update(emit, EnsureFileIndex, parked, unresolved)
  assert_true(refused_index == parked)
  let (_, selected) = update(
    emit,
    ExplorerModeSelected(ExplorerChanges),
    parked,
    unresolved,
  )
  assert_true(selected.explorer_mode is ExplorerChanges)
}

///|
test "Search Explorer selection survives a conversation owner switch" {
  let state = { ..owned_state(), explorer_mode: ExplorerSearch, }
  let next_ctx = {
    ..test_ctx(),
    owner: { ..test_ctx().owner, session: "another-conversation", },
    open_files: [],
    active_file: None,
  }
  let (switched, _) = sync(test_emit(), state, next_ctx)
  assert_true(switched.owner == Some(next_ctx.owner))
  assert_true(switched.explorer_mode is ExplorerSearch)
}

///|
test "RevealDirectory opens the breadcrumb picker without moving the explorer" {
  let emit = test_emit()
  let (_, closed) = update(
    emit,
    ToggleTree,
    { ..owned_state(), explorer_mode: ExplorerChanges, },
    test_ctx(),
  )
  assert_false(closed.tree_open)
  let (_, opened) = update(
    emit,
    RevealDirectory(Relative("src")),
    closed,
    test_ctx(),
  )
  assert_false(opened.tree_open)
  assert_true(opened.explorer_mode is ExplorerChanges)
  assert_true(opened.highlighted is Some(Relative("src")))
  assert_true(opened.loading.contains(Relative("src")))
}

///|
test "breadcrumb directory picker loads once, navigates cached folders, and toggles" {
  let emit = test_emit()
  let (_, loading) = update(
    emit,
    RevealDirectory(Relative("deepseek")),
    owned_state(),
    test_ctx(),
  )
  assert_true(loading.highlighted is Some(Relative("deepseek")))
  assert_true(loading.loading.contains(Relative("deepseek")))
  let children = loading.children.copy()
  children[Relative("deepseek/docs")] = []
  let cached = { ..loading, children, }
  let (_, nested) = update(
    emit,
    RevealDirectory(Relative("deepseek/docs")),
    cached,
    test_ctx(),
  )
  assert_true(nested.highlighted is Some(Relative("deepseek/docs")))
  assert_false(nested.loading.contains(Relative("deepseek/docs")))
  let (_, closed) = update(
    emit,
    RevealDirectory(Relative("deepseek/docs")),
    nested,
    test_ctx(),
  )
  assert_true(closed.highlighted is None)
}

///|
test "breadcrumb dismissal does not disturb the explorer tree" {
  let state = {
    ..owned_state(),
    tree_open: false,
    expanded: [Relative("src")],
    highlighted: Some(Relative("deepseek")),
  }
  let (_, dismissed) = update(
    test_emit(),
    HighlightCleared(Relative("deepseek")),
    state,
    test_ctx(),
  )
  assert_true(dismissed.highlighted is None)
  assert_false(dismissed.tree_open)
  assert_true(dismissed.expanded == [Relative("src")])
}

///|
test "a ready file index watches non-ignored descendants while hidden" {
  let state = {
    ..owned_state(),
    index: IndexReady(
      files=[Relative("nested/deep/file.mbt")],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
  }
  let hidden = { ..test_ctx(), panel_open: false, }
  let (watched, _) = sync(test_emit(), state, hidden)
  assert_true(
    watched.watching
    is Some(
      {
        owner: { channel: Local, session: "desktop-test", },
        root: _,
        files: [],
        directories: [],
        recursive: true,
      }
    ),
  )
}

///|
test "reopening Changes refreshes after the explorer is hidden" {
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let closed_ctx = { ..test_ctx(), panel_open: false, }
  let (closed, _) = sync(test_emit(), state, closed_ctx)
  assert_false(closed.explorer_was_visible)
  assert_true(closed.watching is None)
  let (refreshed, _) = sync(test_emit(), closed, test_ctx())
  assert_true(refreshed.explorer_was_visible)
  assert_true(
    refreshed.changes
    is ChangeListReady(refreshing=true, refresh_again=false, ..),
  )
}

///|
test "showing a hidden explorer refreshes Changes before polling resumes" {
  let hidden_ctx = {
    ..test_ctx(),
    active_file: Some(Relative("src/main.mbt")),
  }
  let state = {
    ..owned_state(),
    tree_open: false,
    explorer_mode: ExplorerChanges,
    explorer_was_visible: false,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let (hidden, _) = sync(test_emit(), state, hidden_ctx)
  assert_false(hidden.explorer_was_visible)
  assert_true(hidden.changes is ChangeListReady(refreshing=false, ..))
  let (refreshed, _) = sync(
    test_emit(),
    { ..hidden, tree_open: true, },
    hidden_ctx,
  )
  assert_true(refreshed.explorer_was_visible)
  assert_true(refreshed.changes is ChangeListReady(refreshing=true, ..))
}

///|
test "reopening Changes latches a follow-up for an in-flight refresh" {
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=true,
      refresh_again=false,
    ),
    changes_generation: 1,
    explorer_was_visible: false,
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let (refreshed, _) = sync(test_emit(), state, test_ctx())
  assert_true(
    refreshed.changes
    is ChangeListReady(refreshing=true, refresh_again=true, ..),
  )
  assert_true(refreshed.changes_generation == 1)
}

///|
test "reopening Changes latches a follow-up for the initial load" {
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    explorer_was_visible: false,
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
  }
  let (refreshed, _) = sync(test_emit(), state, test_ctx())
  assert_true(refreshed.changes is ChangeListLoading(refresh_again=true))
  assert_true(refreshed.changes_generation == 1)
}

///|
test "selecting Changes loads once and coalesces an in-flight refresh" {
  let emit = test_emit()
  let (_, loading) = update(
    emit,
    ExplorerModeSelected(ExplorerChanges),
    owned_state(),
    test_ctx(),
  )
  assert_true(loading.explorer_mode is ExplorerChanges)
  assert_true(loading.changes is ChangeListLoading(refresh_again=false))
  assert_true(loading.changes_generation == 1)
  // Re-selecting while the first request is in flight latches one follow-up,
  // without starting another request before this reply lands.
  let (_, latched) = update(
    emit,
    ExplorerModeSelected(ExplorerChanges),
    loading,
    test_ctx(),
  )
  assert_true(latched.changes is ChangeListLoading(refresh_again=true))
  let (_, following_up) = update(
    emit,
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files=[],
    ),
    latched,
    test_ctx(),
  )
  assert_true(
    following_up.changes
    is ChangeListReady(refreshing=true, refresh_again=false, ..),
  )
  assert_true(following_up.changes_generation == 2)
}

///|
test "moving focus to a ready Changes snapshot defers its fallback refresh" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerFiles,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 4,
  }
  let (_, selected) = update(
    emit,
    ExplorerModeSelected(ExplorerChanges),
    state,
    test_ctx(),
  )
  assert_true(selected.explorer_mode is ExplorerChanges)
  assert_true(selected.changes_generation == 4)
  assert_true(selected.changes is ChangeListReady(refreshing=false, ..))
  // Re-selecting the active tab remains the explicit, immediate refresh.
  let (_, refreshing) = update(
    emit,
    ExplorerModeSelected(ExplorerChanges),
    selected,
    test_ctx(),
  )
  assert_true(refreshing.changes_generation == 5)
  assert_true(refreshing.changes is ChangeListReady(refreshing=true, ..))
}

///|
test "watcher events latch a follow-up during the initial change load" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
  }
  let (_, latched) = update(
    emit,
    FsChanged(
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(state.watch_generation),
      changes=Some([Modified(Relative("src/main.mbt"))]),
    ),
    state,
    test_ctx(),
  )
  assert_true(latched.changes is ChangeListLoading(refresh_again=true))
}

///|
test "changed-file replies are owner-and-generation-fenced" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
  }
  let files = [
    {
      path: Relative("src/main.mbt"),
      original_path: None,
      index_status: " ",
      worktree_status: "M",
      kind: ChangeModified,
    },
  ]
  let (_, ready) = update(
    emit,
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files~,
    ),
    state,
    test_ctx(),
  )
  assert_true(
    ready.changes
    is ChangeListReady(
      repository=true,
      files=[{ path: Relative("src/main.mbt"), .. }],
      refreshing=false,
      refresh_again=false
    ),
  )
  let (_, stale) = update(
    emit,
    ChangesLoaded(
      owner={
        channel: @interop.ChannelId::Remote("other"),
        session: "desktop-test",
      },
      generation=1,
      repository=true,
      head=None,
      files=[],
    ),
    ready,
    test_ctx(),
  )
  assert_true(stale == ready)
  let (_, stale_failure) = update(
    emit,
    ChangesFailed(
      owner={
        channel: @interop.ChannelId::Remote("other"),
        session: "desktop-test",
      },
      generation=1,
      message="stale git failure",
    ),
    ready,
    test_ctx(),
  )
  assert_true(stale_failure == ready)
  let (_, stale_generation) = update(
    emit,
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=0,
      repository=true,
      head=None,
      files=[],
    ),
    ready,
    test_ctx(),
  )
  assert_true(stale_generation == ready)
  let idle = { ..owned_state(), changes_generation: 1, }
  let (_, stale_idle_failure) = update(
    emit,
    ChangesFailed(
      owner=test_ctx().owner,
      generation=1,
      message="stale git failure",
    ),
    idle,
    test_ctx(),
  )
  assert_true(stale_idle_failure == idle)
}

///|
test "a settled Changes snapshot re-stats loaded reviews whose rows disappeared" {
  let path = @pathx.Relative("src/committed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    review_generation: 3,
    docs,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files=[],
    ),
    state,
    ctx,
  )
  assert_true(
    settled.docs.get(path)
    is Some({ state: TabLoaded(content="", ..), review: None, .. }),
  )
  // Reconciliation schedules this stat even when the watcher is unavailable;
  // a committed deletion must replace the cached working source.
  let (_, deleted) = update(
    test_emit(),
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[{ path, signature: Missing, }]),
    settled,
    ctx,
  )
  assert_true(
    deleted.docs.get(path)
    is Some({ state: TabDeleted, review: None, stale: false, .. }),
  )
}

///|
test "a review that becomes a symlink clears its cached regular-file source" {
  let path = @pathx.Relative("src/replaced.mbt")
  let selected = test_modified_change(path)
  let symlink = { ..selected, kind: ChangeSymlink, }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected,
    }),
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, unavailable) = update(
    test_emit(),
    ChangesLoaded(owner=ctx.owner, generation=1, repository=true, head=None, files=[
      symlink,
    ]),
    {
      ..owned_state(),
      explorer_mode: ExplorerChanges,
      changes: ChangeListLoading(refresh_again=false),
      changes_generation: 1,
      review_generation: 3,
      docs,
    },
    ctx,
  )
  assert_true(
    unavailable.docs.get(path)
    is Some({ state: TabUnavailable(message), review: None, stale: false, .. }) &&
    message == symlink.unselectable_title(),
  )
  let (_, missing_unavailable) = update(
    test_emit(),
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[{ path, signature: Missing, }]),
    unavailable,
    ctx,
  )
  assert_true(missing_unavailable == unavailable)
  // A later file stat must not follow the non-file entry and resurrect the
  // source that preceded it. An explicit ordinary reopen remains the retry.
  let (_, still_unavailable) = update(
    test_emit(),
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[
      { path, signature: Present("4:0"), },
    ]),
    missing_unavailable,
    ctx,
  )
  assert_true(still_unavailable == unavailable)
  guard @resource.of_path(@interop.ChannelId::Local, "/work/src/replaced.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let stale_reply = FileLoaded(
    owner=ctx.owner,
    epoch=0,
    path~,
    name="replaced.mbt",
    file=Content(content="stale regular source", absolute~, sig="4:0"),
    file_link_generation=None,
    review_generation=None,
    range=None,
    annotation=None,
  )
  let (_, fenced) = update(test_emit(), stale_reply, still_unavailable, ctx)
  assert_true(fenced == still_unavailable)
  let (_, failed) = update(
    test_emit(),
    FileFailed(
      owner=ctx.owner,
      epoch=0,
      path~,
      file_link_generation=None,
      review_generation=None,
      message="late symlink read",
    ),
    fenced,
    ctx,
  )
  assert_true(failed == fenced)
  let (_, reopening) = open_document(
    test_emit(),
    fenced,
    ctx,
    path,
    name="replaced.mbt",
    range=None,
    had_active=true,
  )
  assert_true(
    reopening.docs.get(path)
    is Some({ state: TabLoading, review: None, stale: false, .. }),
  )
  let (_, reopened) = update(test_emit(), stale_reply, reopening, ctx)
  assert_true(
    reopened.docs.get(path)
    is Some(
      {
        state: TabLoaded(content="stale regular source", sig="4:0", ..),
        review: None,
        stale: false,
        ..
      }
    ),
  )
}

///|
test "a disappearing review row hands an active reload to an ordinary read" {
  let path = @pathx.Relative("src/committed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let state = {
    ..owned_state(),
    changes: ChangeListFailed("park refresh"),
    review_generation: 3,
    docs,
  }
  let (_, reloading) = update(
    test_emit(),
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[
      { path, signature: Present("2:1"), },
    ]),
    state,
    ctx,
  )
  assert_true(
    reloading.docs.get(path)
    is Some({ state: TabLoaded(..), review: Some(_), stale: true, .. }),
  )
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(owner=ctx.owner, generation=1, repository=true, head=None, files=[]),
    {
      ..reloading,
      changes: ChangeListLoading(refresh_again=false),
      changes_generation: 1,
    },
    ctx,
  )
  assert_true(
    settled.docs.get(path)
    is Some({ state: TabLoaded(..), review: None, stale: true, .. }),
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/src/committed.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, fenced) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="committed.mbt",
      file=Content(content="stale review read", absolute~, sig="2:7"),
      file_link_generation=None,
      review_generation=Some(3),
      range=None,
      annotation=None,
    ),
    settled,
    ctx,
  )
  assert_true(fenced == settled)
  let (_, current) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="committed.mbt",
      file=Content(content="current working", absolute~, sig="2:7"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    fenced,
    ctx,
  )
  assert_true(
    current.docs.get(path)
    is Some(
      {
        state: TabLoaded(content="current working", sig="2:7", ..),
        review: None,
        stale: false,
        ..
      }
    ),
  )
}

///|
test "a newer review reload fences an older working-tree reply" {
  let path = @pathx.Relative("src/racing.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let state = { ..owned_state(), review_generation: 3, docs, }
  // A watcher reload starts while the original changed-row read is still in
  // flight. It receives its own token without invalidating the HEAD request.
  let (_, reloading) = update(
    test_emit(),
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[
      { path, signature: Present("2:0"), },
    ]),
    state,
    ctx,
  )
  assert_true(reloading.review_generation == 4)
  assert_true(
    reloading.docs.get(path)
    is Some(
      {
        review: Some({ generation: 3, working_generation: 4, .. }),
        stale: true,
        ..
      }
    ),
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/src/racing.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, newest) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="racing.mbt",
      file=Content(content="newest working", absolute~, sig="2:0"),
      file_link_generation=None,
      review_generation=Some(4),
      range=None,
      annotation=None,
    ),
    reloading,
    ctx,
  )
  assert_true(
    newest.docs.get(path)
    is Some(
      {
        state: TabLoaded(content="newest working", sig="2:0", ..),
        review: Some({ generation: 3, working_generation: 4, .. }),
        stale: false,
        ..
      }
    ),
  )
  let (_, stale) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="racing.mbt",
      file=Content(content="older working", absolute~, sig="1:0"),
      file_link_generation=None,
      review_generation=Some(3),
      range=None,
      annotation=None,
    ),
    newest,
    ctx,
  )
  assert_true(stale == newest)
  // A later deletion likewise invalidates the accepted generation. A reply
  // that captured the file just before it disappeared cannot resurrect it.
  let (_, deleted) = update(
    test_emit(),
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[{ path, signature: Missing, }]),
    newest,
    ctx,
  )
  assert_true(deleted.review_generation == 5)
  assert_true(
    deleted.docs.get(path)
    is Some(
      {
        state: TabDeleted,
        review: Some({ generation: 3, working_generation: 5, .. }),
        ..
      }
    ),
  )
  let (_, resurrected) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="racing.mbt",
      file=Content(content="pre-deletion working", absolute~, sig="2:0"),
      file_link_generation=None,
      review_generation=Some(4),
      range=None,
      annotation=None,
    ),
    deleted,
    ctx,
  )
  assert_true(resurrected == deleted)
}

///|
test "only a final Changes snapshot reconciles reviews and moved HEAD refreshes survivors" {
  let path = @pathx.Relative("src/partial.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=true),
    changes_generation: 1,
    changes_head: Some("old-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  // The coalesced first reply is intermediate. Its temporary absence must not
  // clear the review or consume the new HEAD identity before the follow-up.
  let (_, following_up) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=Some("new-head"),
      files=[],
    ),
    state,
    ctx,
  )
  assert_true(
    following_up.docs.get(path)
    is Some(
      {
        review: Some({ generation: 3, baseline: ReviewContent("old HEAD"), .. }),
        ..
      }
    ),
  )
  assert_true(following_up.changes_head == Some("old-head"))
  assert_true(following_up.changes_generation == 2)
  let files = [
    {
      path,
      original_path: None,
      index_status: " ",
      worktree_status: "M",
      kind: ChangeModified,
    },
  ]
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=2,
      repository=true,
      head=Some("new-head"),
      files~,
    ),
    following_up,
    ctx,
  )
  assert_true(settled.changes_head == Some("new-head"))
  assert_true(settled.changes_head_known)
  assert_true(settled.review_generation == 4)
  assert_true(
    settled.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some(
          { generation: 4, working_generation: 4, baseline: ReviewLoading, .. }
        ),
        ..
      }
    ),
  )
  let (_, refreshed) = update(
    test_emit(),
    GitOriginalLoaded(
      owner=test_ctx().owner,
      path~,
      generation=4,
      background=false,
      original=@protocol.OriginalContent("new HEAD"),
    ),
    settled,
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
  )
  assert_true(
    refreshed.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some(
          { working_generation: 4, baseline: ReviewContent("new HEAD"), .. }
        ),
        ..
      }
    ),
  )
}

///|
test "HEAD refresh restarts the generation-fenced working-tree read" {
  let path = @pathx.Relative("src/paired.mbt")
  let change = test_modified_change(path)
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: change,
    }),
  }
  let state = {
    ..owned_state(),
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    changes_head: Some("old-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, refreshed) = update(
    test_emit(),
    ChangesLoaded(
      owner=ctx.owner,
      generation=1,
      repository=true,
      head=Some("new-head"),
      files=[change],
    ),
    state,
    ctx,
  )
  assert_true(
    refreshed.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 4, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/src/paired.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, ignored_old_working) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="paired.mbt",
      file=Content(content="stale working", absolute~, sig="2:13"),
      file_link_generation=None,
      review_generation=Some(3),
      range=None,
      annotation=None,
    ),
    refreshed,
    ctx,
  )
  assert_true(ignored_old_working == refreshed)
  let (_, baseline_ready) = update(
    test_emit(),
    GitOriginalLoaded(
      owner=ctx.owner,
      background=false,
      path~,
      generation=4,
      original=@protocol.OriginalContent("new HEAD"),
    ),
    ignored_old_working,
    ctx,
  )
  assert_true(
    baseline_ready.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 4, baseline: ReviewContent("new HEAD"), .. }),
        ..
      }
    ),
  )
  let (_, paired) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="paired.mbt",
      file=Content(content="current working", absolute~, sig="3:15"),
      file_link_generation=None,
      review_generation=Some(4),
      range=None,
      annotation=None,
    ),
    baseline_ready,
    ctx,
  )
  assert_true(
    paired.docs.get(path)
    is Some(
      {
        state: TabLoaded(content="current working", ..),
        review: Some({ generation: 4, baseline: ReviewContent("new HEAD"), .. }),
        ..
      }
    ),
  )
}

///|
test "legacy Changes replies without HEAD refresh baseline-bearing reviews" {
  let path = @pathx.Relative("src/legacy-host.mbt")
  let change = test_modified_change(path)
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: change,
    }),
  }
  let state = {
    ..owned_state(),
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    // Legacy hosts decode as `None` even though their repository has a HEAD.
    changes_head: None,
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files=[change],
    ),
    state,
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
  )
  assert_true(settled.review_generation == 4)
  assert_true(
    settled.docs.get(path)
    is Some(
      {
        state: TabLoaded(..),
        review: Some(
          {
            generation: 4,
            working_generation: 3,
            baseline: ReviewContent("old HEAD"),
            ..
          }
        ),
        ..
      }
    ),
  )
  assert_true(settled.background_review_requests.get(path) == Some(4))
  // The next poll can settle before the slow compatibility read. It must keep
  // that request's generation live rather than launch a replacement that
  // would fence the first reply forever.
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, polling) = update(test_emit(), ChangesPollDue, settled, ctx)
  assert_true(polling.changes_generation == 2)
  let (_, coalesced) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=2,
      repository=true,
      head=None,
      files=[change],
    ),
    polling,
    ctx,
  )
  assert_true(coalesced.review_generation == 4)
  assert_true(coalesced.background_review_requests.get(path) == Some(4))
  assert_true(
    coalesced.docs.get(path)
    is Some({ review: Some({ generation: 4, .. }), .. }),
  )
  let (_, refreshed) = update(
    test_emit(),
    GitOriginalLoaded(
      owner=test_ctx().owner,
      path~,
      generation=4,
      background=true,
      original=@protocol.OriginalContent("new HEAD"),
    ),
    coalesced,
    ctx,
  )
  assert_true(refreshed.background_review_requests.is_empty())
  assert_true(
    refreshed.docs.get(path)
    is Some(
      {
        state: TabLoaded(..),
        review: Some(
          { working_generation: 3, baseline: ReviewContent("new HEAD"), .. }
        ),
        ..
      }
    ),
  )
}

///|
test "unborn repository polls do not churn untracked reviews" {
  let path = @pathx.Relative("new.mbt")
  let change : ChangedFile = {
    path,
    original_path: None,
    index_status: "?",
    worktree_status: "?",
    kind: ChangeUntracked,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewMissing,
      view_mode: ReviewSource,
      selected: change,
    }),
  }
  let state = {
    ..owned_state(),
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    changes_head: None,
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files=[change],
    ),
    state,
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
  )
  assert_true(settled.review_generation == 3)
  assert_true(
    settled.docs.get(path)
    is Some(
      { review: Some({ generation: 3, baseline: ReviewMissing, .. }), .. }
    ),
  )
}

///|
test "legacy HEAD omission refreshes a missing baseline once tracking is proven" {
  let path = @pathx.Relative("recreated.mbt")
  let untracked : ChangedFile = {
    path,
    original_path: None,
    index_status: "?",
    worktree_status: "?",
    kind: ChangeUntracked,
  }
  let deleted : ChangedFile = {
    path,
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: ChangeDeleted,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewMissing,
      view_mode: ReviewSource,
      selected: untracked,
    }),
  }
  let state = {
    ..owned_state(),
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    changes_head: None,
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let (_, refreshed) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files=[deleted, untracked],
    ),
    state,
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
  )
  assert_true(
    refreshed.docs.get(path)
    is Some(
      {
        state: TabLoaded(..),
        review: Some({ generation: 4, baseline: ReviewMissing, selected, .. }),
        ..
      }
    ) &&
    selected == untracked,
  )
}

///|
test "Changes reconciliation preserves the selected duplicate-path row" {
  let path = @pathx.Relative("recreated.mbt")
  let deleted : ChangedFile = {
    path,
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: ChangeDeleted,
  }
  let untracked : ChangedFile = {
    path,
    original_path: None,
    index_status: "?",
    worktree_status: "?",
    kind: ChangeUntracked,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, reviewing) = open_changed_document(
    test_emit(),
    owned_state(),
    ctx,
    untracked,
    had_active=false,
  )
  let refreshing = {
    ..reviewing,
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    changes_head: Some("old-head"),
    changes_head_known: true,
  }
  // Porcelain sorts both rows by the same path, with the staged deletion
  // first. A moved HEAD must refresh the selected untracked working side,
  // never silently turn the document into a deleted-file preview.
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=ctx.owner,
      generation=1,
      repository=true,
      head=Some("new-head"),
      files=[deleted, untracked],
    ),
    refreshing,
    ctx,
  )
  assert_true(
    settled.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 2, baseline: ReviewLoading, selected, .. }),
        ..
      }
    ) &&
    selected == untracked,
  )
  assert_false(deleted.is_selected(settled, ctx))
  assert_true(untracked.is_selected(settled, ctx))
  // If the selected untracked side disappears, the incompatible staged
  // deletion must not become the review merely because it is the sole row.
  assert_true(
    selected_review_change([deleted], [deleted, untracked], untracked) is None,
  )
}

///|
test "moved HEAD normalizes reviewed tabs across the working-file boundary" {
  let path = @pathx.Relative("src/crossing.mbt")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let deleted : ChangedFile = {
    path,
    original_path: None,
    index_status: " ",
    worktree_status: "D",
    kind: ChangeDeleted,
  }
  let loading_docs : Map[@pathx.Relative, Doc] = Map([])
  loading_docs[path] = {
    name: "crossing.mbt",
    state: TabLoading,
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
    stale: true,
  }
  let loading = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    changes_head: Some("old-head"),
    changes_head_known: true,
    review_generation: 3,
    docs: loading_docs,
  }
  let (_, became_deleted) = update(
    test_emit(),
    ChangesLoaded(
      owner=ctx.owner,
      generation=1,
      repository=true,
      head=Some("new-head"),
      files=[deleted],
    ),
    loading,
    ctx,
  )
  assert_true(
    became_deleted.docs.get(path)
    is Some(
      {
        state: TabDeleted,
        review: Some({ generation: 4, baseline: ReviewLoading, .. }),
        stale: false,
        ..
      }
    ),
  )

  let deleted_docs : Map[@pathx.Relative, Doc] = Map([])
  deleted_docs[path] = {
    name: "crossing.mbt",
    state: TabDeleted,
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: deleted,
    }),
    stale: false,
  }
  let deleted_state = { ..loading, docs: deleted_docs, }
  let restored = { ..deleted, worktree_status: "M", kind: ChangeModified, }
  let (_, became_loading) = update(
    test_emit(),
    ChangesLoaded(
      owner=ctx.owner,
      generation=1,
      repository=true,
      head=Some("new-head"),
      files=[restored],
    ),
    deleted_state,
    ctx,
  )
  assert_true(
    became_loading.docs.get(path)
    is Some(
      {
        state: TabLoading,
        review: Some({ generation: 4, baseline: ReviewLoading, .. }),
        ..
      }
    ),
  )
}

///|
test "a changed rename source refreshes its review without moving HEAD" {
  let path = @pathx.Relative("src/new.mbt")
  let previous : ChangedFile = {
    path,
    original_path: Some(@pathx.Relative("src/old.mbt")),
    index_status: "R",
    worktree_status: " ",
    kind: ChangeRenamed,
  }
  let current = {
    ..previous,
    original_path: None,
    index_status: "?",
    worktree_status: "?",
    kind: ChangeUntracked,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old source"),
      view_mode: ReviewSource,
      selected: previous,
    }),
  }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[previous],
      refreshing=true,
      refresh_again=false,
    ),
    changes_generation: 1,
    changes_head: Some("same-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  let (_, settled) = update(
    test_emit(),
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=Some("same-head"),
      files=[current],
    ),
    state,
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
  )
  assert_true(settled.review_generation == 4)
  assert_true(
    settled.docs.get(path)
    is Some(
      { review: Some({ generation: 4, baseline: ReviewLoading, .. }), .. }
    ),
  )
}

///|
test "only a visible settled Changes snapshot accepts its polling fallback" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 4,
  }
  let (_, refreshing) = update(emit, ChangesPollDue, state, test_ctx())
  assert_true(refreshing.changes_generation == 5)
  assert_true(refreshing.changes is ChangeListReady(refreshing=true, ..))
  let (_, stale) = update(emit, ChangesPollDue, refreshing, test_ctx())
  assert_true(stale == refreshing)
  let (_, hidden) = update(emit, ChangesPollDue, state, {
    ..test_ctx(),
    panel_open: false,
  })
  assert_true(hidden == state)
  let (_, hidden_tree) = update(
    emit,
    ChangesPollDue,
    { ..state, tree_open: false, },
    { ..test_ctx(), active_file: Some(Relative("open.mbt")), },
  )
  assert_true(hidden_tree == { ..state, tree_open: false, })
  let (_, files_mode) = update(
    emit,
    ChangesPollDue,
    { ..state, explorer_mode: ExplorerFiles, },
    test_ctx(),
  )
  assert_true(files_mode.explorer_mode is ExplorerFiles)
  assert_true(files_mode.changes_generation == 4)
}

///|
test "the fallback poll is declared only for a settled live inventory" {
  let ready = {
    ..owned_state(),
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
  }
  assert_true(changes_poll_wanted(ready, test_ctx()))
  // A request already in flight owns the next refresh. Retiring the interval
  // here is what makes it restart from that reply instead of from a fixed
  // wall-clock cadence running underneath it.
  assert_false(
    changes_poll_wanted(
      {
        ..ready,
        changes: ChangeListReady(
          repository=true,
          files=[],
          refreshing=true,
          refresh_again=false,
        ),
      },
      test_ctx(),
    ),
  )
  // Outside a repository, and before an inventory exists, there is nothing to
  // poll for.
  assert_false(
    changes_poll_wanted(
      {
        ..ready,
        changes: ChangeListReady(
          repository=false,
          files=[],
          refreshing=false,
          refresh_again=false,
        ),
      },
      test_ctx(),
    ),
  )
  assert_false(
    changes_poll_wanted({ ..ready, changes: ChangeListIdle, }, test_ctx()),
  )
  // No consumer on screen: another explorer mode, a closed panel, or a panel
  // the conversation switch has not handed over yet.
  assert_false(
    changes_poll_wanted({ ..ready, explorer_mode: ExplorerFiles, }, test_ctx()),
  )
  assert_false(changes_poll_wanted(ready, { ..test_ctx(), panel_open: false, }))
  assert_false(changes_poll_wanted({ ..ready, owner: None, }, test_ctx()))
  // An open changed-file review consumes the inventory even off-screen, so it
  // keeps the fallback alive on its own.
  let path = @pathx.Relative("src/reviewed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 2,
      working_generation: 2,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  assert_true(
    changes_poll_wanted({ ..ready, docs, }, {
      ..test_ctx(),
      panel_open: false,
      open_files: [path],
      active_file: Some(path),
    }),
  )
}

///|
test "a parked checkout stops the fallback poll until repair" {
  let emit = test_emit()
  let present = test_ctx().test_worktree("wt")
  let path = @pathx.Relative("reviewed.mbt")
  let change = test_modified_change(path)
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: change,
    }),
  }
  let reviewing : Ctx = {
    ..present,
    open_files: [path],
    active_file: Some(path),
  }
  let state = {
    ..owned_state_at(present),
    explorer_mode: ExplorerChanges,
    changes: ChangeListReady(
      repository=true,
      files=[change],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 1,
    changes_head: Some("same-head"),
    changes_head_known: true,
    review_generation: 3,
    docs,
  }
  assert_true(changes_poll_wanted(state, reviewing))
  let missing : Ctx = {
    ..reviewing,
    placement: Some(
      @interop.MissingWorktree(project=present.test_root(), name="wt"),
    ),
  }
  // The parked panel keeps its settled inventory and its open review readable,
  // so every other axis of the predicate still holds. Only the lost checkout
  // stops the interval, and a tick that outlived the park is refused too.
  let (parked, _) = sync(emit, state, missing)
  assert_true(
    parked.changes is ChangeListReady(repository=true, refreshing=false, ..),
  )
  assert_true(changes_live(parked, missing))
  assert_false(changes_poll_wanted(parked, missing))
  let (_, after_tick) = update(emit, ChangesPollDue, parked, missing)
  assert_true(after_tick == parked)
  // Repair restores it: its own refresh settles, and the settled shape is what
  // declares the poll again.
  let (restored, _) = sync(emit, parked, reviewing)
  assert_true(restored.changes is ChangeListReady(refreshing=true, ..))
  let (_, settled) = update(
    emit,
    ChangesLoaded(
      owner=present.owner,
      generation=restored.changes_generation,
      repository=true,
      head=Some("same-head"),
      files=[change],
    ),
    restored,
    reviewing,
  )
  assert_true(changes_poll_wanted(settled, reviewing))
}

///|
test "hidden explorer drops coalesced follow-ups when requests settle" {
  let emit = test_emit()
  let hidden = { ..test_ctx(), panel_open: false, }
  let refreshing = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=true,
      refresh_again=true,
    ),
    changes_generation: 4,
  }
  let (_, loaded) = update(
    emit,
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=4,
      repository=true,
      head=None,
      files=[],
    ),
    refreshing,
    hidden,
  )
  assert_true(loaded.changes_generation == 4)
  assert_true(
    loaded.changes is ChangeListReady(refreshing=false, refresh_again=false, ..),
  )
  let (_, failed_refresh) = update(
    emit,
    ChangesFailed(owner=test_ctx().owner, generation=4, message="git failed"),
    refreshing,
    hidden,
  )
  assert_true(failed_refresh.changes_generation == 4)
  assert_true(
    failed_refresh.changes
    is ChangeListReady(refreshing=false, refresh_again=false, ..),
  )
  let loading = {
    ..owned_state(),
    changes: ChangeListLoading(refresh_again=true),
    changes_generation: 4,
  }
  let (_, failed_load) = update(
    emit,
    ChangesFailed(owner=test_ctx().owner, generation=4, message="git failed"),
    loading,
    hidden,
  )
  assert_true(failed_load.changes_generation == 4)
  assert_true(failed_load.changes is ChangeListIdle)
  let (_, failed_unlatched_load) = update(
    emit,
    ChangesFailed(owner=test_ctx().owner, generation=4, message="git failed"),
    { ..loading, changes: ChangeListLoading(refresh_again=false), },
    hidden,
  )
  assert_true(failed_unlatched_load.changes_generation == 4)
  assert_true(failed_unlatched_load.changes is ChangeListIdle)
}

///|
test "conversation re-roots retain the change request generation" {
  let state = {
    ..owned_state(),
    owner: Some({
      channel: @interop.ChannelId::Remote("previous"),
      session: "previous-session",
    }),
    explorer_mode: ExplorerChanges,
    changes_generation: 7,
  }
  let (rerooted, _) = sync(test_emit(), state, test_ctx())
  assert_true(rerooted.owner == Some(test_ctx().owner))
  assert_true(rerooted.changes is ChangeListLoading(refresh_again=false))
  assert_true(rerooted.changes_generation == 8)
}

///|
test "watcher refresh keeps the ready change snapshot visible" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
  }
  let (_, refreshing) = update(
    emit,
    FsChanged(
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(state.watch_generation),
      changes=Some([Modified(Relative("src/main.mbt"))]),
    ),
    state,
    test_ctx(),
  )
  assert_true(refreshing.changes_generation == 1)
  assert_true(
    refreshing.changes
    is ChangeListReady(
      repository=true,
      files=[],
      refreshing=true,
      refresh_again=false
    ),
  )
  let (_, latched) = update(
    emit,
    FsChanged(
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(refreshing.watch_generation),
      changes=Some([Modified(Relative("src/other.mbt"))]),
    ),
    refreshing,
    test_ctx(),
  )
  assert_true(
    latched.changes
    is ChangeListReady(
      repository=true,
      files=[],
      refreshing=true,
      refresh_again=true
    ),
  )
  // The first reply consumes the latch by starting one follow-up request; the
  // second reply settles the snapshot.
  let (_, following_up) = update(
    emit,
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=1,
      repository=true,
      head=None,
      files=[],
    ),
    latched,
    test_ctx(),
  )
  assert_true(following_up.changes_generation == 2)
  assert_true(
    following_up.changes
    is ChangeListReady(
      repository=true,
      files=[],
      refreshing=true,
      refresh_again=false
    ),
  )
  let (_, settled) = update(
    emit,
    ChangesLoaded(
      owner=test_ctx().owner,
      generation=2,
      repository=true,
      head=None,
      files=[],
    ),
    following_up,
    test_ctx(),
  )
  assert_true(
    settled.changes
    is ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false
    ),
  )
}

///|
test "hidden explorer parks event-driven change refreshes until reopen" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 4,
  }
  let hidden = { ..test_ctx(), panel_open: false, }
  let (_, after_watch) = update(
    emit,
    FsChanged(
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(state.watch_generation),
      changes=Some([]),
    ),
    state,
    hidden,
  )
  assert_true(after_watch.changes_generation == 4)
  assert_true(after_watch.changes is ChangeListReady(refreshing=false, ..))
  let (_, after_run) = update(
    emit,
    RunSettled(owner=test_ctx().owner),
    after_watch,
    hidden,
  )
  assert_true(after_run.changes_generation == 4)
  assert_true(after_run.changes is ChangeListReady(refreshing=false, ..))
}

///|
test "hidden explorer keeps Git refresh live for an open review" {
  let path = @pathx.Relative("src/reviewed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 2,
      working_generation: 2,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let state = {
    ..owned_state(),
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 4,
    docs,
  }
  let hidden = {
    ..test_ctx(),
    panel_open: false,
    open_files: [path],
    active_file: Some(path),
  }
  let (_, after_run) = update(
    test_emit(),
    RunSettled(owner=test_ctx().owner),
    state,
    hidden,
  )
  assert_true(after_run.changes_generation == 5)
  assert_true(after_run.changes is ChangeListReady(refreshing=true, ..))
  let (_, after_poll) = update(test_emit(), ChangesPollDue, state, hidden)
  assert_true(after_poll.changes_generation == 5)
  assert_true(after_poll.changes is ChangeListReady(refreshing=true, ..))
}

///|
test "sync refreshes a hidden review after its workspace watch was parked" {
  let path = @pathx.Relative("src/reviewed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 2,
      working_generation: 2,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let state = {
    ..owned_state(),
    explorer_was_visible: false,
    watching: None,
    changes: ChangeListReady(
      repository=true,
      files=[],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 4,
    docs,
  }
  let hidden = {
    ..test_ctx(),
    panel_open: false,
    open_files: [path],
    active_file: Some(path),
  }
  let (refreshed, _) = sync(test_emit(), state, hidden)
  assert_true(refreshed.changes_generation == 5)
  assert_true(refreshed.changes is ChangeListReady(refreshing=true, ..))
}

///|
test "a hidden review accepts its file-only watch without a refresh loop" {
  let path = @pathx.Relative("src/reviewed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    ..loaded_doc(path.0),
    review: Some({
      generation: 2,
      working_generation: 2,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let state = {
    ..owned_state(),
    explorer_was_visible: false,
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [path],
      directories: [],
      recursive: false,
    }),
    changes: ChangeListReady(
      repository=true,
      files=[test_modified_change(path)],
      refreshing=false,
      refresh_again=false,
    ),
    changes_generation: 4,
    docs,
  }
  let hidden = {
    ..test_ctx(),
    panel_open: false,
    open_files: [path],
    active_file: Some(path),
  }
  let (settled, _) = sync(test_emit(), state, hidden)
  assert_true(settled.changes_generation == 4)
  assert_true(
    settled.changes
    is ChangeListReady(refreshing=false, refresh_again=false, ..),
  )
  let in_flight = {
    ..state,
    changes: ChangeListReady(
      repository=true,
      files=[test_modified_change(path)],
      refreshing=true,
      refresh_again=false,
    ),
  }
  let (still_in_flight, _) = sync(test_emit(), in_flight, hidden)
  assert_true(
    still_in_flight.changes
    is ChangeListReady(refreshing=true, refresh_again=false, ..),
  )
}

///|
test "change-list failures stay isolated from file errors and watcher retries" {
  let emit = test_emit()
  let state = {
    ..owned_state(),
    changes: ChangeListLoading(refresh_again=false),
    changes_generation: 1,
    error: Some("file read failed"),
  }
  let (_, failed) = update(
    emit,
    ChangesFailed(owner=test_ctx().owner, generation=1, message="git failed"),
    state,
    test_ctx(),
  )
  assert_true(failed.changes is ChangeListFailed("git failed"))
  assert_true(failed.error == Some("file read failed"))
  // A watcher event does not hammer an already-failed request. A settled run
  // or an explicit Changes click remains the retry boundary.
  let (_, still_failed) = update(
    emit,
    FsChanged(
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(failed.watch_generation),
      changes=Some([Modified(Relative("src/main.mbt"))]),
    ),
    failed,
    test_ctx(),
  )
  assert_true(still_failed.changes is ChangeListFailed("git failed"))
  let (_, retrying) = update(
    emit,
    RunSettled(owner=test_ctx().owner),
    still_failed,
    test_ctx(),
  )
  assert_true(retrying.changes is ChangeListLoading(refresh_again=false))
  assert_true(retrying.changes_generation == 2)
}

///|
test "StatsLoaded marks deletions, reloads the active change, stales the rest" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  docs[Relative("b.mbt")] = loaded_doc("b.mbt")
  docs[Relative("c.mbt")] = loaded_doc("c.mbt")
  let state = { ..owned_state(), docs, }
  let ctx = {
    ..test_ctx(),
    open_files: [Relative("a.mbt"), Relative("b.mbt"), Relative("c.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      // The active file changed: reloaded eagerly, so its document stays
      // loaded (the baseline the scroll-keeping reload compares against).
      { path: Relative("a.mbt"), signature: Present("9:0"), },
      // A background file changed: only marked stale.
      { path: Relative("b.mbt"), signature: Present("9:0"), },
      // Deleted: the document flips to the deleted notice state.
      { path: Relative("c.mbt"), signature: Missing, },
    ]),
    state,
    ctx,
  )
  assert_true(
    next.docs.get(Relative("a.mbt"))
    is Some({ state: TabLoaded(..), stale: false, .. }),
  )
  assert_true(next.docs.get(Relative("b.mbt")) is Some({ stale: true, .. }))
  assert_true(
    next.docs.get(Relative("c.mbt")) is Some({ state: TabDeleted, .. }),
  )
  // An unchanged signature on a background file still compares against the
  // loaded baseline.
  let solo : Map[@pathx.Relative, Doc] = Map([])
  solo[Relative("b.mbt")] = loaded_doc("b.mbt")
  let (_, same) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      { path: Relative("b.mbt"), signature: Present("9:0"), },
    ]),
    { ..next, docs: solo, },
    { ..ctx, active_file: None, },
  )
  assert_true(
    same.docs.get(Relative("b.mbt"))
    is Some({ state: TabLoaded(sig="1:0", ..), stale: true, .. }),
  )
  // A watcher proving a previously unreadable review path exists makes a
  // background tab retryable on activation.
  let failed_path = @pathx.Relative("failed.mbt")
  let failed_docs : Map[@pathx.Relative, Doc] = Map([])
  failed_docs[failed_path] = {
    name: "failed.mbt",
    state: TabReadFailed("temporary failure"),
    review: Some({
      generation: 4,
      working_generation: 4,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewSource,
      selected: test_modified_change(failed_path),
    }),
    stale: false,
  }
  let (_, retryable) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      { path: failed_path, signature: Present("10:0"), },
    ]),
    { ..owned_state(), docs: failed_docs, },
    { ..ctx, active_file: None, },
  )
  assert_true(
    retryable.docs.get(failed_path)
    is Some({ state: TabReadFailed(_), review: Some(_), stale: true, .. }),
  )
  // A reply from another conversation is dropped.
  let (_, other) = update(
    emit,
    StatsLoaded(
      owner={
        channel: @interop.ChannelId::Remote("other"),
        session: "desktop-test",
      },
      epoch=0,
      stats=[{ path: Relative("a.mbt"), signature: Missing, }],
    ),
    state,
    ctx,
  )
  assert_true(
    other.docs.get(Relative("a.mbt")) is Some({ state: TabLoaded(..), .. }),
  )
}

///|
test "a stat the host could not complete reads as a failed read, never a deletion" {
  let emit = test_emit()
  let gone_path = @pathx.Relative("gone.mbt")
  let reviewed_path = @pathx.Relative("reviewed.mbt")
  let deletion_row : ChangedFile = {
    path: gone_path,
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: ChangeDeleted,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = loaded_doc("a.mbt")
  docs[Relative("b.mbt")] = {
    name: "b.mbt",
    state: TabLoading,
    review: None,
    stale: false,
  }
  docs[Relative("c.mbt")] = {
    name: "c.mbt",
    state: TabDeleted,
    review: None,
    stale: false,
  }
  docs[gone_path] = {
    name: "gone.mbt",
    state: TabDeleted,
    review: Some({
      generation: 3,
      working_generation: 3,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewSource,
      selected: deletion_row,
    }),
    stale: false,
  }
  docs[reviewed_path] = {
    ..loaded_doc("reviewed.mbt"),
    review: Some({
      generation: 7,
      working_generation: 7,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewSource,
      selected: test_modified_change(reviewed_path),
    }),
  }
  let ctx = {
    ..test_ctx(),
    open_files: [
      Relative("a.mbt"),
      Relative("b.mbt"),
      Relative("c.mbt"),
      gone_path,
      reviewed_path,
    ],
    active_file: Some(Relative("a.mbt")),
  }
  let failed : @protocol.FileSignature = Failed("permission denied")
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      { path: Relative("a.mbt"), signature: failed, },
      { path: Relative("b.mbt"), signature: failed, },
      { path: Relative("c.mbt"), signature: failed, },
      { path: gone_path, signature: failed, },
      { path: reviewed_path, signature: failed, },
    ]),
    { ..owned_state(), docs, review_generation: 7, },
    ctx,
  )
  // A loaded document, active or not, shows the failure where the deleted
  // notice would otherwise have appeared.
  assert_true(
    next.docs.get(Relative("a.mbt"))
    is Some({ state: TabReadFailed("permission denied"), stale: false, .. }),
  )
  // A read in flight settles the document itself.
  assert_true(
    next.docs.get(Relative("b.mbt")) is Some({ state: TabLoading, .. }),
  )
  // Something the host cannot inspect sits where a deleted file was: that is
  // a failed read of a present path, not a confirmed deletion.
  assert_true(
    next.docs.get(Relative("c.mbt"))
    is Some({ state: TabReadFailed("permission denied"), .. }),
  )
  // A selected deletion row keeps its HEAD preview: the object at the path
  // belongs to a separate untracked row.
  assert_true(
    next.docs.get(gone_path)
    is Some(
      { state: TabDeleted, review: Some({ working_generation: 3, .. }), .. }
    ),
  )
  // A reviewed working file fences the tagged read that may still be in
  // flight, like a deletion does.
  assert_true(
    next.docs.get(reviewed_path)
    is Some(
      {
        state: TabReadFailed("permission denied"),
        review: Some(
          {
            generation: 7,
            working_generation: 8,
            baseline: ReviewContent("HEAD source"),
            ..
          }
        ),
        stale: false,
        ..
      }
    ),
  )
  assert_eq(next.review_generation, 8)
}

///|
test "StatsLoaded preserves a settled HEAD preview when its active file disappears" {
  let emit = test_emit()
  let path = @pathx.Relative("reviewed.mbt")
  let doc = {
    ..loaded_doc("reviewed.mbt"),
    review: Some({
      generation: 7,
      working_generation: 7,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
  }
  let docs : Map[@pathx.Relative, Doc] = Map([(path, doc)])
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      { path, signature: Missing, },
    ]),
    { ..owned_state(), docs, },
    { ..test_ctx(), open_files: [path], active_file: Some(path), },
  )
  assert_true(
    next.docs.get(path)
    is Some(
      {
        state: TabDeleted,
        review: Some(
          { generation: 7, baseline: ReviewContent("HEAD source"), .. }
        ),
        stale: false,
        ..
      }
    ),
  )
}

///|
test "a deleted document whose file reappears reloads on the next stats" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = {
    name: "a.mbt",
    state: TabDeleted,
    review: None,
    stale: false,
  }
  let state = { ..owned_state(), docs, }
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      { path: Relative("a.mbt"), signature: Present("3:0"), },
    ]),
    state,
    { ..test_ctx(), open_files: [Relative("a.mbt")], },
  )
  // Background reappearance: stale, reloaded on activation.
  assert_true(
    next.docs.get(Relative("a.mbt"))
    is Some({ state: TabDeleted, stale: true, .. }),
  )
}

///|
test "a selected deletion hands a clean restoration to an ordinary read" {
  let emit = test_emit()
  let path = @pathx.Relative("recreated.mbt")
  let deleted : ChangedFile = {
    path,
    original_path: None,
    index_status: "D",
    worktree_status: " ",
    kind: ChangeDeleted,
  }
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    name: "recreated.mbt",
    state: TabDeleted,
    review: Some({
      generation: 7,
      working_generation: 7,
      baseline: ReviewContent("HEAD source"),
      view_mode: ReviewSource,
      selected: deleted,
    }),
    stale: false,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let (_, reviewed) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, epoch=0, stats=[
      { path, signature: Present("3:0"), },
    ]),
    { ..owned_state(), docs, },
    ctx,
  )
  // The signature belongs to the separate untracked row. The deletion review
  // remains the HEAD-only preview until Changes reconciliation selects a
  // different row explicitly.
  assert_true(
    reviewed.docs.get(path)
    is Some(
      {
        state: TabDeleted,
        review: Some(
          {
            generation: 7,
            baseline: ReviewContent("HEAD source"),
            selected,
            ..
          }
        ),
        stale: false,
        ..
      }
    ) &&
    selected == deleted,
  )
  // If the path was restored exactly to HEAD, Git reports no row. Reconcile
  // clears review and schedules a fresh stat; this models that reply arriving
  // after the earlier, deliberately ignored review-side stat.
  let (_, ordinary) = update(
    emit,
    ChangesLoaded(
      owner=ctx.owner,
      generation=1,
      repository=true,
      head=Some("same-head"),
      files=[],
    ),
    {
      ..reviewed,
      changes: ChangeListLoading(refresh_again=false),
      changes_generation: 1,
      changes_head: Some("same-head"),
      changes_head_known: true,
    },
    ctx,
  )
  assert_true(
    ordinary.docs.get(path)
    is Some({ state: TabDeleted, review: None, stale: false, .. }),
  )
  let (_, reloading) = update(
    emit,
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[
      { path, signature: Present("3:0"), },
    ]),
    ordinary,
    ctx,
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/recreated.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, restored) = update(
    emit,
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="recreated.mbt",
      file=Content(content="HEAD source", absolute~, sig="3:0"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    reloading,
    ctx,
  )
  assert_true(
    restored.docs.get(path)
    is Some(
      {
        state: TabLoaded(content="HEAD source", sig="3:0", ..),
        review: None,
        stale: false,
        ..
      }
    ),
  )
}

///|
test "a vanished review retries a failed ordinary read" {
  let emit = test_emit()
  let path = @pathx.Relative("committed.mbt")
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[path] = {
    name: "committed.mbt",
    state: TabReadFailed("temporary failure"),
    review: Some({
      generation: 7,
      working_generation: 7,
      baseline: ReviewContent("old HEAD"),
      view_mode: ReviewSource,
      selected: test_modified_change(path),
    }),
    stale: false,
  }
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  // A commit can remove the Git row without changing the working-tree file.
  // Reconciliation must leave review mode and arrange a fresh stat instead of
  // stranding the ordinary tab in the review read's transient failure.
  let (_, ordinary) = update(
    emit,
    ChangesLoaded(
      owner=ctx.owner,
      generation=1,
      repository=true,
      head=Some("new-head"),
      files=[],
    ),
    {
      ..owned_state(),
      docs,
      changes: ChangeListLoading(refresh_again=false),
      changes_generation: 1,
      changes_head: Some("old-head"),
      changes_head_known: true,
    },
    ctx,
  )
  assert_true(
    ordinary.docs.get(path)
    is Some({ state: TabReadFailed(_), review: None, stale: false, .. }),
  )
  let (_, reloading) = update(
    emit,
    StatsLoaded(owner=ctx.owner, epoch=0, stats=[
      { path, signature: Present("4:0"), },
    ]),
    ordinary,
    ctx,
  )
  guard @resource.of_path(@interop.ChannelId::Local, "/work/committed.mbt")
    is Some(absolute) else {
    fail("test file resource was not absolute")
  }
  let (_, restored) = update(
    emit,
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="committed.mbt",
      file=Content(content="committed source", absolute~, sig="4:0"),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    reloading,
    ctx,
  )
  assert_true(
    restored.docs.get(path)
    is Some(
      {
        state: TabLoaded(content="committed source", sig="4:0", ..),
        review: None,
        stale: false,
        ..
      }
    ),
  )
}

///|
test "watcher replacement baseline re-lists directories and refreshes the index" {
  let emit = test_emit()
  let children : Map[@pathx.Relative, Array[FileEntry]] = Map([])
  children[Relative("")] = []
  children[Relative("src")] = []
  let state = {
    ..owned_state(),
    children,
    expanded: [Relative("src"), Relative("never-listed")],
    index: IndexReady(
      files=[Relative("src/main.mbt")],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
  }
  let baseline = FsChanged(
    root=test_ctx().test_root(),
    generation=test_ctx().watch_identity(state.watch_generation),
    changes=None,
  )
  let (_, next) = update(emit, baseline, state, test_ctx())
  // Both known directories are marked in flight; the never-listed one is
  // left to its own first expansion.
  assert_true(next.loading.contains(Relative("")))
  assert_true(next.loading.contains(Relative("src")))
  assert_false(next.loading.contains(Relative("never-listed")))
  // Equivalent recursive selections never issue a replacement. If a baseline
  // arrives, the Host activated a new watcher and the index must close that
  // observation gap with a refresh.
  assert_true(
    next.index is IndexReady(refreshing=true, refresh_again=false, ..),
  )
  // A second push while the lists are in flight stacks nothing.
  let (_, again) = update(emit, baseline, next, test_ctx())
  assert_eq(again.loading.length(), next.loading.length())
}

///|
test "recursive watcher configuration omits paths already covered by its index" {
  let state = {
    ..owned_state(),
    expanded: [Relative("src"), Relative("node_modules/vendor")],
    index: IndexReady(
      files=[Relative("src/main.mbt")],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
  }
  let ctx = {
    ..test_ctx(),
    open_files: [
      Relative("src/main.mbt"),
      Relative("node_modules/pkg/index.js"),
    ],
  }
  guard state.watched_paths(ctx) is Some(watched) else {
    fail("live index did not request a recursive watcher")
  }
  assert_true(watched.recursive)
  // Ordinary selections are already included by the recursive watcher. Only
  // explicit paths under pruned directories affect its native filter.
  assert_true(watched.files == [Relative("node_modules/pkg/index.js")])
  assert_true(watched.directories == [Relative("node_modules/vendor")])
}

///|
test "concrete watcher events refresh only affected listed directories" {
  let emit = test_emit()
  let children : Map[@pathx.Relative, Array[FileEntry]] = Map([])
  children[Relative("")] = []
  children[Relative("src")] = []
  children[Relative("docs")] = []
  let state = {
    ..owned_state(),
    children,
    expanded: [Relative("src"), Relative("docs")],
  }
  let message = FsChanged(
    root=test_ctx().test_root(),
    generation=test_ctx().watch_identity(state.watch_generation),
    changes=Some([Created(Relative("src/new.mbt"))]),
  )
  let (_, first) = update(emit, message, state, test_ctx())
  assert_true(first.loading == [Relative("src")])
  // Rabbita purity: the same message and model produce the same state.
  let (_, second) = update(emit, message, state, test_ctx())
  assert_true(first.loading == second.loading)
  // Another concrete batch with the current watcher identity is accepted.
  let (_, current) = update(
    emit,
    FsChanged(
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(state.watch_generation),
      changes=Some([Created(Relative("docs/new.mbt"))]),
    ),
    state,
    test_ctx(),
  )
  assert_true(current.loading == [Relative("docs")])
  // A late batch from the previous conversation is ignored.
  let (_, stale) = update(
    emit,
    FsChanged(
      root=test_ctx().test_resource("/previous-root"),
      generation=test_ctx().watch_identity(state.watch_generation),
      changes=Some([Created(Relative("docs/new.md"))]),
    ),
    state,
    test_ctx(),
  )
  assert_true(stale.loading.is_empty())
}

///|
test "moonbit-relevant changes cover sources, interfaces, and manifests" {
  assert_true(Modified(Relative("src/lib.mbt")).moonbit_relevant())
  assert_true(Removed(Relative("pkg.generated.mbti")).moonbit_relevant())
  assert_true(Created(Relative("README.mbt.md")).moonbit_relevant())
  assert_true(Modified(Relative("src/moon.pkg")).moonbit_relevant())
  assert_true(Modified(Relative("moon.mod")).moonbit_relevant())
  assert_true(
    Renamed(old=Relative("notes.md"), new=Relative("src/a.mbt")).moonbit_relevant(),
  )
  assert_false(Modified(Relative("README.md")).moonbit_relevant())
  assert_false(Modified(Relative("src/notmoon.pkg.bak")).moonbit_relevant())
  assert_false(Created(Relative("assets/logo.png")).moonbit_relevant())
}

///|
test "sync reconciles the watcher with the panel and its open files" {
  let emit = test_emit()
  // Open panel: watch the active session.
  let (watched, _) = sync(
    emit,
    { ..owned_state(), watch_error: Some("old watcher failure"), },
    test_ctx(),
  )
  assert_true(
    watched.watching
    is Some(
      {
        owner: { session: "desktop-test", .. },
        root: _,
        files: [],
        directories: [Relative("")],
        recursive: false,
      }
    ),
  )
  // Issuing a new watch attempt retires the previous failure.
  assert_true(watched.watch_error is None)
  let attached_generation = watched.watch_generation
  // Opening a file or expanding a directory replaces the same conversation's
  // watcher with the new exact selection.
  let selected_ctx = { ..test_ctx(), open_files: [Relative("a.mbt")], }
  let selected = { ..watched, expanded: [Relative("src")], }
  let (replaced, _) = sync(emit, selected, selected_ctx)
  assert_true(
    replaced.watching
    is Some(
      {
        files: [Relative("a.mbt")],
        directories: [Relative(""), Relative("src")],
        ..
      }
    ),
  )
  assert_eq(replaced.watch_generation, attached_generation + 1)
  let (_, after_old_failure) = update(
    emit,
    FileWatchFailed(
      channel=test_ctx().owner.channel,
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(attached_generation),
      message="replaced watcher stopped",
    ),
    replaced,
    selected_ctx,
  )
  assert_true(after_old_failure.watch_error is None)
  // A breadcrumb list is live even when its directory was not expanded in
  // the docked tree; dismissing it lets the next sync retire that watch.
  let (picking, _) = sync(
    emit,
    { ..after_old_failure, highlighted: Some(Relative("deepseek")), },
    selected_ctx,
  )
  assert_true(
    picking.watching
    is Some(
      { directories: [Relative(""), Relative("deepseek"), Relative("src")], .. }
    ),
  )
  assert_eq(picking.watch_generation, attached_generation + 2)
  // Closed panel with files still open: keep watching (staleness tracking).
  let still_ctx = {
    ..test_ctx(),
    panel_open: false,
    open_files: [Relative("a.mbt")],
  }
  let closed = { ..picking, children: Map([]), loading: [], highlighted: None, }
  let (still, _) = sync(emit, closed, still_ctx)
  assert_true(
    still.watching is Some({ files: [Relative("a.mbt")], directories: [], .. }),
  )
  assert_eq(still.watch_generation, attached_generation + 3)
  // Closed panel, nothing open: park the watcher.
  let (parked, _) = sync(emit, still, { ..test_ctx(), panel_open: false, })
  assert_true(parked.watching is None)
  assert_eq(parked.watch_generation, attached_generation + 4)
}

///|
test "watcher failures are visible only in their owning conversation" {
  let emit = test_emit()
  let owner = test_ctx().owner
  let (_, failed) = update(
    emit,
    FileWatchFailed(
      channel=owner.channel,
      root=test_ctx().test_root(),
      generation=test_ctx().watch_identity(0),
      message="File watching stopped",
    ),
    owned_state(),
    test_ctx(),
  )
  assert_true(failed.watch_error is Some("File watching stopped"))
  let other : @interop.ConversationKey = {
    channel: @interop.ChannelId::Remote("other"),
    session: owner.session,
  }
  let other_ctx : Ctx = { ..test_ctx(), owner: other, }
  let (_, unchanged) = update(
    emit,
    FileWatchFailed(
      channel=other.channel,
      root=other_ctx.test_resource("/work"),
      generation=other_ctx.watch_identity(0),
      message="stale failure",
    ),
    failed,
    test_ctx(),
  )
  assert_true(unchanged.watch_error is Some("File watching stopped"))
}

///|
test "a recursive watcher failure stops retries and refreshes its index" {
  let emit = test_emit()
  let ctx = { ..test_ctx(), panel_open: false, }
  let generation = 5
  let watched = {
    ..owned_state(),
    index: IndexReady(
      files=[Relative("src/old.mbt")],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
    watching: Some({
      owner: ctx.owner,
      root: ctx.test_root(),
      files: [],
      directories: [],
      recursive: true,
    }),
    watch_generation: generation,
  }
  let (_, failed) = update(
    emit,
    FileWatchFailed(
      channel=ctx.owner.channel,
      root=ctx.test_root(),
      generation=ctx.watch_identity(generation),
      message="File watching stopped",
    ),
    watched,
    ctx,
  )
  assert_true(failed.watching is Some({ recursive: true, .. }))
  assert_true(
    failed.index is IndexReady(refreshing=true, refresh_again=false, ..),
  )
  assert_true(failed.watch_error is Some("File watching stopped"))
  let (stopped, _) = sync(emit, failed, ctx)
  // An unchanged desired configuration cannot create a request/failure loop.
  assert_true(stopped.watching is Some({ recursive: true, .. }))
  assert_eq(stopped.watch_generation, generation)
  assert_true(stopped.watch_error is Some("File watching stopped"))
  // A real policy change starts one fresh concrete watcher generation.
  let retry_ctx = {
    ..ctx,
    open_files: [Relative("node_modules/pkg/index.js")],
  }
  let (retried, _) = sync(emit, stopped, retry_ctx)
  assert_true(
    retried.watching
    is Some({ files: [Relative("node_modules/pkg/index.js")], .. }),
  )
  assert_eq(retried.watch_generation, generation + 1)
  assert_true(retried.watch_error is None)
}

///|
test "a settled run retries one failed watcher activation" {
  let emit = test_emit()
  let ctx = { ..test_ctx(), panel_open: false, }
  let generation = 5
  let watched = {
    ..owned_state(),
    index: IndexReady(
      files=[],
      truncated=false,
      refreshing=false,
      refresh_again=false,
    ),
    watching: Some({
      owner: ctx.owner,
      root: ctx.test_root(),
      files: [],
      directories: [],
      recursive: true,
    }),
    watch_generation: generation,
    watch_error: Some("watch root did not exist"),
  }
  let (_, settled) = update(emit, RunSettled(owner=ctx.owner), watched, ctx)
  assert_true(settled.watching is None)
  assert_true(settled.watch_error is Some("watch root did not exist"))
  let (retried, _) = sync(emit, settled, ctx)
  assert_true(retried.watching is Some({ recursive: true, .. }))
  assert_eq(retried.watch_generation, generation + 1)
  assert_true(retried.watch_error is None)
}

///|
test "same-root conversation switch fences every old watcher push" {
  let emit = test_emit()
  let old_generation = 4
  let state = {
    ..owned_state(),
    watching: Some({
      owner: test_ctx().owner,
      root: test_ctx().test_root(),
      files: [],
      directories: [@pathx.Relative::root()],
      recursive: false,
    }),
    watch_generation: old_generation,
  }
  let next_owner : @interop.ConversationKey = {
    channel: test_ctx().owner.channel,
    session: "desktop-other",
  }
  let next_ctx : Ctx = { ..test_ctx(), owner: next_owner, }
  let (switched, _) = sync(emit, state, next_ctx)
  assert_eq(switched.watch_generation, old_generation + 1)
  assert_true(switched.watching is Some({ owner, .. }) && owner == next_owner)

  // Both watchers use the same absolute root. Placement epochs fence concrete
  // change events; per-configuration generations independently fence failures.
  let ready = {
    ..switched,
    children: Map([(@pathx.Relative::root(), [])]),
    loading: [],
  }
  let (_, after_old_change) = update(
    emit,
    FsChanged(
      root=next_ctx.test_root(),
      generation=test_ctx().watch_identity(state.watch_generation),
      changes=None,
    ),
    ready,
    next_ctx,
  )
  assert_true(after_old_change.loading.is_empty())
  let stale_failure = FileWatchFailed(
    channel=next_owner.channel,
    root=next_ctx.test_root(),
    generation=test_ctx().watch_identity(old_generation),
    message="File watching stopped",
  )
  let (_, after_old_failure) = update(
    emit, stale_failure, after_old_change, next_ctx,
  )
  assert_true(after_old_failure.watch_error is None)
  // The native watcher survives a page reload while the frontend counter
  // starts over. A page namespace keeps an equal counter from the outgoing
  // page distinct from this page's current watcher.
  let previous_page_ctx : Ctx = {
    ..next_ctx,
    watch_namespace: "previous-page",
  }
  let (_, after_previous_page_failure) = update(
    emit,
    FileWatchFailed(
      channel=next_owner.channel,
      root=next_ctx.test_root(),
      generation=previous_page_ctx.watch_identity(switched.watch_generation),
      message="previous page watcher stopped",
    ),
    after_old_failure,
    next_ctx,
  )
  assert_true(after_previous_page_failure.watch_error is None)
  let current_failure = FileWatchFailed(
    channel=next_owner.channel,
    root=next_ctx.test_root(),
    generation=next_ctx.watch_identity(switched.watch_generation),
    message="current watcher stopped",
  )
  let (_, first) = update(
    emit, current_failure, after_previous_page_failure, next_ctx,
  )
  let (_, second) = update(emit, current_failure, ready, next_ctx)
  assert_eq(first.watch_error, Some("current watcher stopped"))
  assert_true(first.watch_error == second.watch_error)
}
