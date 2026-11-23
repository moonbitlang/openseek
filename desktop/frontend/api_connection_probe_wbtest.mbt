///|
test "built-in API providers start a connection test with saved settings" {
  let dispatch = test_dispatch()
  for provider in [Deepseek, Glm, OpenRouter] {
    let initial = test_model().with_host_endpoint(
      provider~,
      deepseek_key_saved=true,
      glm_key_saved=true,
      openrouter_key_saved=true,
    )
    let (_, started) = update_msg(dispatch, TestApiConnection(None), initial)
    let (_, repeated) = update_msg(dispatch, TestApiConnection(None), started)
    assert_true(started == repeated)
    assert_true(
      started.current_api_connection_probe() is Some({ reply: None, .. }),
    )
    let (_, received) = update_msg(
      dispatch,
      ApiConnectionProbed(1, { error: None, }),
      started,
    )
    assert_true(
      received.current_api_connection_probe()
      is Some({ reply: Some({ error: None, }), .. }),
    )
    assert_true(received.host_settings() == initial.host_settings())
  }
}

///|
test "Custom URL uses the saved endpoint for the connection test" {
  let dispatch = test_dispatch()
  let initial = test_model().with_host_endpoint(provider=Custom)
  let (_, blocked) = update_msg(dispatch, TestApiConnection(None), initial)
  assert_true(blocked == initial)
  let configured = initial.with_host_endpoint(
    provider=Custom,
    custom_api_url="https://example.test/complete",
  )
  let (_, started) = update_msg(dispatch, TestApiConnection(None), configured)
  assert_true(
    started.current_api_connection_probe() is Some({ reply: None, .. }),
  )
  assert_true(started.host_settings() == configured.host_settings())
}

///|
test "an older API settings probe cannot replace the newest result" {
  let dispatch = test_dispatch()
  let (_, started) = update_msg(dispatch, TestApiConnection(None), test_model())
  let changed = started.with_host_settings(mirror => {
    ..mirror,
    current: mirror.current.map(settings => {
      ..settings,
      revision: settings.revision + 1,
    }),
  })
  assert_true(changed.current_api_connection_probe() is None)
  let (_, retested) = update_msg(dispatch, TestApiConnection(None), changed)
  let (_, stale) = update_msg(
    dispatch,
    ApiConnectionProbed(1, { error: None, }),
    retested,
  )
  assert_true(stale == retested)
  let (_, newest) = update_msg(
    dispatch,
    ApiConnectionProbed(2, { error: Some("The connection test timed out."), }),
    stale,
  )
  assert_true(
    newest.current_api_connection_probe()
    is Some(
      { reply: Some({ error: Some("The connection test timed out."), }), .. },
    ),
  )
}

///|
fn custom_model_status(id : String) -> @protocol.ModelStatus {
  {
    id,
    label: None,
    api_url: None,
    full_url: false,
    has_api_key: false,
    images: true,
    context_window: 1_000_000,
  }
}

///|
fn custom_api_model(entries : Array[@protocol.ModelStatus]) -> Model {
  test_model().with_host_settings(mirror => {
    let current = host_settings(
      provider="custom",
      has_custom_key=true,
      custom_api_url="https://gateway.example/v1",
      models=entries,
    )
    { ..mirror, current: Some(current), }
  })
}

///|
test "a Custom model row tests its own saved entry" {
  let dispatch = test_dispatch()
  let model = custom_api_model([
    custom_model_status("gpt-9"),
    custom_model_status("claude-9"),
  ])
  assert_true(model.api_ready())
  let (_, started) = update_msg(
    dispatch,
    TestApiConnection(Some("gpt-9")),
    model,
  )
  assert_true(
    started.current_api_connection_probe(model_id=Some("gpt-9"))
    is Some({ reply: None, payload: { model: Some("gpt-9"), .. }, .. }),
  )
  // The other row, and the provider-wide route, stay idle.
  assert_true(
    started.current_api_connection_probe(model_id=Some("claude-9")) is None,
  )
  assert_true(started.current_api_connection_probe() is None)
  // One test at a time: another row waits for this one to settle.
  let (_, blocked) = update_msg(
    dispatch,
    TestApiConnection(Some("claude-9")),
    started,
  )
  assert_true(blocked == started)
  let (_, received) = update_msg(
    dispatch,
    ApiConnectionProbed(1, { error: None, }),
    started,
  )
  assert_true(
    received.current_api_connection_probe(model_id=Some("gpt-9"))
    is Some({ reply: Some({ error: None, }), .. }),
  )
}

///|
test "a row whose entry is gone cannot start a test" {
  let dispatch = test_dispatch()
  let model = custom_api_model([custom_model_status("gpt-9")])
  let removed = model.with_host_settings(mirror => {
    let current = mirror.current.unwrap()
    { ..mirror, current: Some({ ..current, models: [], }), }
  })
  let (_, blocked) = update_msg(
    dispatch,
    TestApiConnection(Some("gpt-9")),
    removed,
  )
  assert_true(blocked == removed)
}
