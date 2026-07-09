// State-transition tests for the filter input's keyboard driving: the
// cursor walking the visible rows, Enter acting on the cursor's row, and
// Escape's clear-then-close ladder. Commands are opaque, so the tests
// assert on the returned state only.

///|
fn nav_state() -> State {
  {
    ..State::empty(),
    open: true,
    session: "desktop-test",
    children: Map::from_array([
      (
        Relative(""),
        [
          { name: "src", path: Relative("src"), is_dir: true },
          { name: "main.mbt", path: Relative("main.mbt"), is_dir: false },
        ],
      ),
      (
        Relative("src"),
        [{ name: "lib.mbt", path: Relative("src/lib.mbt"), is_dir: false }],
      ),
    ]),
  }
}

///|
test "arrow keys walk the visible rows and clamp at the edges" {
  let emit = test_emit()
  let (_, one) = update(emit, TreeKeyMove(delta=1), nav_state(), test_ctx())
  assert_true(one.cursor is Some(Relative("src")))
  let (_, two) = update(emit, TreeKeyMove(delta=1), one, test_ctx())
  assert_true(two.cursor is Some(Relative("main.mbt")))
  // The bottom edge holds.
  let (_, three) = update(emit, TreeKeyMove(delta=1), two, test_ctx())
  assert_true(three.cursor is Some(Relative("main.mbt")))
  // ↑ from nothing enters at the bottom.
  let (_, tail) = update(emit, TreeKeyMove(delta=-1), nav_state(), test_ctx())
  assert_true(tail.cursor is Some(Relative("main.mbt")))
}

///|
test "expanding a directory splices its children into the walk" {
  let emit = test_emit()
  let state = { ..nav_state(), expanded: [Relative("src")] }
  let (_, one) = update(emit, TreeKeyMove(delta=1), state, test_ctx())
  let (_, two) = update(emit, TreeKeyMove(delta=1), one, test_ctx())
  assert_true(two.cursor is Some(Relative("src/lib.mbt")))
}

///|
test "Enter toggles a directory under the cursor and opens a file" {
  let emit = test_emit()
  let (_, on_dir) = update(emit, TreeKeyMove(delta=1), nav_state(), test_ctx())
  let (_, toggled) = update(emit, TreeKeyAccept, on_dir, test_ctx())
  assert_true(toggled.expanded.contains(Relative("src")))
  let (_, on_file) = update(
    emit,
    TreeKeyMove(delta=-1),
    nav_state(),
    test_ctx(),
  )
  let (_, opened) = update(emit, TreeKeyAccept, on_file, test_ctx())
  assert_true(opened.active is Some(Relative("main.mbt")))
  assert_eq(opened.tabs.length(), 1)
}

///|
test "Enter with no cursor opens a non-blank filter's top match" {
  let emit = test_emit()
  let state = { ..nav_state(), filter: "lib" }
  let (_, opened) = update(emit, TreeKeyAccept, state, test_ctx())
  assert_true(opened.active is Some(Relative("src/lib.mbt")))
  // A blank filter with no cursor has nothing to act on.
  let (_, untouched) = update(emit, TreeKeyAccept, nav_state(), test_ctx())
  assert_true(untouched.active is None)
}

///|
test "Escape clears the filter first, then closes the tree" {
  let emit = test_emit()
  let state = {
    ..nav_state(),
    filter: "lib",
    tabs: [loaded_tab("main.mbt", "main.mbt")],
    active: Some(Relative("main.mbt")),
  }
  let (_, cleared) = update(emit, TreeKeyDismiss, state, test_ctx())
  assert_eq(cleared.filter, "")
  assert_true(cleared.tree_open)
  let (_, closed) = update(emit, TreeKeyDismiss, cleared, test_ctx())
  assert_false(closed.tree_open)
  // With no file open the tree is unconditional; Escape leaves it alone.
  let (_, kept) = update(emit, TreeKeyDismiss, nav_state(), test_ctx())
  assert_true(kept.tree_open)
}

///|
test "the fuzzy filter matches the workspace index, best score first" {
  let state = {
    ..nav_state(),
    filter: "lib",
    index: IndexReady(
      // `deep/lib.mbt` is nowhere in `children` — index matches must not
      // depend on which directories happen to be listed. `list_bin.txt`
      // also contains l-i-b as a subsequence but scattered, so the
      // word-boundary hit ranks first.
      files=[Relative("list_bin.txt"), Relative("deep/lib.mbt")],
      truncated=false,
    ),
  }
  let rows = visible_entries(state)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].0.path.0, "deep/lib.mbt")
  assert_eq(rows[0].0.name, "lib.mbt")
  assert_false(rows[0].0.is_dir)
  // A query nothing matches shows nothing.
  assert_eq(visible_entries({ ..state, filter: "zzz" }).length(), 0)
}

///|
test "Enter opens the index's top match even when unlisted" {
  let emit = test_emit()
  let state = {
    ..nav_state(),
    filter: "lib",
    index: IndexReady(files=[Relative("deep/lib.mbt")], truncated=false),
  }
  let (_, opened) = update(emit, TreeKeyAccept, state, test_ctx())
  assert_true(opened.active is Some(Relative("deep/lib.mbt")))
  assert_eq(opened.tabs[0].name, "lib.mbt")
}

///|
test "an index reply lands only for its own conversation" {
  let emit = test_emit()
  let stale = FilesIndexed(
    session="someone-else",
    files=[Relative("a.txt")],
    truncated=false,
  )
  let (_, dropped) = update(emit, stale, nav_state(), test_ctx())
  assert_true(dropped.index is IndexEmpty)
  let fresh = FilesIndexed(
    session="desktop-test",
    files=[Relative("a.txt")],
    truncated=true,
  )
  let (_, landed) = update(emit, fresh, nav_state(), test_ctx())
  assert_true(landed.index is IndexReady(truncated=true, ..))
}

///|
test "a failed fetch retries later, a failed refresh keeps the index" {
  let emit = test_emit()
  let loading = { ..nav_state(), index: IndexLoading }
  let (_, reset) = update(
    emit,
    FileIndexFailed(session="desktop-test"),
    loading,
    test_ctx(),
  )
  assert_true(reset.index is IndexEmpty)
  let ready = {
    ..nav_state(),
    index: IndexReady(files=[Relative("a.txt")], truncated=false),
  }
  let (_, kept) = update(
    emit,
    FileIndexFailed(session="desktop-test"),
    ready,
    test_ctx(),
  )
  assert_true(kept.index is IndexReady(..))
}

///|
test "the first non-blank keystroke requests the index once" {
  let emit = test_emit()
  let (_, typing) = update(
    emit,
    FileFilterChanged("l"),
    nav_state(),
    test_ctx(),
  )
  assert_true(typing.index is IndexLoading)
  // Further keystrokes must not re-request (the state already says loading);
  // clearing the filter leaves the fetch to finish.
  let (_, more) = update(emit, FileFilterChanged("li"), typing, test_ctx())
  assert_true(more.index is IndexLoading)
}

///|
test "changing the filter resets the cursor" {
  let emit = test_emit()
  let (_, moved) = update(emit, TreeKeyMove(delta=1), nav_state(), test_ctx())
  let (_, filtered) = update(emit, FileFilterChanged("lib"), moved, test_ctx())
  assert_true(filtered.cursor is None)
}
