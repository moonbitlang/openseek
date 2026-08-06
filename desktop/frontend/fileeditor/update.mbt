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
        ctx.owner,
        tab.path,
        tab.name,
        range=None,
        workspace=ctx.workspace,
      )
    TabLoaded(content~, absolute~, ..) => {
      let show = show_file_in_viewer(
        ctx.owner,
        ctx.workspace,
        tab.name,
        content,
        absolute~,
        relative=tab.path,
        restore_scroll=true,
      )
      if language_id(tab.name) == "moonbit" {
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
  // A tab that went stale in the background (or was deleted and reappeared)
  // shows what it has and reloads in the same breath; the reply lands with
  // the scroll kept in place.
  if tab.stale && !(tab.state is TabLoading) {
    @cmd.batch([
      show,
      read_file(
        dispatch,
        ctx.owner,
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
    // Gaining the first active tab reveals the breadcrumb row, and the
    // narrow drill-down closing the tree reveals a viewer that was last
    // measured while hidden — both need a remeasure alongside the show.
    let cmd = if state.active is None || (state.tree_open && ctx.narrow) {
      @cmd.batch([show, request_viewer_remeasure()])
    } else {
      show
    }
    return (
      cmd,
      {
        ..state,
        active: Some(path),
        error: None,
        tree_open: state.tree_open && !ctx.narrow,
      },
    )
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
  let cmd = if state.active is None || (state.tree_open && ctx.narrow) {
    @cmd.batch([read, request_viewer_remeasure()])
  } else {
    read
  }
  (
    cmd,
    {
      ..state,
      tabs,
      active: Some(path),
      error: None,
      tree_open: state.tree_open && !ctx.narrow,
    },
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
/// Whether this event can change the file currently addressed by `path`.
/// Structural directory events cover every descendant; a content modification
/// applies only to the exact file returned by the watcher.
fn FileChange::touches(self : FileChange, path : @pathx.Relative) -> Bool {
  match self {
    Modified(changed) => changed == path
    Created(changed) | Removed(changed) => @pathx.contains(changed.0, path.0)
    Renamed(old~, new~) =>
      @pathx.contains(old.0, path.0) || @pathx.contains(new.0, path.0)
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
fn FileChange::changes_file_list(self : FileChange) -> Bool {
  !(self is Modified(_))
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
/// The diagnostics request for the active tab when it is a loaded MoonBit
/// file, or `None` when it is anything else — the shared trigger behind the
/// stats, watcher, and run-finish re-check paths.
fn active_moonbit_diagnostics(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  tabs : Array[Tab],
  active : @pathx.Relative?,
) -> @cmd.Cmd? {
  guard active is Some(active) &&
    tabs.search_by(tab => tab.path == active) is Some(index) &&
    tabs[index] is { name, state: TabLoaded(absolute~, ..), .. } &&
    language_id(name) == "moonbit" else {
    return None
  }
  Some(request_diagnostics(dispatch, owner, absolute))
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
/// Reconcile the host's workspace watcher with what the panel needs: follow
/// the active session while the panel is open or tabs remain open in the
/// background (their staleness must keep being tracked for the reopen), park
/// it otherwise. Wraps every `sync` exit so the bookkeeping cannot be missed.
fn State::watched_paths(self : State, ctx : Ctx) -> WatchedPaths? {
  if (!self.open && self.tabs.is_empty()) || ctx.owner.session.is_empty() {
    return None
  }
  let files = self.tabs.map(tab => tab.path)
  files.sort_by((left, right) => left.0.lexical_compare(right.0))
  let directories : Array[@pathx.Relative] = []
  if self.open {
    directories.push(@pathx.Relative::root())
    for directory in self.expanded {
      if !directories.contains(directory) {
        directories.push(directory)
      }
    }
    directories.sort_by((left, right) => left.0.lexical_compare(right.0))
  }
  Some({ owner: ctx.owner, workspace: ctx.workspace, files, directories })
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
    // A watcher is host-local. Moving across channels must explicitly retire
    // the old host; placing a new watch on another socket cannot replace it.
    if state.watching is Some(current) &&
      (
        want is None ||
        (want is Some(next) && current.owner.channel != next.owner.channel)
      ) {
      commands.push(
        watch_workspace(dispatch, channel=current.owner.channel, None),
      )
    }
    if want is Some(next) {
      commands.push(
        watch_workspace(dispatch, channel=next.owner.channel, Some(next)),
      )
    }
    ({ ..state, watching: want, watch_error: None }, @cmd.batch(commands))
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
  // file. The open tabs are parked by conversation key and restored (identities
  // only: the active one reloads now, the rest load on activation) when
  // their conversation returns. This runs even while the panel is closed:
  // `with_watch` follows `ctx.owner` whenever tabs remain, so leaving the
  // tabs rooted in the previous conversation would have the next fs_changed
  // stat their paths against the new conversation's workspace — marking
  // hidden tabs deleted/stale for files that never moved.
  let (state, reroot_cmd) = if state.owner == Some(ctx.owner) {
    (state, @cmd.none)
  } else {
    let remembered = state.remembered.copy()
    if state.owner is Some(owner) && !owner.session.is_empty() {
      remembered[owner] = {
        entries: state.tabs.map(tab => { path: tab.path, name: tab.name }),
        active: state.active,
      }
    }
    let (tabs, active) = match remembered.get(ctx.owner) {
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
          ctx.owner,
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
        owner: Some(ctx.owner),
        tree_open: state.tree_open,
        // Preserve the last host configuration long enough for `with_watch`
        // to retire or replace it on the way out.
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
  guard state.open else { return with_watch(dispatch, state, ctx, reroot_cmd) }
  // Load as soon as there is a conversation: the workspace directory is a pure
  // function of the session id, so the host can list it without waiting for a
  // run to report `cwd` (it reports an empty workspace until the first turn
  // creates the directory).
  if ctx.owner.session.is_empty() ||
    state.children.contains("") ||
    state.loading.contains("") {
    return with_watch(dispatch, state, ctx, reroot_cmd)
  }
  let loading = state.loading.copy()
  loading.push("")
  with_watch(
    dispatch,
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
        let show = show_tab(dispatch, ctx, state.tabs[index])
        // The narrow drill-down closing the tree reveals a viewer that was
        // last measured while hidden; it must remeasure with the show.
        let cmd = if state.tree_open && ctx.narrow {
          @cmd.batch([show, request_viewer_remeasure()])
        } else {
          show
        }
        (
          cmd,
          {
            ..state,
            active: Some(path),
            error: None,
            tree_open: state.tree_open && !ctx.narrow,
          },
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
    FileSelected(path~, name~) =>
      open_or_activate(dispatch, state, ctx, path, name, range=None)
    OpenNavigationLocation(owner~, path~, range~) =>
      if state.owner == Some(owner) && ctx.owner == owner {
        open_file(dispatch, state, ctx, path, range=Some(range))
      } else {
        (@cmd.none, state)
      }
    FileLoaded(owner~, path~, name~, file~, range~, annotation~) =>
      // A stale read — the conversation switched, or the tab was closed
      // while the read was in flight — must not resurrect state.
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else if tab_index(state, path) is Some(index) {
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
            // runs `moon check` over the file's module and returns its
            // current diagnostics, and future re-analysis arrives as
            // `diagnostics` events. Other files have nothing behind
            // `lsp_open` — moon has no diagnostics for a README or JSON file
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
        (cmd, { ..state, tabs, })
      } else {
        (@cmd.none, state)
      }
    RunSettled(owner~) =>
      if state.owner == Some(owner) &&
        active_moonbit_diagnostics(dispatch, owner, state.tabs, state.active)
        is Some(recheck) {
        (recheck, state)
      } else {
        (@cmd.none, state)
      }
    FsChanged(session~, changes~) =>
      if state.owner is Some(owner) &&
        (session is None || session == Some(owner.session)) {
        // A baseline checks the whole selection after watcher replacement.
        // Concrete batches stat only affected tabs and re-list only directories
        // whose immediate children changed.
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
            for tab in state.tabs {
              if change.touches(tab.path) && !stat_paths.contains(tab.path) {
                stat_paths.push(tab.path)
              }
            }
            for directory in change.relist_candidates() {
              if !relist.contains(directory) &&
                state.children.contains(directory) &&
                (directory.is_root() || state.expanded.contains(directory)) &&
                !state.loading.contains(directory) {
                relist.push(directory)
              }
            }
            if change.changes_file_list() {
              refresh_index = true
            }
          }
        } else {
          for tab in state.tabs {
            stat_paths.push(tab.path)
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
          refresh_index = true
        }
        if !stat_paths.is_empty() {
          cmds.push(
            stat_files(dispatch, owner, stat_paths, workspace=ctx.workspace),
          )
        } else if moonbit_changed &&
          active_moonbit_diagnostics(dispatch, owner, state.tabs, state.active)
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
            read_directory(dispatch, owner, directory, workspace=ctx.workspace),
          )
        }
        // Only structural events can change the fuzzy index's path list.
        if refresh_index && !(state.index is IndexEmpty) {
          cmds.push(list_files(dispatch, owner, workspace=ctx.workspace))
        }
        (@cmd.batch(cmds), { ..state, loading, })
      } else {
        (@cmd.none, state)
      }
    StatsLoaded(owner~, stats~) =>
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        let tabs = state.tabs.copy()
        let cmds = []
        // Whether the loop below already reloads the active tab — that path
        // re-requests diagnostics on its own.
        let mut active_reloading = false
        for stat in stats {
          guard tabs.search_by(tab => tab.path == stat.path) is Some(index) else {
            continue
          }
          let tab = tabs[index]
          guard stat.sig is Some(current_sig) else {
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
            continue
          }
          let changed = match tab.state {
            // The loaded baseline says whether the disk moved on.
            TabLoaded(sig~, ..) => sig != current_sig
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
              active_reloading = true
              cmds.push(
                read_file(
                  dispatch,
                  owner,
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
        // A change elsewhere in the module can add or remove the active
        // file's diagnostics without touching its own mtime — the one-shot
        // `moon check` behind `lsp_open` only runs when asked, unlike the
        // resident server it replaced. One re-check per (debounced) change
        // burst covers that: the reload above brings its own request, so
        // only an active tab the stats left untouched needs the explicit
        // refresh. Its check's pushes update the other open tabs too.
        if !active_reloading &&
          active_moonbit_diagnostics(dispatch, owner, tabs, state.active)
          is Some(recheck) {
          cmds.push(recheck)
        }
        (@cmd.batch(cmds), { ..state, tabs, })
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
    FileWatchFailed(owner~, message~) =>
      if state.owner != Some(owner) {
        (@cmd.none, state)
      } else {
        (@cmd.none, { ..state, watch_error: Some(message) })
      }
    // Owned by the main package's update: the comment becomes a composer
    // chip there, which then clears the editor bubble through
    // `remove_editor_feedback`. Reaching this arm means the main update
    // didn't intercept it; changing nothing is the safe answer.
    EditorCommentAdded(..) => (@cmd.none, state)
  }
}

// State-transition tests for the tab strip: opening, activating, closing,
// and how a conversation switch parks and restores a tab set. Commands are
// opaque, so the tests assert on the returned state only.

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
  }
}

///|
fn open_state() -> State {
  { ..State::empty(), open: true, owner: Some(test_ctx().owner) }
}

///|
fn loaded_tab(path : String, name : String) -> Tab {
  {
    path: Relative(path),
    name,
    state: TabLoaded(content="", absolute=Absolute("/work/" + path), sig="1:0"),
    stale: false,
  }
}

///|
test "FileSelected opens tabs in click order and activates the last" {
  let emit = test_emit()
  let (_, one) = update(
    emit,
    FileSelected(path=Relative("a.mbt"), name="a.mbt"),
    open_state(),
    test_ctx(),
  )
  let (_, two) = update(
    emit,
    FileSelected(path=Relative("src/b.mbt"), name="b.mbt"),
    one,
    test_ctx(),
  )
  assert_eq(two.tabs.length(), 2)
  assert_true(two.tabs[0].path == Relative("a.mbt"))
  assert_true(two.tabs[1].path == Relative("src/b.mbt"))
  assert_true(two.active is Some(Relative("src/b.mbt")))
  // Re-selecting an open file refocuses its tab, never a duplicate.
  let (_, again) = update(
    emit,
    FileSelected(path=Relative("a.mbt"), name="a.mbt"),
    two,
    test_ctx(),
  )
  assert_eq(again.tabs.length(), 2)
  assert_true(again.active is Some(Relative("a.mbt")))
}

///|
test "narrow ctx: opening or activating a file closes the tree pane" {
  let emit = test_emit()
  let narrow : Ctx = { ..test_ctx(), narrow: true }
  let start = { ..open_state(), tree_open: true }
  // A fresh open drills down into the viewer.
  let (_, opened) = update(
    emit,
    FileSelected(path=Relative("a.mbt"), name="a.mbt"),
    start,
    narrow,
  )
  assert_false(opened.tree_open)
  // Back to the tree (the breadcrumb toggle), then activating an open tab
  // drills down again.
  let (_, tree) = update(emit, ToggleTree, opened, narrow)
  assert_true(tree.tree_open)
  let (_, activated) = update(
    emit,
    FileSelected(path=Relative("a.mbt"), name="a.mbt"),
    { ..tree, tabs: [loaded_tab("a.mbt", "a.mbt")], active: None },
    narrow,
  )
  assert_false(activated.tree_open)
  // The wide layout keeps the pane open alongside the viewer.
  let (_, wide) = update(
    emit,
    FileSelected(path=Relative("b.mbt"), name="b.mbt"),
    start,
    test_ctx(),
  )
  assert_true(wide.tree_open)
}

///|
/// The bug this guards against: re-selecting an already-loaded file from the
/// tree used to only issue a re-read and leave the document switch to the
/// `FileLoaded` reply — whose identical-content dedup then skipped the
/// redraw, leaving the previous tab's document on screen. A plain tree click
/// on an open tab now shows the cached content directly (like a tab-strip
/// click), so the tab must keep its loaded state rather than dropping back
/// to `TabLoading` for a read.
test "re-selecting a loaded file switches to its cached content" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [loaded_tab("a.mbt", "a.mbt"), loaded_tab("b.mbt", "b.mbt")],
    active: Some(Relative("b.mbt")),
  }
  let (_, next) = update(
    emit,
    FileSelected(path=Relative("a.mbt"), name="a.mbt"),
    state,
    test_ctx(),
  )
  assert_true(next.active is Some(Relative("a.mbt")))
  assert_true(next.tabs[0].state is TabLoaded(..))
  assert_eq(next.tabs.length(), 2)
}

///|
test "TabActivated switches only to an existing tab" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [loaded_tab("a.mbt", "a.mbt"), loaded_tab("b.mbt", "b.mbt")],
    active: Some(Relative("a.mbt")),
  }
  let (_, next) = update(
    emit,
    TabActivated(Relative("b.mbt")),
    state,
    test_ctx(),
  )
  assert_true(next.active is Some(Relative("b.mbt")))
  // An unknown path (a stale click racing a close) changes nothing.
  let (_, stray) = update(
    emit,
    TabActivated(Relative("gone.mbt")),
    next,
    test_ctx(),
  )
  assert_true(stray.active is Some(Relative("b.mbt")))
  // Re-activating the active tab is idempotent.
  let (_, same) = update(
    emit,
    TabActivated(Relative("b.mbt")),
    stray,
    test_ctx(),
  )
  assert_true(same.active is Some(Relative("b.mbt")))
  assert_eq(same.tabs.length(), 2)
}

///|
test "closing the active tab activates the right neighbor, else the left" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [
      loaded_tab("a.mbt", "a.mbt"),
      loaded_tab("b.mbt", "b.mbt"),
      loaded_tab("c.mbt", "c.mbt"),
    ],
    active: Some(Relative("b.mbt")),
  }
  // Middle tab closed: the right neighbor inherits the screen.
  let (_, next) = update(emit, TabClosed(Relative("b.mbt")), state, test_ctx())
  assert_eq(next.tabs.length(), 2)
  assert_true(next.active is Some(Relative("c.mbt")))
  // Rightmost tab closed: the left neighbor inherits.
  let (_, next) = update(emit, TabClosed(Relative("c.mbt")), next, test_ctx())
  assert_true(next.active is Some(Relative("a.mbt")))
}

///|
test "closing a background tab keeps the active one" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [loaded_tab("a.mbt", "a.mbt"), loaded_tab("b.mbt", "b.mbt")],
    active: Some(Relative("b.mbt")),
  }
  let (_, next) = update(emit, TabClosed(Relative("a.mbt")), state, test_ctx())
  assert_eq(next.tabs.length(), 1)
  assert_true(next.active is Some(Relative("b.mbt")))
}

///|
test "closing the last tab clears the viewer and forces the tree open" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tree_open: false,
    tabs: [loaded_tab("a.mbt", "a.mbt")],
    active: Some(Relative("a.mbt")),
  }
  let (_, next) = update(emit, TabClosed(Relative("a.mbt")), state, test_ctx())
  assert_eq(next.tabs.length(), 0)
  assert_true(next.active is None)
  assert_true(next.tree_open)
}

///|
test "FileLoaded settles content into its tab, active or not" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [
      {
        path: Relative("a.mbt"),
        name: "a.mbt",
        state: TabLoading,
        stale: false,
      },
      loaded_tab("b.mbt", "b.mbt"),
    ],
    active: Some(Relative("b.mbt")),
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
    test_ctx(),
  )
  assert_true(next.tabs[0].state is TabLoaded(content="fn main {}", ..))
  assert_true(next.active is Some(Relative("b.mbt")))
  // A reply for a closed tab (or another conversation) is dropped.
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
    test_ctx(),
  )
  assert_eq(stray.tabs.length(), 2)
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
    test_ctx(),
  )
  assert_true(other.tabs[0].state is TabLoaded(..))
}

