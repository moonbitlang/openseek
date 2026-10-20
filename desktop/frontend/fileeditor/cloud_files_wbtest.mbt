///|
fn cloud_ctx(account : String, session : String, epoch : Int32) -> Ctx {
  {
    ..test_ctx(),
    owner: @interop.Cloud(account~, session~),
    placement: None,
    cloud_files: Some({ epoch, token: "fixture-token", }),
  }
}

///|
test "Cloud file indexes reject retired owners and restart after refresh epochs" {
  let ctx = cloud_ctx("account", "session", 1)
  let emit = test_emit()
  let (state, _) = sync(emit, State::empty(), ctx)
  let (_, loading) = update(emit, EnsureFileIndex, state, ctx)
  assert_true(loading.index is IndexLoading(..))
  let reply = FilesIndexed(
    owner=ctx.owner,
    epoch=loading.request_epoch,
    files=[Relative("index.html")],
    truncated=false,
  )
  let (_, refreshed) = update(emit, RunSettled(owner=ctx.owner), loading, ctx)
  let (_, ignored) = update(emit, reply, refreshed, ctx)
  assert_true(ignored.index is IndexLoading(..))
  let (_, ready) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=refreshed.request_epoch,
      files=[Relative("new.html")],
      truncated=false,
    ),
    refreshed,
    ctx,
  )
  assert_true(
    ready.index
    is IndexReady(files=[Relative("new.html")], refreshing=false, ..),
  )
  let (_, refreshing) = update(emit, RunSettled(owner=ctx.owner), ready, ctx)
  let (_, restarted) = update(
    emit,
    RunSettled(owner=ctx.owner),
    refreshing,
    ctx,
  )
  let (_, settled) = update(
    emit,
    FilesIndexed(
      owner=ctx.owner,
      epoch=restarted.request_epoch,
      files=[Relative("latest.html")],
      truncated=false,
    ),
    restarted,
    ctx,
  )
  assert_true(
    settled.index
    is IndexReady(
      files=[Relative("latest.html")],
      refreshing=false,
      refresh_again=false,
      ..
    ),
  )
  for
    next in [
      cloud_ctx("other-account", "session", 2),
      cloud_ctx("account", "other-session", 1),
      cloud_ctx("account", "session", 3),
    ] {
    let (next_state, _) = sync(emit, loading, next)
    let (_, ignored) = update(emit, reply, next_state, next)
    assert_true(ignored.index is IndexEmpty)
  }
}

///|
test "Cloud file state fences session switches and account lifecycle changes" {
  let emit = test_emit()
  let a = cloud_ctx("account-a", "session", 1)
  let b = cloud_ctx("account-b", "session", 2)
  let path = a.resource(Relative("same.mbt")).unwrap()
  let a = { ..a, open_files: [path], active_file: Some(path), }
  let (first, _) = sync(emit, State::empty(), a)
  let (away, _) = sync(emit, first, b)
  let (returned, _) = sync(emit, away, a)
  let stale = FileLoaded(
    owner=a.owner,
    epoch=first.request_epoch,
    path~,
    name="same.mbt",
    file=Content(content="old", sig="old"),
    file_link_generation=None,
    review_generation=None,
    range=None,
    annotation=None,
  )
  let (_, ignored) = update(emit, stale, returned, a)
  assert_true(ignored.docs.get(path) is Some({ state: TabLoading, .. }))
  let relogged = { ..a, cloud_files: Some({ epoch: 3, token: "new-token", }), }
  assert_eq(relogged.resource(Relative("same.mbt")), Some(path))
  let (renewed, _) = sync(emit, returned, relogged)
  assert_true(renewed.request_epoch > returned.request_epoch)
  let (_, ignored) = update(
    emit,
    DirLoaded(
      owner=a.owner,
      epoch=returned.request_epoch,
      path=@pathx.Relative::root(),
      entries=[{ name: "old", path: Relative("old"), is_dir: false, }],
    ),
    renewed,
    relogged,
  )
  assert_true(ignored.children.is_empty())
  assert_true(renewed.watched_paths(relogged) is None)
  assert_true(renewed.polled_files(relogged).is_empty())
  assert_true(relogged.search_input() is None)
}

///|
test "Cloud credentials never expose a retained Host checkout" {
  let host = test_ctx()
  let unavailable = {
    ..host,
    owner: @interop.Cloud(account="account", session="session"),
  }
  assert_true(unavailable.root() is None)
  assert_false(unavailable.checkout_ready())
  let draft = cloud_ctx("account", "draft", 1)
  let draft = { ..draft, cloud_files: None, }
  assert_true(draft.root() is None)
  assert_false(draft.checkout_ready())
}

