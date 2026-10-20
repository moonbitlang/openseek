///|
test "Office destinations preserve paths and decode their location once" {
  assert_eq(
    @office_location.parse("/docs/年度报告.PDF#page=12"),
    Some({ path: "/docs/年度报告.PDF", target: PdfPage(12), }),
  )
  assert_eq(
    @office_location.parse(
      "C:\\Reports\\budget.xlsx#sheet=Q1%20%26%20Q2&range=B2:D8",
    ),
    Some({
      path: "C:\\Reports\\budget.xlsx",
      target: ExcelRange(sheet="Q1 & Q2", range="B2:D8"),
    }),
  )
  assert_eq(
    @office_location.parse(
      "report.docx#heading=%E8%90%A5%E6%94%B6%20%F0%9F%8C%99",
    ),
    Some({ path: "report.docx", target: WordHeading("营收 🌙"), }),
  )
  assert_eq(
    @office_location.parse("report.docx#paragraph=%2Fdocx%2Fbody%2Fp%5B1%5D"),
    Some({ path: "report.docx", target: WordParagraph("/docx/body/p[1]"), }),
  )
  assert_eq(
    @office_location.parse("book.xlsx#sheet=A%2520B&range=XFD1048576"),
    Some({
      path: "book.xlsx",
      target: ExcelRange(sheet="A%20B", range="XFD1048576"),
    }),
  )
}

///|
test "malformed and unrelated locations never become Office destinations" {
  for
    reference in [
      "https://example.com/report.pdf#page=2", "code.mbt#L12", "report.pdf#page=0",
      "report.pdf#page=-1", "report.pdf#page=1.5", "report.pdf#page=99999999999999",
      "report.pdf#page=2&page=3", "report.pdf#page=2&unknown=1", "report.docx#heading=",
      "report.docx#paragraph=/docx/header[1]/p[1]", "report.pdf#heading=Summary",
      "book.xlsx#sheet=Data", "book.xlsx#sheet=Data&range=A0", "book.xlsx#sheet=Data&range=XFE1",
      "book.xlsx#sheet=Data&range=A1048577", "book.xlsx#sheet=Data&range=B2:A1",
      "book.xlsx#sheet=Data&range=a1", "book.xlsx#sheet=Data%0AOther&range=A1",
    ] {
    assert_eq(@office_location.parse(reference), None)
  }
}

///|
test "saved PDF page metadata has an explicit bounded compatibility path" {
  assert_eq(
    @office_location.citation_destination(
      "/docs/report.pdf", "Report — p. 12, Revenue.",
    ),
    "/docs/report.pdf#page=12",
  )
  assert_eq(
    @office_location.citation_destination(
      "/docs/report.pdf", "报告 — 第 2 页，营业收入。",
    ),
    "/docs/report.pdf#page=2",
  )
  for
    summary in [
      "Report — p. 0", "Report — p. 2–4", "Report — mentions page 2", "Report — p. 2oops",
    ] {
    assert_eq(
      @office_location.citation_destination("report.pdf", summary),
      "report.pdf",
    )
  }
  assert_eq(
    @office_location.citation_destination(
      "report.pdf#page=3", "Report — p. 12",
    ),
    "report.pdf#page=3",
  )
}
