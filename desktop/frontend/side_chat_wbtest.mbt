// A side chat beside the fixture conversation: its tab follows its record,
// it never takes a sidebar row, and what its composer does in the dock lands
// on it and never on the conversation in the column.

///|
const SideChatId : String = "desktop-test-sc-0a1b2c3d"

///|
test "a side chat file mention opens in the visible parent dock" {
  let model = { ..side_chat_model(), is_desktop: true, }
  let parent = model.dock_owner().host().unwrap()
  let target = model.test_file("src/main.mbt")
  let action = ComposerAction(
    @composer.MentionOpened(identity=side_chat_identity(model), mention={
      ref_: File(path="src/main.mbt"),
      range: None,
    }),
  )
  let (_, pending) = update(test_dispatch(), action, model)
  let (_, repeated) = update(test_dispatch(), action, model)
  assert_eq(
    pending.file_panel.file_link_generation,
    repeated.file_panel.file_link_generation,
  )
  let context = FileOpenContext::new(
    side_chat_owner(),
    pending.file_panel.file_link_generation,
    return_to=parent,
  )
  // Its tab belongs in the parent's dock.
  assert_true(context.destination == parent)
  let replies : Array[@protocol.OpenPathReply] = [
    Editor({ path: target.path, line: None, column: None, }),
    Directory({ path: "src", }),
    Browser(target.path),
  ]
  for reply in replies {
    let response = OpenPathResolved(context, reply)
    let (_, opened) = update(test_dispatch(), response, pending)
    let (_, replayed) = update(test_dispatch(), response, pending)
    assert_true(opened.docks == replayed.docks)
    assert_eq(opened.active_session, parent.session)
    match reply {
      Editor(_) =>
        assert_eq(@dock.active_file(opened.dock_state()), Some(target))
      Directory(_) => {
        assert_true(opened.dock_state().active is Some(FilePicker))
        assert_true(opened.file_panel.expanded.contains(Relative("src")))
      }
      Browser(_) => {
        assert_true(@dock.active_browser(opened.dock_state()) is Some(_))
        assert_eq(opened.preview.pages.length(), 1)
        assert_eq(replayed.preview.pages.length(), 1)
      }
      _ => fail("the fixture must resolve to an in-app dock tab")
    }
    assert_true(
      opened.dock_state().tabs.contains(SideChat(owner=side_chat_owner())),
    )
    // A side chat has no strip of its own.
    assert_true(opened.docks.get(@interop.Host(side_chat_owner())) is None)
  }
  assert_true(
    pending.dock_state().active == Some(SideChat(owner=side_chat_owner())),
  )
  assert_true(model.dock_state() == pending.dock_state())
}

///|
fn side_chat_owner() -> @interop.ConversationKey {
  { channel: @interop.ChannelId::Local, session: SideChatId, }
}

///|
/// The fixture conversation in the column, its side chat listed and running
/// with a question waiting, and the dock open. One message through `update`
/// lets the post-dispatch sync give the strip its tab.
fn side_chat_model() -> Model raise {
  let side = fold_engine(
    {
      ..empty_conversation(
        @interop.ChannelId::Local,
        SideChatId,
        @interop.ChannelId::Local.test_project(),
      ),
      run: Open(run_id="r7", stage=Opened),
    },
    ApprovalRequested(
      id="ap-side",
      tool_name="mbtx",
      detail="escalate",
      body=None,
    ),
  )
  let model = {
    ..test_model().with_listed(["desktop-test", SideChatId]),
    right_panel_open: true,
    window_focused: true,
  }.replace_conversation(side)
  let (_, synced) = update(test_dispatch(), CloseSelectMenu, model)
  synced
}

///|
fn side_chat_identity(model : Model) -> @composer.Identity {
  {
    owner: @interop.Host(side_chat_owner()),
    archive_generation: model.composer_entry_changes.length(),
  }
}

