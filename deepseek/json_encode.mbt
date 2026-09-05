///|
/// Provider-specific thinking fields for a chat-completions request.
///
/// GLM-5.3 models cannot disable thinking. Map OpenSeek's lowest setting to
/// GLM's `low` effort and preserve complete reasoning across agent tool turns.
///
/// Providers are matched by name, never by wildcard, so adding a model
/// variant fails exhaustiveness here until its thinking policy is chosen.
fn thinking_json_fields(
  model : Model,
  thinking : ThinkingMode?,
) -> Array[(String, Json)] {
  match (model, thinking) {
    (Kimi(_), _) | (Deepseek(_) | Glm(_), None) => []
    (Glm(_), Some(mode)) => {
      let effort = match mode {
        No => "low"
        High => "high"
        Max => "max"
      }
      [
        ("thinking", { "type": "enabled", "clear_thinking": false }),
        ("reasoning_effort", Json(effort)),
      ]
    }
    (Deepseek(_), Some(No)) => [("thinking", { "type": "disabled" })]
    (Deepseek(_), Some(High)) =>
      [("thinking", { "type": "enabled" }), ("reasoning_effort", "high")]
    (Deepseek(_), Some(Max)) =>
      [("thinking", { "type": "enabled" }), ("reasoning_effort", "max")]
  }
}

///|
/// Encodes a `ChatMessage` as a chat-completions `messages[]` entry.
///
/// Assistant messages whose `content` is empty but carry tool calls are
/// encoded with JSON `content: null`, as the API requires.
///
/// Assistant `reasoning_content` is always replayed: DeepSeek requires it
/// when tools are enabled and ignores it otherwise, Kimi K2.7 Code always
/// requires it, and GLM coding-agent requests use preserved thinking.
///
/// See: https://api-docs.deepseek.com/guides/thinking_mode#thinking-mode-with-tool-calls
/// See: https://platform.kimi.ai/docs/guide/use-kimi-k2-thinking-model#using-the-kimi-k2-7-code-model
impl ToJson for ChatMessage with fn to_json(message : ChatMessage) -> Json {
  let content = match message.role {
    Assistant if message.tool_calls.length() > 0 && message.content == "" =>
      Json::null()
    _ => Json(message.content)
  }
  Json(
    Map(
      [
        ("role", Json("\{message.role}")),
        ("content", content),
        ..if message.role is Tool(tool_call_id) {
          [("tool_call_id", Json(tool_call_id))]
        },
        ..if message.tool_calls.length() > 0 {
          [("tool_calls", ([ for call in message.tool_calls => call ] : Json))]
        },
        ..if message.role is Assistant &&
          message.reasoning_content is Some(reasoning) {
          [("reasoning_content", Json(reasoning))]
        },
      ],
    ),
  )
}

///|
/// Encodes a `ToolDefinition` as a DeepSeek `tools[]` entry.
impl ToJson for ToolDefinition with fn to_json(tool : ToolDefinition) -> Json {
  let function = Json(
    Map(
      [
        ("name", Json(tool.name)),
        ("description", Json(tool.description)),
        ("parameters", tool.parameters),
        ..if tool.strict {
          [("strict", Json(true))]
        },
      ],
    ),
  )
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
  Json(
    Map(
      [
        ("model", Json(Show::to_string(model))),
        ("messages", ([ for message in messages => message ] : Json)),
        ("stream", Json(stream)),
        ..if response_format is Some(format) {
          [("response_format", ({ "type": "\{format}" } : Json))]
        },
        ..if stream {
          [("stream_options", ({ "include_usage": true } : Json))]
        },
        ..if tools.length() > 0 {
          [("tools", ([ for tool in tools => tool ] : Json))]
        },
        ..thinking_json_fields(model, thinking),
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
test "assistant tool calls preserve reasoning content" {
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
    "reasoning_content": "checked available tools",
  })
}

///|
test "assistant reasoning content is always replayed" {
  let body = ChatMessage(
    Assistant,
    content="The tests pass.",
    reasoning_content="checked the test output",
  )
  json_inspect(body, content={
    "role": "assistant",
    "content": "The tests pass.",
    "reasoning_content": "checked the test output",
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
