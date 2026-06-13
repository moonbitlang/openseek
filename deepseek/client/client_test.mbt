///|
test "client defaults" {
  let client = @client.Client(api_key="test-key")
  inspect(client.model, content="deepseek-v4-pro")
  assert_eq(client.api_url, "https://api.deepseek.com/chat/completions")
  assert_true(client.thinking is No)
}

///|
test "client debug redacts api key" {
  let client = @client.Client(api_key="test-key", thinking=Max)
  debug_inspect(
    client,
    content=(
      #|{
      #|  api_key: ...,
      #|  model: V4Pro,
      #|  api_url: "https://api.deepseek.com/chat/completions",
      #|  thinking: Max,
      #|  retry_attempts: 3,
      #|  retry_backoff_ms: 500,
      #|}
    ),
  )
}
