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
test "each Custom model row tests its own saved entry one at a time" {
  let dispatch = test_dispatch()
  let model = test_model().with_host_settings(mirror => {
    let current = host_settings(
      provider="custom",
      has_custom_key=true,
      custom_api_url="https://gateway.example/v1",
      models=[
        {
          id: "gpt-9",
          label: None,
          context_window: @protocol.DefaultCustomModelContextWindow,
        },
        {
          id: "claude-9",
          label: None,
          context_window: @protocol.DefaultCustomModelContextWindow,
        },
      ],
    )
    { ..mirror, current: Some(current), }
  })
  let (_, started) = update_msg(
    dispatch,
    TestApiConnection(Some("gpt-9")),
    model,
  )
  assert_true(
    started.current_api_connection_probe(model_id=Some("gpt-9"))
    is Some({ reply: None, payload: { model: Some("gpt-9"), .. }, .. }),
  )
  assert_true(
    started.current_api_connection_probe(model_id=Some("claude-9")) is None,
  )
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
  // An unsaved model id cannot start a probe.
  let (_, unknown) = update_msg(
    dispatch,
    TestApiConnection(Some("gone")),
    received,
  )
  assert_true(unknown == received)
}
