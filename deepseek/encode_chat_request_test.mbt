// `encode_chat_request` builds the JSON request body sent to DeepSeek's
// chat-completions endpoint. Each test snapshots the exact body a given set of
// options produces, so the file doubles as documentation of the wire format.
// Regenerate the snapshots with `moon test --update` after changing the encoder.

///|
test "minimal request: flash model, no response_format, non-stream" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Flash)) <| [
    ChatMessage(System, content="plain text is fine"),
    ChatMessage(User, content="ping"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [
      { "role": "system", "content": "plain text is fine" },
      { "role": "user", "content": "ping" },
    ],
    "stream": false,
  })
}

///|
test "model defaults to Deepseek(V4Pro)" {
  let body = @deepseek.encode_chat_request() <| [
    ChatMessage(User, content="ping"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-pro",
    "messages": [{ "role": "user", "content": "ping" }],
    "stream": false,
  })
}

///|
test "response_format=JsonObject asks for a JSON object reply" {
  let body = @deepseek.encode_chat_request(
    model=Deepseek(V4Flash),
    response_format=JsonObject,
  ) <| [
    ChatMessage(System, content="json only"),
    ChatMessage(User, content="ping"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [
      { "role": "system", "content": "json only" },
      { "role": "user", "content": "ping" },
    ],
    "stream": false,
    "response_format": { "type": "json_object" },
  })
}

///|
test "tools are advertised as function definitions" {
  let tool = @deepseek.ToolDefinition("shell", "Run a shell command.", {
    "type": "object",
    "properties": { "cmd": { "type": "string" } },
    "required": ["cmd"],
  })
  let body = @deepseek.encode_chat_request(
    model=Deepseek(V4Flash),
    tools=[tool],
  ) <| [
    ChatMessage(User, content="run tests"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [{ "role": "user", "content": "run tests" }],
    "stream": false,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "shell",
          "description": "Run a shell command.",
          "parameters": {
            "type": "object",
            "properties": { "cmd": { "type": "string" } },
            "required": ["cmd"],
          },
        },
      },
    ],
  })
}

///|
test "stream=true requests usage-bearing streaming" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Flash), stream=true) <| [
    ChatMessage(User, content="stream this"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [{ "role": "user", "content": "stream this" }],
    "stream": true,
    "stream_options": { "include_usage": true },
  })
}

///|
test "thinking=High enables reasoning at high effort" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Pro), thinking=High) <| [
    ChatMessage(User, content="solve"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-pro",
    "messages": [{ "role": "user", "content": "solve" }],
    "stream": false,
    "thinking": { "type": "enabled" },
    "reasoning_effort": "high",
  })
}

///|
test "thinking=Max enables reasoning at max effort" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Pro), thinking=Max) <| [
    ChatMessage(User, content="solve"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-pro",
    "messages": [{ "role": "user", "content": "solve" }],
    "stream": false,
    "thinking": { "type": "enabled" },
    "reasoning_effort": "max",
  })
}

///|
test "thinking=No disables reasoning and omits reasoning_effort" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Pro), thinking=No) <| [
    ChatMessage(User, content="solve"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-pro",
    "messages": [{ "role": "user", "content": "solve" }],
    "stream": false,
    "thinking": { "type": "disabled" },
  })
}

///|
test "kimi code omits thinking and preserves assistant reasoning" {
  let call = @deepseek.ToolCall(
    id="call_42",
    name="shell",
    arguments="{\"cmd\":\"moon test\"}",
  )
  let body = @deepseek.encode_chat_request(
    model=Kimi(K27Code),
    thinking=Max,
    stream=true,
  ) <| [
    ChatMessage(User, content="run tests"),
    ChatMessage(
      Assistant,
      content="",
      tool_calls=[call],
      reasoning_content="need to validate first",
    ),
    ChatMessage(Tool("call_42"), content="exit=0\nok"),
  ]
  json_inspect(body, content={
    "model": "kimi-k2.7-code",
    "messages": [
      { "role": "user", "content": "run tests" },
      {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_42",
            "type": "function",
            "function": {
              "name": "shell",
              "arguments": "{\"cmd\":\"moon test\"}",
            },
          },
        ],
        "reasoning_content": "need to validate first",
      },
      { "role": "tool", "content": "exit=0\nok", "tool_call_id": "call_42" },
    ],
    "stream": true,
    "stream_options": { "include_usage": true },
  })
}

///|
test "kimi highspeed uses the same code-model request policy" {
  let body = @deepseek.encode_chat_request(
    model=Kimi(K27CodeHighSpeed),
    thinking=No,
  ) <| [
    ChatMessage(User, content="solve"),
  ]
  json_inspect(body, content={
    "model": "kimi-k2.7-code-highspeed",
    "messages": [{ "role": "user", "content": "solve" }],
    "stream": false,
  })
}

///|
test "deepseek tool-enabled reasoning and tool result round-trip" {
  let tool = @deepseek.ToolDefinition("shell", "Run a shell command.", {
    "type": "object",
    "properties": { "cmd": { "type": "string" } },
    "required": ["cmd"],
  })
  let call = @deepseek.ToolCall(
    id="call_42",
    name="shell",
    arguments="{\"cmd\":\"moon test\"}",
  )
  let body = @deepseek.encode_chat_request(
    model=Deepseek(V4Flash),
    tools=[tool],
  ) <| [
    ChatMessage(System, content="be terse"),
    ChatMessage(User, content="check the setup"),
    ChatMessage(
      Assistant,
      content="ready",
      reasoning_content="checked the setup",
    ),
    ChatMessage(User, content="run the tests"),
    ChatMessage(
      Assistant,
      content="",
      tool_calls=[call],
      reasoning_content="need to run the tests",
    ),
    ChatMessage(Tool("call_42"), content="exit=0\nok"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [
      { "role": "system", "content": "be terse" },
      { "role": "user", "content": "check the setup" },
      {
        "role": "assistant",
        "content": "ready",
        "reasoning_content": "checked the setup",
      },
      { "role": "user", "content": "run the tests" },
      {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_42",
            "type": "function",
            "function": {
              "name": "shell",
              "arguments": "{\"cmd\":\"moon test\"}",
            },
          },
        ],
        "reasoning_content": "need to run the tests",
      },
      { "role": "tool", "content": "exit=0\nok", "tool_call_id": "call_42" },
    ],
    "stream": false,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "shell",
          "description": "Run a shell command.",
          "parameters": {
            "type": "object",
            "properties": { "cmd": { "type": "string" } },
            "required": ["cmd"],
          },
        },
      },
    ],
  })
}

///|
test "multiple tool definitions are all encoded" {
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
    model=Deepseek(V4Flash),
    tools=[shell, read_tool],
  ) <| [
    ChatMessage(User, content="look around"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [{ "role": "user", "content": "look around" }],
    "stream": false,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "shell",
          "description": "Run a shell command.",
          "parameters": {
            "type": "object",
            "properties": { "cmd": { "type": "string" } },
            "required": ["cmd"],
          },
        },
      },
      {
        "type": "function",
        "function": {
          "name": "read",
          "description": "Read a file.",
          "parameters": {
            "type": "object",
            "properties": { "path": { "type": "string" } },
            "required": ["path"],
          },
        },
      },
    ],
  })
}
