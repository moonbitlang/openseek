///|
/// A visible Files view follows each active document or directory link once.
/// Pending survives lazy directory reads; settled also records missing/failed
/// targets so unrelated updates cannot retry or undo a manual collapse.
enum TreeReveal {
  TreeRevealInactive
  TreeRevealPending(@pathx.Relative)
  TreeRevealSettled(@pathx.Relative)
  TreeRevealDirectoryPending(@pathx.Relative)
  TreeRevealDirectorySettled(@pathx.Relative)
} derive(Eq)

///|
pub extend TreeReveal with Eq::{equal, not_equal}

///|
fn TreeReveal::settle(self : TreeReveal) -> TreeReveal {
  match self {
    TreeRevealPending(path) => TreeRevealSettled(path)
    TreeRevealDirectoryPending(path) => TreeRevealDirectorySettled(path)
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
  if ctx.checkout_ready() &&
    ctx.panel_open &&
    self.explorer_mode is ExplorerFiles &&
    ctx.active_file is None &&
    ctx.active_history_diff is None {
    match self.tree_reveal {
      TreeRevealDirectorySettled(_) => return (self, @cmd.none)
      TreeRevealDirectoryPending(target) => {
        let visible = if target.is_root() {
          self.children.contains(@pathx.Relative::root())
        } else {
          visible_entries(self).any(row => row.0.path == target && row.0.is_dir)
        }
        if visible {
          let focus = if target.is_root() { None } else { Some(target) }
          let settled = TreeRevealDirectorySettled(target)
          return (
            { ..self, tree_focus: focus, tree_reveal: settled, },
            @cmd.batch([
              focus_tree_after_render(focus),
              settled.scroll_after_render(),
            ]),
          )
        }
        // The directory link already expanded and requested its ancestors.
        // Wait for those owner-fenced replies, but never retry a missing row.
        let waiting = !self.children.contains(@pathx.Relative::root()) ||
          self.loading.any(path => {
            path.is_root() || target.0.has_prefix(path.0 + "/")
          })
        return (
          if waiting {
            self
          } else {
            { ..self, tree_reveal: TreeRevealDirectorySettled(target), }
          },
          @cmd.none,
        )
      }
      _ => ()
    }
  }
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
/// Center the row within the tree's nearest scrolling container. The caller
/// controls DOM focus; the browser clamps scrolling near either end of the list.
fn TreeReveal::scroll_after_render(self : TreeReveal) -> @cmd.Cmd {
  let path = match self {
    TreeRevealSettled(path) | TreeRevealDirectorySettled(path) => path
    _ => return @cmd.none
  }
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

///|
test "directory contents failure still reveals its row after the parent loads" {
  let emit = test_emit()
  let ctx = test_ctx()
  let target = @pathx.Relative("src")
  let root = @pathx.Relative::root()
  let state = {
    ..owned_state(),
    tree_reveal: TreeRevealDirectoryPending(target),
    expanded: [target],
    loading: [root, target],
  }
  let (_, failed) = update(
    emit,
    DirFailed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path=target,
      message="Permission denied",
    ),
    state,
    ctx,
  )
  let (_, loaded) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=root, entries=[
      { name: "a", path: Relative("a"), is_dir: true, },
      { name: "src", path: target, is_dir: true, },
    ]),
    failed,
    ctx,
  )
  let (revealed, _) = loaded.sync_tree_reveal(emit, ctx)
  assert_eq(revealed.directory_errors.get(target), Some("Permission denied"))
  assert_eq(revealed.tree_focus, Some(target))
  assert_true(
    revealed.tree_reveal is TreeRevealDirectorySettled(path) && path == target,
  )
  let (_, retrying) = update(emit, DirExpand(target), revealed, ctx)
  assert_eq(retrying.directory_errors.get(target), Some("Permission denied"))
  assert_true(retrying.loading.contains(target))
}

