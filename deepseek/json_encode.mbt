///|
/// Keep assistant reasoning_content for Kimi K2.7 Code as per their documentation:
///
/// > Because Preserved Thinking is always on, in multi-turn conversations you
/// > must keep the `reasoning_content` of every historical assistant message in
/// > `messages` as-is.
///
/// See: https://platform.kimi.ai/docs/guide/use-kimi-k2-thinking-model#using-the-kimi-k2-7-code-model
fn ChatMessage::reasoning_json_fields(
  message : ChatMessage,
  model : Model,
) -> Array[(String, Json)] {
  match (model, message.role, message.reasoning_content) {
    (Kimi(_), Assistant, Some(reasoning)) =>
      [("reasoning_content", Json::string(reasoning))]
    _ => []
  }
}

///|
/// Encodes a `ChatMessage` for a selected chat-completions model.
///
/// Assistant messages whose `content` is empty but carry tool calls are
/// encoded with JSON `content: null`, as the API requires.
fn ChatMessage::to_json_for_model(message : ChatMessage, model : Model) -> Json {
  let content = match message.role {
    Assistant if message.tool_calls.length() > 0 && message.content == "" =>
      Json::null()
    _ => Json::string(message.content)
  }
  Json::object(
    Map(
      [
        ("role", Json::string("\{message.role}")),
        ("content", content),
        ..if message.role is Tool(tool_call_id) {
          [("tool_call_id", Json::string(tool_call_id))]
        },
        ..if message.tool_calls.length() > 0 {
          [("tool_calls", ([ for call in message.tool_calls => call ] : Json))]
        },
        ..message.reasoning_json_fields(model),
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
/// `response_format`, `tools`, and `thinking` are omitted when empty / `None`.
pub fn encode_chat_request(
  tools? : Array[ToolDefinition] = [],
  thinking? : ThinkingMode,
  stream? : Bool = false,
  response_format? : ResponseFormat,
  model? : Model = Deepseek(V4Pro),
  messages : Array[ChatMessage],
) -> Json {
  Json::object(
    Map(
      [
        ("model", Json::string(Show::to_string(model))),
        (
          "messages",
          [
            for message in messages => message.to_json_for_model(model)
          ],
        ),
        ("stream", Json::boolean(stream)),
        ..if response_format is Some(format) {
          [("response_format", ({ "type": "\{format}" } : Json))]
        },
        ..if stream {
          [("stream_options", ({ "include_usage": true } : Json))]
        },
        ..if tools.length() > 0 {
          [("tools", ([ for tool in tools => tool ] : Json))]
        },
        // Kimi K2.7 Code documentation says not to pass `thinking`.
        // https://platform.kimi.ai/docs/guide/use-kimi-k2-thinking-model#using-the-kimi-k2-7-code-model
        ..if !(model is Kimi(_)) && thinking is Some(mode) {
          match mode {
            No => [("thinking", ({ "type": "disabled" } : Json))]
            High =>
              [
                ("thinking", ({ "type": "enabled" } : Json)),
                ("reasoning_effort", Json::string("high")),
              ]
            Max =>
              [
                ("thinking", ({ "type": "enabled" } : Json)),
                ("reasoning_effort", Json::string("max")),
              ]
          }
        },
      ],
    ),
  )
}

///|
test "tool messages include tool call id" {
  let body = ChatMessage(Tool("call_123"), content="tool result")
  json_inspect(body.to_json_for_model(Deepseek(V4Pro)), content={
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
  json_inspect(body.to_json_for_model(Deepseek(V4Pro)), content={
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
test "kimi assistant messages preserve reasoning content" {
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
  json_inspect(body.to_json_for_model(Kimi(K27Code)), content={
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
    "reasoning_content": "checked available tools",
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
  json_inspect(body.to_json_for_model(Deepseek(V4Pro)), content={
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
  json_inspect(body.to_json_for_model(Deepseek(V4Pro)), content={
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
