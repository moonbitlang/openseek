// State-transition tests for the strip machine: opening, activating,
// closing, and their projections. Conversation ownership is the root's;
// the dock is command-free, so every assertion is on the returned state.

///|
fn owner(session : String) -> @interop.ConversationIdentity {
  @interop.Host({ channel: @interop.ChannelId::Local, session, })
}

///|
/// A file below the fixture checkout, as the dock keys it.
fn work_file(path : String) -> @common.Uri raise {
  guard @resource.of_path(@interop.ChannelId::Local, "/work/" + path)
    is Some(file) else {
    fail("fixture path must be absolute")
  }
  file
}

///|
fn file_tab(path : String) -> @dock.DockTab raise {
  @dock.DockTab::File(path=work_file(path))
}

///|
test "bulk close selects relative to the clicked tab across tab kinds" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_browser(7)
    |> @dock.open_picker()
    |> @dock.open_workflows()
  let anchor = @dock.DockTab::Browser(id=7)
  assert_true(@dock.tabs_to_close(state, ToLeft(anchor)) == [file_tab("a.mbt")])
  assert_true(
    @dock.tabs_to_close(state, ToRight(anchor)) ==
    [@dock.DockTab::FilePicker, @dock.DockTab::Workflows],
  )
  assert_true(
    @dock.tabs_to_close(state, Others(anchor)) ==
    [file_tab("a.mbt"), @dock.DockTab::FilePicker, @dock.DockTab::Workflows],
  )
  assert_true(@dock.tabs_to_close(state, All) == state.tabs)
  assert_true(@dock.tabs_to_close(state, ToLeft(file_tab("a.mbt"))).is_empty())
  assert_true(@dock.tabs_to_close(state, ToRight(Workflows)).is_empty())
  assert_true(
    @dock.tabs_to_close(state, Others(file_tab("missing"))).is_empty(),
  )
  assert_true(
    @dock.tabs_to_close(state, ToLeft(file_tab("missing"))).is_empty(),
  )
  assert_true(
    @dock.tabs_to_close(state, ToRight(file_tab("missing"))).is_empty(),
  )
  let single = @dock.DockState::empty() |> @dock.open_picker()
  assert_true(@dock.tabs_to_close(single, Others(FilePicker)).is_empty())
}

///|
test "open_file appends in order and activates" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
  assert_true(
    @dock.file_paths(state) == [work_file("a.mbt"), work_file("b.mbt")],
  )
  assert_true(@dock.active_file(state) == Some(work_file("b.mbt")))
}

///|
test "open_file re-activates an existing tab without duplicating it" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
    |> @dock.open_file(work_file("a.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
}

///|
test "TabActivated switches to a present tab and ignores an absent one" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
  let activated = @dock.update(@dock.TabActivated(file_tab("a.mbt")), state)
  assert_true(activated.active == Some(file_tab("a.mbt")))
  // Idempotent: activating the active tab changes nothing.
  let again = @dock.update(@dock.TabActivated(file_tab("a.mbt")), activated)
  assert_true(again == activated)
  let ghost = @dock.update(@dock.TabActivated(file_tab("ghost.mbt")), state)
  assert_true(ghost == state)
}

