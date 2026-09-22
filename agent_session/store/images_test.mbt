///|
async test "resumed inline images are sent directly in user and tool content" {
  let bytes = @fs.read_file("deepseek/client/testdata/two-colors.png").binary()
  let image = @agent_session.Image::from_bytes(bytes)
  let original = @agent_session.Session(
      SessionId("images"),
      system_prompt="system",
    )
    .append(
      User(
        UserMessage(
          Content([Text("before"), Image(image), Text("after"), Image(image)]),
        ),
      ),
    )
    .append(
      Assistant(
        AssistantMessage(
          "",
          tool_calls=[ToolCall(id="call", name="read_image", arguments="{}")],
          reasoning_content="reason",
        ),
      ),
    )
    .append(
      Tool(
        ToolResult(tool_call_id="call", tool_name="read_image", content=[
          Image(image),
        ]),
      ),
    )
  let event_json = original.events().iter().map(event => Json(event)).to_array()
  let mut resumed = @agent_session.Session(
    SessionId("resumed"),
    system_prompt="system",
  )
  for json in event_json {
    let event : @agent_session.SessionEvent = @json.from_json(json)
    resumed = resumed.append(event.item())
  }
  let messages = resumed.chat_messages()
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    let chats : Array[Json] = []
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, body, connection) => {
        let data = body.read_all()
        assert_eq(request.path, "/chat/completions")
        chats.push(@json.parse(data.text()))
        connection.send_response(200, "OK")
        connection.write(
          (
            {
              "choices": [
                {
                  "message": { "role": "assistant", "content": "seen" },
                  "finish_reason": "stop",
                },
              ],
              "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 1,
                "total_tokens": 11,
              },
            } : Json).stringify(),
        )
      })
    }
    let client = @client.Client(
      api_key="test",
      api_url="http://127.0.0.1:\{server.addr.port()}/chat/completions",
    )
    let url = image.data_url()
    assert_eq(messages[1].content.text(), "beforeafter")
    assert_true(
      messages[1].content.0
      is [
        Text("before"),
        ImageUrl(url=first),
        Text("after"),
        ImageUrl(url=second),
      ] &&
      first == url &&
      second == url,
    )
    assert_eq(messages[2].reasoning_content, Some("reason"))
    assert_true(
      messages[3].content.0 is [ImageUrl(url=actual)] && actual == url,
    )
    let response = client.chat(messages)
    assert_eq(response.content, "seen")
    assert_eq(chats.length(), 1)
    guard chats[0] is { "messages": Array(sent), .. } else {
      fail("missing model messages")
    }
    assert_true(
      sent[3]
      is {
        "role": "tool",
        "tool_call_id": "call",
        "content": [
          {
            "type": "image_url",
            "image_url": { "url": String(actual), .. },
            ..
          },
        ],
        ..
      } &&
      actual == url,
    )
    assert_true(
      messages[1].content.0[1] is ImageUrl(url=actual) && actual == url,
    )
    assert_eq(
      resumed.events().iter().map(event => Json(event)).to_array(),
      event_json,
    )
  }
}
