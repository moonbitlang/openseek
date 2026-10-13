// The file tree's visible hierarchy. Quick Open owns workspace-wide fuzzy
// matching; this package renders only the expanded directory tree.

///|
/// Tree rows currently on screen, in depth-first render order with indentation
/// depth. Only listed, expanded directories contribute descendants.
fn visible_entries(state : State) -> Array[(FileEntry, Int32)] {
  let rows : Array[(FileEntry, Int32)] = []
  push_tree_entries(state, @pathx.Relative::root(), 0, rows)
  rows
}

///|
fn push_tree_entries(
  state : State,
  dir_path : @pathx.Relative,
  depth : Int32,
  into : Array[(FileEntry, Int32)],
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
test "visible tree entries follow expanded directories depth first" {
  let state = {
    ..State::empty(),
    children: Map::from_array([
      (
        Relative(""),
        [
          { name: "src", path: Relative("src"), is_dir: true, },
          { name: "main.mbt", path: Relative("main.mbt"), is_dir: false, },
        ],
      ),
      (
        Relative("src"),
        [{ name: "lib.mbt", path: Relative("src/lib.mbt"), is_dir: false, }],
      ),
    ]),
    expanded: [Relative("src")],
  }
  let rows = visible_entries(state)
  assert_eq(rows.map(pair => pair.0.path.0), ["src", "src/lib.mbt", "main.mbt"])
  assert_eq(rows.map(pair => pair.1), [0, 1, 0])
}

///|
fn tree_focus_target(state : State) -> @pathx.Relative? {
  let rows = visible_entries(state)
  let mut candidate = state.tree_focus
  while candidate is Some(path) {
    if rows.any(row => row.0.path == path) {
      return Some(path)
    }
    candidate = if path.is_root() {
      None
    } else {
      Some(FileChange::parent(path))
    }
  }
  rows.get(0).map(row => row.0.path)
}

///|
priv enum TreeKeyAction {
  TreeMove(@pathx.Relative)
  TreeToggle
  TreeOpen
  TreeStay
}

///|
fn tree_key_action(
  state : State,
  entry : FileEntry,
  key : String,
) -> TreeKeyAction? {
  let rows = visible_entries(state)
  guard rows.search_by(row => row.0.path == entry.path) is Some(index) else {
    return None
  }
  let expanded = state.expanded.contains(entry.path)
  match key {
    "ArrowUp" =>
      Some(if index > 0 { TreeMove(rows[index - 1].0.path) } else { TreeStay })
    "ArrowDown" =>
      Some(
        if index + 1 < rows.length() {
          TreeMove(rows[index + 1].0.path)
        } else {
          TreeStay
        },
      )
    "Home" => Some(TreeMove(rows[0].0.path))
    "End" => Some(TreeMove(rows[rows.length() - 1].0.path))
    "ArrowRight" =>
      Some(
        if entry.is_dir && !expanded {
          TreeToggle
        } else if entry.is_dir &&
          index + 1 < rows.length() &&
          rows[index + 1].1 > rows[index].1 {
          TreeMove(rows[index + 1].0.path)
        } else {
          TreeStay
        },
      )
    "ArrowLeft" =>
      Some(
        if entry.is_dir && expanded {
          TreeToggle
        } else if rows[index].1 > 0 {
          TreeMove(FileChange::parent(entry.path))
        } else {
          TreeStay
        },
      )
    "Enter" | " " => Some(if entry.is_dir { TreeToggle } else { TreeOpen })
    _ => None
  }
}

///|
extern "js" fn tree_has_dom_focus() -> Bool =
  #| () => typeof document !== "undefined" && !!document.activeElement?.matches('.workspace-file-list [role="treeitem"], #workspace-file-tree')

///|
fn focus_tree_after_render(path : @pathx.Relative?) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      let id = match path {
        Some(path) => "workspace-tree-" + path.0
        None => "workspace-file-tree"
      }
      if @dom.document().get_element_by_id(id).to_option() is Some(row) {
        let _ : @js.Value = @js.Value::cast_from(row).apply_with_string(
          "focus",
          ([] : FixedArray[@js.Value]),
        )
      }
    },
    kind=@cmd.after_render,
  )
}

///|
test "tree focus recovers from a removed node through visible ancestors" {
  let src : FileEntry = { name: "src", path: Relative("src"), is_dir: true, }
  let main : FileEntry = {
    name: "main.mbt",
    path: Relative("src/main.mbt"),
    is_dir: false,
  }
  let state = {
    ..State::empty(),
    children: Map::from_array([(Relative(""), [src]), (Relative("src"), [main])]),
    expanded: [Relative("src")],
    tree_focus: Some(main.path),
  }
  assert_eq(tree_focus_target(state), Some(main.path))
  assert_eq(tree_focus_target({ ..state, expanded: [], }), Some(src.path))
  let children = state.children.copy()
  children[Relative("src")] = []
  assert_eq(tree_focus_target({ ..state, children, }), Some(src.path))
  children[Relative("")] = []
  assert_eq(tree_focus_target({ ..state, children, }), None)
}
