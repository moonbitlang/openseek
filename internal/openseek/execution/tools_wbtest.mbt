///|
test "web_search_api_key reuses the DeepSeek key only for official-endpoint runs" {
  let official = None
  let gateway = Some("https://gateway.example/v1")
  // DeepSeek model on the official endpoint: reuse the turn's key.
  assert_eq(
    web_search_api_key(Deepseek(V4Pro), "turn-key", official, Some("dk")),
    Some("turn-key"),
  )
  // A custom chat endpoint disables the tool regardless of provider: the key
  // in hand (and the desktop-exported $DEEPSEEK) may be a gateway credential
  // that must not reach the official search endpoint.
  assert_true(
    web_search_api_key(Deepseek(V4Pro), "gateway-token", gateway, Some("dk"))
    is None,
  )
  assert_true(
    web_search_api_key(Kimi(K27Code), "kimi-key", gateway, Some("dk")) is None,
  )
  // A Kimi run falls back to the dedicated $DEEPSEEK credential.
  assert_eq(
    web_search_api_key(Kimi(K27Code), "kimi-key", official, Some("dk")),
    Some("dk"),
  )
  // Without any DeepSeek credential the tool is simply not registered.
  assert_true(
    web_search_api_key(Kimi(K27Code), "kimi-key", official, None) is None,
  )
}
