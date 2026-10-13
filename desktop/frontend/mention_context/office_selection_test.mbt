///|
fn display_selection(selection : Json, source : Json) -> String {
  let payload : Json = {
    "schema": "office.selection.materialized.v1",
    "selection": selection,
    "source": source,
  }
  payload.stringify()
}

///|
test "Office labels show the selected content and Word page or Excel range" {
  let word = display_selection(
    { "text": "  项目计划\n下一步 ", "pages": [2] },
    { "file": "/docs/report.docx" },
  )
  assert_eq(
    @mention_context.label(OfficeSelection(materialized=word)),
    "report.docx · p. 2 · “项目计划 下一步”",
  )
  assert_true(
    @mention_context.office_selection_title(word).contains(
      "项目计划\n下一步",
    ),
  )
  let excel = display_selection(
    { "text": "Revenue\t100\nCost\t40", "sheet": "Data", "range": "B4:C5" },
    { "file": "/docs/budget.xlsx" },
  )
  assert_eq(
    @mention_context.office_selection_label(excel),
    "budget.xlsx · Data!B4:C5 · “Revenue 100 Cost 40”",
  )
  let empty = display_selection(
    { "text": "", "sheet": "Data", "range": "A1" },
    { "file": "/docs/budget.xlsx" },
  )
  assert_eq(
    @mention_context.office_selection_label(empty),
    "budget.xlsx · Data!A1",
  )
}

///|
test "PDF labels get file and cross-page position from the retained reference" {
  let pdf = display_selection(
    { "format": "pdf", "text": "Second page selection" },
    {
      "reference": {
        "file": "/docs/report.pdf",
        "start": { "page": 2 },
        "end": { "page": 3 },
      },
    },
  )
  assert_eq(
    @mention_context.office_selection_label(pdf),
    "report.pdf · pp. 2–3 · “Second page selection”",
  )
}

///|
test "Office display handles malformed input and truncates whole Unicode characters" {
  for
    value in [
      "null", "invalid", "{}", "{\"schema\":\"office.selection.materialized.v1\",\"selection\":{\"text\":null}}",
    ] {
    assert_true(@mention_context.office_selection_summary(value) is None)
    assert_eq(
      @mention_context.office_selection_label(value),
      "Office selection",
    )
  }
  let text = "😀".repeat(65)
  let selection = display_selection({ "text": text }, {
    "file": "/docs/中文.docx",
  })
  assert_eq(
    @mention_context.office_selection_label(selection),
    "中文.docx · “" + "😀".repeat(64) + "…”",
  )
  assert_true(@mention_context.office_selection_title(selection).contains(text))
}
