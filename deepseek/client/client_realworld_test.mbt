///|
async test "realworld DeepSeek API smoke test" {
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println(
      "DEEPSEEK environment variable is not set or is empty; skipping realworld API smoke test",
    )
    return
  }

  let client = @client.Client(
    api_key~,
    model=V4Pro,
    thinking=Some(Enabled),
    reasoning_effort=Some(High),
  )
  let response = client.chat(
    [
      ChatMessage(
        System,
        content=(
          #|Reply with exactly this JSON object and no markdown: {"answer":"pong"}
        ),
      ),
      ChatMessage(User, content="ping"),
    ],
    response_format=JsonObject,
  )
  // It may fail in theory, but in practice it should always work.
  debug_inspect(
    response.content,
    content=(
      #|"{\"answer\":\"pong\"}"
    ),
  )
  assert_true(response.content.contains("pong"))
  assert_true(response.usage.total_tokens > 0)
}
