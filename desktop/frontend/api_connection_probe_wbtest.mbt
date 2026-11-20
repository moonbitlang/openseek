///|
test "built-in API providers start a probe without a temporary model ID" {
  let dispatch = test_dispatch()
  for provider in [Deepseek, Glm, OpenRouter] {
    let initial = test_model().with_host_endpoint(
      provider~,
      deepseek_key_saved=true,
      glm_key_saved=true,
      openrouter_key_saved=true,
    )
    let (_, started) = update_msg(dispatch, TestApiConnection, initial)
    let (_, repeated) = update_msg(dispatch, TestApiConnection, initial)
    assert_true(started == repeated)
    assert_true(
      started.current_api_connection_probe()
      is Some({ payload: { custom_model_id: None, .. }, reply: None, .. }),
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
test "Custom URL tests a temporary model ID with the saved provider settings" {
  let dispatch = test_dispatch()
  let initial = test_model().with_host_endpoint(
    provider=Custom,
    custom_api_url="https://example.test/complete",
  )
  let (_, blocked) = update_msg(dispatch, TestApiConnection, initial)
  assert_true(blocked == initial)
  let (_, typed) = update_msg(
    dispatch,
    ApiProbeModelChanged("  third-party/model  "),
    initial,
  )
  let (_, started) = update_msg(dispatch, TestApiConnection, typed)
  assert_true(
    started.current_api_connection_probe()
    is Some(
      {
        payload: { custom_model_id: Some("third-party/model"), .. },
        reply: None,
        ..
      },
    ),
  )
  assert_true(started.host_settings() == initial.host_settings())
}

///|
test "an older API settings probe cannot replace the newest result" {
  let dispatch = test_dispatch()
  let (_, started) = update_msg(dispatch, TestApiConnection, test_model())
  let changed = started.with_host_settings(mirror => {
    ..mirror,
    current: mirror.current.map(settings => {
      ..settings,
      revision: settings.revision + 1,
    }),
  })
  assert_true(changed.current_api_connection_probe() is None)
  let (_, retested) = update_msg(dispatch, TestApiConnection, changed)
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
