///|
/// The conversation whose dock the right panel shows. Checkout readiness
/// affects file operations, while this identity keeps its tabs available.
fn Model::dock_owner(self : Model) -> @interop.ConversationIdentity {
  let host = @interop.Host(
    (if self.cloud_selected() { None } else { self.active_checkout() })
    .map(active => active.owner)
    .unwrap_or({ channel: self.focused, session: "", }),
  )
  if self.cloud_selected() {
    self
    .cloud_identity()
    .unwrap_or_else(() => self.cloud_draft_identity().unwrap_or(host))
  } else {
    host
  }
}

///|
fn Model::dock_state_for(
  self : Model,
  owner : @interop.ConversationIdentity,
) -> @dock.DockState {
  self.docks.get(owner).unwrap_or_else(@dock.DockState::empty)
}

///|
fn Model::dock_state(self : Model) -> @dock.DockState {
  self.dock_state_for(self.dock_owner())
}

///|
/// Change one conversation's tabs without affecting the strip on screen or
/// mutating an earlier model snapshot. Background opens use this same path.
fn Model::with_dock_state_for(
  self : Model,
  owner : @interop.ConversationIdentity,
  dock : @dock.DockState,
) -> Model {
  let docks = self.docks.copy()
  docks[owner] = dock
  { ..self, docks, }
}

///|
fn Model::with_dock_state(self : Model, dock : @dock.DockState) -> Model {
  self.with_dock_state_for(self.dock_owner(), dock)
}

///|
/// Open a listed conversation through the same request and snapshot messages
/// as a sidebar selection. A durable answer keeps it when another chat opens.
fn Model::test_open_dock_conversation(
  self : Model,
  session : String,
) -> Model raise {
  let (_, pending) = update(
    test_dispatch(),
    OpenSession(@interop.ChannelId::Local, session),
    self,
  )
  guard pending.find_conversation(@interop.ChannelId::Local, session)
    is Some({ sync: Reloading(generation~, ..), .. }) else {
    fail("opening the listed conversation must request its snapshot")
  }
  let (_, opened) = update(
    test_dispatch(),
    on_home(
      SessionLoaded(
        session~,
        items=[
          {
            kind: @transcript.Answer("Saved answer"),
            sequence: Some(1),
            ts: None,
          },
        ],
        watermark=1,
        goal=None,
        goal_markers=[],
        prediction=None,
        generation~,
      ),
    ),
    pending,
  )
  assert_eq(opened.active_session, session)
  opened
}

///|
test "conversation navigation retains docks and reveals background browser opens" {
  let dispatch = test_dispatch()
  let initial = desktop_model()
    .with_listed(["desktop-test", "dock-other"])
    .test_open_dock_conversation("desktop-test")
  let (_, browser) = update(dispatch, BrowserTabRequested, initial)
  let (_, picker) = update(dispatch, ExplorerRequested(ExplorerFiles), browser)
  let (_, first) = update(dispatch, Dock(TabActivated(Browser(id=1))), picker)
  let first_dock = first.dock_state()
  assert_true(first_dock.tabs == [Browser(id=1), FilePicker])
  assert_true(first_dock.active == Some(Browser(id=1)))

  let other = first.test_open_dock_conversation("dock-other")
  assert_true(other.dock_state().tabs.is_empty())
  let (_, other) = update(dispatch, JobsRequested, other)
  let other_dock = other.dock_state()
  assert_true(other_dock.tabs == [Jobs])
  assert_true(other_dock.active == Some(Jobs))
  let returned = other.test_open_dock_conversation("desktop-test")
  assert_true(returned.dock_state() == first_dock)

  let other = returned.test_open_dock_conversation("dock-other")
  assert_true(other.dock_state() == other_dock)
  let (_, other) = update(dispatch, ToggleRightPanelMenu, other)
  assert_true(other.right_panel_menu_open)
  let input_snapshot = file_ctx(other)
  let (_, background) = update(
    dispatch,
    BrowserOpenRequested(
      request="dock-background-request",
      session="desktop-test",
      url="https://example.com/background",
    ),
    other,
  )
  assert_eq(background.active_session, "dock-other")
  assert_true(background.dock_state() == other_dock)
  assert_true(background.right_panel_open == other.right_panel_open)
  assert_true(background.right_panel_menu_open)
  assert_true(
    background.file_panel.file_link_generation ==
    other.file_panel.file_link_generation,
  )
  assert_true(
    background.chat_navigation_generation == other.chat_navigation_generation,
  )
  // Allocating a background page must not mutate the earlier model or the
  // file context already projected from it.
  assert_true(file_ctx(other) == input_snapshot)
  assert_true(other.dock_state_for(first.dock_owner()) == first_dock)

  let returned = background.test_open_dock_conversation("desktop-test")
  assert_true(
    returned.dock_state().tabs == [Browser(id=1), FilePicker, Browser(id=2)],
  )
  assert_true(returned.dock_state().active == Some(Browser(id=2)))
  let other = returned.test_open_dock_conversation("dock-other")
  assert_true(other.dock_state() == other_dock)
}

