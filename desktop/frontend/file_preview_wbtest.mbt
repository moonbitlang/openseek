///|
test "HTML preview opens a browser tab only for files on this Desktop" {
  let model = desktop_model()
  let path = "/workspace/demo.HTML"
  let (_, opened) = update(test_dispatch(), PreviewFile(path), model)
  let id = @dock.active_browser(opened.dock_state()).unwrap()
  let page = @preview.page(opened.preview, id).unwrap()
  assert_eq(page.url, None)
  assert_true(page.loading)
  assert_true(opened.preview.local_files().is_empty())
  assert_true(opened.right_panel_open)
  for path in ["/workspace/main.mbt", "/workspace/image.svg"] {
    let (_, ignored) = update(test_dispatch(), PreviewFile(path), model)
    assert_eq(ignored.preview.next_id, model.preview.next_id)
  }
  let web = { ..model, is_desktop: false, }
  let (_, ignored) = update(test_dispatch(), PreviewFile(path), web)
  assert_eq(ignored.preview.next_id, web.preview.next_id)
}

///|
test "a late navigation event cannot resurrect a closed preview tab" {
  let (_, opened) = update(
    test_dispatch(),
    PreviewFile("/workspace/demo.html"),
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

///|
test "Cloud HTML preview capability follows the signed-in file owner on both clients" {
  let model = integrated_cloud_model()
  for desktop in [true, false] {
    assert_true(file_ctx(model).can_preview_html(desktop~))
    assert_false(
      file_ctx({ ..model, account: None, }).can_preview_html(desktop~),
    )
    let (_, blank) = update(test_dispatch(), CloudAction(@cloud.Create), model)
    assert_false(file_ctx(blank).can_preview_html(desktop~))
  }
}

///|
test "Cloud preview results belong to the requesting account epoch and selected session" {
  let model = integrated_cloud_model()
  let owner = file_ctx(model).owner
  let completed = CloudFilePreviewCreated(
    owner~,
    auth_epoch=model.cloud.epoch,
    result=Ok("https://preview.example.test/page.html"),
  )
  let (_, opened) = update(test_dispatch(), completed, model)
  let id = @dock.active_browser(opened.dock_state()).unwrap()
  assert_eq(
    @preview.page(opened.preview, id).unwrap().url,
    Some("https://preview.example.test/page.html"),
  )
  let (_, switched) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-b"),
    model,
  )
  assert_true(file_ctx(switched).owner != owner)
  for
    retired in [
      switched,
      { ..model, account: None, },
      { ..model, cloud: { ..model.cloud, epoch: model.cloud.epoch + 1, }, },
    ] {
    let (_, ignored) = update(test_dispatch(), completed, retired)
    assert_true(ignored.preview == retired.preview)
    assert_eq(ignored.notification_seq, retired.notification_seq)
  }
}
