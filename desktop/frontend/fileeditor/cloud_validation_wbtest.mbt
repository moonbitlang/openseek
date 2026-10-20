///|
test "Cloud version checks preserve cached content and reject retired authentication, epochs and versions" {
  let ctx = cloud_ctx("account", "session", 4)
  let path = ctx.resource(Relative("hello.txt")).unwrap()
  let ctx = { ..ctx, active_file: Some(path), open_files: [path], }
  let (base, _) = sync(test_emit(), State::empty(), ctx)
  let doc : Doc = {
    name: "hello.txt",
    state: TabLoaded(content="cached", sig="W/\"etag\""),
    review: None,
    stale: true,
  }
  let state = { ..base, docs: Map([(path, doc)]), }
  let reply = FileVersionChecked(
    owner=ctx.owner,
    epoch=state.request_epoch,
    path~,
    sig="W/\"etag\"",
    unchanged=true,
  )
  let (_, checked) = update(test_emit(), reply, state, ctx)
  assert_true(
    checked.docs.get(path)
    is Some(
      { state: TabLoaded(content="cached", sig="W/\"etag\""), stale: false, .. }
    ),
  )
  for
    reply in [
      FileVersionChecked(
        owner=ctx.owner,
        epoch=state.request_epoch - 1,
        path~,
        sig="W/\"etag\"",
        unchanged=false,
      ),
      FileVersionChecked(
        owner=@interop.Cloud(account="other", session="session"),
        epoch=state.request_epoch,
        path~,
        sig="W/\"etag\"",
        unchanged=false,
      ),
      FileVersionChecked(
        owner=ctx.owner,
        epoch=state.request_epoch,
        path~,
        sig="old-etag",
        unchanged=true,
      ),
    ] {
    let (_, ignored) = update(test_emit(), reply, state, ctx)
    assert_true(ignored == state)
  }
  let renewed = { ..ctx, cloud_files: Some({ epoch: 5, token: "new-token", }), }
  let (_, retired) = update(test_emit(), reply, state, renewed)
  assert_true(retired == state)
  let (renewed_state, _) = sync(test_emit(), state, renewed)
  let (_, ignored) = update(test_emit(), reply, renewed_state, renewed)
  assert_true(ignored == renewed_state)
  assert_true(doc.cloud_signature(test_ctx().owner) is None)
}

///|
test "unchanged Cloud PDF runtimes retain ready events while read epochs validate their content" {
  let (_, _, _, document) = pdf_fixture()
  let ctx = cloud_ctx("account", "session", 4)
  let path = ctx.resource(Relative("report.pdf")).unwrap()
  let ctx = { ..ctx, active_file: Some(path), open_files: [path], }
  let state = {
    ..State::empty(),
    owner: Some(ctx.owner),
    cloud_epoch: Some(4),
    request_epoch: 10,
    cloud_surface_epoch: 9,
    docs: Map([
      (
        path,
        {
          name: "report.pdf",
          state: TabPdf(document~, sig="etag"),
          review: None,
          stale: true,
        },
      ),
    ]),
    pdf_generation: document.generation,
  }
  let (_, ready) = update(
    test_emit(),
    PdfStateChanged(
      owner=ctx.owner,
      epoch=9,
      path~,
      sig="etag",
      generation=document.generation,
      event="{\"status\":\"ready\",\"pages\":2,\"page\":1}",
    ),
    state,
    ctx,
  )
  assert_true(pdf_in(ready, path).status is PdfReady)
  assert_false(
    ready.accepts_pdf_callback(
      ctx,
      ctx.owner,
      9,
      path,
      "etag",
      document.generation,
    ),
  )
  let (_, checked) = update(
    test_emit(),
    FileVersionChecked(
      owner=ctx.owner,
      epoch=10,
      path~,
      sig="etag",
      unchanged=true,
    ),
    ready,
    ctx,
  )
  assert_true(
    checked.accepts_pdf_callback(
      ctx,
      ctx.owner,
      9,
      path,
      "etag",
      document.generation,
    ),
  )
  assert_false(
    checked.accepts_pdf_callback(
      ctx,
      ctx.owner,
      9,
      path,
      "old-etag",
      document.generation,
    ),
  )
  assert_false(
    checked.accepts_pdf_callback(
      ctx,
      ctx.owner,
      9,
      path,
      "etag",
      document.generation - 1,
    ),
  )
  assert_false(
    checked.accepts_pdf_callback(
      { ..ctx, cloud_files: Some({ epoch: 5, token: "new-token", }), },
      ctx.owner,
      9,
      path,
      "etag",
      document.generation,
    ),
  )
}
