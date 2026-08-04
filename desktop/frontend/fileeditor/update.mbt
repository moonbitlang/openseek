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
    request_viewer_remeasure(),
  ])
}

///|
/// The command that puts `path`'s document on screen: its content (scroll
/// restored to where the tab was left), a withheld/deleted notice, or — for
/// a document whose content is not loaded yet — a fresh read, whose
/// `FileLoaded` does the showing. A MoonBit file also re-syncs diagnostics,
/// matching what its first load did.
fn show_tab(
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
  path : @pathx.Relative,
  doc : Doc,
) -> @cmd.Cmd {
  let show = match doc.state {
    TabLoading =>
      // Covers both "a read is already in flight" (a duplicate reply is
      // folded idempotently) and "parked since a conversation restore, never
      // read" — the read is the only way to tell the viewer has something to
      // show.
      read_file(
        dispatch,
        ctx.owner,
        path,
        doc.name,
        range=None,
        workspace=ctx.workspace,
      )
    TabLoaded(content~, absolute~, ..) => {
      let show = show_file_in_viewer(
        ctx.owner,
        ctx.workspace,
        doc.name,
        content,
        absolute~,
        relative=path,
        restore_scroll=true,
      )
      if language_id(doc.name) == "moonbit" {
        @cmd.batch([show, request_diagnostics(dispatch, ctx.owner, absolute)])
      } else {
        show
      }
    }
    // Withheld and deleted tabs show the panel's own notice overlay (see
    // `viewer_notice`), never a synthesized source document; the viewer just
    // drops back to no document underneath it.
    TabBinary | TabOversized | TabDeleted => clear_document()
  }
  // A document that went stale in the background (or was deleted and
  // reappeared) shows what it has and reloads in the same breath; the reply
  // lands with the scroll kept in place.
  if doc.stale && !(doc.state is TabLoading) {
    @cmd.batch([
      show,
      read_file(
        dispatch,
        ctx.owner,
        path,
        doc.name,
        range=None,
        workspace=ctx.workspace,
      ),
    ])
  } else {
    show
  }
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
/// `range`/`annotation` ride the reply to be revealed on arrival.
pub fn open_document(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  name~ : String,
  range~ : @common.Range?,
  annotation? : String,
  had_active~ : Bool,
) -> (@cmd.Cmd, State) {
  // The plain-activation case must not rely on the read's reply to switch
  // the document: `FileLoaded`'s identical-content dedup assumes the reply's
  // document is the one on screen, so a re-read of an unchanged file would
  // skip the redraw and leave the previous tab's document showing. Withheld
  // and deleted documents still fall through to the read — a tree click is
  // the explicit re-open that refreshes them (see `TabState`).
  if range is None &&
    annotation is None &&
    state.docs.get(path) is Some(doc) &&
    !(doc.state is (TabBinary | TabOversized | TabDeleted)) {
    let show = show_tab(dispatch, ctx, path, doc)
    // Gaining the first active tab reveals the breadcrumb row, and the
    // narrow drill-down closing the tree reveals a viewer that was last
    // measured while hidden — both need a remeasure alongside the show.
    let cmd = if !had_active || (state.tree_open && ctx.narrow) {
      @cmd.batch([show, request_viewer_remeasure()])
    } else {
      show
    }
    return (
      cmd,
      { ..state, error: None, tree_open: state.tree_open && !ctx.narrow },
    )
  }
  let docs = state.docs.copy()
  if !docs.contains(path) {
    docs[path] = { name, state: TabLoading, stale: false }
  }
  let read = read_file(
    dispatch,
    ctx.owner,
    path,
    name,
    range~,
    annotation?,
    workspace=ctx.workspace,
  )
  // Gaining the first active tab reveals the breadcrumb row, and the narrow
  // drill-down closing the tree reveals a hidden-measured viewer — either
  // way the viewer must remeasure before the reply's document lands.
  let cmd = if !had_active || (state.tree_open && ctx.narrow) {
    @cmd.batch([read, request_viewer_remeasure()])
  } else {
    read
  }
  (
    cmd,
    { ..state, docs, error: None, tree_open: state.tree_open && !ctx.narrow },
  )
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
  guard state.docs.get(path) is Some(doc) else { return (@cmd.none, state) }
  let show = show_tab(dispatch, ctx, path, doc)
  // The narrow drill-down closing the tree reveals a viewer that was last
  // measured while hidden; it must remeasure with the show.
  let cmd = if state.tree_open && ctx.narrow {
    @cmd.batch([show, request_viewer_remeasure()])
  } else {
    show
  }
  (cmd, { ..state, error: None, tree_open: state.tree_open && !ctx.narrow })
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
  guard was_active else { return (forget_view_state(path), { ..state, docs, }) }
  match next {
    Some(next_path) =>
      if docs.get(next_path) is Some(doc) {
        (
          @cmd.batch([
            show_tab(dispatch, ctx, next_path, doc),
            forget_view_state(path),
          ]),
          { ..state, docs, },
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
        { ..state, docs, tree_open: true },
      )
  }
}

///|
/// The commands a panel-visibility toggle needs: the mount set always, plus
/// — when opening — a read for an active document that was restored while
/// the panel was closed and never read (it sits at `TabLoading`; opening is
/// what makes it worth showing, and a duplicate of an in-flight read folds
/// idempotently).
pub fn panel_toggle_cmds(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  opening~ : Bool,
) -> @cmd.Cmd {
  let cmds = [mount_cmds(dispatch)]
  if opening &&
    ctx.active_file is Some(path) &&
    state.docs.get(path) is Some(doc) &&
    doc.state is TabLoading {
    cmds.push(show_tab(dispatch, ctx, path, doc))
  }
  @cmd.batch(cmds)
}

///|
/// Reconcile the host's workspace watcher with what the panel needs: follow
/// the active session while the panel is open or tabs remain open in the
/// background (their staleness must keep being tracked for the reopen), park
/// it otherwise. Wraps every `sync` exit so the bookkeeping cannot be missed.
fn with_watch(state : State, ctx : Ctx, cmd : @cmd.Cmd) -> (State, @cmd.Cmd) {
  let want = if (ctx.panel_open || !ctx.open_files.is_empty()) &&
    !ctx.owner.session.is_empty() {
    Some(ctx.owner)
  } else {
    None
  }
  if state.watching == want {
    (state, cmd)
  } else {
    let commands = [cmd]
    // A watcher is host-local. Moving across channels must explicitly retire
    // the old host; placing a new watch on another socket cannot replace it.
    if state.watching is Some(current) &&
      (want is None || (want is Some(next) && current.channel != next.channel)) {
      commands.push(
        watch_workspace(channel=current.channel, "", workspace=None),
      )
    }
    if want is Some(next) {
      commands.push(
        watch_workspace(
          channel=next.channel,
          next.session,
          workspace=ctx.workspace,
        ),
      )
    }
    ({ ..state, watching: want }, @cmd.batch(commands))
  }
}

///|
/// Reconcile the file subsystem with the active conversation after every
/// message: rebuild the document table and drop the tree cache when the
/// conversation changed (the dock parks/restores strip identities; this side
/// re-seeds documents from the fresh `Ctx` projection), list the workspace
/// root once its path is known, and keep the host's file watcher pointed at
/// the right workspace. The main update runs this post-dispatch — after the
/// dock's own sync, so the projection is already the new conversation's.
/// The re-root happens whether the panel is open or closed — hidden
/// documents and the watcher must always agree on the session — while
/// listing the tree waits for an open panel. A no-op unless something is
/// actually due, so it never re-fires while a request is in flight or the
/// tree is already current.
pub fn sync(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  // When the active conversation changes, drop the cached tree *and* the
  // viewer's open document — the viewer is imperative state outside the
  // model, so it would otherwise keep showing the previous conversation's
  // file. The dock has already parked the outgoing strip and restored this
  // conversation's; the document table is rebuilt from the projection —
  // identities only, every entry `TabLoading` until a read lands. This runs
  // even while the panel is closed: `with_watch` follows `ctx.owner`
  // whenever open files remain, so leaving the documents rooted in the
  // previous conversation would have the next fs_changed stat their paths
  // against the new conversation's workspace — marking hidden documents
  // deleted/stale for files that never moved.
  let (state, reroot_cmd) = if state.owner == Some(ctx.owner) {
    (state, @cmd.none)
  } else {
    let docs : Map[@pathx.Relative, Doc] = Map([])
    for path in ctx.open_files {
      docs[path] = {
        name: basename(path),
        state: TabState::TabLoading,
        stale: false,
      }
    }
    let cmds = [clear_viewer()]
    // A hidden panel's restored active document is not worth a read yet; it
    // stays TabLoading and the panel-open toggle reads it on reopen.
    if ctx.panel_open && ctx.active_file is Some(path) && docs.contains(path) {
      cmds.push(
        read_file(
          dispatch,
          ctx.owner,
          path,
          basename(path),
          range=None,
          workspace=ctx.workspace,
        ),
      )
    }
    (
      {
        ..State::empty(),
        owner: Some(ctx.owner),
        tree_open: state.tree_open,
        // What the host actually watches doesn't change with the reroot;
        // `with_watch` re-points it against this record on the way out.
        watching: state.watching,
        docs,
      },
      @cmd.batch(cmds),
    )
  }
  // A closed panel re-roots (above) and keeps the watcher placed, but the
  // tree itself can wait for the reopen.
  guard ctx.panel_open else { return with_watch(state, ctx, reroot_cmd) }
  // Load as soon as there is a conversation: the workspace directory is a pure
  // function of the session id, so the host can list it without waiting for a
  // run to report `cwd` (it reports an empty workspace until the first turn
  // creates the directory).
  if ctx.owner.session.is_empty() ||
    state.children.contains("") ||
    state.loading.contains("") {
    return with_watch(state, ctx, reroot_cmd)
  }
  let loading = state.loading.copy()
  loading.push("")
  with_watch(
    { ..state, loading, },
    ctx,
    @cmd.batch([
      reroot_cmd,
      read_directory(
        dispatch,
        ctx.owner,
        @pathx.Relative::root(),
        workspace=ctx.workspace,
      ),
    ]),
  )
}

///|
pub fn update(
  dispatch : @cmd.Emit[Msg],
  msg : Msg,
  state : State,
  ctx : Ctx,
) -> (@cmd.Cmd, State) {
  match msg {
    ToggleTree => {
      // The docked panel takes its height from the viewer, and the viewer
      // cannot see a CSS change on its own. Opening also puts the keyboard
      // in the filter input, so the panel is drivable without the mouse.
      let opening = !state.tree_open
      let cmds = [request_viewer_remeasure()]
      if opening {
        cmds.push(focus_filter_after_render())
      }
      (@cmd.batch(cmds), { ..state, tree_open: opening })
    }
    RevealDirectory(path) =>
      if path.is_root() {
        (@cmd.none, { ..state, tree_open: true, highlighted: None })
      } else {
        let expanded = state.expanded.copy()
        let loading = state.loading.copy()
        let cmds = []
        for ancestor in ancestor_paths(path) {
          if !expanded.contains(ancestor) {
            expanded.push(ancestor)
          }
          if !state.children.contains(ancestor) && !loading.contains(ancestor) {
            loading.push(ancestor)
            cmds.push(
              read_directory(
                dispatch,
                ctx.owner,
                ancestor,
                workspace=ctx.workspace,
              ),
            )
          }
        }
        cmds.push(reveal_row_after_render(path))
        cmds.push(@cmd.delay(dispatch(HighlightCleared(path)), 1500))
        (
          @cmd.batch(cmds),
          {
            ..state,
            tree_open: true,
            expanded,
            loading,
            highlighted: Some(path),
          },
        )
      }
    HighlightCleared(path) =>
      if state.highlighted == Some(path) {
        (@cmd.none, { ..state, highlighted: None })
      } else {
        (@cmd.none, state)
      }
    DirToggle(path) =>
      if state.expanded.contains(path) {
        (
          @cmd.none,
          { ..state, expanded: state.expanded.filter(entry => entry != path) },
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
            read_directory(dispatch, ctx.owner, path, workspace=ctx.workspace),
            { ..state, expanded, loading },
          )
        }
      }
    FileFilterChanged(query) => {
      // A new query re-flattens the rows, so the old cursor position is
      // meaningless; the next ↑/↓ re-enters at an edge.
      let state = { ..state, filter: query, cursor: None }
      // The first non-blank query is what makes the workspace index worth
      // building. Setting `IndexLoading` right away keeps the keystrokes
      // that follow from stacking duplicate requests.
      if !query.trim().is_empty() && state.index is IndexEmpty {
        (
          list_files(dispatch, ctx.owner, workspace=ctx.workspace),
          { ..state, index: IndexLoading },
        )
      } else {
        (@cmd.none, state)
      }
    }
    TreeKeyMove(delta~) => {
      let entries = visible_entries(state)
      guard entries.length() > 0 else { return (@cmd.none, state) }
      let index = match cursor_index(state, entries) {
        Some(index) => (index + delta).clamp(min=0, max=entries.length() - 1)
        // First move (or the cursor's row vanished): enter the list at the
        // edge the key points away from.
        None => if delta > 0 { 0 } else { entries.length() - 1 }
      }
      let path = entries[index].0.path
      (scroll_cursor_after_render(path), { ..state, cursor: Some(path) })
    }
    TreeKeyAccept => {
      let entries = visible_entries(state)
      // The cursor's row; without one, a non-blank filter acts on its top
      // match, so "type then Enter" needs no arrow keys.
      let target = match cursor_index(state, entries) {
        Some(index) => Some(entries[index].0)
        None =>
          if !state.filter.trim().is_empty() && entries is [(entry, _), ..] {
            Some(entry)
          } else {
            None
          }
      }
      match target {
        Some(entry) =>
          if entry.is_dir {
            update(dispatch, DirToggle(entry.path), state, ctx)
          } else {
            // Opening a file is the dock strip's business: re-dispatch the
            // same message a tree click produces, which the root update
            // intercepts (see `FileSelected`).
            (dispatch(FileSelected(path=entry.path, name=entry.name)), state)
          }
        None => (@cmd.none, state)
      }
    }
    TreeKeyDismiss =>
      if !state.filter.trim().is_empty() {
        (@cmd.none, { ..state, filter: "", cursor: None })
      } else if ctx.active_file is Some(_) {
        // Close the panel like ToggleTree; with no file open the tree is
        // unconditional (see panel_view), so there is nothing to close into.
        (request_viewer_remeasure(), { ..state, tree_open: false })
      } else {
        (@cmd.none, state)
      }
    DirLoaded(owner~, path~, entries~) =>
      // Drop a reply whose conversation is no longer the panel's.
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        let children = state.children.copy()
        children[path] = entries
        // A pending highlight's target row may only now exist in the DOM —
        // this directory could be one of the ancestors `RevealDirectory` had
        // to list first (e.g. reached via a mention jump, which never
        // touched `expanded`/`children` itself).
        let reveal_cmd = match state.highlighted {
          Some(target) if ancestor_paths(target).contains(path) =>
            reveal_row_after_render(target)
          _ => @cmd.none
        }
        (
          reveal_cmd,
          {
            ..state,
            children,
            loading: state.loading.filter(entry => entry != path),
            error: None,
          },
        )
      }
    DirFailed(owner~, path~, message~) =>
      if state.owner != Some(owner) {
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
    FilesIndexed(owner~, files~, truncated~) =>
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, index: IndexReady(files~, truncated~) })
      }
    FileIndexFailed(owner~) =>
      // Only a failed first fetch drops back to retry-on-keystroke; a failed
      // refresh keeps serving the index it already has.
      if state.owner != Some(owner) || !(state.index is IndexLoading) {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, index: IndexEmpty })
      }
    // Owned by the main package's update: which dock tab a tree click opens
    // is the strip's business, so the root intercepts this (the
    // `EditorCommentAdded` pattern), opens/activates the dock tab, and calls
    // `open_document`. Reaching this arm means the root didn't intercept it;
    // changing nothing is the safe answer.
    FileSelected(..) => (@cmd.none, state)
    // Intercepted by the root for the same reason: a navigation jump opens
    // a dock tab before the document loads.
    OpenNavigationLocation(..) => (@cmd.none, state)
    FileLoaded(owner~, path~, name~, file~, range~, annotation~) =>
      // A stale read — the conversation switched, or the tab was closed
      // while the read was in flight — must not resurrect state.
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else if state.docs.get(path) is Some(doc) {
        let previous = doc.state
        let doc_state = match file {
          Content(content~, absolute~, sig~) =>
            TabState::TabLoaded(content~, absolute~, sig~)
          Binary => TabBinary
          Oversized => TabOversized
        }
        let docs = state.docs.copy()
        docs[path] = { name, state: doc_state, stale: false }
        // Only the tab on screen touches the viewer; a background load just
        // settles into its tab for the next activation. No content
        // comparison happens here: whether anything actually needs redrawing
        // is the show command's call, made against what the viewer really
        // displays (see `show_file_in_viewer`) — this side would only be
        // guessing from the tab cache.
        let cmd = if ctx.active_file == Some(path) {
          match file {
            // A real MoonBit file also gets a diagnostics request: the host
            // opens it in the language server and returns its current
            // diagnostics, and future re-analysis arrives as `diagnostics`
            // events. Other files have no server behind `lsp_open` — syncing
            // a README or JSON file to moon-lsp would surface bogus squiggles
            // — so only the viewer shows.
            Content(content~, absolute~, ..) => {
              let show = show_file_in_viewer(
                ctx.owner,
                ctx.workspace,
                name,
                content,
                absolute~,
                relative=path,
                range~,
                annotation?,
                // A reload of a document already on screen keeps the reading
                // position; only a genuinely fresh document opens at the top.
                restore_scroll=previous is TabLoaded(..),
              )
              if language_id(name) == "moonbit" {
                @cmd.batch([
                  show,
                  request_diagnostics(dispatch, ctx.owner, absolute),
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
    FsChanged => {
      guard state.owner is Some(owner) else { return (@cmd.none, state) }
      // Something under the watched workspace moved. Find out what: one
      // batched stat for the open files (the dock strip's projection), and a
      // re-list of the root plus every expanded directory already on screen
      // (marked loading so a burst of pushes cannot stack duplicate lists;
      // the watcher already debounces).
      let cmds = []
      if !ctx.open_files.is_empty() {
        cmds.push(
          stat_files(dispatch, owner, ctx.open_files, workspace=ctx.workspace),
        )
      }
      let relist : Array[@pathx.Relative] = []
      if state.children.contains("") && !state.loading.contains("") {
        relist.push(@pathx.Relative::root())
      }
      for dir in state.expanded {
        if state.children.contains(dir) && !state.loading.contains(dir) {
          relist.push(dir)
        }
      }
      let loading = state.loading.copy()
      for dir in relist {
        loading.push(dir)
        cmds.push(read_directory(dispatch, owner, dir, workspace=ctx.workspace))
      }
      // The fuzzy filter's index goes stale with the tree; rebuild it if
      // anyone has ever needed it (the reply just replaces the old list, so
      // the filter keeps showing the previous matches meanwhile).
      if !(state.index is IndexEmpty) {
        cmds.push(list_files(dispatch, owner, workspace=ctx.workspace))
      }
      (@cmd.batch(cmds), { ..state, loading, })
    }
    StatsLoaded(owner~, stats~) =>
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        let docs = state.docs.copy()
        let cmds = []
        for stat in stats {
          guard docs.get(stat.path) is Some(doc) else { continue }
          guard stat.sig is Some(current_sig) else {
            // The file is gone. The tab stays as the user's bookmark; the
            // notice replaces the document if it is the one on screen.
            if !(doc.state is TabDeleted) {
              docs[stat.path] = { ..doc, state: TabDeleted, stale: false }
              // The notice overlay renders from the document's new state;
              // the viewer only needs its stale document dropped.
              if ctx.active_file == Some(stat.path) {
                cmds.push(clear_document())
              }
            }
            continue
          }
          let changed = match doc.state {
            // The loaded baseline says whether the disk moved on.
            TabLoaded(sig~, ..) => sig != current_sig
            // A deleted file whose signature came back: it reappeared.
            TabDeleted => true
            // A read is already in flight; its reply carries a fresh
            // signature anyway.
            TabLoading => false
            // Withheld documents carry no baseline to compare against (see
            // `TabState`); they refresh on explicit re-open instead.
            TabBinary | TabOversized => false
          }
          if changed {
            if ctx.active_file == Some(stat.path) {
              // The document on screen reloads eagerly (scroll kept —
              // `FileLoaded` sees the previous content). The document keeps
              // its loaded state so that restore has its baseline.
              cmds.push(
                read_file(
                  dispatch,
                  owner,
                  stat.path,
                  doc.name,
                  range=None,
                  workspace=ctx.workspace,
                ),
              )
            } else {
              // Background documents just remember they are behind;
              // activation reloads them. A build storm therefore costs one
              // read, not one per open tab.
              docs[stat.path] = { ..doc, stale: true }
            }
          }
        }
        (@cmd.batch(cmds), { ..state, docs, })
      }
    DiagnosticsLoaded(owner~, absolute~, diagnostics~) =>
      if state.owner == Some(owner) {
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
    FileFailed(owner~, message~) =>
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, error: Some(message) })
      }
    // Owned by the main package's update: the comment becomes a composer
    // chip there, which then clears the editor bubble through
    // `remove_editor_feedback`. Reaching this arm means the main update
    // didn't intercept it; changing nothing is the safe answer.
    EditorCommentAdded(..) => (@cmd.none, state)
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
    owner: { channel: @interop.ChannelId::Local, session: "desktop-test" },
    workspace: None,
    dark_mode: false,
    tree_layout: BottomPanel,
    narrow: false,
    panel_open: true,
    open_files: [],
    active_file: None,
  }
}

///|
fn owned_state() -> State {
  { ..State::empty(), owner: Some(test_ctx().owner) }
}

///|
fn loaded_doc(path : String) -> Doc {
  {
    name: basename(Relative(path)),
    state: TabLoaded(content="", absolute=Absolute("/work/" + path), sig="1:0"),
    stale: false,
  }
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
test "narrow ctx: opening or activating a document closes the tree pane" {
  let emit = test_emit()
  let narrow : Ctx = {
    ..test_ctx(),
    narrow: true,
    open_files: [Relative("a.mbt")],
    active_file: Some(Relative("a.mbt")),
  }
  let start = { ..owned_state(), tree_open: true }
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
  let state = { ..owned_state(), docs, tree_open: false }
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
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = { name: "a.mbt", state: TabLoading, stale: false }
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
      path=Relative("a.mbt"),
      name="a.mbt",
      file=Content(
        content="fn main {}",
        absolute=Absolute("/work/a.mbt"),
        sig="2:0",
      ),
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
  let (_, stray) = update(
    emit,
    FileLoaded(
      owner=test_ctx().owner,
      path=Relative("gone.mbt"),
      name="gone.mbt",
      file=Content(content="", absolute=Absolute("/work/gone.mbt"), sig="2:0"),
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
      path=Relative("a.mbt"),
      name="a.mbt",
      file=Binary,
      range=None,
      annotation=None,
    ),
    stray,
    ctx,
  )
  assert_true(
    other.docs.get(Relative("a.mbt")) is Some({ state: TabLoaded(..), .. }),
  )
}

///|
test "sync re-roots the document table from the dock's projection" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("old.mbt")] = loaded_doc("old.mbt")
  let state = { ..owned_state(), docs, tree_open: false }
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
  let state = { ..owned_state(), docs, watching: Some(test_ctx().owner) }
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
  assert_true(
    restored.docs.get(Relative("a.mbt")) is Some({ state: TabLoading, .. }),
  )
  assert_true(
    restored.watching is Some({ channel: Local, session: "desktop-test" }),
  )
}

///|
test "ToggleTree flips the pane and RevealDirectory forces it open" {
  let emit = test_emit()
  let (_, closed) = update(emit, ToggleTree, owned_state(), test_ctx())
  assert_false(closed.tree_open)
  let (_, revealed) = update(
    emit,
    RevealDirectory(Relative("src")),
    closed,
    test_ctx(),
  )
  assert_true(revealed.tree_open)
  assert_true(revealed.highlighted is Some(Relative("src")))
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
    StatsLoaded(owner=test_ctx().owner, stats=[
      // The active file changed: reloaded eagerly, so its document stays
      // loaded (the baseline the scroll-keeping reload compares against).
      { path: Relative("a.mbt"), sig: Some("9:0") },
      // A background file changed: only marked stale.
      { path: Relative("b.mbt"), sig: Some("9:0") },
      // Deleted: the document flips to the deleted notice state.
      { path: Relative("c.mbt"), sig: None },
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
    StatsLoaded(owner=test_ctx().owner, stats=[
      { path: Relative("b.mbt"), sig: Some("9:0") },
    ]),
    { ..next, docs: solo },
    { ..ctx, active_file: None },
  )
  assert_true(
    same.docs.get(Relative("b.mbt"))
    is Some({ state: TabLoaded(sig="1:0", ..), stale: true, .. }),
  )
  // A reply from another conversation is dropped.
  let (_, other) = update(
    emit,
    StatsLoaded(
      owner={
        channel: @interop.ChannelId::Remote("other"),
        session: "desktop-test",
      },
      stats=[{ path: Relative("a.mbt"), sig: None }],
    ),
    state,
    ctx,
  )
  assert_true(
    other.docs.get(Relative("a.mbt")) is Some({ state: TabLoaded(..), .. }),
  )
}

///|
test "a deleted document whose file reappears reloads on the next stats" {
  let emit = test_emit()
  let docs : Map[@pathx.Relative, Doc] = Map([])
  docs[Relative("a.mbt")] = { name: "a.mbt", state: TabDeleted, stale: false }
  let state = { ..owned_state(), docs, }
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, stats=[
      { path: Relative("a.mbt"), sig: Some("3:0") },
    ]),
    state,
    { ..test_ctx(), open_files: [Relative("a.mbt")] },
  )
  // Background reappearance: stale, reloaded on activation.
  assert_true(
    next.docs.get(Relative("a.mbt"))
    is Some({ state: TabDeleted, stale: true, .. }),
  )
}

