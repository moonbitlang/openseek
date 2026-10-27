///|
test "download caches preserve original UTF-8 and binary source bytes" {
  let original = b"\xef\xbb\xbfraw\r\n\xe6\x9c\x88\r\n"
  let states = [
    TabLoaded(content=try! @utf8.decode(original), sig="etag"),
    TabImage(
      url="data:image/png;base64," + @base64.encode(original),
      sig="etag",
    ),
    TabPdf(
      document={
        bytes: original,
        generation: 1,
        status: PdfFailed("preview failed"),
        page: 1,
        pages: None,
        rotation: 0,
        search: None,
        password: "",
      },
      sig="etag",
    ),
  ]
  for state in states {
    let doc : Doc = { name: "file", state, review: None, stale: true, }
    let cached = doc.download_cache().unwrap()
    assert_eq(cached.0, "etag")
    assert_eq(cached.1, original)
  }
  for
    state in [
      TabLoading,
      TabBinary,
      TabOversized,
      TabReadFailed("no preview"),
      TabDeleted,
      TabLoaded(content="text", sig=""),
      TabImage(url="blob:preview", sig="etag"),
    ] {
    let doc : Doc = { name: "file", state, review: None, stale: false, }
    assert_true(doc.download_cache() is None)
  }
}

///|
test "download completions are fenced by account epoch and owner" {
  let ctx = cloud_ctx("account-a", "session", 4)
  let path = ctx.resource(Relative("file.txt")).unwrap()
  let ctx = { ..ctx, active_file: Some(path), open_files: [path], }
  let (state, _) = sync(test_emit(), State::empty(), ctx)
  let (_, pending) = update(
    test_emit(),
    DownloadFile(desktop=false, path~),
    state,
    ctx,
  )
  assert_true(pending.download == Some(path))
  let failed = FileDownloaded(
    owner=ctx.owner,
    auth_epoch=4,
    generation=pending.download_generation,
    path~,
    result=Err("HTTP 403"),
  )
  let (_, rejected) = update(test_emit(), failed, pending, {
    ..ctx,
    cloud_files: Some({ epoch: 5, token: "other-token", }),
  })
  assert_true(rejected == pending)
  let (_, rejected) = update(test_emit(), failed, pending, {
    ..ctx,
    owner: @interop.Cloud(account="account-b", session="session"),
  })
  assert_true(rejected == pending)
  let newer = {
    ..pending,
    download_generation: pending.download_generation + 1,
  }
  let (_, ignored) = update(test_emit(), failed, newer, ctx)
  assert_true(ignored == newer)
  let (_, shown) = update(test_emit(), failed, pending, ctx)
  assert_true(shown.download is None)
  let (retired, _) = forget_cloud_files(pending, "account-a")
  assert_true(
    !accepts_download(
      retired,
      ctx,
      ctx.owner,
      4,
      pending.download_generation,
      path,
    ),
  )
}
