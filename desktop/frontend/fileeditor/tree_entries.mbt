// The file tree's visible hierarchy. Quick Open owns workspace-wide fuzzy
// matching; this package renders only the expanded directory tree.

///|
/// Tree rows currently on screen, in depth-first render order with indentation
/// depth. Only listed, expanded directories contribute descendants.
fn visible_entries(state : State) -> Array[(FileEntry, Int)] {
  let rows : Array[(FileEntry, Int)] = []
  push_tree_entries(state, @pathx.Relative::root(), 0, rows)
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
test "visible tree entries follow expanded directories depth first" {
  let state = {
    ..State::empty(),
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
    expanded: [Relative("src")],
  }
  let rows = visible_entries(state)
  assert_eq(rows.map(pair => pair.0.path.0), ["src", "src/lib.mbt", "main.mbt"])
  assert_eq(rows.map(pair => pair.1), [0, 1, 0])
}
