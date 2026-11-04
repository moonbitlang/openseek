///|
/// Public contract only: `sync` arms the workspace watcher from a dock that
/// holds native previews and opens no text document. The polling fallback this
/// scenario also covers (`State::polled_files`, `Ctx::observed_files`) is
/// package-private, so that half of the coverage is a whitebox test in
/// `fileeditor_wbtest.mbt`.
test "PDF-only dock retains the watcher without opening text documents" {
  let root = @resource.of_path(@interop.ChannelId::Local, "/work").unwrap()
  let preview = @resource.of_path(
    @interop.ChannelId::Local,
    "/work/_build/report.pdf",
  ).unwrap()
  let ctx : @fileeditor.Ctx = {
    locale: English,
    cloud_files: None,
    feedback_enabled: true,
    owner: @interop.Host({
      channel: @interop.ChannelId::Local,
      session: "preview-test",
    }),
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
  let outside = @resource.of_path(
    @interop.ChannelId::Local,
    "/outside/report.pdf",
  ).unwrap()
  let (closed, _) = @fileeditor.sync(emit, state, {
    ..ctx,
    preview_files: [outside],
  })
  assert_true(closed.watching is None)
}
