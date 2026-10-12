///|
fn office_selection_model(
  codex~ : Bool = false,
) -> (Model, @fileeditor.Ctx, @common.Uri) raise {
  let base = desktop_model()
  let model = if codex {
    let codex = @codex.State::from_thread_snapshot({
      "thread": {
        "id": "office-codex",
        "preview": "Office",
        "cwd": "/work",
        "turns": [],
      },
    })
    let (_, model) = update(test_dispatch(), CodexOpenThread("office-codex"), {
      ..base,
      codex,
    })
    model
  } else {
    base
  }
  let path = model.test_file("report.docx")
  let model = {
    ..model,
    dock: @dock.open_file(model.dock, path),
    right_panel_open: true,
  }
  let ctx = file_ctx(model)
  let document : @office_viewer.RenderedDocument = {
    kind: Word,
    file: path.path,
    name: "report.docx",
    surface_html: "",
    item_count: 1,
    warning: "",
    annotations: Json::null(),
  }
  let docs : Map[@common.Uri, @fileeditor.Doc] = Map([])
  docs[path] = {
    name: "report.docx",
    state: TabOffice(document~, sig="docx:1"),
    review: None,
    stale: false,
  }
  let file_panel = {
    ..model.file_panel,
    owner: Some(ctx.owner),
    placement: @fileeditor.PlacementUnknown.reconcile(ctx.placement),
    docs,
  }
  ({ ..model, file_panel, }, ctx, path)
}

///|
fn root_office_selection(
  ctx : @fileeditor.Ctx,
  path : @common.Uri,
  text : String,
) -> Msg {
  let selection : Json = {
    "schema": "office.selection.v1",
    "file": path.path,
    "format": "docx",
    "kind": "word",
    "text": text,
    "pages": [2],
    "anchors": [
      {
        "part": "word/document.xml",
        "path": "p[3]",
        "selector": "/docx/body/p[3]",
        "stability": "snapshot-relative",
        "start_utf16": 0,
        "end_utf16": text.length(),
        "page": 2,
        "text": text,
      },
    ],
  }
  FileEditor(
    @fileeditor.OfficeSelectionChanged(
      owner=ctx.owner,
      epoch=ctx.request_epoch,
      path~,
      sig="docx:1",
      selection=selection.stringify(),
    ),
  )
}

///|
test "Office selection needs confirmation and retains multiple accepted quotations on both screens" {
  for codex in [false, true] {
    let (model, ctx, path) = office_selection_model(codex~)
    let draft = if codex {
      model.codex_composer_input().draft
    } else {
      let conv = model.active_conversation().unwrap()
      @composer.Draft::{
        task: conv.task,
        images: conv.images,
        mentions: conv.mentions,
      }
    }
    let (_, pending) = update(
      test_dispatch(),
      root_office_selection(ctx, path, "First passage"),
      model,
    )
    assert_true(
      pending.active_conversation().unwrap().mentions ==
      model.active_conversation().unwrap().mentions,
    )
    assert_true(pending.codex_composer_input().draft.mentions == draft.mentions)
    let first = pending.file_panel
      .pending_office_selection(file_ctx(pending))
      .unwrap()
    let confirm = FileEditor(@fileeditor.OfficeSelectionConfirmed(first))
    let (_, accepted) = update(test_dispatch(), confirm, pending)
    assert_true(accepted.file_panel.office_selection is None)
    let mentions = if codex {
      accepted.codex_composer_input().draft.mentions
    } else {
      accepted.active_conversation().unwrap().mentions
    }
    assert_eq(mentions.length(), 1)
    assert_true(
      @mention_context.label(mentions[0].ref_).contains("First passage"),
    )
    let (_, duplicate) = update(test_dispatch(), confirm, accepted)
    assert_true(duplicate == accepted)
    let (_, second) = update(
      test_dispatch(),
      root_office_selection(file_ctx(accepted), path, "Second passage"),
      accepted,
    )
    let preview = second.file_panel
      .pending_office_selection(file_ctx(second))
      .unwrap()
    let (_, both) = update(
      test_dispatch(),
      FileEditor(@fileeditor.OfficeSelectionConfirmed(preview)),
      second,
    )
    let mentions = if codex {
      both.codex_composer_input().draft.mentions
    } else {
      both.active_conversation().unwrap().mentions
    }
    assert_eq(mentions.length(), 2)
    assert_true(
      @mention_context.encode(mentions.map(mention => mention.ref_), "Explain").contains(
        "First passage",
      ),
    )
    assert_true(
      @mention_context.encode(mentions.map(mention => mention.ref_), "Explain").contains(
        "Second passage",
      ),
    )
  }
}

///|
test "cancel and stale Office confirmation leave the composer unchanged" {
  let (model, ctx, path) = office_selection_model()
  let (_, first) = update(
    test_dispatch(),
    root_office_selection(ctx, path, "First passage"),
    model,
  )
  let preview = first.file_panel
    .pending_office_selection(file_ctx(first))
    .unwrap()
  let (_, second) = update(
    test_dispatch(),
    root_office_selection(ctx, path, "Second passage"),
    first,
  )
  let (_, unchanged) = update(
    test_dispatch(),
    FileEditor(@fileeditor.OfficeSelectionConfirmed(preview)),
    second,
  )
  assert_true(unchanged == second)
  let current = second.file_panel
    .pending_office_selection(file_ctx(second))
    .unwrap()
  // Identical text in another owner still cannot approve this owner's preview.
  let previous_owner = {
    ..current,
    owner: { ..current.owner, session: "previous", },
  }
  let (_, unchanged) = update(
    test_dispatch(),
    FileEditor(@fileeditor.OfficeSelectionConfirmed(previous_owner)),
    second,
  )
  assert_true(unchanged == second)
  let (_, cancelled) = update(
    test_dispatch(),
    FileEditor(@fileeditor.OfficeSelectionDismissed(current)),
    second,
  )
  assert_true(cancelled.file_panel.office_selection is None)
  assert_true(cancelled.active_conversation().unwrap().mentions.is_empty())
  let other = { ..ctx, owner: { ..ctx.owner, session: "other", }, }
  let (_, stale) = update(
    test_dispatch(),
    root_office_selection(other, path, "Late passage"),
    cancelled,
  )
  assert_true(stale == cancelled)
  let hidden = { ..second, right_panel_open: false, }
  let (_, rejected) = update_msg(
    test_dispatch(),
    FileEditor(@fileeditor.OfficeSelectionConfirmed(current)),
    hidden,
  )
  assert_true(rejected == hidden)
}
