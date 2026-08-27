// State-transition tests for the strip machine: opening, activating,
// closing, and how a conversation switch parks and restores a strip. The
// dock is command-free, so every assertion is on the returned state.

///|
fn owner(session : String) -> @interop.ConversationKey {
  { channel: @interop.ChannelId::Local, session, }
}

///|
fn file_tab(path : String) -> @dock.DockTab {
  @dock.DockTab::File(path=@pathx.Relative(path))
}

///|
test "open_file appends in order and activates" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
  assert_true(
    @dock.file_paths(state) ==
    [@pathx.Relative("a.mbt"), @pathx.Relative("b.mbt")],
  )
  assert_true(@dock.active_file(state) == Some(@pathx.Relative("b.mbt")))
}

///|
test "open_file re-activates an existing tab without duplicating it" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
    |> @dock.open_file(@pathx.Relative("a.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
}

///|
test "TabActivated switches to a present tab and ignores an absent one" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
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
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
    |> @dock.open_file(@pathx.Relative("c.mbt"))
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
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
  let state = @dock.update(@dock.TabClosed(file_tab("a.mbt")), state)
  assert_true(state.tabs == [file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
  // Idempotent: closing an already-closed tab changes nothing.
  let again = @dock.update(@dock.TabClosed(file_tab("a.mbt")), state)
  assert_true(again == state)
}

///|
test "sync parks the strip and restores it when the conversation returns" {
  let first = owner("alpha")
  let second = owner("beta")
  let state = @dock.sync(@dock.State::empty(), first)
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
  let state = @dock.update(@dock.TabActivated(file_tab("a.mbt")), state)
  // Switch away: the strip parks and the panel starts empty.
  let away = @dock.sync(state, second)
  assert_true(away.owner == Some(second))
  assert_true(away.tabs.is_empty())
  assert_true(away.active is None)
  // A same-owner sync is a no-op.
  assert_true(@dock.sync(away, second) == away)
  // Switch back: identities and the active tab return.
  let back = @dock.sync(away, first)
  assert_true(back.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(back.active == Some(file_tab("a.mbt")))
}

///|
test "sync does not park a strip owned by an empty session" {
  let nameless = owner("")
  let real = owner("alpha")
  let state = @dock.sync(@dock.State::empty(), nameless)
    |> @dock.open_file(@pathx.Relative("a.mbt"))
  let moved = @dock.sync(state, real)
  assert_true(moved.tabs.is_empty())
  // Returning to the empty session restores nothing.
  let back = @dock.sync(moved, nameless)
  assert_true(back.tabs.is_empty())
  assert_true(back.active is None)
}

///|
test "open_browser appends and re-activates without duplicating" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_browser("browser-7")
  assert_true(
    state.tabs == [file_tab("a.mbt"), @dock.DockTab::Browser(id="browser-7")],
  )
  assert_true(state.active == Some(@dock.DockTab::Browser(id="browser-7")))
  assert_true(@dock.active_browser(state) == Some("browser-7"))
  assert_true(@dock.active_file(state) is None)
  // Files projection skips non-file tabs.
  assert_true(@dock.file_paths(state) == [@pathx.Relative("a.mbt")])
  let again = @dock.open_browser(state, "browser-7")
  assert_true(again.tabs == state.tabs)
}

///|
test "open_picker keeps at most one picker tab" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_picker
    |> @dock.open_file(@pathx.Relative("b.mbt"))
    |> @dock.open_picker
  assert_true(
    state.tabs ==
    [file_tab("a.mbt"), @dock.DockTab::FilePicker, file_tab("b.mbt")],
  )
  assert_true(state.active == Some(@dock.DockTab::FilePicker))
}

///|
test "resolve_pick replaces the picker in place with a fresh file" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_picker
  let state = @dock.resolve_pick(state, @pathx.Relative("b.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
}

///|
test "resolve_pick activates an already-open file and closes the picker" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_file(@pathx.Relative("b.mbt"))
    |> @dock.open_picker
  let state = @dock.resolve_pick(state, @pathx.Relative("a.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
}

///|
test "resolve_pick without a picker is a plain open" {
  let state = @dock.State::empty() |> @dock.open_file(@pathx.Relative("a.mbt"))
  let state = @dock.resolve_pick(state, @pathx.Relative("b.mbt"))
  assert_true(state.tabs == [file_tab("a.mbt"), file_tab("b.mbt")])
  assert_true(state.active == Some(file_tab("b.mbt")))
}

///|
test "closing the picker activates a neighbor like any tab" {
  let state = @dock.State::empty()
    |> @dock.open_file(@pathx.Relative("a.mbt"))
    |> @dock.open_picker
  let state = @dock.update(TabClosed(@dock.DockTab::FilePicker), state)
  assert_true(state.tabs == [file_tab("a.mbt")])
  assert_true(state.active == Some(file_tab("a.mbt")))
}

///|
test "park and restore keeps browser and picker tabs" {
  let state = @dock.sync(@dock.State::empty(), owner("s1"))
    |> @dock.open_browser("browser-3")
    |> @dock.open_picker
  let state = @dock.sync(state, owner("s2"))
  assert_true(state.tabs.is_empty())
  let state = @dock.sync(state, owner("s1"))
  assert_true(
    state.tabs ==
    [@dock.DockTab::Browser(id="browser-3"), @dock.DockTab::FilePicker],
  )
  assert_true(state.active == Some(@dock.DockTab::FilePicker))
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
  let state = @dock.State::empty()
    |> @dock.open_history_diff(first)
    |> @dock.open_history_diff(first)
    |> @dock.open_history_diff(second)
  assert_eq(state.tabs.length(), 2)
  assert_eq(@dock.history_diffs(state), [first, second])
  assert_eq(@dock.active_history_diff(state), Some(second))
  assert_true(@dock.file_paths(state).is_empty())
  assert_true(@dock.active_file(state) is None)
}
