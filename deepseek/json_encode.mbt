///|
/// Keep assistant reasoning_content when the provider requires it.
///
/// DeepSeek requires every historical assistant reasoning trace to be sent
/// back when tools are enabled. Kimi K2.7 Code always requires the reasoning
/// from every historical assistant message to be preserved.
///
/// See: https://api-docs.deepseek.com/guides/thinking_mode#thinking-mode-with-tool-calls
/// See: https://platform.kimi.ai/docs/guide/use-kimi-k2-thinking-model#using-the-kimi-k2-7-code-model
fn ChatMessage::reasoning_json_fields(
  message : ChatMessage,
  model : Model,
  preserve_deepseek_reasoning : Bool,
) -> Array[(String, Json)] {
  match (model, message.role, message.reasoning_content) {
    (Deepseek(_), Assistant, Some(reasoning)) if preserve_deepseek_reasoning =>
      [("reasoning_content", Json::string(reasoning))]
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
fn ChatMessage::to_json_for_model(
  message : ChatMessage,
  model : Model,
  preserve_deepseek_reasoning? : Bool = false,
) -> Json {
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
        ..message.reasoning_json_fields(model, preserve_deepseek_reasoning),
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
            for message in messages => {
              message.to_json_for_model(
                model,
                preserve_deepseek_reasoning=tools.length() > 0,
              )
            }
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
test "deepseek assistant tool calls preserve reasoning content" {
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
  json_inspect(
    body.to_json_for_model(Deepseek(V4Pro), preserve_deepseek_reasoning=true),
    content={
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
    },
  )
}

///|
test "deepseek reasoning follows tool availability" {
  let body = ChatMessage(
    Assistant,
    content="The tests pass.",
    reasoning_content="checked the test output",
  )
  json_inspect(body.to_json_for_model(Deepseek(V4Pro)), content={
    "role": "assistant",
    "content": "The tests pass.",
  })
  json_inspect(
    body.to_json_for_model(Deepseek(V4Pro), preserve_deepseek_reasoning=true),
    content={
      "role": "assistant",
      "content": "The tests pass.",
      "reasoning_content": "checked the test output",
    },
  )
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
