// State-transition tests for the strip machine: opening, activating,
// closing, and how a conversation switch parks and restores a strip. The
// dock is command-free, so every assertion is on the returned state.

///|
fn owner(session : String) -> @interop.ConversationKey {
  { channel: @interop.ChannelId::Local, session }
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
test "TogglePanel flips the panel" {
  let state = @dock.update(@dock.TogglePanel, @dock.State::empty())
  assert_true(state.open)
  let state = @dock.update(@dock.TogglePanel, state)
  assert_true(!state.open)
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
  let scratch = owner("")
  let real = owner("alpha")
  let state = @dock.sync(@dock.State::empty(), scratch)
    |> @dock.open_file(@pathx.Relative("a.mbt"))
  let moved = @dock.sync(state, real)
  assert_true(moved.tabs.is_empty())
  // Returning to the empty session restores nothing.
  let back = @dock.sync(moved, scratch)
  assert_true(back.tabs.is_empty())
  assert_true(back.active is None)
}
