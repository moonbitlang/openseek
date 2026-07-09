// The panel's message handlers and post-dispatch reconciliation, extracted
// from the main package's update loop. `update` is pure: effects go out as
// commands, and every host reply carries the `session` it answers so a reply
// that lost a conversation switch is dropped against `ctx`/`state.session`.

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
fn tab_index(state : State, path : @pathx.Relative) -> Int? {
  state.tabs.search_by(tab => tab.path == path)
}

///|
/// The command that puts `tab`'s document on screen: its content (scroll
/// restored to where the tab was left), a withheld/deleted notice, or — for
/// a tab whose content is not loaded yet — a fresh read, whose `FileLoaded`
/// does the showing. A MoonBit file also re-syncs diagnostics, matching what
/// its first load did.
fn show_tab(dispatch : @cmd.Emit[Msg], ctx : Ctx, tab : Tab) -> @cmd.Cmd {
  let show = match tab.state {
    TabLoading =>
      // Covers both "a read is already in flight" (a duplicate reply is
      // folded idempotently) and "parked since a conversation restore, never
      // read" — the read is the only way to tell the viewer has something to
      // show.
      read_file(
        dispatch,
        ctx.session,
        tab.path,
        tab.name,
        range=None,
        workspace=ctx.workspace,
      )
    TabLoaded(content~, absolute~, ..) => {
      let show = show_file_in_viewer(
        tab.name,
        content,
        absolute~,
        relative=tab.path,
        restore_scroll=true,
      )
      if language_id(tab.name) == "moonbit" {
        @cmd.batch([show, request_diagnostics(dispatch, absolute)])
      } else {
        show
      }
    }
    // Withheld and deleted tabs show the panel's own notice overlay (see
    // `viewer_notice`), never a synthesized source document; the viewer just
    // drops back to no document underneath it.
    TabBinary | TabOversized | TabDeleted => clear_document()
  }
  // A tab that went stale in the background (or was deleted and reappeared)
  // shows what it has and reloads in the same breath; the reply lands with
  // the scroll kept in place.
  if tab.stale && !(tab.state is TabLoading) {
    @cmd.batch([
      show,
      read_file(
        dispatch,
        ctx.session,
        tab.path,
        tab.name,
        range=None,
        workspace=ctx.workspace,
      ),
    ])
  } else {
    show
  }
}

///|
/// Open `path` in a tab (appending one if it is not open yet) and make it
/// active. A plain activation of an already-open tab shows what the tab has,
/// exactly like a tab-strip click; everything else reads the file — so a
/// jump's `range`/`annotation` ride the reply to be revealed on arrival.
fn open_or_activate(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  name : String,
  range~ : @common.Range?,
  annotation? : String,
) -> (@cmd.Cmd, State) {
  // The plain-activation case must not rely on the read's reply to switch
  // the document: `FileLoaded`'s identical-content dedup assumes the reply's
  // document is the one on screen, so a re-read of an unchanged file would
  // skip the redraw and leave the previous tab's document showing. Withheld
  // and deleted tabs still fall through to the read — a tree click is the
  // explicit re-open that refreshes them (see `TabState`).
  if range is None &&
    annotation is None &&
    tab_index(state, path) is Some(index) &&
    !(state.tabs[index].state is (TabBinary | TabOversized | TabDeleted)) {
    let show = show_tab(dispatch, ctx, state.tabs[index])
    let cmd = if state.active is None {
      @cmd.batch([show, request_viewer_remeasure()])
    } else {
      show
    }
    return (cmd, { ..state, active: Some(path), error: "" })
  }
  let tabs = if tab_index(state, path) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push({ path, name, state: TabLoading, stale: false })
    tabs
  }
  let read = read_file(
    dispatch,
    ctx.session,
    path,
    name,
    range~,
    annotation?,
    workspace=ctx.workspace,
  )
  // Gaining the first active tab reveals the breadcrumb row, so the viewer
  // must remeasure before the reply's document lands.
  let cmd = if state.active is None {
    @cmd.batch([read, request_viewer_remeasure()])
  } else {
    read
  }
  (cmd, { ..state, tabs, active: Some(path), error: "" })
}

///|
/// Open (or refocus) the panel on `path` — the tail of a composer chip's or
/// transcript chip's jump, after the main package has relativized the raw
/// path. Ensures the viewer is mounted, since the jump may be what opens the
/// panel.
pub fn open_file(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  range~ : @common.Range?,
  annotation? : String,
) -> (@cmd.Cmd, State) {
  let (cmd, state) = open_or_activate(
    dispatch,
    state,
    ctx,
    path,
    basename(path),
    range~,
    annotation?,
  )
  (@cmd.batch([mount_cmds(dispatch), cmd]), { ..state, open: true })
}

