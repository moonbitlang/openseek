///|
fn pdf_capture_model(
  codex~ : Bool = false,
) -> (Model, @fileeditor.Ctx, @common.Uri) raise {
  let (model, ctx, path) = office_selection_model(codex~)
  let model = if codex {
    update_msg(
      test_dispatch(),
      Codex(
        channel=ctx.owner.channel,
        @codex.Msg::status_changed({ "status": "ready" }),
      ),
      model,
    ).1
  } else {
    guard model.active_conversation() is Some(conv) else {
      fail("missing conversation")
    }
    model.replace_conversation({ ..conv, engine_model: DsFlash, })
  }
  let docs = model.file_panel.docs.copy()
  let doc = docs[path]
  docs[path] = {
    ..doc,
    state: TabPdf(sig="pdf:1", document={
      bytes: b"%PDF",
      generation: 7,
      status: PdfReady,
      page: 1,
      pages: Some(2),
      rotation: 0,
      search: None,
      password: "",
    }),
  }
  ({ ..model, file_panel: { ..model.file_panel, docs, }, }, ctx, path)
}

///|
fn captured(
  ctx : @fileeditor.Ctx,
  path : @common.Uri,
  generation~ : Int32 = 7,
) -> Msg {
  FileEditor(
    @fileeditor.PdfCaptureFinished(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path~,
      sig="pdf:1",
      generation~,
      result=Ok({
        url: "data:image/png;base64,capture",
        regions: [],
        rotation: 0,
      }),
    ),
  )
}

///|
test "PDF region capture offers feedback without changing either composer and is pure" {
  for codex in [false, true] {
    let (model, ctx, path) = pdf_capture_model(codex~)
    assert_true(model.can_attach_pdf_capture())
    // No DOM exists in the test: constructing the capture command must not read it.
    let (_, requested) = update_msg(
      test_dispatch(),
      FileEditor(@fileeditor.PdfCaptureRequested),
      model,
    )
    assert_true(requested.file_panel.docs == model.file_panel.docs)
    let (_, first) = update_msg(test_dispatch(), captured(ctx, path), model)
    let (_, again) = update_msg(test_dispatch(), captured(ctx, path), model)
    let input = if codex {
      first.codex_composer_input()
    } else {
      first.composer_input()
    }
    let repeated = if codex {
      again.codex_composer_input()
    } else {
      again.composer_input()
    }
    assert_true(input.draft.images == repeated.draft.images)
    assert_true(input.draft.images.is_empty())
    guard first.file_panel.pdf_capture is Some(draft) else {
      fail("missing feedback preview")
    }
    assert_eq(draft.preview.capture.url, "data:image/png;base64,capture")
    assert_true(
      input.draft.task ==
      (if codex {
        model.codex_composer_input()
      } else {
        model.composer_input()
      }).draft.task,
    )
  }
}

///|
test "retired PDF capture and a closed panel cannot add an image" {
  let (model, ctx, path) = pdf_capture_model()
  let (_, stale) = update_msg(
    test_dispatch(),
    captured(ctx, path, generation=6),
    model,
  )
  assert_true(stale.composer_input().draft.images.is_empty())
  assert_true(stale.file_panel.pdf_capture is None)
  let (_, closed) = update_msg(test_dispatch(), captured(ctx, path), {
    ..model,
    right_panel_open: false,
  })
  assert_true(closed.composer_input().draft.images.is_empty())
  assert_true(closed.file_panel.pdf_capture is None)
  let other = { ..ctx, owner: { ..ctx.owner, session: "other", }, }
  let (_, switched) = update_msg(test_dispatch(), captured(other, path), model)
  assert_true(switched.composer_input().draft.images.is_empty())
  assert_true(switched.file_panel.pdf_capture is None)
}

///|
test "unsupported image model refuses PDF screenshots" {
  let (model, ctx, path) = pdf_capture_model()
  guard model.active_conversation() is Some(conv) else {
    fail("missing conversation")
  }
  let model = model.replace_conversation({ ..conv, engine_model: DsPro, })
  assert_false(model.can_attach_pdf_capture())
  let (_, rejected) = update_msg(test_dispatch(), captured(ctx, path), model)
  assert_true(rejected.composer_input().draft.images.is_empty())
  assert_true(rejected.file_panel.pdf_capture is None)
}

///|
test "PDF feedback edits are pure and stale checkbox callbacks cannot change Batch" {
  let (model, ctx, path) = pdf_capture_model()
  let (_, model) = update_msg(test_dispatch(), captured(ctx, path), model)
  guard model.file_panel.pdf_capture is Some(draft) else {
    fail("missing capture")
  }
  let preview = draft.preview
  for
    msg in [
      FileEditor(
        @fileeditor.PdfCaptureFeedbackChanged(preview, "Keep this instruction"),
      ),
      FileEditor(@fileeditor.PdfCaptureBatchChanged(preview, true)),
    ] {
    let (_, first) = update_msg(test_dispatch(), msg, model)
    let (_, again) = update_msg(test_dispatch(), msg, model)
    assert_true(first.file_panel == again.file_panel)
  }
  let (_, batched) = update_msg(
    test_dispatch(),
    FileEditor(@fileeditor.PdfCaptureBatchChanged(preview, true)),
    model,
  )
  assert_true(batched.file_panel.pdf_capture_batch)
  assert_false(model.file_panel.pdf_capture_batch)
  let stale = { ..preview, generation: preview.generation - 1, }
  let (_, ignored) = update_msg(
    test_dispatch(),
    FileEditor(@fileeditor.PdfCaptureBatchChanged(stale, false)),
    batched,
  )
  assert_true(ignored.file_panel.pdf_capture_batch)
  let (_, dismissed) = update_msg(
    test_dispatch(),
    FileEditor(@fileeditor.PdfCaptureDismissed(preview)),
    batched,
  )
  assert_true(dismissed.file_panel.pdf_capture is None)
  assert_true(dismissed.file_panel.pdf_capture_batch)
  let (_, next) = update_msg(test_dispatch(), captured(ctx, path), dismissed)
  assert_true(next.file_panel.pdf_capture_batch)
  assert_true(next.file_panel.pdf_capture is Some({ comment: "", .. }))
}