///|
test "a listed side chat is a tab in its conversation's dock" {
  let model = side_chat_model()
  assert_true(model.dock_state().tabs == [SideChat(owner=side_chat_owner())])
  assert_true(model.mounted_side_chat_owner() == Some(side_chat_owner()))
  assert_true(
    model.side_chats_of({
      channel: @interop.ChannelId::Local,
      session: "desktop-test",
    }) ==
    [side_chat_owner()],
  )
  // Its finish is watched there.
  assert_true(
    model.conversation_is_visible(@interop.ChannelId::Local, SideChatId),
  )
  // The record going away takes the tab along.
  let (_, gone) = update(
    test_dispatch(),
    CloseSelectMenu,
    model.with_listed(["desktop-test"]),
  )
  assert_true(gone.dock_state().tabs.is_empty())
  assert_true(gone.mounted_side_chat_owner() is None)
}

///|
test "a side chat never takes a sidebar row" {
  let model = side_chat_model()
  guard model.focused_device() is Some(dev) else { fail("no device") }
  let rows : Array[(RowStamp, @conversation.Input)] = []
  model.push_group_component_inputs(
    rows,
    dev,
    @interop.ChannelId::Local.test_project(),
    listed=id => id == "desktop-test" || id == SideChatId,
    archived=_ => false,
  )
  assert_true(rows.any(row => row.1.id().conversation() == "desktop-test"))
  assert_false(
    rows.any(row => {
      row.1.id().conversation() == SideChatId ||
      row.1.children.any(child => child.id().conversation() == SideChatId)
    }),
  )
}

///|
test "an approval answered in the dock settles the side chat's question" {
  let model = side_chat_model()
  let (_, answered) = update(
    test_dispatch(),
    ComposerAction(
      @composer.ApprovalAnswered(identity=side_chat_identity(model), allow=true),
    ),
    model,
  )
  guard answered.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) &&
    side.pending_approval is Some(pending) else {
    fail("the side chat's question must still be held")
  }
  assert_true(pending.answered)
  // The column is where it was, and its conversation is untouched.
  assert_eq(answered.active_session, "desktop-test")
  assert_true(answered.active().pending_approval is None)
}

///|
test "a column control sent from the dock is dropped" {
  let model = side_chat_model()
  let (_, toggled) = update(
    test_dispatch(),
    ComposerAction(
      @composer.ModelMenuToggled(identity=side_chat_identity(model)),
    ),
    model,
  )
  assert_true(toggled.select_menu is None)
  // Nor does the side chat answer anything once its tab is not on screen.
  let hidden = { ..model, right_panel_open: false, }
  let (_, ignored) = update(
    test_dispatch(),
    ComposerAction(
      @composer.ApprovalAnswered(
        identity=side_chat_identity(hidden),
        allow=true,
      ),
    ),
    hidden,
  )
  guard ignored.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) &&
    side.pending_approval is Some(pending) else {
    fail("the side chat's question must still be held")
  }
  assert_false(pending.answered)
}

///|
test "switching conversations keeps the side chat's state" {
  let model = side_chat_model()
  let other = model.activate(
    @interop.ChannelId::Local,
    "desktop-other",
    @interop.ChannelId::Local.test_project(),
  )
  assert_true(
    other.find_conversation(@interop.ChannelId::Local, SideChatId) is Some(_),
  )
}

///|
test "opening a background side chat changes only its parent's dock" {
  let initial = side_chat_model()
  let parent = initial.dock_owner()
  let file = initial.test_file("a.mbt")
  let initial = initial.with_dock_state(
    @dock.open_file(@dock.DockState::empty(), file),
  )
  let other = initial.activate(
    Local,
    "desktop-other",
    initial.active().project(),
  )
  let visible = other.dock_state()
  let opened = other.with_dock_state_for(
    parent,
    @dock.open_side_chat(other.dock_state_for(parent), side_chat_owner()),
  )
  assert_true(opened.dock_state() == visible)
  assert_true(other.dock_state_for(parent).tabs == [File(path=file)])
  let returned = opened.activate(
    Local,
    "desktop-test",
    initial.active().project(),
  )
  assert_true(
    returned.dock_state().tabs ==
    [File(path=file), SideChat(owner=side_chat_owner())],
  )
  assert_true(
    returned.dock_state().active == Some(SideChat(owner=side_chat_owner())),
  )
}