///|
test "FsChanged re-lists the root and expanded, already-listed directories" {
  let emit = test_emit()
  let children : Map[@pathx.Relative, Array[FileEntry]] = Map([])
  children[Relative("")] = []
  children[Relative("src")] = []
  let state = {
    ..owned_state(),
    children,
    expanded: [Relative("src"), Relative("never-listed")],
  }
  let (_, next) = update(emit, FsChanged, state, test_ctx())
  // Both known directories are marked in flight; the never-listed one is
  // left to its own first expansion.
  assert_true(next.loading.contains(Relative("")))
  assert_true(next.loading.contains(Relative("src")))
  assert_false(next.loading.contains(Relative("never-listed")))
  // A second push while the lists are in flight stacks nothing.
  let (_, again) = update(emit, FsChanged, next, test_ctx())
  assert_true(again.loading.length() == next.loading.length())
}

///|
test "sync reconciles the watcher with the panel and its open files" {
  let emit = test_emit()
  // Open panel: watch the active session.
  let (watched, _) = sync(emit, owned_state(), test_ctx())
  assert_true(watched.watching == Some(test_ctx().owner))
  // Closed panel with files still open: keep watching (staleness tracking).
  let still_ctx = {
    ..test_ctx(),
    panel_open: false,
    open_files: [Relative("a.mbt")],
  }
  let (still, _) = sync(
    emit,
    { ..watched, children: Map([]), loading: [] },
    still_ctx,
  )
  assert_true(still.watching == Some(test_ctx().owner))
  // Closed panel, nothing open: park the watcher.
  let (parked, _) = sync(emit, still, { ..test_ctx(), panel_open: false })
  assert_true(parked.watching is None)
}
