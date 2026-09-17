///|
/// Keep exact Git rows as identities: a deletion and a recreated untracked
/// file may share a path without sharing review progress or selection.
pub(all) enum ChangeTreeItem {
  ChangeDirectory(@pathx.Relative)
  ChangeFile(ChangedFile)
} derive(Eq)

///|
pub extend ChangeTreeItem with Eq::{equal, not_equal}

///|
priv struct ChangeTreeNode {
  item : ChangeTreeItem
  label : String
  changes : Array[ChangedFile]
  children : Array[ChangeTreeNode]
}

///|
priv struct ChangeTreeRow {
  node : ChangeTreeNode
  depth : Int
  parent : ChangeTreeItem?
  expanded : Bool
  position : Int
  siblings : Int
}

///|
fn ChangeTreeItem::path(self : ChangeTreeItem) -> @pathx.Relative {
  match self {
    ChangeDirectory(path) => path
    ChangeFile(change) => change.path
  }
}

///|
/// Only changed paths contribute directories. Single-child directory chains
/// are compacted without flattening a branching directory or swallowing files.
fn change_tree_nodes(
  files : Array[ChangedFile],
  parent : @pathx.Relative,
) -> Array[ChangeTreeNode] {
  let directories : Map[String, Array[ChangedFile]] = Map([])
  let names : Array[String] = []
  let leaves : Array[ChangeTreeNode] = []
  let depth = path_segments(parent).length()
  for change in files {
    let parts = path_segments(change.path)
    if depth + 1 < parts.length() {
      let name = parts[depth]
      match directories.get(name) {
        Some(members) => members.push(change)
        None => {
          names.push(name)
          directories[name] = [change]
        }
      }
    } else {
      leaves.push({
        item: ChangeFile(change),
        label: basename(change.path),
        changes: [change],
        children: [],
      })
    }
  }
  let nodes : Array[ChangeTreeNode] = []
  for name in names {
    guard directories.get(name) is Some(changes) else { continue }
    let path = child_path(parent, name)
    let children = change_tree_nodes(changes, path)
    if children is [child] && child.item is ChangeDirectory(_) {
      nodes.push({ ..child, label: name + "/" + child.label, })
    } else {
      nodes.push({
        item: ChangeDirectory(path),
        label: name,
        changes,
        children,
      })
    }
  }
  nodes.append(leaves)
  nodes
}

///|
fn change_tree_rows(state : State) -> Array[ChangeTreeRow] {
  let rows : Array[ChangeTreeRow] = []
  fn visit(
    nodes : Array[ChangeTreeNode],
    depth : Int,
    parent : ChangeTreeItem?,
  ) {
    for position, node in nodes {
      let expanded = node.item is ChangeDirectory(path) &&
        !state.change_tree_collapsed.contains(path)
      rows.push({
        node,
        depth,
        parent,
        expanded,
        position,
        siblings: nodes.length(),
      })
      if expanded {
        visit(node.children, depth + 1, Some(node.item))
      }
    }
  }
  visit(
    change_tree_nodes(filtered_changes(state), @pathx.Relative::root()),
    0,
    None,
  )
  rows
}

///|
fn change_tree_focus_target(
  state : State,
  rows : Array[ChangeTreeRow],
) -> ChangeTreeItem? {
  if state.change_tree_focus is Some(item) {
    if rows.any(row => row.node.item == item) {
      return Some(item)
    }
    // Folding an ancestor or removing a file returns focus to its nearest
    // visible directory, including compact directory chains.
    for index = rows.length() - 1; index >= 0; index = index - 1 {
      let candidate = rows[index].node.item
      if candidate is ChangeDirectory(path) &&
        item.path().0.has_prefix(path.0 + "/") {
        return Some(candidate)
      }
    }
  }
  rows.get(0).map(row => row.node.item)
}

