///|
/// Encodes a `ChatMessage` as the DeepSeek chat completions wire object.
///
/// Assistant messages whose `content` is empty but carry tool calls are
/// encoded with JSON `content: null`, as the API requires.
///
/// `reasoning_content` is deliberately never encoded: it is response-side
/// data the model does not read back (DeepSeek's docs say not to return it),
/// and resending it grows every request — a real 156-step run accumulated
/// 64KB of dead reasoning, 11% of its final 141K-token context. Sessions
/// still store it for the TUI transcript and the visualizer.
impl ToJson for ChatMessage with fn to_json(message : ChatMessage) -> Json {
  let content = match message.role {
    Assistant if message.tool_calls.length() > 0 && message.content == "" =>
      Json::null()
    _ => Json::string(message.content)
  }
  Json::object(
    Map(
      [
        ("role", Json::string(message.role.to_string())),
        ("content", content),
        ..match message.role {
          Tool(tool_call_id) => [("tool_call_id", Json::string(tool_call_id))]
          _ => []
        },
        ..if message.tool_calls.length() > 0 {
          [("tool_calls", ([ for call in message.tool_calls => call ] : Json))]
        } else {
          []
        },
      ],
    ),
  )
}

///|
/// Encodes a `ToolDefinition` as a DeepSeek `tools[]` entry.
impl ToJson for ToolDefinition with fn to_json(tool : ToolDefinition) -> Json {
  let function : Json = if tool.strict {
    {
      "name": tool.name,
      "description": tool.description,
      "parameters": tool.parameters,
      "strict": true,
    }
  } else {
    {
      "name": tool.name,
      "description": tool.description,
      "parameters": tool.parameters,
    }
  }
  { "type": "function", "function": function }
}

///|
/// Encodes a `ToolCall` as the DeepSeek assistant `tool_calls[]` entry.
impl ToJson for ToolCall with fn to_json(call : ToolCall) -> Json {
  {
    "id": call.id,
    "type": "function",
    "function": { "name": call.name, "arguments": call.arguments },
  }
}

///|
/// Encodes a DeepSeek chat completions request body.
///
/// `response_format`, `tools`, `thinking`, and `reasoning_effort` are omitted
/// when empty / `None`.
pub fn encode_chat_request(
  model : Model,
  messages : Array[ChatMessage],
  tools? : Array[ToolDefinition] = [],
  thinking? : ThinkingMode,
  reasoning_effort? : ReasoningEffort,
  stream? : Bool = false,
  response_format? : ResponseFormat,
) -> Json {
  Json::object(
    Map(
      [
        ("model", Json::string(model.to_string())),
        ("messages", ([ for message in messages => message ] : Json)),
        ("stream", Json::boolean(stream)),
        ..match response_format {
          Some(format) =>
            [("response_format", ({ "type": format.to_string() } : Json))]
          None => []
        },
        ..if stream {
          [("stream_options", ({ "include_usage": true } : Json))]
        } else {
          []
        },
        ..if tools.length() > 0 {
          [("tools", ([ for tool in tools => tool ] : Json))]
        } else {
          []
        },
        ..match thinking {
          Some(thinking) =>
            [("thinking", ({ "type": thinking.to_string() } : Json))]
          None => []
        },
        ..match reasoning_effort {
          Some(reasoning_effort) =>
            [("reasoning_effort", Json::string(reasoning_effort.to_string()))]
          None => []
        },
      ],
    ),
  )
}

///|
test "tool messages include tool call id" {
  let body = ChatMessage(Tool("call_123"), content="tool result")
  json_inspect(body, content={
    "role": "tool",
    "content": "tool result",
    "tool_call_id": "call_123",
  })
}

///|
test "tool definitions encode as native DeepSeek tools" {
  let tool = ToolDefinition(
    "get_weather",
    "Get weather for a location.",
    {
      "type": "object",
      "properties": { "location": { "type": "string" } },
      "required": ["location"],
    },
    strict=true,
  )
  json_inspect(tool, content={
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get weather for a location.",
      "parameters": {
        "type": "object",
        "properties": { "location": { "type": "string" } },
        "required": ["location"],
      },
      "strict": true,
    },
  })
}

///|
test "assistant tool call messages encode tool_calls, never reasoning" {
  // reasoning_content is response-side data: it must not reach the wire even
  // when the in-memory message carries it (see the codec doc comment).
  let body = ChatMessage(
    Assistant,
    content="",
    tool_calls=[
      ToolCall(
        id="call_123",
        name="get_weather",
        arguments="{\"location\":\"Hangzhou\"}",
      ),
    ],
    reasoning_content="checked available tools",
  )
  json_inspect(body, content={
    "role": "assistant",
    "content": null,
    "tool_calls": [
      {
        "id": "call_123",
        "type": "function",
        "function": {
          "name": "get_weather",
          "arguments": "{\"location\":\"Hangzhou\"}",
        },
      },
    ],
  })
}

///|
test "assistant tool call messages preserve content when present" {
  let body = ChatMessage(Assistant, content="I will check that now.", tool_calls=[
    ToolCall(
      id="call_123",
      name="get_weather",
      arguments="{\"location\":\"Hangzhou\"}",
    ),
  ])
  json_inspect(body, content={
    "role": "assistant",
    "content": "I will check that now.",
    "tool_calls": [
      {
        "id": "call_123",
        "type": "function",
        "function": {
          "name": "get_weather",
          "arguments": "{\"location\":\"Hangzhou\"}",
        },
      },
    ],
  })
}

///|
test "tool call arguments pass through as opaque strings" {
  let call = ToolCall(
    id="call_1",
    name="write",
    arguments="not even valid json{",
  )
  let body = ChatMessage(Assistant, content="", tool_calls=[call])
  json_inspect(body, content={
    "role": "assistant",
    "content": null,
    "tool_calls": [
      {
        "id": "call_1",
        "type": "function",
        "function": { "name": "write", "arguments": "not even valid json{" },
      },
    ],
  })
}
