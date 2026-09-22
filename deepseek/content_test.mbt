///|
test "text extraction joins all fragments while iteration preserves files" {
  let parts : Array[@deepseek.ContentPart] = [
    File(file_id="file-api-before"),
    Text("previous agent"),
    File(file_id="file-api-middle"),
    Text(" process"),
    Text(" exited"),
    File(file_id="file-api-after"),
    ImageUrl(url="data:image/png;base64,aW1hZ2U="),
  ]
  let message = @deepseek.ChatMessage(User, content=parts)
  assert_eq(message.content.text(), "previous agent process exited")
  assert_true(message.content.contains("previous agent process exited"))
  assert_false(message.content.is_text_only())
  assert_eq(message.content.iter().collect(), parts)
}

///|
test "inline image encoding preserves ordered user and tool content" {
  let url = "data:image/png;base64,aW1hZ2U="
  for role in [@deepseek.User, Tool("call-image")] {
    let message = @deepseek.ChatMessage(role, content=[
      Text("before"),
      ImageUrl(url~),
      Text("after"),
    ])
    guard @deepseek.encode_chat_request([message])
      is { "messages": [encoded], .. } else {
      fail("expected one message")
    }
    guard encoded is { "content": parts, .. } else { fail("missing content") }
    let expected : Json = [
      { "type": "text", "text": "before" },
      { "type": "image_url", "image_url": { "url": Json(url) } },
      { "type": "text", "text": "after" },
    ]
    assert_eq(parts, expected)
    if role is Tool(id) {
      assert_true(
        encoded is { "role": "tool", "tool_call_id": String(actual), .. } &&
        actual == id,
      )
    }
    assert_eq(message.content.text(), "beforeafter")
    assert_false(message.content.contains("base64"))
    assert_false(message.content.is_text_only())
  }
}

///|
test "request encoding rejects images for unsupported roles and blank URLs" {
  for role in [@deepseek.System, Assistant] {
    try
      @deepseek.encode_chat_request([
        ChatMessage(role, content=[
          ImageUrl(url="data:image/png;base64,aW1hZ2U="),
        ]),
      ])
    catch {
      ImageContentNotAllowed(actual) => assert_eq(actual, role)
      error => raise error
    } noraise {
      _ => fail("expected unsupported image role")
    }
  }
  for url in ["", " "] {
    try
      @deepseek.encode_chat_request([
        ChatMessage(User, content=[ImageUrl(url~)]),
      ])
    catch {
      EmptyImageUrl => ()
      error => raise error
    } noraise {
      _ => fail("expected blank image URL to fail")
    }
  }
}

///|
test "empty and file-only content contribute no text" {
  let empty = @deepseek.Content([])
  assert_eq(empty.text(), "")
  assert_true(empty.is_text_only())
  assert_true(empty.contains(""))
  let file_only = @deepseek.Content([File(file_id="file-api-only")])
  assert_eq(file_only.text(), "")
  assert_false(file_only.contains("previous agent process exited"))
  assert_false(file_only.is_text_only())
  assert_false(file_only.contains("file-api-only"))
  let text_only = @deepseek.Content([
    Text(""),
    Text("hello"),
    Text("\nworld"),
    Text(""),
  ])
  assert_eq(text_only.text(), "hello\nworld")
  assert_true(text_only.is_text_only())
}

///|
test "content parts preserve interleaved text and uploaded files" {
  let user = @deepseek.ChatMessage(User, content=[
    Text("first image"),
    File(file_id="file-api-one"),
    Text("compare with this"),
    File(file_id="file-api-two"),
    Text("explain the difference"),
  ])
  guard @deepseek.encode_chat_request([user]) is { "messages": [message], .. } else {
    fail("expected one encoded message")
  }
  json_inspect(message, content={
    "role": "user",
    "content": [
      { "type": "text", "text": "first image" },
      { "type": "file", "file_id": "file-api-one" },
      { "type": "text", "text": "compare with this" },
      { "type": "file", "file_id": "file-api-two" },
      { "type": "text", "text": "explain the difference" },
    ],
  })
}

///|
test "tool file content keeps its tool call identity" {
  let tool = @deepseek.ChatMessage(Tool("call-1"), content=[
    File(file_id="file-api-result"),
  ])
  guard @deepseek.encode_chat_request([tool]) is { "messages": [message], .. } else {
    fail("expected one encoded message")
  }
  json_inspect(message, content={
    "role": "tool",
    "content": [{ "type": "file", "file_id": "file-api-result" }],
    "tool_call_id": "call-1",
  })
}

///|
test "encoding chooses the wire shape from the content array" {
  guard @deepseek.encode_chat_request([
      ChatMessage(User, content=[Text("hello"), Text(" world")]),
      ChatMessage(User, content=[Text("hello")]),
    ])
    is { "messages": Array(messages), .. } else {
    fail("expected messages")
  }
  json_inspect(messages, content=[
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "hello" },
        { "type": "text", "text": " world" },
      ],
    },
    { "role": "user", "content": "hello" },
  ])
}

///|
test "system and assistant text parts are concatenated without separators" {
  for role in [@deepseek.System, Assistant] {
    let message = @deepseek.ChatMessage(role, content=[
      Text("hello"),
      Text(" world"),
    ])
    guard @deepseek.encode_chat_request([message])
      is { "messages": [{ "content": content, .. }], .. } else {
      fail("expected one message")
    }
    json_inspect(content, content="hello world")
  }
}

///|
test "empty content arrays preserve role and tool call encoding" {
  let call = @deepseek.ToolCall(id="call-1", name="read", arguments="{}")
  guard @deepseek.encode_chat_request([
      ChatMessage(System, content=[]),
      ChatMessage(User, content=[]),
      ChatMessage(Tool("call-1"), content=[]),
      ChatMessage(Assistant, content=[]),
      ChatMessage(Assistant, content=[], tool_calls=[call]),
    ])
    is { "messages": Array(messages), .. } else {
    fail("expected messages")
  }
  let contents = messages.map(message => {
    match message {
      { "content": content, .. } => content
      _ => fail("expected content")
    }
  })
  json_inspect(contents, content=["", [], [], "", null])
}

///|
test "request encoding rejects files for unsupported roles and blank file IDs" {
  for role in [@deepseek.System, Assistant] {
    let message = @deepseek.ChatMessage(role, content=[
      File(file_id="file-api-x"),
    ])
    try @deepseek.encode_chat_request([message]) catch {
      FileContentNotAllowed(actual) => assert_eq(actual, role)
      error => raise error
    } noraise {
      _ => fail("expected unsupported content role")
    }
    try
      @deepseek.openrouter_encode_chat_request(model=V4Pro, thinking=No, [
        message,
      ])
    catch {
      FileContentNotAllowed(actual) => assert_eq(actual, role)
      error => raise error
    } noraise {
      _ => fail("expected unsupported content role")
    }
  }
  for file_id in ["", " "] {
    let message = @deepseek.ChatMessage(User, content=[File(file_id~)])
    try @deepseek.encode_chat_request([message]) catch {
      EmptyFileId => ()
      error => raise error
    } noraise {
      _ => fail("expected blank file ID to fail")
    }
  }
}
