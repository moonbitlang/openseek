///|
test "OpenRouter encodes DeepSeek models and reasoning fields" {
  for
    (model, model_id) in [
      (@deepseek.Deepseek(V4Pro), "deepseek/deepseek-v4-pro"),
      (Deepseek(V4Flash), "deepseek/deepseek-v4-flash-0731"),
      (Deepseek(V41Flash), "deepseek/deepseek-v4.1-flash"),
    ] {
    for
      (thinking, effort) in [
        (@deepseek.No, "none"),
        (High, "high"),
        (Max, "max"),
      ] {
      let expected : Json = {
        "model": model_id,
        "messages": [{ "role": "user", "content": "hello" }],
        "stream": false,
        "reasoning": { "effort": effort },
      }
      assert_eq(
        encode_chat_request_for_endpoint(
          api_url="https://openrouter.ai/api/v1/chat/completions",
          model~,
          thinking~,
          tools=[],
          stream=false,
          [ChatMessage(User, content="hello")],
        ),
        expected,
      )
    }
  }
}
