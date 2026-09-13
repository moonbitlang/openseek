///|
test "desktop selects Markdown presentation and resource kind explicitly" {
  assert_true(uses_markdown_presentation("README.md"))
  assert_true(uses_markdown_presentation("Guide.MD"))
  assert_true(uses_markdown_presentation("tour.mbt.md"))
  assert_false(uses_markdown_presentation("main.mbt"))
  assert_eq(language_id("README.md"), "markdown")
  assert_eq(language_id("tour.mbt.md"), "moonbit")
  assert_true(markdown_resource_kind("README.md") is @viewer.OrdinaryMarkdown)
  assert_true(markdown_resource_kind("tour.MBT.MD") is @viewer.MoonBitMarkdown)
  assert_eq(diff_language_id("README.md"), "markdown")
  assert_eq(diff_language_id("tour.mbt.md"), "markdown")
  assert_eq(diff_language_id("main.mbt"), "moonbit")
  assert_eq(diff_language_id("moon.pkg"), "moonbit-config")
}

///|
fn feedback_test_model(
  scheme : String,
  path : String,
  content : String,
) -> @model.TextModel {
  @model.TextModel(
    try! @common.Uri::from(scheme~, path~),
    path,
    "markdown",
    1,
    "feedback-test",
    content,
  )
}

///|
test "Markdown source feedback falls back to the modified diff kernel" {
  let original = feedback_test_model("review-original", "/README.md", "old")
  let modified = feedback_test_model("file", "/README.md", "new")
  let unrelated = feedback_test_model("file", "/other.md", "other")
  defer original.dispose()
  defer modified.dispose()
  defer unrelated.dispose()
  let pair = @viewer.DiffEditorModel(original, modified)

  assert_true(
    working_feedback_model(None, Some(pair), modified.uri) is Some(model) &&
    model.same(modified),
  )
  assert_true(
    working_feedback_model(Some(unrelated), Some(pair), modified.uri)
    is Some(model) &&
    model.same(modified),
  )
  assert_true(
    working_feedback_model(Some(unrelated), Some(pair), unrelated.uri)
    is Some(model) &&
    model.same(unrelated),
  )
}
