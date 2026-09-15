///|
test "web_search_api_key reuses the DeepSeek key only for official-endpoint runs" {
  let matches = run_matches(argv=["task"], env={ "DEEPSEEK": " dk " })
  // DeepSeek model on the official endpoint: reuse the turn's key.
  assert_eq(
    web_search_api_key(Deepseek(V4Pro), "turn-key", None, matches),
    Some("turn-key"),
  )
  // A custom chat endpoint disables the tool regardless of provider: the key
  // in hand (and the desktop-exported $DEEPSEEK) may be a gateway credential
  // that must not reach the official search endpoint.
  assert_true(
    web_search_api_key(
      Deepseek(V4Pro),
      "gateway-token",
      Some("https://gateway.example/v1"),
      matches,
    )
    is None,
  )
  assert_true(
    web_search_api_key(
      Kimi(K27Code),
      "kimi-key",
      Some("https://gateway.example/v1"),
      matches,
    )
    is None,
  )
  // A Kimi run falls back to the dedicated $DEEPSEEK credential, trimmed.
  assert_eq(
    web_search_api_key(Kimi(K27Code), "kimi-key", None, matches),
    Some("dk"),
  )
  // Without any DeepSeek credential the tool is simply not registered.
  let keyless = run_matches(argv=["task"], env=Map([]))
  assert_true(
    web_search_api_key(Kimi(K27Code), "kimi-key", None, keyless) is None,
  )
}