///|
/// Reconcile the host's workspace watcher with what the panel needs: follow
/// the active session while the panel is open or tabs remain open in the
/// background (their staleness must keep being tracked for the reopen), park
/// it otherwise. Wraps every `sync` exit so the bookkeeping cannot be missed.
fn with_watch(state : State, ctx : Ctx, cmd : @cmd.Cmd) -> (State, @cmd.Cmd) {
  let want = if state.open || !state.tabs.is_empty() { ctx.session } else { "" }
  if state.watching == want {
    (state, cmd)
  } else {
    (
      { ..state, watching: want },
      @cmd.batch([cmd, watch_workspace(want, workspace=ctx.workspace)]),
    )
  }
}

///|
/// Reconcile the panel with the active conversation after every message:
/// swap the tab set and tree when the conversation changed (parking the old
/// conversation's tabs in `remembered`, restoring the new one's), list the
/// workspace root once its path is known, and keep the host's file watcher
/// pointed at the right workspace. The main update runs this post-dispatch,
/// so no conversation-switching handler has to re-root the panel itself.
/// The re-root happens whether the panel is open or closed — hidden tabs
/// and the watcher must always agree on the session — while listing the
/// tree waits for an open panel. A no-op unless something is actually due,
/// so it never re-fires while a request is in flight or the tree is already
/// current.
pub fn sync(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  // When the active conversation changes, drop the cached tree *and* the
  // viewer's open document — the viewer is imperative state outside the
  // model, so it would otherwise keep showing the previous conversation's
  // file. The open tabs are parked by session id and restored (identities
  // only: the active one reloads now, the rest load on activation) when
  // their conversation returns. This runs even while the panel is closed:
  // `with_watch` follows `ctx.session` whenever tabs remain, so leaving the
  // tabs rooted in the previous conversation would have the next fs_changed
  // stat their paths against the new conversation's workspace — marking
  // hidden tabs deleted/stale for files that never moved.
  let (state, reroot_cmd) = if state.session == ctx.session {
    (state, @cmd.none)
  } else {
    let remembered = state.remembered.copy()
    if !state.session.is_empty() {
      remembered[state.session] = {
        entries: state.tabs.map(tab => { path: tab.path, name: tab.name }),
        active: state.active,
      }
    }
    let (tabs, active) = match remembered.get(ctx.session) {
      Some(parked) =>
        (
          parked.entries.map(entry => {
            path: entry.path,
            name: entry.name,
            state: TabState::TabLoading,
            stale: false,
          }),
          parked.active,
        )
      None => ([], (None : @pathx.Relative?))
    }
    let cmds = [clear_viewer()]
    // A hidden panel's restored active tab is not worth a read yet; it stays
    // TabLoading and `ToggleFilePanel` reads it on reopen.
    if state.open &&
      active is Some(path) &&
      tabs.search_by(tab => tab.path == path) is Some(index) {
      cmds.push(
        read_file(
          dispatch,
          ctx.session,
          path,
          tabs[index].name,
          range=None,
          workspace=ctx.workspace,
        ),
      )
    }
    (
      {
        ..State::empty(),
        open: state.open,
        session: ctx.session,
        tree_open: state.tree_open,
        // What the host actually watches doesn't change with the reroot;
        // `with_watch` re-points it against this record on the way out.
        watching: state.watching,
        remembered,
        tabs,
        active,
      },
      @cmd.batch(cmds),
    )
  }
  // A closed panel re-roots (above) and keeps the watcher placed, but the
  // tree itself can wait for the reopen.
  guard state.open else { return with_watch(state, ctx, reroot_cmd) }
  // Load as soon as there is a conversation: the workspace directory is a pure
  // function of the session id, so the host can list it without waiting for a
  // run to report `cwd` (it reports an empty workspace until the first turn
  // creates the directory).
  if ctx.session.is_empty() ||
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
        ctx.session,
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
    ToggleFilePanel => {
      // Loading the tree is left to `sync`. A re-root while the panel was
      // closed leaves the restored active tab unread (TabLoading); opening
      // is what makes it worth showing, so read it now (a duplicate of an
      // in-flight read folds idempotently).
      let opening = !state.open
      let cmds = [mount_cmds(dispatch)]
      if opening &&
        state.active is Some(path) &&
        tab_index(state, path) is Some(index) &&
        state.tabs[index].state is TabLoading {
        cmds.push(show_tab(dispatch, ctx, state.tabs[index]))
      }
      (@cmd.batch(cmds), { ..state, open: opening })
    }
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
    TabActivated(path) =>
      if state.active == Some(path) {
        (@cmd.none, state)
      } else if tab_index(state, path) is Some(index) {
        (
          show_tab(dispatch, ctx, state.tabs[index]),
          { ..state, active: Some(path), error: "" },
        )
      } else {
        (@cmd.none, state)
      }
    TabClosed(path) =>
      if tab_index(state, path) is Some(index) {
        let tabs = state.tabs.filter(tab => tab.path != path)
        if state.active == Some(path) {
          // The right neighbor inherits the screen; at the strip's end, the
          // left one. The closed tab's parked scroll is forgotten after the
          // neighbor's show re-parks the outgoing (closed) document.
          let next = match tabs.get(index) {
            Some(tab) => Some(tab)
            None => if index > 0 { tabs.get(index - 1) } else { None }
          }
          match next {
            Some(tab) =>
              (
                @cmd.batch([
                  show_tab(dispatch, ctx, tab),
                  forget_view_state(path),
                ]),
                { ..state, tabs, active: Some(tab.path) },
              )
            // The last tab: fall back to the placeholder and force the tree
            // open so the panel is never a dead pane. Losing the active tab
            // also hides the breadcrumb row, so the viewer must remeasure.
            None =>
              (
                @cmd.batch([
                  clear_document(),
                  forget_view_state(path),
                  request_viewer_remeasure(),
                ]),
                { ..state, tabs, active: None, tree_open: true },
              )
          }
        } else {
          (forget_view_state(path), { ..state, tabs, })
        }
      } else {
        (@cmd.none, state)
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
                ctx.session,
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
            read_directory(dispatch, ctx.session, path, workspace=ctx.workspace),
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
          list_files(dispatch, ctx.session, workspace=ctx.workspace),
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
          if !state.filter.trim().is_empty() && entries.length() > 0 {
            Some(entries[0].0)
          } else {
            None
          }
      }
      match target {
        Some(entry) =>
          if entry.is_dir {
            update(dispatch, DirToggle(entry.path), state, ctx)
          } else {
            update(
              dispatch,
              FileSelected(path=entry.path, name=entry.name),
              state,
              ctx,
            )
          }
        None => (@cmd.none, state)
      }
    }
    TreeKeyDismiss =>
      if !state.filter.trim().is_empty() {
        (@cmd.none, { ..state, filter: "", cursor: None })
      } else if state.active is Some(_) {
        // Close the panel like ToggleTree; with no file open the tree is
        // unconditional (see panel_view), so there is nothing to close into.
        (request_viewer_remeasure(), { ..state, tree_open: false })
      } else {
        (@cmd.none, state)
      }
    DirLoaded(session~, path~, entries~) =>
      // Drop a reply whose conversation is no longer the panel's.
      if state.session != session {
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
            error: "",
          },
        )
      }
    DirFailed(session~, path~, message~) =>
      if state.session != session {
        (@cmd.none, state)
      } else {
        (
          @cmd.none,
          {
            ..state,
            loading: state.loading.filter(entry => entry != path),
            error: message,
          },
        )
      }
    FilesIndexed(session~, files~, truncated~) =>
      if state.session != session {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, index: IndexReady(files~, truncated~) })
      }
    FileIndexFailed(session~) =>
      // Only a failed first fetch drops back to retry-on-keystroke; a failed
      // refresh keeps serving the index it already has.
      if state.session != session || !(state.index is IndexLoading) {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, index: IndexEmpty })
      }
    FileSelected(path~, name~) =>
      open_or_activate(dispatch, state, ctx, path, name, range=None)
    FileLoaded(session~, path~, name~, file~, range~, annotation~) =>
      // A stale read — the conversation switched, or the tab was closed
      // while the read was in flight — must not resurrect state.
      if state.session != session || tab_index(state, path) is None {
        (@cmd.none, state)
      } else {
        guard tab_index(state, path) is Some(index)
        let previous = state.tabs[index].state
        let tab_state = match file {
          Content(content~, absolute~, sig~) =>
            TabState::TabLoaded(content~, absolute~, sig~)
          Binary => TabBinary
          Oversized => TabOversized
        }
        let tabs = state.tabs.copy()
        tabs[index] = { ..tabs[index], name, state: tab_state, stale: false }
        // Only the tab on screen touches the viewer; a background load just
        // settles into its tab for the next activation. No content
        // comparison happens here: whether anything actually needs redrawing
        // is the show command's call, made against what the viewer really
        // displays (see `show_file_in_viewer`) — this side would only be
        // guessing from the tab cache.
        let cmd = if state.active == Some(path) {
          match file {
            // A real MoonBit file also gets a diagnostics request: the host
            // opens it in the language server and returns its current
            // diagnostics, and future re-analysis arrives as `diagnostics`
            // events. Other files have no server behind `lsp_open` — syncing
            // a README or JSON file to moon-lsp would surface bogus squiggles
            // — so only the viewer shows.
            Content(content~, absolute~, ..) => {
              let show = show_file_in_viewer(
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
                @cmd.batch([show, request_diagnostics(dispatch, absolute)])
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
        (cmd, { ..state, tabs, })
      }
    FsChanged => {
      // Something under the watched workspace moved. Find out what: one
      // batched stat for the open tabs, and a re-list of the root plus every
      // expanded directory already on screen (marked loading so a burst of
      // pushes cannot stack duplicate lists; the watcher already debounces).
      let cmds = []
      if !state.tabs.is_empty() {
        cmds.push(
          stat_files(
            dispatch,
            state.session,
            state.tabs.map(tab => tab.path),
            workspace=ctx.workspace,
          ),
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
        cmds.push(
          read_directory(dispatch, state.session, dir, workspace=ctx.workspace),
        )
      }
      // The fuzzy filter's index goes stale with the tree; rebuild it if
      // anyone has ever needed it (the reply just replaces the old list, so
      // the filter keeps showing the previous matches meanwhile).
      if !(state.index is IndexEmpty) {
        cmds.push(list_files(dispatch, state.session, workspace=ctx.workspace))
      }
      (@cmd.batch(cmds), { ..state, loading, })
    }
    StatsLoaded(session~, stats~) =>
      if state.session != session {
        (@cmd.none, state)
      } else {
        let tabs = state.tabs.copy()
        let cmds = []
        for stat in stats {
          guard tabs.search_by(tab => tab.path == stat.path) is Some(index) else {
            continue
          }
          let tab = tabs[index]
          if stat.sig.is_empty() {
            // The file is gone. The tab stays as the user's bookmark; the
            // notice replaces the document if it is the one on screen.
            if !(tab.state is TabDeleted) {
              tabs[index] = { ..tab, state: TabDeleted, stale: false }
              // The notice overlay renders from the tab's new state; the
              // viewer only needs its stale document dropped.
              if state.active == Some(tab.path) {
                cmds.push(clear_document())
              }
            }
          } else {
            let changed = match tab.state {
              // The loaded baseline says whether the disk moved on.
              TabLoaded(sig~, ..) => sig != stat.sig
              // A deleted file whose signature came back: it reappeared.
              TabDeleted => true
              // A read is already in flight; its reply carries a fresh
              // signature anyway.
              TabLoading => false
              // Withheld tabs carry no baseline to compare against (see
              // `TabState`); they refresh on explicit re-open instead.
              TabBinary | TabOversized => false
            }
            if changed {
              if state.active == Some(tab.path) {
                // The document on screen reloads eagerly (scroll kept —
                // `FileLoaded` sees the previous content). The tab keeps its
                // loaded state so that restore has its baseline.
                cmds.push(
                  read_file(
                    dispatch,
                    state.session,
                    tab.path,
                    tab.name,
                    range=None,
                    workspace=ctx.workspace,
                  ),
                )
              } else {
                // Background tabs just remember they are behind; activation
                // reloads them. A build storm therefore costs one read, not
                // one per open tab.
                tabs[index] = { ..tab, stale: true }
              }
            }
          }
        }
        (@cmd.batch(cmds), { ..state, tabs, })
      }
    DiagnosticsPublished(absolute~, diagnostics~) =>
      (apply_diagnostics(absolute, diagnostics), state)
    FileFailed(session~, message~) =>
      if state.session != session {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, error: message })
      }
    // Owned by the main package's update: the comment becomes a composer
    // chip there, which then clears the editor bubble through
    // `remove_editor_feedback`. Reaching this arm means the main update
    // didn't intercept it; changing nothing is the safe answer.
    EditorCommentAdded(..) => (@cmd.none, state)
  }
}
