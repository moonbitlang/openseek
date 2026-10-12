///|
fn context(session : String) -> @fileeditor.Ctx {
  let root = @resource.of_path(@interop.ChannelId::Local, "/work").unwrap()
  {
    owner: { channel: @interop.ChannelId::Local, session, },
    request_epoch: 0,
    watch_namespace: "conversation-ui-test",
    model: "deepseek-v4-flash",
    thinking: None,
    placement: Some(@interop.WorkspaceRoot(root~)),
    dark_mode: false,
    tree_layout: RightSidebar,
    narrow: false,
    panel_open: false,
    open_files: [],
    preview_files: [],
    preview_rechecks: [],
    active_file: None,
    open_history_diffs: [],
    active_history_diff: None,
    github: @github.State::empty(),
  }
}

///|
test "conversation explorer choices restore through sync and early opens" {
  let emit = @cmd.Emit(_ => @cmd.none)
  let a = context("a")
  let b = context("b")
  let (initial, _) = @fileeditor.sync(emit, @fileeditor.State::empty(), a)
  let first = {
    ..initial,
    tree_open: false,
    explorer_mode: ExplorerSearch,
    expanded: [@pathx.Relative("src")],
    tree_focus: Some(@pathx.Relative("src/main.mbt")),
    change_extensions: Some([Some("mbt")]),
    change_path_filter: "src/",
    change_tree_collapsed: [@pathx.Relative("src")],
    changes_collapsed: true,
    git_graph_collapsed: true,
  }
  let (second, _) = @fileeditor.sync(emit, first, b)
  assert_true(second.tree_open)
  assert_true(second.explorer_mode is ExplorerFiles)
  assert_true(second.expanded.is_empty())
  assert_true(second.tree_focus is None)
  assert_eq(second.change_path_filter, "")
  assert_false(second.changes_collapsed)
  let restored = second.prepare_owner(a.owner, [])
  assert_false(restored.tree_open)
  assert_true(restored.explorer_mode is ExplorerSearch)
  assert_true(restored.expanded == first.expanded)
  assert_true(restored.tree_focus == first.tree_focus)
  assert_true(restored.change_extensions == first.change_extensions)
  assert_eq(restored.change_path_filter, "src/")
  assert_true(restored.change_tree_collapsed == first.change_tree_collapsed)
  assert_true(restored.changes_collapsed)
  assert_true(restored.git_graph_collapsed)
  // Repeating reconciliation on the same input neither mutates the outgoing
  // conversation nor consumes another snapshot.
  let (again, _) = @fileeditor.sync(emit, first, b)
  assert_true(again == second)
  assert_true(second.prepare_owner(a.owner, []) == restored)
  assert_false(first.tree_open)
  assert_true(initial.remembered_ui.is_empty())
  let (back, _) = @fileeditor.sync(emit, restored, a)
  assert_true(back.expanded == first.expanded)
  assert_false(back.tree_open)
  assert_true(back.git_graph_collapsed)
}

///|
test "a failed restored directory is not automatically retried" {
  let emit = @cmd.Emit(_ => @cmd.none)
  let a = context("a")
  let (first, _) = @fileeditor.sync(emit, @fileeditor.State::empty(), a)
  let first = { ..first, expanded: [@pathx.Relative("gone")], }
  let (away, _) = @fileeditor.sync(emit, first, context("b"))
  let (restored, _) = @fileeditor.sync(emit, away, { ..a, panel_open: true, })
  assert_true(restored.loading.contains(@pathx.Relative("gone")))
  assert_true(restored.pending_directory_restores.is_empty())
  let ctx = { ..a, request_epoch: restored.request_epoch, panel_open: true, }
  let (_, loaded) = @fileeditor.update(
    emit,
    DirLoaded(
      owner=a.owner,
      epoch=restored.request_epoch,
      path=@pathx.Relative::root(),
      entries=[],
    ),
    restored,
    ctx,
  )
  let (_, failed) = @fileeditor.update(
    emit,
    DirFailed(
      owner=a.owner,
      epoch=restored.request_epoch,
      path=@pathx.Relative("gone"),
      message="cannot read directory",
    ),
    loaded,
    ctx,
  )
  let (settled, _) = @fileeditor.sync(emit, failed, ctx)
  assert_false(settled.loading.contains(@pathx.Relative("gone")))
  assert_eq(settled.error, Some("cannot read directory"))
  assert_true(settled.expanded.contains(@pathx.Relative("gone")))
  let (again, _) = @fileeditor.sync(emit, failed, ctx)
  assert_true(again == settled)
}

///|
test "checkout repair restores expanded directories once" {
  let emit = @cmd.Emit(_ => @cmd.none)
  let ctx = { ..context("a"), panel_open: true, }
  let (initial, _) = @fileeditor.sync(emit, @fileeditor.State::empty(), ctx)
  let state = { ..initial, expanded: [@pathx.Relative("src")], }
  let (parked, _) = @fileeditor.sync(emit, state, { ..ctx, placement: None, })
  assert_true(parked.pending_directory_restores == state.expanded)
  let (restored, _) = @fileeditor.sync(emit, parked, ctx)
  assert_true(restored.loading.contains(@pathx.Relative("src")))
  assert_true(restored.pending_directory_restores.is_empty())
  let (again, _) = @fileeditor.sync(emit, parked, ctx)
  assert_true(again == restored)
}