///|
test "sync parks the outgoing conversation's tabs and restores them later" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [loaded_tab("a.mbt", "a.mbt"), loaded_tab("b.mbt", "b.mbt")],
    active: Some(Relative("a.mbt")),
    tree_open: false,
  }
  // Switch away: the tab set parks under its full conversation identity.
  let other : Ctx = {
    ..test_ctx(),
    owner: {
      channel: @interop.ChannelId::Remote("other"),
      session: "desktop-test",
    },
  }
  let (parked, _) = sync(emit, state, other)
  assert_true(parked.owner is Some({ channel: Remote("other"), .. }))
  assert_eq(parked.tabs.length(), 0)
  assert_true(parked.remembered.contains(test_ctx().owner))
  // The pane-visibility preference follows the panel, not the conversation.
  assert_false(parked.tree_open)
  // Switch back: identities return, contents reload lazily (the tabs are
  // TabLoading until read replies land).
  let (restored, _) = sync(emit, parked, test_ctx())
  assert_eq(restored.tabs.length(), 2)
  assert_true(restored.tabs[0].path == Relative("a.mbt"))
  assert_true(restored.tabs[0].state is TabLoading)
  assert_true(restored.active is Some(Relative("a.mbt")))
}

///|
/// The bug this guards against: with the panel closed but tabs remaining,
/// switching conversations used to skip the re-root while `with_watch`
/// followed the new session — the next fs_changed then stat'ed the old
/// conversation's paths against the new workspace, marking hidden tabs
/// deleted or stale for files that never moved.
test "a closed panel still re-roots when the conversation switches" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    open: false,
    watching: open_state().watched_paths(test_ctx()),
    tabs: [loaded_tab("a.mbt", "a.mbt")],
    active: Some(Relative("a.mbt")),
  }
  let other : Ctx = {
    ..test_ctx(),
    owner: {
      channel: @interop.ChannelId::Remote("other"),
      session: "desktop-test",
    },
  }
  let (parked, _) = sync(emit, state, other)
  assert_true(parked.owner is Some({ channel: Remote("other"), .. }))
  assert_false(parked.open)
  assert_eq(parked.tabs.length(), 0)
  assert_true(parked.remembered.contains(test_ctx().owner))
  // Nothing left to track in the new conversation, so the watcher parks.
  assert_true(parked.watching is None)
  // Switching back restores the identities — still hidden, not read yet —
  // and the watcher follows the tabs again.
  let (restored, _) = sync(emit, parked, test_ctx())
  assert_false(restored.open)
  assert_eq(restored.tabs.length(), 1)
  assert_true(restored.tabs[0].state is TabLoading)
  assert_true(restored.active is Some(Relative("a.mbt")))
  assert_true(
    restored.watching
    is Some(
      {
        owner: { channel: Local, session: "desktop-test" },
        workspace: None,
        files: [Relative("a.mbt")],
        directories: [],
      }
    ),
  )
  // Reopening is what reads the restored active tab (the command is opaque;
  // the tab stays TabLoading until the reply lands).
  let (_, reopened) = update(emit, ToggleFilePanel, restored, test_ctx())
  assert_true(reopened.open)
}