///|
test "the side chat's file completions index its conversation's checkout" {
  let model = side_chat_model()
  assert_true(model.file_panel.index is IndexEmpty)
  let (_, indexed) = update(
    test_dispatch(),
    ComposerAction(
      @composer.FileIndexEnsured(identity=side_chat_identity(model)),
    ),
    model,
  )
  assert_true(indexed.file_panel.index is IndexLoading(..))
  assert_eq(indexed.active_session, "desktop-test")
}

///|
test "the dock's composer stays with the side-chat tab while the dock is hidden" {
  let model = side_chat_model()
  let shown = model.dock_composer_input()
  assert_true(shown.identity.owner == @interop.Host(side_chat_owner()))
  // Hiding the dock keeps the composer on the side chat, so the component
  // still holds what was typed when the dock comes back.
  let hidden = { ..model, right_panel_open: false, }
  assert_true(hidden.mounted_side_chat_owner() is None)
  assert_true(
    hidden.dock_composer_input().identity.owner ==
    @interop.Host(side_chat_owner()),
  )
}

///|
test "a restored side chat uses an already loaded shared worktree" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_project()
  let worktree = @interop.ChannelId::Local.test_resource(
    "/work/shared-checkout",
  )
  for present in [true, false] {
    let (_, registry_loaded) = update_dev(
      dispatch,
      WorktreesLoaded(
        [
          {
            name: "shared",
            sessions: ["desktop-test", SideChatId],
            codex_thread: None,
            path: if present {
              Some(worktree)
            } else {
              None
            },
            present,
          },
        ],
        workspace~,
        connection_generation=0,
        request_generation=1,
      ),
      test_model(),
    )
    assert_true(
      registry_loaded.active().workspace is Worktree(name="shared", ..),
    )
    assert_true(registry_loaded.find_conversation(Local, SideChatId) is None)
    let listed = {
      ..registry_loaded.with_listed(["desktop-test", SideChatId]),
      right_panel_open: true,
    }
    let (_, restored) = update(dispatch, CloseSelectMenu, listed)
    let (_, again) = update(dispatch, CloseSelectMenu, listed)
    guard restored.find_conversation(Local, SideChatId) is Some(side) &&
      again.find_conversation(Local, SideChatId) is Some(repeated) else {
      fail("the listed side chat was not restored")
    }
    assert_true(side.workspace == repeated.workspace)
    assert_true(side.workspace is Worktree(name="shared", ..))
    assert_true(listed.find_conversation(Local, SideChatId) is None)
    assert_true(restored.dev().worktree_row(workspace, SideChatId) is Some(_))
    let expected_root = if present { Some(worktree) } else { None }
    assert_eq(restored.conversation_root(restored.active()), expected_root)
    // The registry row already identifies the child's checkout. Restoring its
    // transcript must not need another registry update to use that checkout.
    assert_eq(restored.conversation_root(side), expected_root)
    assert_eq(
      restored.side_chat_composer_input(side_chat_owner()).root,
      expected_root,
    )
    if !present {
      assert_true(
        restored.conversation_placement(side)
        is Some(@interop.MissingWorktree(name="shared", ..)),
      )
    }
  }
}

