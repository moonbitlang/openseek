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
/// active, re-reading the file so the viewer shows current content — and so
/// a jump's `range`/`annotation` ride the reply to be revealed on arrival.
fn open_or_activate(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
  path : @pathx.Relative,
  name : String,
  range~ : @common.Range?,
  annotation? : String,
) -> (@cmd.Cmd, State) {
  let tabs = if tab_index(state, path) is Some(_) {
    state.tabs
  } else {
    let tabs = state.tabs.copy()
    tabs.push({ path, name, state: TabLoading, stale: false })
    tabs
  }
  (
    read_file(
      dispatch,
      ctx.session,
      path,
      name,
      range~,
      annotation?,
      workspace=ctx.workspace,
    ),
    { ..state, tabs, active: Some(path), error: "" },
  )
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
/// so no conversation-switching handler has to re-root the panel itself. A
/// no-op unless something is actually due, so it never re-fires while a
/// request is in flight or the tree is already current.
pub fn sync(
  dispatch : @cmd.Emit[Msg],
  state : State,
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  guard state.open else { return with_watch(state, ctx, @cmd.none) }
  // When the active conversation changes, drop the cached tree *and* the
  // viewer's open document — the viewer is imperative state outside the
  // model, so it would otherwise keep showing the previous conversation's
  // file. The open tabs are parked by session id and restored (identities
  // only: the active one reloads now, the rest load on activation) when
  // their conversation returns.
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
    if active is Some(path) &&
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
        open: true,
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
    ToggleFilePanel =>
      // Loading the tree is left to `sync`.
      (mount_cmds(dispatch), { ..state, open: !state.open })
    ToggleTree =>
      // The viewer's width changes with the pane, and it cannot see a CSS
      // change on its own.
      (request_viewer_remeasure(), { ..state, tree_open: !state.tree_open })
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
            // open so the panel is never a dead pane.
            None =>
              (
                @cmd.batch([clear_document(), forget_view_state(path)]),
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
    FileFilterChanged(query) => (@cmd.none, { ..state, filter: query })
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
        // settles into its tab for the next activation.
        let cmd = if state.active == Some(path) {
          match file {
            // A disk change that produced identical text (a touch, a
            // rewrite-in-place) only refreshes the tab's signature; redrawing
            // would pointlessly reset the selection and feedback bubbles. A
            // jump (`range`) still redraws — its reveal is the point.
            Content(content~, ..) if range is None &&
              previous is TabLoaded(content=old, ..) &&
              old == content => @cmd.none
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
