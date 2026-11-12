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
    settings: Some({ model: V4Pro, thinking: ThinkingMax, }),
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
      Some({
        ..page,
        settings: Some(CommandSettings::default()),
        etag: Some("stale"),
      }),
    ),
  )
  assert_eq(late.conversations["session"].history_etag, Some("fresh"))
  assert_eq(late.sequence, fresh.sequence)
  assert_true(late.conversations["session"].settings == page.settings)
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
test "history settings travel with their cached page and validator" {
  let history = decode_history({
    "settings": { "model": "deepseek-v4-pro", "thinking": "max" },
    "messages": [],
    "session": { "events": [] },
    "generating": false,
    "page": { "offset": 2 },
  })
  let page = { ..history, etag: Some("settings-v1"), }.cache_page()
  let decoded : @protocol.CloudHistoryCachePage = @json.from_json(
    page.to_json(),
  )
  let restored = cached_history(decoded).unwrap()
  assert_eq(restored.etag, Some("settings-v1"))
  assert_true(
    restored.settings is Some({ model: V4Pro, thinking: ThinkingMax, }),
  )
  for
    value in [
      Json::null(),
      {},
      { "model": "deepseek-v4-pro" },
      { "thinking": "max" },
      { "model": "other", "thinking": "max" },
    ] {
    let unknown = decode_history({
      "settings": value,
      "messages": [],
      "session": { "events": [] },
      "generating": false,
    })
    assert_true(unknown.settings is None)
  }
  let state = deletion_state()
  let request = state.conversations["a"].request
  let cached = metadata_update(
    state,
    Loaded(2, "a", request, { ..history, etag: Some("settings-v1"), }),
  )
  let revalidating = cached.load("a", Some("fixture"), _ => @cmd.none).0
  let unchanged = metadata_update(
    revalidating,
    HistoryUnchanged(
      2,
      "a",
      revalidating.conversations["a"].request,
      "settings-v1",
    ),
  )
  assert_true(unchanged.conversations["a"].settings == history.settings)
  assert_eq(
    unchanged.conversations["a"].settings_request,
    revalidating.conversations["a"].request,
  )
}
