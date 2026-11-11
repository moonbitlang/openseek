///|
test "preview_open accepts workspace file paths and rejects roots URLs and escapes" {
  for
    path in [
      "index.html", "pages/demo #.HTM", "reports/report.pdf", "图片/图.png", "src/main.mbt",
      "notes without extension",
    ] {
    let args : @protocol.PreviewOpenArgs = @json.from_json({
      "path": Json(path),
    })
    assert_eq(args.path, path)
  }
  for
    path in [
      "", "  ", "/tmp/report.pdf", "C:/report.pdf", "C:\\report.pdf", "https://example.com",
      "file:///tmp/a.html", "../a.txt", "pages/../../a.html",
    ] {
    let rejected = try {
      let _ : @protocol.PreviewOpenArgs = @json.from_json({ "path": Json(path) })
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "preview requests preserve trusted Local and Cloud ownership through notifications" {
  let requests : Array[@protocol.PreviewOpenRequest] = [
    Local(session="local-a", workspace="/workspace/a", path="index.html"),
    Cloud(account="account", session="cloud-a", path="report.pdf"),
  ]
  for request in requests {
    let notification = @protocol.Notification::PreviewOpen(request)
    assert_eq(
      @protocol.Notification::from_wire(
        notification.wire_name(),
        notification.params(),
      ),
      Some(notification),
    )
  }
  let rejected = try {
    let _ : @protocol.PreviewOpenRequest = @json.from_json({
      "kind": "local",
      "session": "a",
      "path": "a.txt",
    })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
