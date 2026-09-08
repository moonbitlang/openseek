///|
test "OpenRouter adapts DeepSeek model and reasoning fields" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Pro), thinking=High) <| [
    ChatMessage(User, content="hello"),
  ]
  json_inspect(
    adapt_chat_request_for_endpoint(
      "https://openrouter.ai/api/v1/chat/completions",
      Deepseek(V4Pro),
      High,
      body,
    ),
    content={
      "model": "deepseek/deepseek-v4-pro",
      "messages": [{ "role": "user", "content": "hello" }],
      "stream": false,
      "reasoning": { "effort": "high" },
    },
  )
}

///|
test "non-OpenRouter custom endpoints keep DeepSeek wire format" {
  let body = @deepseek.encode_chat_request(
    model=Deepseek(V4Flash),
    thinking=Max,
  ) <| [
    ChatMessage(User, content="hello"),
  ]
  json_inspect(
    adapt_chat_request_for_endpoint(
      "https://proxy.example/v1/chat/completions",
      Deepseek(V4Flash),
      Max,
      body,
    ),
    content={
      "model": "deepseek-v4-flash",
      "messages": [{ "role": "user", "content": "hello" }],
      "stream": false,
      "thinking": { "type": "enabled" },
      "reasoning_effort": "max",
    },
  )
}
