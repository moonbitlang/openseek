///|
fn office_selection_fixture() -> (State, Ctx, @common.Uri) raise {
  let path = test_file("report.docx")
  let ctx = { ..test_ctx(), active_file: Some(path), open_files: [path], }
  let document : @office_viewer.RenderedDocument = {
    kind: Word,
    file: path.path,
    name: "report.docx",
    surface_html: "",
    item_count: 1,
    warning: "",
    annotations: Json::null(),
  }
  let docs : Map[@common.Uri, Doc] = Map([])
  docs[path] = {
    name: "report.docx",
    state: TabOffice(document~, sig="docx:1"),
    review: None,
    stale: false,
  }
  ({ ..owned_state(), docs, }, ctx, path)
}

///|
fn office_selection_raw(file : String, text : String) -> String {
  let raw : Json = {
    "schema": "office.selection.v1",
    "file": file,
    "format": "docx",
    "kind": "word",
    "text": text,
    "pages": [2],
    "anchors": [
      {
        "source_id": "docx",
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
  raw.stringify()
}

///|
test "a new Office range updates only its pending preview; cancel consumes the current one" {
  let (state, ctx, path) = office_selection_fixture()
  assert_true(state.office_selection_comment is None)
  let first = state
    .offer_office_selection(
      ctx,
      office_selection_raw(path.path, "First passage"),
    )
    .unwrap()
  let first_preview = first.pending_office_selection(ctx).unwrap()
  assert_eq(first.office_selection_comment, Some(""))
  assert_eq(first_preview.summary.text, "First passage")
  let second = first
    .offer_office_selection(
      ctx,
      office_selection_raw(path.path, "Second passage"),
    )
    .unwrap()
  let second_preview = second.pending_office_selection(ctx).unwrap()
  assert_eq(second_preview.summary.text, "Second passage")
  let (_, unchanged) = second.dismiss_office_selection(ctx, first_preview)
  assert_true(unchanged == second)
  let (_, dismissed) = second.dismiss_office_selection(ctx, second_preview)
  assert_true(dismissed.office_selection is None)
  assert_true(dismissed.office_selection_comment is None)
  assert_true(dismissed.docs == state.docs)
}

///|
test "pending Office selections expire on file owner epoch panel or revision changes" {
  let (state, ctx, path) = office_selection_fixture()
  let state = state
    .offer_office_selection(
      ctx,
      office_selection_raw(path.path, "Selected passage"),
    )
    .unwrap()
  for
    changed in [
      { ..ctx, active_file: Some(test_file("other.docx")), },
      { ..ctx, active_file: None, },
      { ..ctx, panel_open: false, },
      { ..ctx, owner: { ..ctx.owner, session: "other", }, },
    ] {
    let synced = state.sync_office_selection(changed)
    assert_true(synced.office_selection is None)
    assert_true(synced.office_selection_comment is None)
    assert_true(synced.pending_office_selection(ctx) is None)
  }
  assert_true(
    { ..state, request_epoch: 1, }.pending_office_selection(ctx) is None,
  )
  let docs = state.docs.copy()
  docs[path] = { ..docs[path], stale: true, }
  assert_true({ ..state, docs, }.pending_office_selection(ctx) is None)
  assert_false(state.accepts_office_callback(ctx, ctx.owner, 0, path, "docx:2"))
  assert_true(
    state.offer_office_selection(
      ctx,
      office_selection_raw("/work/other.docx", "wrong file"),
    )
    is Err(_),
  )
}

///|
test "Excel preview retains the sheet range and selected cell contents" {
  let (state, ctx, _) = office_selection_fixture()
  let path = test_file("budget.xlsx")
  let document : @office_viewer.RenderedDocument = {
    kind: Excel,
    file: path.path,
    name: "budget.xlsx",
    surface_html: "",
    item_count: 1,
    warning: "",
    annotations: Json::null(),
  }
  let docs : Map[@common.Uri, Doc] = Map([])
  docs[path] = {
    name: "budget.xlsx",
    state: TabOffice(document~, sig="xlsx:1"),
    review: None,
    stale: false,
  }
  let ctx = { ..ctx, active_file: Some(path), open_files: [path], }
  let raw : Json = {
    "schema": "office.selection.v1",
    "file": path.path,
    "format": "xlsx",
    "kind": "excel",
    "sheet": "Data",
    "range": "B4:C4",
    "selector": "/xlsx/sheet[name=\"Data\"]/range[B4:C4]",
    "stability": "snapshot-relative",
    "cells": [
      { "address": "B4", "row": 4, "column": 2, "text": "Revenue" },
      { "address": "C4", "row": 4, "column": 3, "text": "100" },
    ],
  }
  let state = { ..state, docs, }
    .offer_office_selection(ctx, raw.stringify())
    .unwrap()
  let preview = state.pending_office_selection(ctx).unwrap()
  assert_eq(preview.summary.heading(), "budget.xlsx · Data!B4:C4")
  assert_eq(preview.summary.text, "Revenue\t100")
}

///|
test "Office selection failures are localized without exposing schema or file details" {
  let (state, ctx, _) = office_selection_fixture()
  let ctx = { ..ctx, locale: @i18n.SimplifiedChinese, }
  for
    raw in [
      "invalid JSON",
      office_selection_raw("/work/other.docx", "wrong file"),
    ] {
    assert_true(
      state.offer_office_selection(ctx, raw)
      is Err("无法添加所选内容。请重新选择。"),
    )
  }
}

///|
test "PDF preview uses the selected text and range and expires with its runtime" {
  let (state, ctx, path, document) = pdf_fixture()
  let ready = state.with_pdf_document(path, {
    ..document,
    status: PdfReady,
    pages: Some(2),
  })
  let identity : Json = {
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "byte_length": 1000,
    "page_count": 2,
    "parser": { "name": "pdfjs", "version": "6.4.299" },
  }
  let raw : Json = {
    "schema": "office.selection.v1",
    "file": path.path,
    "format": "pdf",
    "kind": "pdf",
    "text": "Second",
    "document": identity,
    "reference": {
      "schema": "office.pdf.text-range.v1",
      "file": path.path,
      "document": identity,
      "join": "pdfjs-items-eol-v1",
      "text_content": {
        "include_marked_content": true,
        "disable_normalization": true,
      },
      "start": { "page": 2, "item_index": 0, "offset_utf16": 0 },
      "end": { "page": 2, "item_index": 0, "offset_utf16": 6 },
      "text_utf16_length": 6,
    },
  }
  assert_true(
    state.offer_office_selection(ctx, raw.stringify()).unwrap().office_selection
    is None,
  )
  let pending = ready.offer_office_selection(ctx, raw.stringify()).unwrap()
  let preview = pending.pending_office_selection(ctx).unwrap()
  assert_eq(preview.summary.heading(), "report.pdf · p. 2")
  assert_eq(preview.summary.text, "Second")
  assert_true(preview.materialized.contains("office.pdf.text-range.v1"))
  let reloaded = pending.with_pdf_document(path, {
    ..document,
    status: PdfReady,
    generation: 8,
  })
  assert_true(reloaded.sync_office_selection(ctx).office_selection is None)
  let (_, ignored) = reloaded.dismiss_office_selection(ctx, preview)
  assert_true(ignored == reloaded)
}