///|
test "parallel directory failures clear independently on successful replies" {
  let emit = test_emit()
  let ctx = test_ctx()
  let root = @pathx.Relative::root()
  let child = @pathx.Relative("src")
  let state = {
    ..owned_state(),
    directory_errors: Map([
      (root, "Root unavailable"),
      (child, "Child unavailable"),
      (@pathx.Relative("src/nested"), "Nested unavailable"),
    ]),
  }
  // A root read may recover through sync or a watcher, without DirExpand.
  let (_, root_loaded) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=root, entries=[
      { name: "src", path: child, is_dir: true, },
    ]),
    state,
    ctx,
  )
  assert_eq(root_loaded.directory_errors.get(root), None)
  assert_eq(root_loaded.directory_errors.get(child), Some("Child unavailable"))
  assert_eq(
    root_loaded.directory_errors.get(@pathx.Relative("src/nested")),
    Some("Nested unavailable"),
  )
  let (_, recovered) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=child, entries=[]),
    root_loaded,
    ctx,
  )
  assert_true(recovered.directory_errors.is_empty())
  // Removing the failed directory removes its entire stale error subtree.
  let (_, removed) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=root, entries=[]),
    state,
    ctx,
  )
  assert_true(removed.directory_errors.is_empty())
  // Parent confirmation invalidates only reads already in flight. Keep those
  // paths loading until their replies arrive, so a retry cannot overlap them.
  let nested = @pathx.Relative("src/nested")
  let (_, removed_in_flight) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=root, entries=[]),
    { ..state, loading: [root, child, nested], },
    ctx,
  )
  let (_, late_failure) = update(
    emit,
    DirFailed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path=nested,
      message="Directory unavailable",
    ),
    removed_in_flight,
    ctx,
  )
  assert_true(late_failure.directory_errors.is_empty())
  assert_true(!late_failure.loading.contains(nested))
  let (_, late_success) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=child, entries=[]),
    late_failure,
    ctx,
  )
  assert_true(!late_success.children.contains(child))
  assert_true(late_success.loading.is_empty())
  assert_true(late_success.removed_directory_reads.is_empty())
  // An old empty listing cannot invalidate a new read: the directory may have
  // been created since it was cached. Preserve permission errors in that case.
  let (_, retrying) = update(emit, DirExpand(child), late_success, ctx)
  let (_, new_failure) = update(
    emit,
    DirFailed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path=child,
      message="Permission denied",
    ),
    retrying,
    ctx,
  )
  assert_eq(new_failure.directory_errors.get(child), Some("Permission denied"))
  // A repeated link while the invalidated read drains queues exactly one new
  // read, including when ancestors are still reloading.
  let (_, queued) = update(emit, DirExpand(child), removed_in_flight, ctx)
  let (_, draining) = update(
    emit,
    DirFailed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path=child,
      message="Old failure",
    ),
    queued,
    ctx,
  )
  assert_true(draining.loading.contains(child))
  assert_true(!draining.removed_directory_reads.contains(child))
  assert_true(draining.directory_errors.is_empty())
  let (_, reread) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=child, entries=[]),
    draining,
    ctx,
  )
  assert_true(reread.children.contains(child))
  assert_true(!reread.loading.contains(child))
  let (_, breadcrumb) = update(
    emit,
    RevealDirectory(child),
    removed_in_flight,
    ctx,
  )
  let (_, breadcrumb_drained) = update(
    emit,
    DirLoaded(owner=ctx.owner, epoch=ctx.request_epoch, path=child, entries=[]),
    breadcrumb,
    ctx,
  )
  assert_true(breadcrumb_drained.loading.contains(child))
  assert_true(!breadcrumb_drained.removed_directory_reads.contains(child))
  assert_true(!breadcrumb_drained.children.contains(child))
  // A failed parent refresh likewise cannot prove a child absent.
  let (_, parent_failed) = update(
    emit,
    DirFailed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path=root,
      message="Root unavailable",
    ),
    { ..removed, loading: [root, child], },
    ctx,
  )
  let (_, child_failed) = update(
    emit,
    DirFailed(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path=child,
      message="Permission denied",
    ),
    parent_failed,
    ctx,
  )
  assert_eq(child_failed.directory_errors.get(child), Some("Permission denied"))
}
