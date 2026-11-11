///|
test "a late persistent cache read cannot replace a fresh Cloud page" {
  let state = progress_test_state()
  let (cache, _, _) = update(
    state,
    Open("session"),
    _ => @cmd.none,
    token="fixture",
    navigation=0,
  )
  let cache_request = cache.conversations["session"].request
  let network = cache.load("session", Some("fixture"), _ => @cmd.none).0
  let page : History = {
    session: native_document([]),
    messages: [],
    offset: Some(0),
    etag: Some("fresh"),
    generating: false,
    prediction: None,
  }
  let fresh = metadata_update(
    network,
    Loaded(state.epoch, "session", network.sequence, page),
  )
  let late = metadata_update(
    fresh,
    CachedHistoryLoaded(
      state.epoch,
      "session",
      cache_request,
      Some({ ..page, etag: Some("stale"), }),
    ),
  )
  assert_eq(late.conversations["session"].history_etag, Some("fresh"))
  assert_eq(late.sequence, fresh.sequence)
}

///|
test "legacy cached history remains readable but cannot validate omitted metadata" {
  let page : @protocol.CloudHistoryCachePage = @json.from_json({
    "session": native_document([]).to_json(),
    "messages": [],
    "offset": 3,
    "etag": "legacy",
  })
  guard cached_history(page) is Some(history) else {
    fail("legacy history should still load")
  }
  assert_eq(history.offset, Some(3))
  assert_eq(history.etag, None)
}
