///|
test "external documents share the document lifecycle without workspace membership" {
  let file = test_ctx().test_resource("/outside/notes.md")
  let ctx = { ..test_ctx(), open_files: [file], active_file: Some(file), }
  let before = owned_state()
  let emit = test_emit()
  let (_, opened) = open_file(
    emit,
    before,
    ctx,
    file,
    range=None,
    had_active=false,
  )
  let (_, repeated) = open_file(
    emit,
    before,
    ctx,
    file,
    range=None,
    had_active=false,
  )
  assert_true(opened == repeated)
  assert_true(before.docs.is_empty())
  assert_true(
    opened.docs.get(file) is Some({ state: TabLoading, review: None, .. }),
  )
  assert_true(ctx.relative(file) is None)
  assert_true(opened.error is None)
  assert_true(opened.watched_paths(ctx) is Some({ files: [], .. }))
  let loaded = FileLoaded(
    owner=ctx.owner,
    epoch=ctx.request_epoch,
    path=file,
    name="notes.md",
    file=Content(content="outside", absolute=file, sig="1:0"),
    file_link_generation=None,
    review_generation=None,
    range=None,
    annotation=None,
  )
  let (_, ready) = update(emit, loaded, opened, ctx)
  let (_, again) = update(emit, loaded, opened, ctx)
  assert_true(ready == again)
  assert_true(
    ready.docs.get(file)
    is Some({ state: TabLoaded(content="outside", ..), review: None, .. }),
  )
  // The external poll uses the same signatures and stale-document handling.
  let background = { ..ctx, active_file: None, }
  let changed = StatsLoaded(
    recheck_diagnostics=false,
    owner=ctx.owner,
    epoch=ctx.request_epoch,
    stats=[{ path: file, signature: Present("2:0"), }],
  )
  let (_, stale) = update(emit, changed, ready, background)
  let (_, same_stale) = update(emit, changed, ready, background)
  assert_true(stale == same_stale)
  assert_true(stale.docs.get(file) is Some({ stale: true, .. }))
  let (_, polled) = update(emit, RefreshExternalFiles, stale, background)
  assert_true(polled == stale)
  let (_, closed) = close_document(
    emit,
    stale,
    ctx,
    file,
    next=None,
    was_active=true,
  )
  assert_true(closed.docs.is_empty())
}

///|
test "absolute document keys distinguish devices and equal basenames" {
  let local_file = test_ctx().test_resource("/outside/notes.md")
  let other = test_ctx().test_resource("/another/notes.md")
  guard @resource.of_path(
      @interop.ChannelId::Remote("other"),
      "/outside/notes.md",
    )
    is Some(remote) else {
    fail("expected an absolute remote resource")
  }
  let docs : Map[@common.Uri, Doc] = Map([])
  docs[local_file] = loaded_doc("local.md")
  docs[other] = loaded_doc("other.md")
  docs[remote] = loaded_doc("remote.md")
  assert_eq(docs.length(), 3)
  assert_true(docs.get(local_file) is Some({ name: "local.md", .. }))
  assert_true(docs.get(remote) is Some({ name: "remote.md", .. }))
}
