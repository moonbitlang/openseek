///|
fn pdf_fixture() -> (State, Ctx, @common.Uri, PdfDocument) raise {
  let path = test_file("report.pdf")
  let ctx = { ..test_ctx(), open_files: [path], active_file: Some(path), }
  let document = decode_pdf_document(@base64.encode(b"%PDF-1.7 fixture"), 7).unwrap()
  let docs : Map[@common.Uri, Doc] = Map([])
  docs[path] = {
    name: "report.pdf",
    state: TabPdf(document~, sig="pdf:1"),
    review: None,
    stale: false,
  }
  ({ ..owned_state(), docs, pdf_generation: 7, }, ctx, path, document)
}

///|
fn pdf_in(state : State, path : @common.Uri) -> PdfDocument raise {
  guard state.docs.get(path) is Some({ state: TabPdf(document~, ..), .. }) else {
    fail("expected a PDF tab")
  }
  document
}

///|
test "PDF Changes preserves the manual tree preference during loading and activation" {
  let (fixture, ctx, path, _) = pdf_fixture()
  let change : ChangedFile = {
    path: Relative("report.pdf"),
    original_path: None,
    index_status: " ",
    worktree_status: "M",
    kind: ChangeModified,
  }
  let (_, loading) = open_changed_document(
    test_emit(),
    { ..owned_state(), tree_open: true, },
    ctx,
    change,
    had_active=false,
  )
  assert_true(loading.tree_open)
  assert_true(loading.docs[path].state is TabLoading)
  // Reopening either the pending review or its loaded PDF must apply the
  // same layout without waiting for another working-tree reply.
  for doc_state in [TabLoading, fixture.docs[path].state] {
    let docs = loading.docs.copy()
    docs[path] = { ..docs[path], state: doc_state, }
    let (_, activated) = open_changed_document(
      test_emit(),
      { ..loading, docs, tree_open: true, },
      ctx,
      change,
      had_active=true,
    )
    assert_true(activated.tree_open)
    assert_eq(activated.review_generation, loading.review_generation)
  }
}

///|
test "a tree manually reopened during the initial PDF read stays open" {
  let (state, ctx, path, _) = pdf_fixture()
  let docs = state.docs.copy()
  docs[path] = { ..docs[path], state: TabLoading, }
  let (_, reopened) = update(
    test_emit(),
    ToggleTree,
    { ..state, docs, tree_open: false, },
    ctx,
  )
  assert_true(reopened.tree_open)
  let (_, loaded) = update(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="report.pdf",
      file=Office(
        data_base64=@base64.encode(b"%PDF-1.7 fixture"),
        media_type="application/pdf",
        sig="pdf:1",
      ),
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    reopened,
    ctx,
  )
  assert_true(loaded.docs[path].state is TabPdf(..))
  assert_true(loaded.tree_open)
}

///|
test "PDF callbacks belong to the active file revision and runtime" {
  let (state, ctx, path, _) = pdf_fixture()
  assert_true(state.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 7))
  assert_false(
    state.accepts_pdf_callback(
      ctx,
      { ..ctx.owner, session: "other", },
      0,
      path,
      "pdf:1",
      7,
    ),
  )
  assert_false(state.accepts_pdf_callback(ctx, ctx.owner, 1, path, "pdf:1", 7))
  assert_false(
    state.accepts_pdf_callback(
      ctx,
      ctx.owner,
      0,
      test_file("other.pdf"),
      "pdf:1",
      7,
    ),
  )
  assert_false(state.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:2", 7))
  assert_false(state.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 6))
  assert_false(
    state.accepts_pdf_callback(
      { ..ctx, active_file: None, },
      ctx.owner,
      0,
      path,
      "pdf:1",
      7,
    ),
  )
  let docs = state.docs.copy()
  docs[path] = { ..docs[path], stale: true, }
  assert_false(
    { ..state, docs, }.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 7),
  )
  let closed = { ..state, docs: Map([]), }
  assert_false(closed.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 7))
}

///|
test "PDF remount preserves the parked page and retires old callbacks" {
  let (state, ctx, path, document) = pdf_fixture()
  let state = state.with_pdf_document(path, {
    ..document,
    status: PdfReady,
    page: 2,
    pages: Some(3),
    rotation: 90,
  })
  let doc = state.docs[path].prepare_pdf_runtime(8)
  let state = state
    .record_pdf_generation(doc)
    .with_pdf_document(path, {
      ..pdf_in(state, path),
      generation: 8,
      status: PdfLoading,
    })
  let (_, pending) = apply_pdf_event(
    state,
    path,
    pdf_in(state, path),
    "{\"status\":\"page\",\"page\":1}",
  )
  assert_true(pdf_in(pending, path).page == 2)
  let (_, ready) = apply_pdf_event(
    pending,
    path,
    pdf_in(pending, path),
    "{\"status\":\"ready\",\"pages\":3}",
  )
  assert_true(pdf_in(ready, path).status is PdfReady)
  assert_true(pdf_in(ready, path).page == 2)
  assert_true(pdf_in(ready, path).rotation == 90)
  assert_true(ready.pdf_generation == 8)
  assert_false(ready.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 7))
  let (_, unchanged) = update_pdf(
    ready,
    ctx,
    PdfStateChanged(
      owner=ctx.owner,
      epoch=0,
      path~,
      sig="pdf:1",
      generation=7,
      event="{\"status\":\"error\",\"message\":\"late failure\"}",
    ),
  )
  assert_true(unchanged == ready)
}