///|
test "Cloud manual and run-finish refreshes retire old reads and keep background tabs lazy" {
  let ctx = cloud_ctx("account", "session", 1)
  let path = ctx.resource(Relative("hello.txt")).unwrap()
  let ctx = { ..ctx, open_files: [path], active_file: Some(path), }
  let (state, _) = sync(test_emit(), State::empty(), ctx)
  let state = {
    ..state,
    docs: Map([(path, loaded_doc("hello.txt"))]),
    children: Map([(@pathx.Relative::root(), [])]),
    loading: [],
  }
  let (_, manual) = update(
    test_emit(),
    ExplorerModeSelected(ExplorerFiles),
    state,
    ctx,
  )
  assert_true(manual.request_epoch > state.request_epoch)
  assert_true(manual.docs.get(path) is Some({ stale: true, .. }))
  assert_true(manual.loading.contains(@pathx.Relative::root()))
  let (_, finished) = update(test_emit(), RunSettled(owner=ctx.owner), state, {
    ..ctx,
    panel_open: false,
  })
  assert_true(finished.children.is_empty())
  assert_true(finished.loading.is_empty())
  assert_true(finished.docs.get(path) is Some({ stale: true, .. }))
  let (_, unchanged) = update(
    test_emit(),
    ExplorerModeSelected(ExplorerChanges),
    state,
    ctx,
  )
  assert_true(unchanged == state)
}

///|
test "large preview clicks require the current Cloud size notice and retire on loading" {
  let ctx = cloud_ctx("account", "session", 1)
  let path = ctx.resource(Relative("large.txt")).unwrap()
  let ctx = { ..ctx, open_files: [path], active_file: Some(path), }
  let (state, _) = sync(test_emit(), State::empty(), ctx)
  let state = {
    ..state,
    docs: Map([
      (
        path,
        { name: "large.txt", state: TabOversized, review: None, stale: false, },
      ),
    ]),
  }
  let click = PreviewLargeFile(
    owner=ctx.owner,
    epoch=state.request_epoch,
    path~,
  )
  assert_true(state.large_preview_file(ctx) is Some(_))
  let (_, loading) = update(test_emit(), click, state, ctx)
  assert_true(loading.docs.get(path) is Some({ state: TabLoading, .. }))
  assert_eq(loading.file_link_generation, state.file_link_generation + 1)
  assert_true(loading.large_preview_file(ctx) is None)
  let (_, repeated) = update(test_emit(), click, loading, ctx)
  assert_true(repeated == loading)
  for
    invalid in [
      PreviewLargeFile(owner=ctx.owner, epoch=state.request_epoch - 1, path~),
      PreviewLargeFile(
        owner=@interop.Cloud(account="other", session="session"),
        epoch=state.request_epoch,
        path~,
      ),
    ] {
    let (_, ignored) = update(test_emit(), invalid, state, ctx)
    assert_true(ignored == state)
  }
  let host = { ..test_ctx(), active_file: Some(path), }
  let host_state = { ..state, owner: Some(host.owner), }
  assert_true(host_state.large_preview_file(host) is None)
  let (_, ignored) = update(
    test_emit(),
    PreviewLargeFile(owner=host.owner, epoch=host_state.request_epoch, path~),
    host_state,
    host,
  )
  assert_true(ignored == host_state)
}

///|
test "Cloud notice refreshes and stale activations show loading without changing successful previews" {
  let ctx = cloud_ctx("account", "session", 1)
  let path = ctx.resource(Relative("retry.txt")).unwrap()
  let ctx = { ..ctx, open_files: [path], active_file: Some(path), }
  let (state, _) = sync(test_emit(), State::empty(), ctx)
  for previous in [TabBinary, TabOversized, TabReadFailed("failed")] {
    let state = {
      ..state,
      docs: Map([
        (
          path,
          { name: "retry.txt", state: previous, review: None, stale: false, },
        ),
      ]),
    }
    for
      message in [
        ExplorerModeSelected(ExplorerFiles),
        RunSettled(owner=ctx.owner),
      ] {
      let (_, refreshing) = update(test_emit(), message, state, ctx)
      assert_true(refreshing.docs.get(path) is Some({ state: TabLoading, .. }))
    }
    let doc = { ..state.docs.get(path).unwrap(), stale: true, }
    let (_, activated) = activate(
      test_emit(),
      { ..state, docs: Map([(path, doc)]), },
      ctx,
      path,
    )
    assert_true(activated.docs.get(path) is Some({ state: TabLoading, .. }))
  }
}
