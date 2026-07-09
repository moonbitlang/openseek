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
