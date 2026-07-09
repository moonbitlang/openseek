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
    session: "desktop-test",
    workspace: None,
    dark_mode: false,
    tree_layout: BottomPanel,
  }
}

///|
fn open_state() -> State {
  { ..State::empty(), open: true, session: "desktop-test" }
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
      session="desktop-test",
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
      session="desktop-test",
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
      session="other-session",
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
  // Switch away: the tab set parks under its session id.
  let other : Ctx = {
    session: "other-session",
    workspace: None,
    dark_mode: false,
    tree_layout: BottomPanel,
  }
  let (parked, _) = sync(emit, state, other)
  assert_eq(parked.session, "other-session")
  assert_eq(parked.tabs.length(), 0)
  assert_true(parked.remembered.contains("desktop-test"))
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
    watching: "desktop-test",
    tabs: [loaded_tab("a.mbt", "a.mbt")],
    active: Some(Relative("a.mbt")),
  }
  let other : Ctx = {
    session: "other-session",
    workspace: None,
    dark_mode: false,
    tree_layout: BottomPanel,
  }
  let (parked, _) = sync(emit, state, other)
  assert_eq(parked.session, "other-session")
  assert_false(parked.open)
  assert_eq(parked.tabs.length(), 0)
  assert_true(parked.remembered.contains("desktop-test"))
  // Nothing left to track in the new conversation, so the watcher parks.
  assert_eq(parked.watching, "")
  // Switching back restores the identities — still hidden, not read yet —
  // and the watcher follows the tabs again.
  let (restored, _) = sync(emit, parked, test_ctx())
  assert_false(restored.open)
  assert_eq(restored.tabs.length(), 1)
  assert_true(restored.tabs[0].state is TabLoading)
  assert_true(restored.active is Some(Relative("a.mbt")))
  assert_eq(restored.watching, "desktop-test")
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
    StatsLoaded(session="desktop-test", stats=[
      // The active file changed: reloaded eagerly, so its tab stays loaded
      // (the baseline the scroll-keeping reload compares against).
      { path: Relative("a.mbt"), sig: "9:0" },
      // A background file changed: only marked stale.
      { path: Relative("b.mbt"), sig: "9:0" },
      // Deleted: the tab flips to the deleted notice state.
      { path: Relative("c.mbt"), sig: "" },
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
    StatsLoaded(session="desktop-test", stats=[
      { path: Relative("b.mbt"), sig: "9:0" },
    ]),
    { ..next, tabs: [loaded_tab("b.mbt", "b.mbt")], active: None },
    test_ctx(),
  )
  assert_true(same.tabs[0].state is TabLoaded(sig="1:0", ..))
  assert_true(same.tabs[0].stale) // "9:0" != baseline "1:0" -> stale
  // A reply from another conversation is dropped.
  let (_, other) = update(
    emit,
    StatsLoaded(session="other", stats=[{ path: Relative("a.mbt"), sig: "" }]),
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
    StatsLoaded(session="desktop-test", stats=[
      { path: Relative("a.mbt"), sig: "3:0" },
    ]),
    state,
    test_ctx(),
  )
  // Background reappearance: stale, reloaded on activation.
  assert_true(next.tabs[0].state is TabDeleted)
  assert_true(next.tabs[0].stale)
}

///|
test "FsChanged re-lists the root and expanded, already-listed directories" {
  let emit = test_emit()
  let children : Map[@pathx.Relative, Array[FileEntry]] = {}
  children[Relative("")] = []
  children[Relative("src")] = []
  let state = {
    ..open_state(),
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
  assert_eq(again.loading.length(), next.loading.length())
}

///|
test "sync reconciles the watcher with the panel and its tabs" {
  let emit = test_emit()
  // Open panel: watch the active session.
  let (watched, _) = sync(emit, open_state(), test_ctx())
  assert_eq(watched.watching, "desktop-test")
  // Closed panel with tabs still open: keep watching (staleness tracking).
  let closed = {
    ..watched,
    open: false,
    tabs: [loaded_tab("a.mbt", "a.mbt")],
    children: {},
    loading: [],
  }
  let (still, _) = sync(emit, closed, test_ctx())
  assert_eq(still.watching, "desktop-test")
  // Closed panel, no tabs: park the watcher.
  let empty_panel = { ..still, tabs: [] }
  let (parked, _) = sync(emit, empty_panel, test_ctx())
  assert_eq(parked.watching, "")
}