///|
fn change_tree_row_id(state : State, item : ChangeTreeItem) -> String? {
  match item {
    ChangeDirectory(path) => Some("changed-directory-" + path.0)
    ChangeFile(change) =>
      change_row_index(state, change).map(changed_file_row_id)
  }
}

///|
fn focus_change_tree_after_render(
  state : State,
  item : ChangeTreeItem?,
) -> @cmd.Cmd {
  let id = match item {
    Some(item) => change_tree_row_id(state, item)
    None => Some("review-file-tree")
  }
  @cmd.custom_cmd(
    _ => {
      if id is Some(id) &&
        @dom.document().get_element_by_id(id).to_option() is Some(row) {
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
extern "js" fn change_tree_has_dom_focus() -> Bool =
  #| () => typeof document !== "undefined" && !!document.activeElement?.matches('#review-file-tree, #review-file-tree [role="treeitem"]')

///|
fn change_tree_key(
  dispatch : @cmd.Emit[Msg],
  state : State,
  rows : Array[ChangeTreeRow],
  index : Int,
  key : String,
) -> @cmd.Cmd {
  let row = rows[index]
  let move_to = fn(item) {
    if item is Some(_) {
      focus_change_tree_after_render(state, item)
    } else {
      @cmd.none
    }
  }
  match key {
    "ArrowUp" => move_to(rows.get(index - 1).map(row => row.node.item))
    "ArrowDown" => move_to(rows.get(index + 1).map(row => row.node.item))
    "Home" => move_to(rows.get(0).map(row => row.node.item))
    "End" => move_to(rows.get(rows.length() - 1).map(row => row.node.item))
    "ArrowLeft" =>
      match row.node.item {
        ChangeDirectory(path) if row.expanded =>
          dispatch(ChangeDirectoryExpanded(path, false))
        _ => if row.parent is Some(_) { move_to(row.parent) } else { @cmd.none }
      }
    "ArrowRight" =>
      match row.node.item {
        ChangeDirectory(path) if !row.expanded =>
          dispatch(ChangeDirectoryExpanded(path, true))
        ChangeDirectory(_) =>
          move_to(rows.get(index + 1).map(row => row.node.item))
        _ => @cmd.none
      }
    "Enter" =>
      match row.node.item {
        ChangeDirectory(path) =>
          dispatch(ChangeDirectoryExpanded(path, !row.expanded))
        ChangeFile(change) if change.selectable() =>
          dispatch(ChangedFileSelected(change))
        _ => @cmd.none
      }
    " " => dispatch(ChangeTreeReviewToggled(row.node.item))
    _ => @cmd.none
  }
}

///|
fn change_tree_members(
  state : State,
  item : ChangeTreeItem,
) -> Array[ChangedFile] {
  filtered_changes(state).filter(change => {
    change.selectable() &&
    (match item {
      ChangeFile(selected) => change == selected
      ChangeDirectory(path) => change.path.0.has_prefix(path.0 + "/")
    })
  })
}

///|
fn change_tree_review_state(
  state : State,
  changes : Array[ChangedFile],
) -> ReviewCompletionState {
  let reviewable = changes.filter(change => change.selectable())
  if !reviewable.is_empty() &&
    reviewable.all(change => state.is_change_reviewed(change)) {
    ReviewComplete
  } else if reviewable.any(change => {
      !(state.changed_file_review_state(change) is ReviewUnviewed)
    }) {
    ReviewInProgress
  } else {
    ReviewUnviewed
  }
}

///|
fn State::toggle_change_tree_review(
  self : State,
  item : ChangeTreeItem,
) -> State {
  let changes = change_tree_members(self, item)
  let complete = change_tree_review_state(self, changes) is ReviewComplete
  let progress = self.review_progress.filter(entry => {
    !changes.contains(entry.change)
  })
  if !complete {
    for change in changes {
      progress.push({ change, progress: ReviewFileComplete, })
    }
  }
  { ..self, review_progress: progress, }
}