///|
test "closing the active tab activates the right neighbor, else the left" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
    |> @dock.open_file(work_file("c.mbt"))
  // Close the middle tab while it is active: the right neighbor wins.
  let state = @dock.update(@dock.TabActivated(file_tab("b.mbt")), state)
  let state = @dock.update(@dock.TabClosed(file_tab("b.mbt")), state)
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("c.mbt")])
  assert_true(state.active == Some(file_tab("c.mbt")))
  // Close the last tab while it is active: the left neighbor wins.
  let state = @dock.update(@dock.TabClosed(file_tab("c.mbt")), state)
  assert_true(state.tabs == [file_tab("a.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
  // Close the only tab: the strip empties and nothing is active.
  let state = @dock.update(@dock.TabClosed(file_tab("a.mbt")), state)
  assert_true(state.tabs.is_empty())
  assert_true(state.active is None)
}

///|
test "closing a background tab keeps the active tab" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
  let state = @dock.update(@dock.TabClosed(file_tab("a.mbt")), state)
  assert_true(state.tabs == [file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
  // Idempotent: closing an already-closed tab changes nothing.
  let again = @dock.update(@dock.TabClosed(file_tab("a.mbt")), state)
  assert_true(again == state)
}

///|
test "empty docks have no projections and ignore absent tab actions" {
  let state = @dock.DockState::empty()
  assert_true(state.tabs.is_empty())
  assert_true(state.active is None)
  assert_true(@dock.file_paths(state).is_empty())
  assert_true(@dock.history_diffs(state).is_empty())
  assert_true(@dock.active_file(state) is None)
  assert_true(@dock.active_history_diff(state) is None)
  assert_true(@dock.active_browser(state) is None)
  assert_true(@dock.tabs_to_close(state, All).is_empty())
  assert_true(@dock.update(TabActivated(Browser(id=7)), state) == state)
  assert_true(@dock.update(TabClosed(Browser(id=7)), state) == state)
}

///|
test "tab transitions preserve earlier dock snapshots" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
  let opened = @dock.open_browser(state, 7)
  let closed = @dock.update(TabClosed(file_tab("b.mbt")), state)
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
  assert_true(
    opened.tabs ==
    [file_tab("a.mbt"), file_tab("b.mbt"), @dock.DockTab::Browser(id=7)],
  )
  assert_true(opened.active == Some(Browser(id=7)))
  assert_true(closed.tabs == [file_tab("a.mbt")])
  assert_true(closed.active == Some(file_tab("a.mbt")))
}

///|
test "open_browser appends and re-activates without duplicating" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_browser(7)
  assert_true(state.tabs == [file_tab("a.mbt"), @dock.DockTab::Browser(id=7)])
  assert_true(state.active == Some(@dock.DockTab::Browser(id=7)))
  assert_true(@dock.active_browser(state) == Some(7))
  assert_true(@dock.active_file(state) is None)
  // Files projection skips non-file tabs.
  assert_true(@dock.file_paths(state) == [work_file("a.mbt")])
  let again = @dock.open_browser(state, 7)
  assert_true(again.tabs == state.tabs)
}

///|
test "open_picker keeps at most one picker tab" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_picker
    |> @dock.open_file(work_file("b.mbt"))
    |> @dock.open_picker
  assert_true(
    state.tabs ==
    [file_tab("a.mbt"), @dock.DockTab::FilePicker, file_tab("b.mbt")],
  )
  assert_true(state.active == Some(@dock.DockTab::FilePicker))
}

