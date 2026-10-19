// A side chat beside the fixture conversation: its tab follows its record,
// it never takes a sidebar row, and what its composer does in the dock lands
// on it and never on the conversation in the column.

///|
const SideChatId : String = "desktop-test-sc-0a1b2c3d"

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