///|
test "ToggleTree flips the pane and RevealDirectory forces it open" {
  let emit = test_emit()
  let (_, closed) = update(emit, ToggleTree, open_state(), test_ctx())
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
  let state = {
    ..open_state(),
    tabs: [
      loaded_tab("a.mbt", "a.mbt"),
      loaded_tab("b.mbt", "b.mbt"),
      loaded_tab("c.mbt", "c.mbt"),
    ],
    active: Some(Relative("a.mbt")),
  }
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, stats=[
      // The active file changed: reloaded eagerly, so its tab stays loaded
      // (the baseline the scroll-keeping reload compares against).
      { path: Relative("a.mbt"), sig: Some("9:0") },
      // A background file changed: only marked stale.
      { path: Relative("b.mbt"), sig: Some("9:0") },
      // Deleted: the tab flips to the deleted notice state.
      { path: Relative("c.mbt"), sig: None },
    ]),
    state,
    test_ctx(),
  )
  assert_true(next.tabs[0].state is TabLoaded(..))
  assert_false(next.tabs[0].stale)
  assert_true(next.tabs[1].stale)
  assert_true(next.tabs[2].state is TabDeleted)
  // An unchanged signature is a no-op.
  let (_, same) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, stats=[
      { path: Relative("b.mbt"), sig: Some("9:0") },
    ]),
    { ..next, tabs: [loaded_tab("b.mbt", "b.mbt")], active: None },
    test_ctx(),
  )
  assert_true(same.tabs[0].state is TabLoaded(sig="1:0", ..))
  assert_true(same.tabs[0].stale) // "9:0" != baseline "1:0" -> stale
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
    test_ctx(),
  )
  assert_true(other.tabs[0].state is TabLoaded(..))
}

