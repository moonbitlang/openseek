///|
fn markdown_viewer_lifecycle_test_model(
  path : String,
  source : String,
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="markdown-viewer-lifecycle-test",
      path~,
    ),
    path,
    "moonbit",
    1,
    "markdown-viewer-lifecycle-revision",
    source,
  )
}

///|
test "MarkdownViewerWidget detaches the returned old model before set_model returns" {
  let first = markdown_viewer_lifecycle_test_model(
    "/first.mbt", "# First\n\n```mbt check\nlet first = 1\n```",
  )
  let second = markdown_viewer_lifecycle_test_model(
    "/second.mbt", "# Second\n\n```mbt check\nlet second = 2\n```",
  )
  let viewer = MarkdownViewerWidget::MarkdownViewerWidget()
  defer {
    viewer.dispose()
    first.dispose()
    second.dispose()
  }
  let mut detached_after_cleanup = false
  let detach_count = Ref(0)
  let detach_listener = viewer.on_did_detach_for_diagnostics(() => {
    detach_count.val += 1
    detached_after_cleanup = viewer.current is None
  })
  defer detach_listener.dispose()
  let mut content_deliveries = 0
  let content_listener = viewer.on_did_change_model_content(_ => {
    content_deliveries += 1
  })
  defer content_listener.dispose()
  assert_true(
    viewer.set_model(Some(MarkdownViewerWidgetModel(first, MoonBitMarkdown)))
    is None,
  )
  let returned = viewer.set_model(
    Some(MarkdownViewerWidgetModel(second, OrdinaryMarkdown)),
  )
  guard returned is Some(returned) else { fail("expected detached old model") }
  assert_true(returned.model.same(first))
  assert_true(returned.resource_kind == MoonBitMarkdown)
  assert_eq(detach_count.val, 1)
  assert_true(detached_after_cleanup)
  guard viewer.current is Some(current) else { fail("expected replacement") }
  assert_true(current.model.model.same(second))
  assert_true(current.model.resource_kind == OrdinaryMarkdown)
  first.set_value("detached change")
  assert_eq(content_deliveries, 0)
  second.set_value("# replacement changed")
  assert_eq(content_deliveries, 1)
}

///|
test "explicit resource kind renders a code model as Markdown without classification" {
  let model = markdown_viewer_lifecycle_test_model(
    "/plain-code.mbt", "```mbt check\n///|\nfn rendered_as_markdown() -> Int { 1 }\n```",
  )
  let viewer = MarkdownViewerWidget::MarkdownViewerWidget()
  defer {
    viewer.dispose()
    model.dispose()
  }
  viewer.set_model(Some(MarkdownViewerWidgetModel(model, MoonBitMarkdown)))
  |> ignore
  guard viewer.current is Some(current) else { fail("expected attachment") }
  assert_true(current.model.model.same(model))
  assert_true(current.model.resource_kind == MoonBitMarkdown)
  assert_true(current.model.resource_kind.to_internal() == MoonBitMarkdown)
  // A headless package test has no DOM, but it follows the same attachment
  // constructor and explicit kind path as the mounted MarkdownDocumentView.
  assert_true(current.view is None)
}

///|
test "changing only resource kind is a real detach and reattach" {
  let model = markdown_viewer_lifecycle_test_model(
    "/resource-kind.mbt", "```mbt check\nlet value = 1\n```",
  )
  let viewer = MarkdownViewerWidget::MarkdownViewerWidget()
  defer {
    viewer.dispose()
    model.dispose()
  }
  viewer.set_model(Some(MarkdownViewerWidgetModel(model, OrdinaryMarkdown)))
  |> ignore
  let detach_count = Ref(0)
  let listener = viewer.on_did_detach_for_diagnostics(() => {
    detach_count.val += 1
  })
  defer listener.dispose()
  let old = viewer.set_model(
    Some(MarkdownViewerWidgetModel(model, MoonBitMarkdown)),
  )
  guard old is Some(old) else { fail("expected old explicit model") }
  assert_true(old.model.same(model))
  assert_true(old.resource_kind == OrdinaryMarkdown)
  assert_eq(detach_count.val, 1)
  guard viewer.get_model() is Some(current) else {
    fail("expected current model")
  }
  assert_true(current.model.same(model))
  assert_true(current.resource_kind == MoonBitMarkdown)
}

///|
test "disposing an installed source model clears MarkdownViewerWidget synchronously" {
  let model = markdown_viewer_lifecycle_test_model(
    "/disposed.mbt", "# Dispose me",
  )
  let viewer = MarkdownViewerWidget::MarkdownViewerWidget()
  defer viewer.dispose()
  viewer.set_model(Some(MarkdownViewerWidgetModel(model, OrdinaryMarkdown)))
  |> ignore
  model.dispose()
  assert_true(viewer.get_model() is None)
}
