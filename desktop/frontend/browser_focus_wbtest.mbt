///|
test "returning focus preserves browser geometry, annotation, and composer draft" {
  let dispatch = test_dispatch()
  let original = desktop_model()
  let original = original.replace_conversation({
    ..original.active(),
    task: "Keep this draft",
  })
  let (_, opened) = update(
    dispatch,
    ExternalLinkClicked("https://example.test"),
    original,
  )
  let (_, placed) = update(
    dispatch,
    BrowserPaneMeasured(rect={ x: 800, y: 100, width: 400, height: 600, }),
    opened,
  )
  let (_, selecting) = update(dispatch, BrowserAnnotation(Start), placed)
  let (_, blurred) = update(dispatch, WindowFocusChanged(false), selecting)
  let (_, focused) = update(dispatch, WindowFocusChanged(true), blurred)
  let (_, repeated) = update(dispatch, WindowFocusChanged(true), blurred)
  assert_true(focused == repeated)
  assert_true(focused.window_focused)
  assert_false(blurred.window_focused)
  assert_true(focused.browser_pane == placed.browser_pane)
  assert_true(focused.browser_annotation == selecting.browser_annotation)
  assert_eq(focused.active().task, "Keep this draft")
}
