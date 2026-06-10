///|
test "encode_chat_request omits response format by default" {
  let body = @deepseek.encode_chat_request(V4Flash, [
    ChatMessage(System, content="plain text is fine"),
    ChatMessage(User, content="ping"),
  ])
  let text = body.stringify()
  assert_true(text.contains("\"stream\":false"))
  assert_false(text.contains("\"response_format\""))
}

///|
test "encode_chat_request can ask for json output explicitly" {
  let body = @deepseek.encode_chat_request(
    V4Flash,
    [
      ChatMessage(System, content="json only"),
      ChatMessage(User, content="ping"),
    ],
    response_format=JsonObject,
  )
  guard body is { "response_format": { "type": String("json_object"), .. }, .. } else {
    fail("wrong response_format")
  }
}

///|
test "encode_chat_request includes tools when present" {
  let tool = @deepseek.ToolDefinition("shell", "Run a shell command.", {
    "type": "object",
    "properties": { "cmd": { "type": "string" } },
    "required": ["cmd"],
  })
  let body = @deepseek.encode_chat_request(
    V4Flash,
    [ChatMessage(User, content="run tests")],
    tools=[tool],
  )
  let text = body.stringify()
  assert_true(text.contains("\"model\":\"deepseek-v4-flash\""))
  assert_true(text.contains("\"messages\""))
  assert_true(text.contains("\"tools\""))
  assert_true(text.contains("\"type\":\"function\""))
  assert_true(text.contains("\"name\":\"shell\""))
  assert_true(text.contains("\"required\""))
}

///|
test "encode_chat_request encodes thinking controls" {
  let body = @deepseek.encode_chat_request(
    V4Pro,
    [ChatMessage(User, content="solve")],
    thinking=Enabled,
    reasoning_effort=Max,
  )
  let text = body.stringify()
  assert_true(text.contains("\"thinking\""))
  assert_true(text.contains("\"type\":\"enabled\""))
  assert_true(text.contains("\"reasoning_effort\":\"max\""))
}

///|
test "encode_chat_request omits tools, thinking, and reasoning_effort when absent" {
  let body = @deepseek.encode_chat_request(V4Flash, [
    ChatMessage(User, content="hi"),
  ])
  let text = body.stringify()
  assert_false(text.contains("\"tools\""))
  assert_false(text.contains("\"thinking\""))
  assert_false(text.contains("\"reasoning_effort\""))
}

///|
test "encode_chat_request rounds-trips assistant tool call echo and tool result" {
  let call = @deepseek.ToolCall(
    id="call_42",
    name="shell",
    arguments="{\"cmd\":\"moon test\"}",
  )
  let body = @deepseek.encode_chat_request(V4Flash, [
    ChatMessage(System, content="be terse"),
    ChatMessage(User, content="run the tests"),
    ChatMessage(Assistant, content="", tool_calls=[call]),
    ChatMessage(Tool("call_42"), content="exit=0\nok"),
  ])
  let text = body.stringify()
  assert_true(text.contains("\"role\":\"system\""))
  assert_true(text.contains("\"role\":\"user\""))
  assert_true(text.contains("\"role\":\"assistant\""))
  assert_true(text.contains("\"role\":\"tool\""))
  assert_true(text.contains("\"content\":null"))
  assert_true(text.contains("\"tool_call_id\":\"call_42\""))
  assert_true(
    text.contains("\"arguments\":\"{\\\"cmd\\\":\\\"moon test\\\"}\""),
  )
}

///|
test "encode_chat_request encodes multiple tool definitions" {
  let shell = @deepseek.ToolDefinition("shell", "Run a shell command.", {
    "type": "object",
    "properties": { "cmd": { "type": "string" } },
    "required": ["cmd"],
  })
  let read_tool = @deepseek.ToolDefinition("read", "Read a file.", {
    "type": "object",
    "properties": { "path": { "type": "string" } },
    "required": ["path"],
  })
  let body = @deepseek.encode_chat_request(
    V4Flash,
    [ChatMessage(User, content="look around")],
    tools=[shell, read_tool],
  )
  let text = body.stringify()
  assert_true(text.contains("\"name\":\"shell\""))
  assert_true(text.contains("\"name\":\"read\""))
}
