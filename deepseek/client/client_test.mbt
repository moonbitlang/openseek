///|
test "client defaults" {
  let client = @client.Client(api_key="test-key")
  inspect(client.model, content="deepseek-v4-pro")
  assert_eq(client.api_url, "https://api.deepseek.com/chat/completions")
  assert_true(client.thinking is No)
}

///|
test "client endpoint defaults follow selected model" {
  let kimi = @client.Client(api_key="test-key", model=Kimi(K27Code))
  assert_eq(kimi.api_url, "https://api.moonshot.cn/v1/chat/completions")
  let glm = @client.Client(api_key="test-key", model=Glm(G53))
  assert_eq(glm.api_url, "https://api.z.ai/api/paas/v4/chat/completions")
  let proxied = @client.Client(
    api_key="test-key",
    model=Kimi(K27CodeHighSpeed),
    api_url="https://proxy.example/v1/chat/completions",
  )
  assert_eq(proxied.api_url, "https://proxy.example/v1/chat/completions")
}

///|
test "client debug redacts api key" {
  let client = @client.Client(api_key="test-key", thinking=Max)
  debug_inspect(
    client,
    content=(
      #|{
      #|  api_key: ...,
      #|  model: Deepseek(V4Pro),
      #|  api_url: "https://api.deepseek.com/chat/completions",
      #|  thinking: Max,
      #|  retry_attempts: 3,
      #|  retry_backoff_ms: 500,
      #|  idle_timeout_ms: 120000,
      #|}
    ),
  )
}