///|
test "background dock writes isolate channels and preserve the visible file context" {
  let dispatch = test_dispatch()
  let (_, visible) = update(
    dispatch,
    ExplorerRequested(ExplorerFiles),
    desktop_model(),
  )
  let local_owner = visible.dock_owner()
  let remote : @interop.ConversationKey = {
    channel: @interop.ChannelId::Remote("dock-host"),
    session: local_owner.session(),
  }
  let remote_file = remote.channel.test_resource("/work/remote.mbt")
  let visible_dock = visible.dock_state()
  let input_snapshot = file_ctx(visible)
  let updated = visible.with_dock_state_for(
    @interop.Host(remote),
    @dock.open_file(visible.dock_state_for(@interop.Host(remote)), remote_file),
  )
  assert_true(updated.dock_owner() == local_owner)
  assert_true(updated.dock_state() == visible_dock)
  assert_true(file_ctx(updated) == input_snapshot)
  assert_true(
    updated.dock_state_for(@interop.Host(remote)).tabs ==
    [File(path=remote_file)],
  )
  assert_true(
    updated.dock_state_for(@interop.Host(remote)).active ==
    Some(File(path=remote_file)),
  )
  assert_true(visible.docks.get(@interop.Host(remote)) is None)
  assert_true(visible.dock_state() == visible_dock)
  assert_true(file_ctx(visible) == input_snapshot)
}

///|
test "leaving an empty owner retires its temporary dock before returning" {
  let dispatch = test_dispatch()
  let blank = {
    ..desktop_model().with_listed(["desktop-test"]),
    active_session: "",
    conversations: [],
    selected_conversation: None,
    navigation: AppNavigation::empty(),
  }
  let empty_owner = blank.dock_owner()
  assert_eq(empty_owner.session(), "")
  let (_, temporary) = update(dispatch, BrowserTabRequested, blank)
  assert_true(temporary.dock_state().tabs == [Browser(id=1)])

  let real = temporary.test_open_dock_conversation("desktop-test")
  assert_eq(real.dock_owner().session(), "desktop-test")
  assert_true(real.docks.get(empty_owner) is None)
  assert_true(real.dock_state().tabs.is_empty())
  let (_, real) = update(dispatch, JobsRequested, real)
  assert_true(real.dock_state().active == Some(Jobs))
  let dev = real.dev()
  // Detaching the only project removes the selected conversation and takes
  // the UI back to the same empty owner, as the registry broadcast would.
  let (_, blank_again) = update(
    dispatch,
    on_home(
      ProjectsLoaded(
        [],
        connection_generation=dev.connection_generation,
        request_generation=dev.projects_request_generation,
        chat_root=None,
      ),
    ),
    real,
  )
  assert_true(blank_again.dock_owner() == empty_owner)
  assert_true(blank_again.dock_state().tabs.is_empty())
  assert_true(blank_again.dock_state().active is None)
  assert_true(blank_again.docks.get(empty_owner) is None)
}
