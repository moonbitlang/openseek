///|
test "client defaults" {
  let client = @client.Client(api_key="test-key")
  inspect(client.model, content="deepseek-v4-pro")
  assert_eq(client.api_url, "https://api.deepseek.com/chat/completions")
}

///|
test "client debug redacts api key" {
  let client = @client.Client(
    api_key="test-key",
    thinking=Some(Enabled),
    reasoning_effort=Some(Max),
  )
  debug_inspect(
    client,
    content=(
      #|{
      #|  api_key: ...,
      #|  model: V4Pro,
      #|  api_url: "https://api.deepseek.com/chat/completions",
      #|  response_format: Text,
      #|  thinking: Some(Enabled),
      #|  reasoning_effort: Some(Max),
      #|}
    ),
  )
}
