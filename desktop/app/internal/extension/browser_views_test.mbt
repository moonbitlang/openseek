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
    @extension.view_event_payload(3, navigated),
    Some(Navigated(id=3, url="https://example.test/")),
  )
  let terminated : @proton.WebContentsEvent = RendererProcessTerminated(
    url="https://example.test/",
    status=1,
    error_code=9,
    detail="fixture renderer exit",
  )
  assert_eq(
    @extension.view_event_payload(3, terminated),
    Some(
      RendererProcessTerminated(
        id=3,
        url="https://example.test/",
        code=9,
        text="Renderer process terminated (status 1): fixture renderer exit",
      ),
    ),
  )
  assert_eq(
    @extension.view_event_payload(3, LoadingChanged(is_loading=false)),
    Some(LoadingChanged(id=3, loading=false)),
  )
  assert_eq(
    @extension.view_event_payload(3, TitleUpdated(title="Example")),
    Some(TitleUpdated(id=3, title="Example")),
  )
  assert_eq(
    @extension.view_event_payload(
      3,
      LoadFailed(
        url="https://example.test/",
        error_code=-3,
        error_text="ERR_ABORTED",
      ),
    ),
    Some(
      LoadFailed(id=3, url="https://example.test/", code=-3, text="ERR_ABORTED"),
    ),
  )
}

///|
test "events without frontend consumers do not become browser tab notifications" {
  let events : Array[@proton.WebContentsEvent] = [
    Closed,
    DidStartLoading,
    DidFinishLoad,
    FoundInPage(result={
      request_id: 1,
      active_match_ordinal: 1,
      matches: 2,
      selection_x: 0,
      selection_y: 0,
      selection_width: 10,
      selection_height: 10,
      final_update: true,
    }),
    ResourceRequested(
      url="https://example.test/",
      request_method="GET",
      will_cancel=false,
    ),
    ResourceResponse(url="https://example.test/", status_code=200),
    ResourceCompleted(url="https://example.test/", status=0, received_bytes=42),
  ]
  for event in events {
    assert_true(@extension.view_event_payload(3, event) is None)
  }
}
