///|
test "Cloud workspace invalidation fences authentication and keeps hidden documents lazy" {
  let ctx = cloud_ctx("account", "session", 4)
  let visible = ctx.resource(Relative("visible.txt")).unwrap()
  let background = ctx.resource(Relative("background.txt")).unwrap()
  let ctx = {
    ..ctx,
    active_file: Some(visible),
    open_files: [visible, background],
  }
  let (base, _) = sync(test_emit(), State::empty(), ctx)
  let base = {
    ..base,
    docs: Map([
      (visible, loaded_doc("visible.txt")),
      (background, loaded_doc("background.txt")),
    ]),
    explorer_mode: ExplorerSearch,
  }
  for
    event in [
      WorkspaceInvalidated(owner=ctx.owner, auth_epoch=3),
      WorkspaceInvalidated(
        owner=@interop.Cloud(account="other", session="session"),
        auth_epoch=4,
      ),
    ] {
    let (_, ignored) = update(test_emit(), event, base, ctx)
    assert_true(ignored == base)
  }
  let event = WorkspaceInvalidated(owner=ctx.owner, auth_epoch=4)
  let (_, invalidated) = update(test_emit(), event, base, ctx)
  assert_eq(invalidated.request_epoch, base.request_epoch + 1)
  assert_true(
    invalidated.docs.get(background)
    is Some({ state: TabLoaded(..), stale: true, .. }),
  )
  assert_true(invalidated.explorer_mode is ExplorerSearch)
  let (_, again) = update(test_emit(), event, invalidated, ctx)
  assert_eq(again.request_epoch, invalidated.request_epoch + 1)
  let (_, hidden) = update(test_emit(), event, base, {
    ..ctx,
    panel_open: false,
  })
  assert_true(hidden.loading.is_empty())
  assert_true(
    hidden.docs.get(visible) is Some({ state: TabLoaded(..), stale: true, .. }),
  )
}