///|
test "a restored side chat waits for its worktree registry" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_project()
  let worktree = @interop.ChannelId::Local.test_resource(
    "/work/shared-checkout",
  )
  let listed = {
    ..test_model()
    .with_listed(["desktop-test", SideChatId])
    .with_dev(dev => { ..dev, worktrees: [], }),
    right_panel_open: true,
  }
  let (_, waiting) = update(dispatch, CloseSelectMenu, listed)
  let (_, repeated) = update(dispatch, CloseSelectMenu, listed)
  guard waiting.find_conversation(Local, SideChatId) is Some(side) &&
    repeated.find_conversation(Local, SideChatId) is Some(repeated_side) else {
    fail("the listed side chat was not restored while placement was loading")
  }
  assert_true(side.workspace == repeated_side.workspace)
  assert_true(listed.find_conversation(Local, SideChatId) is None)
  assert_true(waiting.conversation_placement(side) is None)
  assert_true(waiting.conversation_root(side) is None)
  assert_true(waiting.side_chat_composer_input(side_chat_owner()).root is None)
  // The column offers the retry; the dock, which could not act on it, does
  // not repeat the notice.
  assert_true(
    waiting.composer_input_for(side, surface=Column).presentation.context.contains(
      @composer.WorktreePlacementNotice,
    ),
  )
  assert_false(
    waiting.side_chat_composer_input(side_chat_owner()).presentation.context.contains(
      @composer.WorktreePlacementNotice,
    ),
  )
  let (_, loaded) = update(
    dispatch,
    on_home(
      WorktreesLoaded(
        [
          {
            name: "shared",
            sessions: ["desktop-test", SideChatId],
            codex_thread: None,
            path: Some(worktree),
            present: true,
          },
        ],
        workspace~,
        connection_generation=0,
        request_generation=1,
      ),
    ),
    waiting,
  )
  guard loaded.find_conversation(Local, SideChatId) is Some(placed) else {
    fail("the restored side chat was lost when placement loaded")
  }
  assert_true(side.workspace is Project(_))
  assert_true(placed.workspace is Worktree(name="shared", ..))
  assert_eq(loaded.conversation_root(placed), Some(worktree))
}

///|
test "closing an idle side chat's tab deletes it, and a failed delete brings it back" {
  let model = side_chat_model()
  let idle = model.replace_conversation({
    ..empty_conversation(
      @interop.ChannelId::Local,
      SideChatId,
      @interop.ChannelId::Local.test_project(),
    ),
  })
  let (_, closed) = update(
    test_dispatch(),
    Dock(TabClosed(SideChat(owner=side_chat_owner()))),
    idle,
  )
  // The tab is gone at once, though the listing still has the record.
  assert_true(closed.dock_state().tabs.is_empty())
  assert_true(
    closed.closing_side_chats == [{ chat: side_chat_owner(), stage: Deleting, }],
  )
  let (_, failed) = update(
    test_dispatch(),
    SideChatCloseFailed(chat=side_chat_owner(), message="kept"),
    closed,
  )
  assert_true(failed.closing_side_chats.is_empty())
  assert_true(failed.dock_state().tabs == [SideChat(owner=side_chat_owner())])
  // A deleted record leaves the listing, and the closing entry with it.
  let (_, deleted) = update(
    test_dispatch(),
    CloseSelectMenu,
    closed.with_listed(["desktop-test"]),
  )
  assert_true(deleted.closing_side_chats.is_empty())
  assert_true(deleted.dock_state().tabs.is_empty())
}

///|
test "a running side chat is stopped before it is deleted" {
  let model = side_chat_model()
  let (_, closed) = update(
    test_dispatch(),
    Dock(TabClosed(SideChat(owner=side_chat_owner()))),
    model,
  )
  assert_true(
    closed.closing_side_chats == [{ chat: side_chat_owner(), stage: Stopping, }],
  )
  guard closed.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  assert_true(side.run is Open(stage=Cancelling, ..))
  // Its turn ends: now it is deleted.
  let (_, ended) = update(
    test_dispatch(),
    CloseSelectMenu,
    closed.replace_conversation({ ..side, run: NoRun(ended=None), }),
  )
  assert_true(
    ended.closing_side_chats == [{ chat: side_chat_owner(), stage: Deleting, }],
  )
  assert_true(ended.dock_state().tabs.is_empty())
}

///|
test "a side chat closed while its turn starts is stopped once the run opens" {
  let model = side_chat_model()
  guard model.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  let starting = model.replace_conversation({
    ..side,
    run: Starting(submission_id="s1"),
  })
  let (_, closed) = update(
    test_dispatch(),
    Dock(TabClosed(SideChat(owner=side_chat_owner()))),
    starting,
  )
  assert_true(
    closed.closing_side_chats == [{ chat: side_chat_owner(), stage: Stopping, }],
  )
  // Its run opens: now it can be, and is, stopped.
  let (_, opened) = update(
    test_dispatch(),
    CloseSelectMenu,
    closed.replace_conversation({
      ..side,
      run: Open(run_id="r9", stage=Opened),
    }),
  )
  guard opened.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(stopping) else {
    fail("the side chat must be held")
  }
  assert_true(stopping.run is Open(run_id="r9", stage=Cancelling))
  assert_true(opened.dock_state().tabs.is_empty())
}

