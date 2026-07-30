// Keyboard navigation over the file tree, driven from the filter input
// (ivy-style): one flat list of the rows currently on screen, a path-keyed
// cursor walking it, and the focus/scroll plumbing the interactions need.

///|
/// The id the filter input renders under, for the imperative focus below.
const FilterInputId = "file-filter-input"

///|
/// The most matches the filter shows. The matching itself ranks every
/// indexed file; the cap only bounds the rendered rows — with a query this
/// weak, the tail is noise anyway.
const MaxFilterRows = 200

///|
/// The tree rows currently on screen, in render order, each with its
/// indentation depth — the one list both the view renders and the keyboard
/// cursor walks, so they can never disagree. Filter mode fuzzy-matches the
/// workspace's files (flat rows, depth 0, best score first); tree mode
/// walks expanded directories depth-first.
fn visible_entries(state : State) -> Array[(FileEntry, Int)] {
  let rows : Array[(FileEntry, Int)] = []
  let query = state.filter.trim().to_owned()
  if query.is_empty() {
    push_tree_entries(state, @pathx.Relative::root(), 0, rows)
  } else {
    push_fuzzy_entries(state, query, rows)
  }
  rows
}

///|
fn push_tree_entries(
  state : State,
  dir_path : @pathx.Relative,
  depth : Int,
  into : Array[(FileEntry, Int)],
) -> Unit {
  guard state.children.get(dir_path) is Some(entries) else { return }
  for entry in entries {
    into.push((entry, depth))
    if entry.is_dir && state.expanded.contains(entry.path) {
      push_tree_entries(state, entry.path, depth + 1, into)
    }
  }
}

///|
/// Filter mode: the workspace's files fuzzy-matched against `query`
/// (fzf-style — a subsequence match over the whole relative path, ranked
/// best score first, ties to the shorter then lexicographically-earlier
/// path). Matches against the host-built index; until it arrives, against
/// whatever directories are already listed, so the filter degrades rather
/// than blanks.
fn push_fuzzy_entries(
  state : State,
  raw_query : String,
  into : Array[(FileEntry, Int)],
) -> Unit {
  let query = @fuzzy_match.Query::new(raw_query)
  let candidates = match state.index {
    IndexReady(files~, ..) => files
    IndexEmpty | IndexLoading => {
      let loaded : Array[@pathx.Relative] = []
      push_loaded_files(state, @pathx.Relative::root(), loaded)
      loaded
    }
  }
  // Mirrors the package's own `Query::search` ordering; `score` returns 0
  // for a non-match and smaller-is-better otherwise.
  let scored : Array[(Int, Int, @pathx.Relative)] = []
  for path in candidates {
    let score = query.score(item=path.0)
    if score != 0 {
      scored.push((score, path.0.length(), path))
    }
  }
  scored.sort_by((a, b) => {
    if a.0 != b.0 {
      a.0.compare(b.0)
    } else if a.1 != b.1 {
      a.1.compare(b.1)
    } else {
      a.2.0.lexical_compare(b.2.0)
    }
  })
  for pair in scored {
    if into.length() >= MaxFilterRows {
      break
    }
    let path = pair.2
    into.push(({ name: basename(path), path, is_dir: false }, 0))
  }
}

///|
/// The already-listed files, depth-first — the fuzzy filter's stand-in
/// candidates while the workspace index is still on its way.
fn push_loaded_files(
  state : State,
  dir_path : @pathx.Relative,
  into : Array[@pathx.Relative],
) -> Unit {
  guard state.children.get(dir_path) is Some(entries) else { return }
  for entry in entries {
    if entry.is_dir {
      push_loaded_files(state, entry.path, into)
    } else {
      into.push(entry.path)
    }
  }
}

///|
/// Where `state.cursor` sits in `entries`, if its row is still visible.
fn cursor_index(state : State, entries : Array[(FileEntry, Int)]) -> Int? {
  guard state.cursor is Some(cursor) else { return None }
  entries.search_by(pair => pair.0.path == cursor)
}

///|
/// Put the keyboard focus in the filter input once it is in the DOM — the
/// tree just opened, so typing should filter immediately.
fn focus_filter_after_render() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      if @dom.document().get_element_by_id(FilterInputId).to_option()
        is Some(input) {
        let _ : @js.Value = @js.Value::cast_from(input).apply_with_string(
          "focus",
          ([] : Array[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Scroll the cursor's row into view after the render that moved it, only
/// when it actually left the tree's viewport — an in-view cursor must not
/// yank the scroll position around.
fn scroll_cursor_after_render(path : @pathx.Relative) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _scheduler => {
      guard @dom.document()
        .query_selector("[data-path=\"" + path.0 + "\"]")
        .to_option()
        is Some(row) &&
        @dom.document().query_selector(".file-tree").to_option() is Some(box) else {
        return
      }
      let row_rect = row.get_bounding_client_rect()
      let box_rect = box.get_bounding_client_rect()
      if row_rect.get_top() < box_rect.get_top() ||
        row_rect.get_bottom() > box_rect.get_bottom() {
        row.scroll_into_view()
      }
    },
    kind=@cmd.after_render,
  )
}

// State-transition tests for the filter input's keyboard driving: the
// cursor walking the visible rows, Enter acting on the cursor's row, and
// Escape's clear-then-close ladder. Commands are opaque, so the tests
// assert on the returned state only.

///|
fn nav_state() -> State {
  {
    ..State::empty(),
    open: true,
    owner: Some(test_ctx().owner),
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
    owner={
      channel: @interop.ChannelId::Remote("other"),
      session: "desktop-test",
    },
    files=[Relative("a.txt")],
    truncated=false,
  )
  let (_, dropped) = update(emit, stale, nav_state(), test_ctx())
  assert_true(dropped.index is IndexEmpty)
  let fresh = FilesIndexed(
    owner=test_ctx().owner,
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
    FileIndexFailed(owner=test_ctx().owner),
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
    FileIndexFailed(owner=test_ctx().owner),
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
