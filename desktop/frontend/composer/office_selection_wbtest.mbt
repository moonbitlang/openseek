///|
test "confirmed Office quotations accumulate and deduplicate without replacing other context" {
  let file = @mention_context.File(path="report.docx")
  let draft : Draft = {
    task: "Explain",
    images: [],
    mentions: [{ ref_: file, range: None, }],
  }
  let first = draft.with_office_selection(Some("passage A"))
  let second = first.with_office_selection(Some("passage B"))
  assert_eq(first.mentions.length(), 2)
  assert_eq(second.mentions.length(), 3)
  assert_true(second.mentions[0].ref_ == file)
  assert_true(second.with_office_selection(Some("passage A")) == second)
  assert_true(second.with_office_selection(None) == draft)
  assert_true(second.prompt().contains("passage A"))
  assert_true(second.prompt().contains("passage B"))
}
