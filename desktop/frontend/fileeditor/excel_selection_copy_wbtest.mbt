///|
fn excel_copy_raw(range_ : String, cells : Array[(String, String)]) -> String {
  let values = cells.map(pair => {
    let (address, text) = pair
    let (row, column) = excel_copy_cell(address).unwrap_or((0, 0))
    Json::object({
      "address": Json(address),
      "row": Json(row),
      "column": Json(column),
      "text": Json(text),
    })
  })
  let raw : Json = {
    "schema": "office.selection.v1",
    "file": "/work/budget.xlsx",
    "format": "xlsx",
    "kind": "excel",
    "sheet": "Data",
    "range": Json(range_),
    "selector": "/xlsx/sheet[name=\"Data\"]/range[B4:D6]",
    "stability": "snapshot-relative",
    "cells": Json(values),
  }
  raw.stringify()
}

///|
test "Excel table copy keeps sparse coordinates trailing blanks and merged coverage" {
  let table = excel_selection_table(
    excel_copy_raw("B4:D6", [
      ("C6", "尾行 🌙"),
      ("B4", "标题"),
      ("C5", "25"),
    ]),
  ).unwrap()
  assert_eq(table.text(Tsv), Some("标题\t\t\r\n\t25\t\r\n\t尾行 🌙\t"))
  assert_eq(
    table.text(Markdown),
    Some(
      "| 标题 |  |  |\n| --- | --- | --- |\n|  | 25 |  |\n|  | 尾行 🌙 |  |",
    ),
  )
  // A merged cell's anchor may precede the selected rectangle.
  let clipped = excel_selection_table(
    excel_copy_raw("C3:D4", [("B2", "Merged")]),
  ).unwrap()
  assert_eq(clipped.text(Tsv), Some("Merged\t\r\n\t"))
  assert_eq(
    excel_selection_table(excel_copy_raw("B2:D2", [("B2", "Merged")]))
    .unwrap()
    .text(Tsv),
    Some("Merged\t\t"),
  )
}

///|
test "TSV copy quotes embedded tabs line breaks and quotes without changing values" {
  let table = excel_selection_table(
    excel_copy_raw("A1:C2", [
      ("A1", "列\t名"),
      ("B1", "say \"hello\""),
      ("C1", "line1\r\nline2"),
      ("A2", "  spaces  "),
      ("B2", "=literal"),
      ("C2", ""),
    ]),
  ).unwrap()
  assert_eq(
    table.text(Tsv),
    Some(
      "\"列\t名\"\t\"say \"\"hello\"\"\"\t\"line1\r\nline2\"\r\n  spaces  \t=literal\t",
    ),
  )
}

///|
test "Markdown table copy escapes literal markup and uses the first row as header" {
  let table = excel_selection_table(
    excel_copy_raw("A1:B2", [
      ("A1", "a|b\\c"),
      ("B1", "`code` *bold* _em_ [link]"),
      ("A2", "<img> & value\r\nnext\r\nthird\rlast\rfinal"),
      ("B2", "中文 🌙"),
    ]),
  ).unwrap()
  assert_eq(
    table.text(Markdown),
    Some(
      "| a\\|b\\\\c | \\`code\\` \\*bold\\* \\_em\\_ \\[link\\] |\n| --- | --- |\n| &lt;img&gt; &amp; value<br>next<br>third<br>last<br>final | 中文 🌙 |",
    ),
  )
  assert_eq(
    excel_selection_table(excel_copy_raw("C9", [("C9", "one")]))
    .unwrap()
    .text(Markdown),
    Some("| one |\n| --- |"),
  )
}

///|
test "Excel copy rejects invalid ranges and bounds expansion of giant merges" {
  for range_ in ["", "A0", "XFE1", "A1048577", "B2:A1", "A1:A1:B2"] {
    assert_true(
      excel_selection_table(excel_copy_raw(range_, [("A1", "x")])) is None,
    )
  }
  assert_true(excel_selection_table(excel_copy_raw("A1", [])) is None)
  assert_true(
    excel_selection_table(excel_copy_raw("A1", [("B1", "x")])) is None,
  )
  let huge = excel_selection_table(
    excel_copy_raw("A1:XFD1048576", [("A1", "merged")]),
  ).unwrap()
  assert_true(huge.text(Tsv) is None)
  assert_true(huge.text(Markdown) is None)
}

