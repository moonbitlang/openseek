///|
test "view names round-trip and reject foreign views" {
  assert_true(@extension.browser_view_id("browser-3") == Some(3))
  assert_true(@extension.browser_view_id("browser-42") == Some(42))
  assert_true(@extension.browser_view_id("browser-") is None)
  assert_true(@extension.browser_view_id("sidebar") is None)
  assert_true(@extension.browser_view_id("browser-x") is None)
}

///|
test "web contents events preserve the frontend browser notification contract" {
  let navigated : @proton.WebContentsEvent = Navigated(
    url="https://example.test/",
  )
  assert_eq(
    @extension.view_event_json(3, navigated),
    Some({ "id": 3, "kind": "navigated", "url": "https://example.test/" }),
  )
  let terminated : @proton.WebContentsEvent = RendererProcessTerminated(
    url="https://example.test/",
    status=1,
    error_code=9,
    detail="fixture renderer exit",
  )
  assert_eq(
    @extension.view_event_json(3, terminated),
    Some({
      "id": 3,
      "kind": "renderer_process_terminated",
      "url": "https://example.test/",
      "code": 9,
      "text": "Renderer process terminated (status 1): fixture renderer exit",
    }),
  )
  assert_eq(
    @extension.view_event_json(3, Closed),
    Some({ "id": 3, "kind": "closed" }),
  )
}

///|
test "resource events do not become browser tab notifications" {
  let events : Array[@proton.WebContentsEvent] = [
    ResourceRequested(
      url="https://example.test/",
      request_method="GET",
      will_cancel=false,
    ),
    ResourceResponse(url="https://example.test/", status_code=200),
    ResourceCompleted(url="https://example.test/", status=0, received_bytes=42),
  ]
  for event in events {
    assert_true(@extension.view_event_json(3, event) is None)
  }
}