///|
test "PDF event decoding rejects malformed counts without losing the document" {
  let (state, _, path, document) = pdf_fixture()
  for
    raw in [
      "invalid", "null", "{\"status\":\"ready\",\"pages\":null}", "{\"status\":\"ready\",\"pages\":0}",
      "{\"status\":\"ready\",\"pages\":1.5}", "{\"status\":\"ready\",\"pages\":2147483648}",
      "{\"status\":\"rotation\",\"rotation\":45}", "{\"status\":\"search\",\"current\":2,\"total\":1}",
      "{\"status\":\"password\",\"incorrect\":null}", "{\"status\":\"unknown\"}",
    ] {
    let (_, next) = apply_pdf_event(state, path, document, raw)
    assert_true(next == state)
  }
  let (_, ready) = apply_pdf_event(
    state, path, document, "{\"status\":\"ready\",\"pages\":2}",
  )
  let (_, paged) = apply_pdf_event(
    ready,
    path,
    pdf_in(ready, path),
    "{\"status\":\"page\",\"page\":2}",
  )
  assert_true(pdf_in(paged, path).page == 2)
  let (_, found) = apply_pdf_event(
    paged,
    path,
    pdf_in(paged, path),
    "{\"status\":\"search\",\"current\":1,\"total\":2}",
  )
  assert_true(pdf_in(found, path).search == Some((1, 2)))
}

///|
test "PDF passwords clear on submission retry and cancellation" {
  let (state, ctx, path, document) = pdf_fixture()
  let (_, required) = apply_pdf_event(
    state, path, document, "{\"status\":\"password\",\"incorrect\":false}",
  )
  let (_, typed) = update_pdf(
    required,
    ctx,
    PdfPasswordChanged("first attempt"),
  )
  let (_, submitted) = update_pdf(typed, ctx, PdfPasswordSubmitted)
  assert_true(pdf_in(submitted, path).password == "")
  assert_true(pdf_in(submitted, path).status is PdfLoading)
  let (_, retry) = apply_pdf_event(
    submitted,
    path,
    pdf_in(submitted, path),
    "{\"status\":\"password\",\"incorrect\":true}",
  )
  assert_true(pdf_in(retry, path).status is PdfPasswordRequired(incorrect=true))
  let (_, cancelled) = update_pdf(retry, ctx, PdfPasswordCancelled)
  assert_true(pdf_in(cancelled, path).status is PdfFailed(_))
  assert_true(pdf_in(cancelled, path).password == "")
  assert_false(
    cancelled.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 7),
  )
  let (_, late) = update_pdf(
    cancelled,
    ctx,
    PdfStateChanged(
      owner=ctx.owner,
      epoch=0,
      path~,
      sig="pdf:1",
      generation=7,
      event="{\"status\":\"ready\",\"pages\":2}",
    ),
  )
  assert_true(late == cancelled)
}

///|
test "PDF binary replies retain original bytes and recover from failed loads" {
  let (state, ctx, path, _) = pdf_fixture()
  let file = FileContent::from_reply(
    @protocol.BinaryContent(
      data_base64=@base64.encode(b"%PDF-1.7 exact bytes"),
      media_type="application/pdf",
      sig="pdf:2",
    ),
  )
  let (_, loaded) = update_inner(
    test_emit(),
    FileLoaded(
      owner=ctx.owner,
      epoch=0,
      path~,
      name="report.pdf",
      file~,
      file_link_generation=None,
      review_generation=None,
      range=None,
      annotation=None,
    ),
    state,
    ctx,
  )
  let document = pdf_in(loaded, path)
  assert_true(document.bytes == b"%PDF-1.7 exact bytes")
  assert_true(document.status is PdfLoading)
  assert_true(document.generation == 8)
  assert_false(loaded.accepts_pdf_callback(ctx, ctx.owner, 0, path, "pdf:1", 7))
  let (_, failed) = apply_pdf_event(
    loaded, path, document, "{\"status\":\"error\",\"message\":\"Invalid PDF structure.\"}",
  )
  assert_true(
    pdf_in(failed, path).status
    is PdfFailed("Could not preview this PDF. Try reopening the file."),
  )
  assert_true(decode_pdf_document("***invalid base64***", 9) is Err(_))
}

///|
test "PDF failures use the current locale without exposing runtime details" {
  let (state, ctx, path, _) = pdf_fixture()
  let ctx = { ..ctx, locale: @i18n.SimplifiedChinese, }
  let event : Json = {
    "status": "error",
    "message": "Error: invalid payload at /private/tmp/internal-parser.js:42",
  }
  let (_, failed) = update_pdf(
    state,
    ctx,
    PdfStateChanged(
      owner=ctx.owner,
      epoch=0,
      path~,
      sig="pdf:1",
      generation=7,
      event=event.stringify(),
    ),
  )
  assert_true(
    pdf_in(failed, path).status
    is PdfFailed("无法预览此 PDF。请重新打开文件。"),
  )
  let event : Json = {
    "status": "selection-error",
    "message": "Invalid selector: internal document JSON",
  }
  let (_, unavailable) = update_pdf(
    state,
    ctx,
    PdfStateChanged(
      owner=ctx.owner,
      epoch=0,
      path~,
      sig="pdf:1",
      generation=7,
      event=event.stringify(),
    ),
  )
  assert_eq(
    unavailable.error,
    Some("无法添加所选内容。请重新选择。"),
  )
  assert_true(
    decode_pdf_document(locale=ctx.locale, "***invalid base64***", 9)
    is Err("无法预览此 PDF。请重新打开文件。"),
  )
  assert_true(
    render_office_document(
      locale=ctx.locale,
      "report.docx",
      test_file("report.docx"),
      "***invalid base64***",
    )
    is Err("无法预览此文档。请重新打开文件。"),
  )
  assert_true(
    render_office_document(
      locale=ctx.locale,
      "report.docx",
      test_file("report.docx"),
      @base64.encode(b"invalid Office package"),
    )
    is Err("无法预览此文档。请重新打开文件。"),
  )
}
