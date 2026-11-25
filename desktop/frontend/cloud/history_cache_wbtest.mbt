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

///|
test "switching Cloud history view fences delayed page reads and validators" {
  let initial = progress_test_state()
  let active = initial.replace("session", {
    ..initial.conversations["session"],
    request: 3,
    history_reading: true,
    history_cache_request: Some(2),
    history_older_request: Some((4, 0, 0)),
    history_turn_request: Some((5, 0)),
  })
  let (detail, _) = { ..active, sequence: 5, }.switch_history_view(
    Detail,
    Some("session"),
    0,
    Some("fixture"),
    _ => @cmd.none,
  )
  let stale : History = {
    session: native_document([]),
    messages: [],
    offset: Some(0),
    etag: Some("minimal"),
    generating: false,
    prediction: None,
  }
  let epoch = detail.epoch
  for
    msg in (
      [
        Loaded(epoch, "session", 3, stale),
        HistoryUnchanged(epoch, "session", 3, "minimal"),
        CachedHistoryLoaded(epoch, "session", 2, Some(stale)),
        OlderLoaded(epoch, "session", 4, stale),
        TurnLoaded(epoch, "session", 5, stale),
      ] : Array[Msg]) {
    assert_true(metadata_update(detail, msg) == detail)
  }
}
