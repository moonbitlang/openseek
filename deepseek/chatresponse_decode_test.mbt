///|
fn decode_chat_response(text : String) -> @deepseek.ChatResponse raise {
  @json.from_json(@json.parse(text))
}

///|
test "chat response decode keeps first choice and usage" {
  let response = decode_chat_response(
    (
      #|{"id":"resp_1","choices":[{"index":0,"message":{"role":"assistant","content":"first","reasoning_content":null,"tool_calls":null}},{"index":1,"message":{"content":"second"}}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5},"ignored":true}
    ),
  )
  debug_inspect(
    response,
    content=(
      #|{
      #|  content: "first",
      #|  reasoning_content: "",
      #|  tool_calls: [],
      #|  usage: {
      #|    prompt_tokens: 2,
      #|    completion_tokens: 3,
      #|    total_tokens: 5,
      #|    prompt_cache_hit_tokens: 0,
      #|    prompt_cache_miss_tokens: 0,
      #|  },
      #|}
    ),
  )
}

///|
test "chat response decode allows tool call without content or usage" {
  let response = decode_chat_response(
    (
      #|{"choices":[{"message":{"tool_calls":[{"id":"call_1","type":"function","function":{"name":"read","arguments":"{\"path\":\"moon.mod\"}"}}]}}]}
    ),
  )
  debug_inspect(
    response,
    content=(
      #|{
      #|  content: "",
      #|  reasoning_content: "",
      #|  tool_calls: [{ id: "call_1", name: "read", arguments: "{\"path\":\"moon.mod\"}" }],
      #|  usage: {
      #|    prompt_tokens: 0,
      #|    completion_tokens: 0,
      #|    total_tokens: 0,
      #|    prompt_cache_hit_tokens: 0,
      #|    prompt_cache_miss_tokens: 0,
      #|  },
      #|}
    ),
  )
}

///|
test "chat response decode rejects present null usage" {
  try
    decode_chat_response(
      (
        #|{"choices":[{"message":{"content":"ok"}}],"usage":null}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    Key(Root, key="usage"),
          #|    "Usage::from_json: expected object with numeric fields",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected present null usage to fail")
  }
}

///|
test "chat response decode keeps multiple tool calls in order" {
  let response = decode_chat_response(
    (
      #|{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"read","arguments":"{\"path\":\"moon.mod\"}"}},{"id":"call_2","type":"function","function":{"name":"shell","arguments":"{\"cmd\":\"moon test deepseek\"}"}}]}}]}
    ),
  )
  debug_inspect(
    response,
    content=(
      #|{
      #|  content: "",
      #|  reasoning_content: "",
      #|  tool_calls: [
      #|    { id: "call_1", name: "read", arguments: "{\"path\":\"moon.mod\"}" },
      #|    {
      #|      id: "call_2",
      #|      name: "shell",
      #|      arguments: "{\"cmd\":\"moon test deepseek\"}",
      #|    },
      #|  ],
      #|  usage: {
      #|    prompt_tokens: 0,
      #|    completion_tokens: 0,
      #|    total_tokens: 0,
      #|    prompt_cache_hit_tokens: 0,
      #|    prompt_cache_miss_tokens: 0,
      #|  },
      #|}
    ),
  )
}

///|
test "chat response decode rejects missing content without tool calls" {
  try
    decode_chat_response(
      (
        #|{"choices":[{"message":{"role":"assistant"}}]}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    Key(
          #|      Key(Index(Key(Root, key="choices"), index=0), key="message"),
          #|      key="content",
          #|    ),
          #|    "ChatResponse::from_json: expected message content",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected decode to fail")
  }
}

///|
test "chat response decode rejects malformed content" {
  try
    decode_chat_response(
      (
        #|{"choices":[{"message":{"content":1}}]}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    Key(
          #|      Key(Index(Key(Root, key="choices"), index=0), key="message"),
          #|      key="content",
          #|    ),
          #|    "ChatResponse::from_json: expected message content",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected decode to fail")
  }
}

///|
test "chat response decode rejects malformed reasoning_content" {
  try
    decode_chat_response(
      (
        #|{"choices":[{"message":{"content":"ok","reasoning_content":1}}]}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    Key(
          #|      Key(Index(Key(Root, key="choices"), index=0), key="message"),
          #|      key="reasoning_content",
          #|    ),
          #|    "ChatResponse::from_json: expected reasoning_content string",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected decode to fail")
  }
}

///|
test "chat response accepts OpenRouter reasoning alias" {
  let response : @deepseek.ChatResponse = @json.from_json(
    @json.parse(
      (
        #|{"choices":[{"message":{"role":"assistant","content":"done","reasoning":"checked the workspace"}}]}
      ),
    ),
  )
  assert_eq(response.content, "done")
  assert_eq(response.reasoning_content, "checked the workspace")
}

///|
test "chat response decode rejects malformed tool_calls" {
  try
    decode_chat_response(
      (
        #|{"choices":[{"message":{"content":"ok","tool_calls":{}}}]}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    Key(
          #|      Key(Index(Key(Root, key="choices"), index=0), key="message"),
          #|      key="tool_calls",
          #|    ),
          #|    "ChatResponse::from_json: expected tool_calls array",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected decode to fail")
  }
}

///|
test "chat response decode rejects malformed nested tool call" {
  try
    decode_chat_response(
      (
        #|{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"read","arguments":{}}}]}}]}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError(
          #|  (
          #|    Key(
          #|      Key(
          #|        Index(
          #|          Key(
          #|            Key(Index(Key(Root, key="choices"), index=0), key="message"),
          #|            key="tool_calls",
          #|          ),
          #|          index=0,
          #|        ),
          #|        key="function",
          #|      ),
          #|      key="arguments",
          #|    ),
          #|    "ToolCall::from_json: expected function.arguments",
          #|  ),
          #|)
        ),
      )
  } noraise {
    _ => fail("expected decode to fail")
  }
}

///|
test "chat response decode rejects malformed choices" {
  try
    decode_chat_response(
      (
        #|{"choices":[]}
      ),
    )
  catch {
    e =>
      debug_inspect(
        e,
        content=(
          #|JsonDecodeError((Key(Root, key="choices"), "ChatResponse::from_json: empty choices"))
        ),
      )
  } noraise {
    _ => fail("expected decode to fail")
  }
}