///|
test "a side chat whose stop failed gets its tab back" {
  let model = side_chat_model()
  let (_, closed) = update(
    test_dispatch(),
    Dock(TabClosed(SideChat(owner=side_chat_owner()))),
    model,
  )
  assert_true(closed.dock_state().tabs.is_empty())
  let (_, failed) = update_dev(
    test_dispatch(),
    CancelFailed(run_id="r7", message="cancel transport failed"),
    closed,
  )
  assert_true(failed.closing_side_chats.is_empty())
  assert_true(failed.dock_state().tabs == [SideChat(owner=side_chat_owner())])
  guard failed.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  assert_true(side.run is Open(run_id="r7", stage=AtStep(None)))
}

///|
/// `model` with the side chat's tab still in the strip but another tab on
/// screen, and the side chat's transcript in sync state `sync`.
fn side_chat_behind_another_tab(model : Model, sync : TranscriptSync) -> Model {
  guard model.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    abort("the side chat must be held")
  }
  let model = model
    .replace_conversation({ ..side, sync, })
    .with_dock_state({
      tabs: [SideChat(owner=side_chat_owner()), FilePicker],
      active: Some(SideChat(owner=side_chat_owner())),
    })
  update(test_dispatch(), Dock(TabActivated(FilePicker)), model).1
}

///|
fn side_chat_sync(model : Model) -> TranscriptSync? {
  model
  .find_conversation(@interop.ChannelId::Local, SideChatId)
  .map(side => side.sync)
}

///|
test "choosing a side chat's tab re-reads it, and retries a read that gave up" {
  let chosen = @dock.SideChat(owner=side_chat_owner())
  let synced = side_chat_behind_another_tab(side_chat_model(), Synced)
  let (_, reread) = update(test_dispatch(), Dock(TabActivated(chosen)), synced)
  assert_true(side_chat_sync(reread) is Some(Reloading(attempt=1, ..)))
  let failed = side_chat_behind_another_tab(
    side_chat_model(),
    ReloadFailed(generation=1, buffered=[]),
  )
  let (_, retried) = update(test_dispatch(), Dock(TabActivated(chosen)), failed)
  assert_true(side_chat_sync(retried) is Some(Reloading(attempt=1, ..)))
  // A read in flight stays the only one.
  let reading = side_chat_behind_another_tab(
    reread,
    side_chat_sync(reread).unwrap(),
  )
  let (_, again) = update(test_dispatch(), Dock(TabActivated(chosen)), reading)
  assert_eq(
    again.transcript_request_generation,
    reread.transcript_request_generation,
  )
}

///|
test "a reconnect re-reads the side chat in the dock" {
  let model = side_chat_model()
  guard model.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  let shown = model.replace_conversation({ ..side, sync: Synced, })
  assert_true(shown.mounted_side_chat_owner() == Some(side_chat_owner()))
  let (_, reconnected) = update_dev(test_dispatch(), BridgeReady, shown)
  assert_true(side_chat_sync(reconnected) is Some(Reloading(..)))
}

///|
test "a page the side chat's agent opens is a tab in its conversation's dock" {
  let model = side_chat_model()
  let (_, opened) = update(
    test_dispatch(),
    BrowserOpenRequested(
      request="browser-1",
      session=SideChatId,
      url="https://example.com/",
    ),
    model,
  )
  // The tab joins the strip on screen, beside the side chat's own tab, and
  // nothing keeps a strip under the side chat.
  assert_true(@dock.active_browser(opened.dock_state()) is Some(_))
  assert_true(
    opened.dock_state().tabs.contains(SideChat(owner=side_chat_owner())),
  )
  assert_true(opened.docks.get(@interop.Host(side_chat_owner())) is None)
  assert_true(opened.right_panel_open)
}

