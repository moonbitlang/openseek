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
/// The window the agent loop plans against: the launcher's number when it has
/// one, otherwise the build's table for the model.
test "client context window follows the launcher, then the model table" {
  assert_eq(@client.Client(api_key="test-key").context_window(), 1_000_000)
  assert_eq(
    @client.Client(api_key="test-key", model=Kimi(K27Code)).context_window(),
    262_144,
  )
  // A model this build does not ship, as the desktop host saves it: the entry's
  // own window travels with the run and wins over the table.
  assert_eq(
    @client.Client(
      api_key="test-key",
      model=Custom("gemini-4-hydrogen"),
    ).context_window(),
    1_000_000,
  )
  assert_eq(
    @client.Client(
      api_key="test-key",
      model=Custom("gemini-4-hydrogen"),
      context_window=131_072,
    ).context_window(),
    131_072,
  )
  assert_eq(
    @client.Client(api_key="test-key", context_window=200_000).context_window(),
    200_000,
  )
}

///|
test "client debug redacts api key" {
  let client = @client.Client(
    api_key="test-key",
    model=Deepseek(V4Pro),
    api_url="https://api.deepseek.com/chat/completions",
    thinking=Max,
    retry_attempts=3,
    retry_backoff_ms=500,
    idle_timeout_ms=120000,
  )
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
      #|  context_window: None,
      #|}
    ),
  )
}
