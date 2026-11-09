///|
test "HTML preview opens a browser tab only for files on this Desktop" {
  let model = desktop_model()
  let path = "/workspace/demo.HTML"
  let (_, opened) = update(test_dispatch(), PreviewLocalFile(path), model)
  assert_true(@dock.active_browser(opened.dock_state()) is Some(_))
  assert_true(opened.right_panel_open)
  for path in ["/workspace/main.mbt", "/workspace/image.svg"] {
    let (_, ignored) = update(test_dispatch(), PreviewLocalFile(path), model)
    assert_eq(ignored.preview.next_id, model.preview.next_id)
  }
  let web = { ..model, is_desktop: false, }
  let (_, ignored) = update(test_dispatch(), PreviewLocalFile(path), web)
  assert_eq(ignored.preview.next_id, web.preview.next_id)
}

///|
test "a late navigation event cannot resurrect a closed preview tab" {
  let (_, opened) = update(
    test_dispatch(),
    PreviewLocalFile("/workspace/demo.html"),
    desktop_model(),
  )
  let id = @dock.active_browser(opened.dock_state()).unwrap()
  let closed = { ..opened, preview: @preview.close_page(opened.preview, id), }
  let (_, late) = update(
    test_dispatch(),
    Preview(@preview.Msg::Navigated(id~, url="http://127.0.0.1:1234/demo.html")),
    closed,
  )
  assert_true(@preview.page(late.preview, id) is None)
}
