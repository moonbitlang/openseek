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
    working_feedback_model(None, None, Some(pair), modified.uri) is Some(model) &&
    model.same(modified),
  )
  assert_true(
    working_feedback_model(Some(unrelated), None, Some(pair), modified.uri)
    is Some(model) &&
    model.same(modified),
  )
  assert_true(
    working_feedback_model(Some(unrelated), None, Some(pair), unrelated.uri)
    is Some(model) &&
    model.same(unrelated),
  )
}

///|
test "rendered Markdown feedback resolves its source model" {
  let source = feedback_test_model(
    "file", "/README.md", "# Title\n\nPlease **keep** this.\n\nAfter.",
  )
  let original = feedback_test_model("review-original", "/README.md", "old")
  let previous = feedback_test_model("file", "/README.md", "previous revision")
  let unrelated = feedback_test_model("file", "/other.md", "other")
  defer source.dispose()
  defer original.dispose()
  defer previous.dispose()
  defer unrelated.dispose()
  let markdown = @viewer.MarkdownViewerModel(source, OrdinaryMarkdown)
  let pair = @viewer.DiffEditorModel(original, previous)
  for diff in [None, Some(pair)] {
    let resolved = working_feedback_model(
      Some(unrelated),
      Some(markdown),
      diff,
      source.uri,
    )
    assert_true(resolved is Some(model) && model.same(source))
  }
  assert_true(
    working_feedback_model(None, Some(markdown), Some(pair), original.uri)
    is None,
  )
}

///|
test "working feedback keeps rendered selection text separate from source range" {
  let source = feedback_test_model(
    "file", "/README.md", "# Title\n\nPlease **keep** this.\n\nAfter.",
  )
  defer source.dispose()
  let range = @common.Range(3, 1, 3, 22)
  let service = @feedback.DesktopFeedbackService()
  let messages : Array[Msg] = []
  service.on_did_add_feedback(event => {
    messages.push(
      working_feedback_message(Relative("README.md"), source, event.feedback),
    )
  })
  |> ignore
  // Empty visible text is still an explicit selection (for example an image).
  // Only source feedback without a rendered selection quotes the model range.
  for
    (selected_text, expected) in [
      (Some("keep"), "keep"),
      (Some(""), ""),
      (None, "Please **keep** this."),
    ] {
    messages.clear()
    let feedback = service
      .agent_feedback_handle()
      .add_feedback(source.uri, range, "make this clearer", selected_text?)
    guard messages[:]
      is [
        EditorCommentAdded(
          resource~,
          file~,
          range=actual_range,
          quote~,
          comment~,
          feedback_id~
        ),
      ] else {
      fail("expected one working-file annotation")
    }
    assert_eq(resource.0, source.uri.to_string())
    assert_eq(file, Relative("README.md"))
    assert_eq(actual_range, range)
    assert_eq(quote, expected)
    assert_eq(comment, "make this clearer")
    assert_eq(feedback_id, feedback.id)
  }
}
