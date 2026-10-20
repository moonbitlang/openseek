///|
fn pdf_capture_model(
  codex~ : Bool = false,
) -> (Model, @fileeditor.Ctx, @common.Uri) raise {
  let (model, ctx, path) = office_selection_model(codex~)
  let model = if codex {
    update_msg(
      test_dispatch(),
      Codex(
        channel=ctx.owner.host().unwrap().channel,
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
      owner=ctx.owner.host().unwrap(),
      epoch=ctx.request_epoch,
      path~,
      sig="pdf:1",
      generation~,
      result=Ok({
        url: "data:image/png;base64,capture",
        text: None,
        source: { "document": { "sha256": "fixture" }, "regions": [] },
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
    assert_eq(first.file_panel.pdf_capture_id, 1L)
    assert_true(first.file_panel == again.file_panel)
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
test "repeated identical screenshots get distinct identities and reject retired callbacks" {
  let (model, ctx, path) = pdf_capture_model()
  let (_, first) = update_msg(test_dispatch(), captured(ctx, path), model)
  guard first.file_panel.pdf_capture is Some(old) else {
    fail("missing capture")
  }
  let (_, second) = update_msg(test_dispatch(), captured(ctx, path), first)
  assert_eq(second.file_panel.pdf_capture_id, 2L)
  guard second.file_panel.pdf_capture is Some(current) else {
    fail("missing second capture")
  }
  assert_true(old.preview.id != current.preview.id)
  let (_, unchanged) = update_msg(
    test_dispatch(),
    FileEditor(@fileeditor.PdfCaptureDismissed(old.preview)),
    second,
  )
  assert_true(unchanged.file_panel == second.file_panel)
  let (_, edited) = update_msg(
    test_dispatch(),
    FileEditor(
      @fileeditor.PdfCaptureFeedbackChanged(current.preview, "Keep this"),
    ),
    second,
  )
  assert_eq(edited.file_panel.pdf_capture_id, 2L)
}

///|
test "capture requests preserve an existing screenshot with or without comment" {
  for codex in [false, true] {
    let (model, ctx, path) = pdf_capture_model(codex~)
    let (_, model) = update_msg(test_dispatch(), captured(ctx, path), model)
    guard model.file_panel.pdf_capture is Some(draft) else {
      fail("missing screenshot")
    }
    for comment in ["", "Keep the captured region"] {
      let (_, model) = update_msg(
        test_dispatch(),
        FileEditor(
          @fileeditor.PdfCaptureFeedbackChanged(draft.preview, comment),
        ),
        model,
      )
      let msg = FileEditor(@fileeditor.PdfCaptureRequested)
      let (_, first) = update_msg(test_dispatch(), msg, model)
      let (_, again) = update_msg(test_dispatch(), msg, model)
      assert_true(first == model)
      assert_true(again == model)
    }
  }
}

///|
test "capture requests preserve a pinned Office annotation without running browser effects" {
  for codex in [false, true] {
    let (model, ctx, path) = office_selection_model(codex~)
    let (_, pending) = update_msg(
      test_dispatch(),
      root_office_selection(ctx, path, "Selected text"),
      model,
    )
    guard pending.file_panel.pending_office_selection(file_ctx(pending))
      is Some(preview) else {
      fail("missing Office selection")
    }
    let (_, drafting) = update_msg(
      test_dispatch(),
      FileEditor(@fileeditor.OfficeFeedbackChanged(preview, "Keep this draft")),
      pending,
    )
    let msg = FileEditor(@fileeditor.PdfCaptureRequested)
    let (_, first) = update_msg(test_dispatch(), msg, drafting)
    let (_, again) = update_msg(test_dispatch(), msg, drafting)
    assert_true(first == drafting)
    assert_true(again == drafting)
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
  let other = {
    ..ctx,
    owner: @interop.Host({ ..ctx.owner.host().unwrap(), session: "other", }),
  }
  let (_, switched) = update_msg(test_dispatch(), captured(other, path), model)
  assert_true(switched.composer_input().draft.images.is_empty())
  assert_true(switched.file_panel.pdf_capture is None)
}

///|
test "unsupported image model refuses PDF screenshots and explains declined feedback without losing drafts" {
  let (model, ctx, path) = pdf_capture_model()
  guard model.active_conversation() is Some(conv) else {
    fail("missing conversation")
  }
  let model = model.replace_conversation({ ..conv, engine_model: DsPro, })
  assert_false(model.can_attach_pdf_capture())
  let (_, rejected) = update_msg(test_dispatch(), captured(ctx, path), model)
  assert_true(rejected.composer_input().draft.images.is_empty())
  assert_true(rejected.file_panel.pdf_capture is None)
  let (model, ctx, path) = pdf_capture_model()
  let (_, pending) = update_msg(test_dispatch(), captured(ctx, path), model)
  guard pending.file_panel.pdf_capture is Some(draft) else {
    fail("missing screenshot")
  }
  let (_, pending) = update_msg(
    test_dispatch(),
    FileEditor(
      @fileeditor.PdfCaptureFeedbackChanged(draft.preview, "Keep this"),
    ),
    pending,
  )
  guard pending.active_conversation() is Some(conv) else {
    fail("missing conversation")
  }
  let pending = pending.replace_conversation({ ..conv, engine_model: DsPro, })
  let msg = FileEditor(@fileeditor.PdfCaptureSubmissionDeclined(draft.preview))
  // Commands remain inert without a browser; equal inputs give equal models.
  let (_, first) = update_msg(test_dispatch(), msg, pending)
  let (_, again) = update_msg(test_dispatch(), msg, pending)
  assert_true(first == again)
  assert_true(first.file_panel == pending.file_panel)
  assert_true(first.composer_input().draft == pending.composer_input().draft)
  assert_eq(first.notifications.length(), 1)
  assert_eq(
    first.notifications[0].message,
    @fileeditor.capture_submission_declined_message(pending.locale),
  )
  let stale = { ..draft.preview, generation: draft.preview.generation - 1, }
  let (_, unchanged) = update_msg(
    test_dispatch(),
    FileEditor(@fileeditor.PdfCaptureSubmissionDeclined(stale)),
    pending,
  )
  assert_true(unchanged == pending)
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
