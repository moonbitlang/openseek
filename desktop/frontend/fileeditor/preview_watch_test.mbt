///|
test "PDF-only dock retains the watcher without opening text documents" {
  let root = @resource.of_path(@interop.ChannelId::Local, "/work").unwrap()
  let preview = @resource.of_path(
    @interop.ChannelId::Local,
    "/work/_build/report.pdf",
  ).unwrap()
  let ctx : @fileeditor.Ctx = {
    owner: { channel: @interop.ChannelId::Local, session: "preview-test", },
    request_epoch: 0,
    watch_namespace: "preview-test",
    model: "deepseek-v4-flash",
    thinking: None,
    placement: Some(@interop.WorkspaceRoot(root~)),
    dark_mode: false,
    tree_layout: BottomPanel,
    narrow: false,
    panel_open: false,
    open_files: [],
    preview_files: [preview],
    preview_rechecks: [],
    active_file: None,
    open_history_diffs: [],
    active_history_diff: None,
    github: @github.State::empty(),
  }
  let emit = @cmd.Emit(_ => @cmd.none)
  let (state, _) = @fileeditor.sync(emit, @fileeditor.State::empty(), ctx)
  guard state.watching is Some(watching) else {
    fail("PDF tab must retain the workspace watcher")
  }
  assert_true(watching.files.contains(@pathx.Relative("_build/report.pdf")))
  assert_true(state.docs.is_empty())
  assert_true(state.polled_files(ctx).is_empty())
  assert_true(
    state.polled_files({ ..ctx, preview_rechecks: [preview], }) == [preview],
  )
  assert_true(ctx.observed_files() == [preview])
  let duplicate = {
    ..ctx,
    open_files: [preview],
    preview_files: [preview, preview],
  }
  assert_true(duplicate.observed_files() == [preview])
  let failed = { ..state, watch_error: Some("watch stopped"), }
  assert_true(failed.polled_files(duplicate) == [preview])
  let outside = @resource.of_path(
    @interop.ChannelId::Local,
    "/outside/report.pdf",
  ).unwrap()
  let (closed, _) = @fileeditor.sync(emit, state, {
    ..ctx,
    preview_files: [outside],
  })
  assert_true(closed.watching is None)
  assert_true(
    closed.polled_files({ ..ctx, preview_files: [outside], }) == [outside],
  )
  assert_true(
    state.polled_files({ ..ctx, placement: None, preview_files: [outside], }) ==
    [outside],
  )
  let remote_root = @resource.of_path(
    @interop.ChannelId::Remote("device"),
    "/work",
  ).unwrap()
  let remote = {
    ..ctx,
    owner: { channel: @interop.ChannelId::Remote("device"), session: "remote", },
    placement: Some(@interop.WorkspaceRoot(root=remote_root)),
  }
  assert_true(state.polled_files(remote) == [preview])
}