///|
test "resolve_pick replaces the picker in place with a fresh file" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_picker
  let state = @dock.resolve_pick(state, file_tab("b.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
  let picker = @dock.open_picker(state)
  let browser = @dock.resolve_pick(picker, Browser(id=7))
  assert_true(
    browser.tabs ==
    [file_tab("a.mbt"), file_tab("b.mbt"), @dock.DockTab::Browser(id=7)],
  )
  let reused = @dock.resolve_pick(@dock.open_picker(browser), Browser(id=7))
  assert_true(browser == reused)
}

///|
test "resolve_pick activates an already-open file and closes the picker" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_file(work_file("b.mbt"))
    |> @dock.open_picker
  let state = @dock.resolve_pick(state, file_tab("a.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
}

///|
test "resolve_pick without a picker is a plain open" {
  let state = @dock.DockState::empty() |> @dock.open_file(work_file("a.mbt"))
  let state = @dock.resolve_pick(state, file_tab("b.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
}

///|
test "closing the picker activates a neighbor like any tab" {
  let state = @dock.DockState::empty()
    |> @dock.open_file(work_file("a.mbt"))
    |> @dock.open_picker
  let state = @dock.update(TabClosed(@dock.DockTab::FilePicker), state)
  assert_true(state.tabs == [file_tab("a.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
}

///|
test "singleton views re-activate without changing tab order" {
  let state = @dock.DockState::empty()
    |> @dock.open_workflows()
    |> @dock.open_github()
    |> @dock.open_jobs()
    |> @dock.open_workflows()
    |> @dock.open_github()
    |> @dock.open_jobs()
  assert_true(
    state.tabs ==
    [@dock.DockTab::Workflows, @dock.DockTab::Github, @dock.DockTab::Jobs],
  )
  assert_true(state.active == Some(@dock.DockTab::Jobs))
  assert_true(@dock.active_browser(state) is None)
  assert_true(@dock.active_file(state) is None)
  assert_true(@dock.active_history_diff(state) is None)
}

///|
test "tab menus resolve only targets from their explicit conversation owner" {
  let state = @dock.DockState::empty() |> @dock.open_browser(7)
  let dispatch : @cmd.Emit[@dock.Msg] = @cmd.Emit(_ => @cmd.none)
  let close : @cmd.Emit[@dock.CloseSelection] = @cmd.Emit(_ => @cmd.none)
  let target = "dock:host:local:alpha:browser:7"
  assert_true(
    @dock.tab_menu(state, target, dispatch, close, owner=owner("alpha"))
    is Some(_),
  )
  assert_true(
    @dock.tab_menu(state, target, dispatch, close, owner=owner("beta")) is None,
  )
  let remote = @interop.Host({
    channel: @interop.ChannelId::Remote("host"),
    session: "alpha",
  })
  assert_true(
    @dock.tab_menu(state, target, dispatch, close, owner=remote) is None,
  )
  assert_true(
    @dock.tab_menu(
      state,
      "dock:host:remote.host:alpha:browser:7",
      dispatch,
      close,
      owner=remote,
    )
    is Some(_),
  )
}

///|
test "tab menus isolate Cloud accounts and Host conversations" {
  let state = @dock.DockState::empty() |> @dock.open_picker()
  let dispatch : @cmd.Emit[@dock.Msg] = @cmd.Emit(_ => @cmd.none)
  let close : @cmd.Emit[@dock.CloseSelection] = @cmd.Emit(_ => @cmd.none)
  let target = "dock:cloud:7:account:alpha:picker"
  let cloud = @interop.Cloud(account="account", session="alpha")
  assert_true(
    @dock.tab_menu(state, target, dispatch, close, owner=cloud) is Some(_),
  )
  assert_true(
    @dock.tab_menu(
      state,
      target,
      dispatch,
      close,
      owner=@interop.Cloud(account="another", session="alpha"),
    )
    is None,
  )
  assert_true(
    @dock.tab_menu(
      state,
      target,
      dispatch,
      close,
      owner=@interop.Cloud(account="account", session="beta"),
    )
    is None,
  )
  assert_true(
    @dock.tab_menu(state, target, dispatch, close, owner=owner("alpha")) is None,
  )
}

///|
test "historical diffs deduplicate exact commits and distinguish revisions" {
  let first : @dock.GitHistoryDiff = {
    commit: "1111111111111111111111111111111111111111",
    parent: Some("0000000000000000000000000000000000000000"),
    path: @pathx.Relative("src/main.mbt"),
    original_path: None,
    status: "modified",
    kind: "file",
  }
  let second = {
    ..first,
    commit: "2222222222222222222222222222222222222222",
    parent: Some("1111111111111111111111111111111111111111"),
  }
  let state = @dock.DockState::empty()
    |> @dock.open_history_diff(first)
    |> @dock.open_history_diff(first)
    |> @dock.open_history_diff(second)
  assert_eq(state.tabs.length(), 2)
  assert_eq(@dock.history_diffs(state), [first, second])
  assert_eq(@dock.active_history_diff(state), Some(second))
  assert_true(@dock.file_paths(state).is_empty())
  assert_true(@dock.active_file(state) is None)
}