///|
test "a deleted tab whose file reappears reloads on the next stats" {
  let emit = test_emit()
  let state = {
    ..open_state(),
    tabs: [
      {
        path: Relative("a.mbt"),
        name: "a.mbt",
        state: TabDeleted,
        stale: false,
      },
    ],
    active: None,
  }
  let (_, next) = update(
    emit,
    StatsLoaded(owner=test_ctx().owner, stats=[
      { path: Relative("a.mbt"), sig: Some("3:0") },
    ]),
    state,
    test_ctx(),
  )
  // Background reappearance: stale, reloaded on activation.
  assert_true(next.tabs[0].state is TabDeleted)
  assert_true(next.tabs[0].stale)
}

///|
test "watcher baseline re-lists the root and expanded, listed directories" {
  let emit = test_emit()
  let children : Map[@pathx.Relative, Array[FileEntry]] = Map([])
  children[Relative("")] = []
  children[Relative("src")] = []
  let state = {
    ..open_state(),
    children,
    expanded: [Relative("src"), Relative("never-listed")],
  }
  let baseline = FsChanged(session=Some("desktop-test"), changes=None)
  let (_, next) = update(emit, baseline, state, test_ctx())
  // Both known directories are marked in flight; the never-listed one is
  // left to its own first expansion.
  assert_true(next.loading.contains(Relative("")))
  assert_true(next.loading.contains(Relative("src")))
  assert_false(next.loading.contains(Relative("never-listed")))
  // A second push while the lists are in flight stacks nothing.
  let (_, again) = update(emit, baseline, next, test_ctx())
  assert_eq(again.loading.length(), next.loading.length())
}

