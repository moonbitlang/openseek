///|
/// A visible Files view follows each active document once. Pending survives
/// lazy directory reads; settled also records missing/failed targets so an
/// unrelated update cannot start an unbounded retry or undo a manual collapse.
enum TreeReveal {
  TreeRevealInactive
  TreeRevealPending(@pathx.Relative)
  TreeRevealSettled(@pathx.Relative)
} derive(Eq)

///|
pub extend TreeReveal with Eq::{equal, not_equal}

///|
fn TreeReveal::settle(self : TreeReveal) -> TreeReveal {
  match self {
    TreeRevealPending(path) => TreeRevealSettled(path)
    _ => self
  }
}

///|
/// Reconcile after the dock has selected its new editor, including opens from
/// Quick Open, search, links, and restored tabs. Walk only the target's ancestor
/// chain, sharing the normal directory cache and owner/epoch-fenced replies.
fn State::sync_tree_reveal(
  self : State,
  dispatch : @cmd.Emit[Msg],
  ctx : Ctx,
) -> (State, @cmd.Cmd) {
  guard ctx.checkout_ready() &&
    ctx.panel_open &&
    self.tree_open &&
    self.explorer_mode is ExplorerFiles &&
    ctx.active_file.bind(file => ctx.relative(file)) is Some(target) &&
    !target.is_root() else {
    return ({ ..self, tree_reveal: TreeRevealInactive, }, @cmd.none)
  }
  if self.tree_reveal is TreeRevealSettled(previous) && previous == target {
    return (self, @cmd.none)
  }
  let state = { ..self, tree_reveal: TreeRevealPending(target), }
  let ancestors = []
  let mut parent = FileChange::parent(target)
  while !parent.is_root() {
    ancestors.push(parent)
    parent = FileChange::parent(parent)
  }
  let expanded = state.expanded.copy()
  let mut directory = @pathx.Relative::root()
  // Verify each child against its parent listing before expanding it. Missing
  // files (including deleted review files) must not reveal a different row.
  for index = ancestors.length(); index >= 0; index = index - 1 {
    guard state.children.get(directory) is Some(entries) else {
      if state.loading.contains(directory) {
        return ({ ..state, expanded, }, @cmd.none)
      }
      let loading = state.loading.copy()
      loading.push(directory)
      return (
        { ..state, expanded, loading, },
        read_directory(
          dispatch,
          ctx.owner,
          ctx.request_epoch,
          directory,
          root=ctx.root(),
        ),
      )
    }
    let child = if index == 0 { target } else { ancestors[index - 1] }
    guard entries.any(entry => {
      entry.path == child && entry.is_dir == (index > 0)
    }) else {
      return (
        { ..state, expanded, tree_reveal: TreeRevealSettled(target), },
        @cmd.none,
      )
    }
    if index > 0 {
      if !expanded.contains(child) {
        expanded.push(child)
      }
      directory = child
    }
  }
  let settled = TreeRevealSettled(target)
  (
    { ..state, expanded, tree_focus: Some(target), tree_reveal: settled, },
    settled.scroll_after_render(),
  )
}

///|
/// Selection and the keyboard entry follow the editor, but DOM focus stays in
/// the editor. Center the row within the tree's nearest scrolling container;
/// the browser clamps the position near the beginning or end of the list.
fn TreeReveal::scroll_after_render(self : TreeReveal) -> @cmd.Cmd {
  guard self is TreeRevealSettled(path) else { return @cmd.none }
  @cmd.custom_cmd(
    _ => {
      if @dom.document()
        .get_element_by_id("workspace-tree-" + path.0)
        .to_option()
        is Some(row) {
        row.scroll_into_view_with_options(
          block="center",
          inline="nearest",
          container="nearest",
        )
      }
    },
    kind=@cmd.after_render,
  )
}