///|
test "a side chat shown again after the dock was hidden is re-read" {
  let model = side_chat_model()
  guard model.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  let (_, hidden) = update(
    test_dispatch(),
    ToggleRightPanel,
    model.replace_conversation({ ..side, sync: Synced, }),
  )
  assert_true(hidden.mounted_side_chat_owner() is None)
  assert_true(side_chat_sync(hidden) is Some(Synced))
  let (_, shown) = update(test_dispatch(), ToggleRightPanel, hidden)
  assert_true(shown.mounted_side_chat_owner() == Some(side_chat_owner()))
  assert_true(side_chat_sync(shown) is Some(Reloading(..)))
}

///|
test "a side chat's notification opens its conversation with the side chat on screen" {
  let model = side_chat_model()
  guard model.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  // The reader is elsewhere in the strip when the notice is clicked.
  let away = {
    ..model.replace_conversation({ ..side, last_run_id: Some("r7"), }),
    right_panel_open: false,
  }
  let (_, opened) = update(
    test_dispatch(),
    NotificationClicked(run_id="r7"),
    away,
  )
  // The column keeps the conversation; the side chat is its dock's tab.
  assert_eq(opened.active_session, "desktop-test")
  assert_true(opened.right_panel_open)
  assert_true(
    opened.dock_state().active == Some(SideChat(owner=side_chat_owner())),
  )
  assert_true(opened.mounted_side_chat_owner() == Some(side_chat_owner()))
  // The strip keeps its side chats through the next reconcile.
  let (_, settled) = update(test_dispatch(), CloseSelectMenu, opened)
  assert_true(settled.dock_state().tabs == [SideChat(owner=side_chat_owner())])
}

///|
test "an archived conversation's side chats are not rows of their own" {
  let project = @interop.ChannelId::Local.test_project()
  let archived = (id : String) => {
    (
      {
        id,
        title: Some("Archived"),
        workspace: project,
        workspace_name: "work",
        updated_at_ms: Some(1),
      } : @transcript.SessionListItem)
  }
  let model = test_model().with_dev(dev => {
    ..dev,
    archived: [archived("desktop-gone"), archived("desktop-gone-sc-0a1b2c3d")],
  })
  guard model
    .sidebar_component_sections(model.dev())
    .iter()
    .find_first(section => section.label.has_prefix("Archived"))
    is Some(section) else {
    fail("the archived section must be listed")
  }
  assert_eq(section.entries.length(), 1)
}

///|
test "a side chat's address leads to its conversation, never to a route of its own" {
  let model = side_chat_model()
  guard (
      { device: Some("local"), target: Session(SideChatId), } : @routes.Location).path()
    is Some(path) else {
    fail("a host session has an address")
  }
  let snapshot : @navigation_browser.Snapshot = {
    path,
    settings: false,
    can_back: true,
    can_forward: false,
  }
  // The side chat is already held, as after reading it in the dock.
  let away = { ..model, right_panel_open: false, }
  let (_, arrived) = update(
    test_dispatch(),
    Navigation(Browser(snapshot)),
    away,
  )
  assert_eq(arrived.active_session, "desktop-test")
  assert_true(
    arrived.navigation.location is Some({ target: Session("desktop-test"), .. }),
  )
  assert_true(arrived.right_panel_open)
  assert_true(arrived.mounted_side_chat_owner() == Some(side_chat_owner()))
}

///|
test "a reconnect re-reads the side chat while its conversation still loads" {
  let model = side_chat_model()
  guard model.find_conversation(@interop.ChannelId::Local, SideChatId)
    is Some(side) else {
    fail("the side chat must be held")
  }
  // The column's conversation was reselected and its read is still out.
  let loading = {
    ..model.replace_conversation({ ..side, sync: Synced, }),
    loading_conversation: Some({
      channel: @interop.ChannelId::Local,
      session: "desktop-test",
    }),
  }
  let (_, reconnected) = update_dev(test_dispatch(), BridgeReady, loading)
  assert_true(side_chat_sync(reconnected) is Some(Reloading(..)))
}