///|
test "concrete watcher events refresh only affected listed directories" {
  let emit = test_emit()
  let children : Map[@pathx.Relative, Array[FileEntry]] = Map([])
  children[Relative("")] = []
  children[Relative("src")] = []
  children[Relative("docs")] = []
  let state = {
    ..open_state(),
    children,
    expanded: [Relative("src"), Relative("docs")],
  }
  let message = FsChanged(
    session=Some("desktop-test"),
    changes=Some([Created(Relative("src/new.mbt"))]),
  )
  let (_, first) = update(emit, message, state, test_ctx())
  assert_true(first.loading == [Relative("src")])
  // Rabbita purity: the same message and model produce the same state.
  let (_, second) = update(emit, message, state, test_ctx())
  assert_true(first.loading == second.loading)
  // A late batch from the previous conversation is ignored.
  let (_, stale) = update(
    emit,
    FsChanged(
      session=Some("previous-session"),
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
test "sync reconciles the watcher with the panel and its tabs" {
  let emit = test_emit()
  // Open panel: watch the active session.
  let (watched, _) = sync(
    emit,
    { ..open_state(), watch_error: Some("old watcher failure") },
    test_ctx(),
  )
  assert_true(
    watched.watching
    is Some(
      {
        owner: { session: "desktop-test", .. },
        workspace: None,
        files: [],
        directories: [Relative("")],
      }
    ),
  )
  // Issuing a new watch attempt retires the previous failure.
  assert_true(watched.watch_error is None)
  // Opening a tab or expanding a directory replaces the same conversation's
  // watcher with the new exact selection.
  let selected = {
    ..watched,
    tabs: [loaded_tab("a.mbt", "a.mbt")],
    expanded: [Relative("src")],
  }
  let (replaced, _) = sync(emit, selected, test_ctx())
  assert_true(
    replaced.watching
    is Some(
      {
        files: [Relative("a.mbt")],
        directories: [Relative(""), Relative("src")],
        ..,
      }
    ),
  )
  // Closed panel with tabs still open: keep watching (staleness tracking).
  let closed = { ..replaced, open: false, children: Map([]), loading: [] }
  let (still, _) = sync(emit, closed, test_ctx())
  assert_true(
    still.watching is Some({ files: [Relative("a.mbt")], directories: [], .. }),
  )
  // Closed panel, no tabs: park the watcher.
  let empty_panel = { ..still, tabs: [] }
  let (parked, _) = sync(emit, empty_panel, test_ctx())
  assert_true(parked.watching is None)
}

///|
test "watcher failures are visible only in their owning conversation" {
  let emit = test_emit()
  let owner = test_ctx().owner
  let (_, failed) = update(
    emit,
    FileWatchFailed(owner~, message="File watching stopped"),
    open_state(),
    test_ctx(),
  )
  assert_true(failed.watch_error is Some("File watching stopped"))
  let other : @interop.ConversationKey = {
    channel: @interop.ChannelId::Remote("other"),
    session: owner.session,
  }
  let (_, unchanged) = update(
    emit,
    FileWatchFailed(owner=other, message="stale failure"),
    failed,
    test_ctx(),
  )
  assert_true(unchanged.watch_error is Some("File watching stopped"))
}
