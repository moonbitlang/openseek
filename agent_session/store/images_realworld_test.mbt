///|
/// Verify the production session-to-provider encoder against the real API.
/// Expected colors appear only in the assertion, never in the request.
async test "realworld inline user and tool images are recognized" {
  let image = @agent_session.Image::from_bytes(
    @fs.read_file("deepseek/client/testdata/two-colors.png").binary(),
  )
  guard @env.get_env_var("DEEPSEEK") is Some(api_key) && api_key != "" else {
    println("DEEPSEEK is not set; skipping realworld inline image recognition")
    return
  }
  let client = @client.Client(
    api_key~,
    model=Deepseek(V4Flash),
    thinking=No,
    retry_attempts=1,
  )
  let prompt = "Identify the solid color of each half of this image. Reply only with a JSON object with keys left and right, using one lowercase English color name for each."
  let histories : Array[Array[@deepseek.ChatMessage]] = [
    [
      ChatMessage(
        User,
        content=@agent_session.to_deepseek_parts(
          Content([Text(prompt), Image(image)]),
        ),
      ),
    ],
    [
      ChatMessage(User, content=[Text(prompt)]),
      ChatMessage(Assistant, content=[], tool_calls=[
        ToolCall(id="call-image", name="read_image", arguments="{}"),
      ]),
      ChatMessage(
        Tool("call-image"),
        content=@agent_session.to_deepseek_parts(Content([Image(image)])),
      ),
    ],
  ]
  @async.with_timeout(120_000, () => {
    for history in histories {
      let response = client.chat(history, response_format=JsonObject)
      let answer = @json.parse(response.content)
      assert_true(answer is { "left": "blue", "right": "yellow", .. })
      assert_true(response.usage.total_tokens > 0)
    }
  })
}