///|
fn excel_copy_state() -> (State, Ctx, OfficeSelectionPreview) raise {
  let (state, ctx, _) = office_selection_fixture()
  let path = test_file("budget.xlsx")
  let document : @office_viewer.RenderedDocument = {
    kind: Excel,
    file: path.path,
    name: "budget.xlsx",
    surface_html: "",
    item_count: 1,
    warning: "",
    annotations: null,
  }
  let docs : Map[@common.Uri, Doc] = Map([])
  docs[path] = {
    name: "budget.xlsx",
    state: TabOffice(document~, sig="xlsx:1"),
    review: None,
    stale: false,
  }
  let ctx = { ..ctx, active_file: Some(path), open_files: [path], }
  let state = { ..state, docs, }
    .offer_office_selection(
      ctx,
      excel_copy_raw("A1:B1", [("A1", "始".repeat(5000)), ("B1", "END🌙")]),
    )
    .unwrap()
  (state, ctx, state.pending_office_selection(ctx).unwrap())
}

///|
test "Excel clipboard retains the full selection beyond the Agent preview" {
  let (_, _, preview) = excel_copy_state()
  assert_true(preview.summary.text.unwrap().length() < 5000)
  assert_eq(
    preview.excel_table.unwrap().text(Tsv),
    Some("始".repeat(5000) + "\tEND🌙"),
  )
  let (state, ctx, preview) = excel_copy_state()
  let (_, copying) = state.copy_excel_selection(
    ctx,
    _ => @cmd.none,
    preview,
    Tsv,
  )
  let (_, failed) = update_inner(
    _ => @cmd.none,
    ExcelSelectionCopyFinished(preview, 1, false),
    copying,
    ctx,
  )
  assert_true(failed.excel_copy_feedback.unwrap().status is Failed)
  let (_, retried) = failed.copy_excel_selection(
    ctx,
    _ => @cmd.none,
    preview,
    Markdown,
  )
  assert_eq(retried.excel_copy_generation, 2)
  let (_, unchanged) = update_inner(
    _ => @cmd.none,
    ExcelSelectionCopyFinished(preview, 1, true),
    retried,
    ctx,
  )
  assert_true(unchanged.excel_copy_feedback.unwrap().status is Copying)
  let (_, unchanged) = update_inner(
    _ => @cmd.none,
    ExcelSelectionCopyExpired(preview, 1),
    unchanged,
    ctx,
  )
  assert_eq(unchanged.excel_copy_feedback.unwrap().generation, 2)
  let (_, copied) = update_inner(
    _ => @cmd.none,
    ExcelSelectionCopyFinished(preview, 2, true),
    unchanged,
    ctx,
  )
  assert_true(copied.excel_copy_feedback.unwrap().status is Copied)
  let (_, expired) = update_inner(
    _ => @cmd.none,
    ExcelSelectionCopyExpired(preview, 2),
    copied,
    ctx,
  )
  assert_true(expired.excel_copy_feedback is None)
}

///|
test "Excel copy does not accept an old selection or stale document completion" {
  let (state, ctx, preview) = excel_copy_state()
  let (_, copying) = state.copy_excel_selection(
    ctx,
    _ => @cmd.none,
    preview,
    Tsv,
  )
  let replacement = copying
    .offer_office_selection(ctx, excel_copy_raw("C3", [("C3", "next")]))
    .unwrap()
  let (_, unchanged) = replacement.copy_excel_selection(
    ctx,
    _ => @cmd.none,
    preview,
    Tsv,
  )
  assert_true(unchanged.excel_copy_feedback is None)
  let (_, unchanged) = update_inner(
    _ => @cmd.none,
    ExcelSelectionCopyFinished(preview, 1, true),
    replacement,
    ctx,
  )
  assert_true(unchanged.excel_copy_feedback is None)
  let ctx = { ..ctx, panel_open: false, }
  let invalidated = copying.sync_office_selection(ctx)
  assert_true(invalidated.excel_copy_feedback is None)
}

///|
test "Excel clipboard selection survives feedback dismissal and follows cells while a draft is pinned" {
  let (state, ctx, preview) = excel_copy_state()
  let (_, dismissed) = state.dismiss_office_selection(ctx, preview)
  assert_true(dismissed.pending_office_selection(ctx) is None)
  assert_true(dismissed.pending_excel_selection(ctx) == Some(preview))
  let (_, copying) = dismissed.copy_excel_selection(
    ctx,
    _ => @cmd.none,
    preview,
    Tsv,
  )
  assert_true(copying.excel_copy_feedback is Some(_))
  let state = { ..state, office_selection_comment: Some("Keep this feedback"), }
  let next = state
    .offer_office_selection(ctx, excel_copy_raw("C3", [("C3", "next")]))
    .unwrap()
  assert_true(next.pending_office_selection(ctx) == Some(preview))
  assert_eq(next.office_selection_comment, Some("Keep this feedback"))
  assert_eq(
    next.pending_excel_selection(ctx).unwrap().excel_table.unwrap().text(Tsv),
    Some("next"),
  )
}
