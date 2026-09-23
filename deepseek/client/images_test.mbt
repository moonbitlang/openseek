///|
async test "chat rejects unsupported image roles and providers before network IO" {
  let client = @client.Client(
    api_key="test",
    api_url="http://127.0.0.1:1/chat/completions",
  )
  let valid = @deepseek.ChatMessage(User, content=[
    ImageUrl(url="https://example.com/image.png"),
  ])
  try
    client.chat([
      valid,
      ChatMessage(Assistant, content=[
        ImageUrl(url="https://example.com/image.png"),
      ]),
    ])
  catch {
    @deepseek.ImageContentNotAllowed(Assistant) => ()
    error => raise error
  } noraise {
    _ => fail("assistant image accepted")
  }
  for
    provider in [
      @client.Client(api_key="test", model=Kimi(K27Code)),
      Client(api_key="test", model=Glm(G53)),
      Client(
        api_key="test",
        api_url="https://openrouter.ai/api/v1/chat/completions",
      ),
    ] {
    try provider.chat([valid]) catch {
      @client.UnsupportedProvider => ()
      error => raise error
    } noraise {
      _ => fail("unsupported provider accepted")
    }
  }
}
