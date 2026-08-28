# DeepSeek Chat Data

This pure package provides strongly typed DeepSeek chat data and JSON
encoding/decoding. Use it when constructing requests, parsing responses, or
testing compatible chat behavior without network access. The typed model list
also covers Kimi K2.7 Code and Z.AI GLM 5.3 models where their request policies
differ from DeepSeek's.

The HTTP client lives in `bobzhang/openseek/deepseek/client`.

## API Shape

- `Model`: provider-tagged chat models, e.g. `Deepseek(V4Pro)`,
  `Kimi(K27Code)`, and `Glm(G53)`, with `Show` for wire strings and `Debug` for
  inspection.
- `Model::api_key(matches)`: resolves the key a command main should send for
  this model — an explicit `--api-key` first, then the provider-specific
  option (`--deepseek-api-key` / `--kimi-api-key` / `--glm-api-key`, which the
  command tables back with `DEEPSEEK` / `KIMI` / `GLM`), and `None` when
  neither is set. It is the
  shared answer to *where a key may come from*; whether a missing one is fatal,
  and what to say about it, is left to each command main. This is the one place
  in the package that reads parsed CLI options, and it lives here because the
  model tag is what decides which provider a key belongs to.
- `ThinkingMode`: typed thinking control (`No`, `High`, or `Max`), translated
  to each provider's supported request policy.
- `Role`: `System`, `User`, `Assistant`, and `Tool(tool_call_id)`, with `Show`
  for wire strings and `Debug` for inspection.
- `ChatMessage(role, content=..., tool_calls?, reasoning_content?)`: one typed
  chat message constructor. Use `Assistant` with `tool_calls` for the assistant
  message that must be sent back after DeepSeek requests native tool calls.
- `ResponseFormat`: optional assistant content constraint. Leave absent for
  normal text; pass `JsonObject` only when the assistant content must be a JSON
  object.
- `encode_chat_request(tools?, thinking?, stream?, response_format?,
  model?=Deepseek(V4Pro)) <| messages`: builds the full DeepSeek chat completions request
  body. Streaming requests include usage-bearing stream options. Kimi K2.7 Code
  requests omit DeepSeek-specific thinking fields and preserve assistant
  `reasoning_content`. GLM requests keep reasoning across tool turns and map
  `No` to GLM's supported `low` effort. The per-value
  encoders for messages, tool definitions, and tool calls are package-private
  implementation details.
- `ToolDefinition(name, description, parameters, strict?)`: a native DeepSeek
  function tool definition with a JSON Schema parameters object.
- `ToolCall(id~, name~, arguments~)`: a decoded function call request from the
  model; `arguments` is the raw JSON string from the API.
- `Usage` and `ChatResponse`: decoded response values with `Debug`; responses
  include `reasoning_content` and `tool_calls`. `ChatResponse` implements
  `FromJson` for DeepSeek chat completions response envelopes.

## Architecture Diagrams

The root `deepseek` package is pure data plus JSON encoding/decoding. The
effectful HTTP transport lives one package down in `deepseek/client`.

```mermaid
flowchart LR
  app["agent / tests"] --> root["deepseek\nmodels, messages, tools, JSON"]
  session["agent_session\nchat projection"] --> root
  client["deepseek/client\nHTTP, retries, SSE"] --> root
  client --> api["DeepSeek / Kimi / Z.AI GLM chat API"]
```

The core API is a set of public data types around chat request and response
shapes. In this diagram, `+` marks public fields or constructors, and tagged
unions correspond to MoonBit enum constructors.

```mermaid
classDiagram
  direction LR

  class Model {
    <<tagged union>>
    Deepseek(DsVariant)
    Kimi(KimiVariant)
    Glm(GlmVariant)
    +parse(String) Model
  }

  class DsVariant {
    <<enumeration>>
    V4Flash
    V4Pro
  }

  class KimiVariant {
    <<enumeration>>
    K27Code
    K27CodeHighSpeed
  }

  class GlmVariant {
    <<enumeration>>
    G53
    G53Flash
  }

  Model --> DsVariant
  Model --> KimiVariant
  Model --> GlmVariant

  class ThinkingMode {
    <<enumeration>>
    No
    High
    Max
    +parse(String) ThinkingMode
  }

  class ResponseFormat {
    <<enumeration>>
    JsonObject
  }

  class Role {
    <<tagged union>>
    System
    User
    Assistant
    Tool(String)
  }

  class ChatMessage {
    +Role role
    +String content
    +ToolCall[] tool_calls
    +String? reasoning_content
    +ChatMessage(Role, content, tool_calls, reasoning_content)
  }

  class ToolDefinition {
    +String name
    +String description
    +Json parameters
    +Bool strict
  }

  class ToolCall {
    +String id
    +String name
    +String arguments
  }

  class ChatResponse {
    +String content
    +String reasoning_content
    +ToolCall[] tool_calls
    +Usage usage
  }

  class Usage {
    +Int prompt_tokens
    +Int completion_tokens
    +Int total_tokens
    +Int prompt_cache_hit_tokens
    +Int prompt_cache_miss_tokens
  }

  Model --> DsVariant
  Model --> KimiVariant
  ChatMessage --> Role
  ChatMessage --> ToolCall
  ChatResponse --> ToolCall
  ChatResponse --> Usage
  ToolDefinition --> ToolCall : advertised then requested as
```

`encode_chat_request` is the main pure request boundary. `ChatResponse` and
`Usage` decode response JSON back into typed values.

```mermaid
flowchart TD
  messages["ChatMessage[]"] --> encode["encode_chat_request"]
  model["Model"] --> encode
  thinking["ThinkingMode?"] --> encode
  responseFormat["ResponseFormat?"] --> encode
  tools["ToolDefinition[]"] --> encode
  stream["stream Bool"] --> encode
  encode --> requestJson["chat completions request JSON"]

  responseJson["chat completions response JSON"] --> decode["FromJson ChatResponse"]
  decode --> response["ChatResponse"]
  response --> content["content"]
  response --> reasoning["reasoning_content"]
  response --> toolCalls["ToolCall[]"]
  response --> usage["Usage"]
```

## Native Tool Calls

DeepSeek tool calling uses the same flow described in the
[official API docs](https://api-docs.deepseek.com/guides/tool_calls): send
`tools` with a chat request, read `response.tool_calls`, append the assistant
tool-call message, execute each local function, then append
`ChatMessage(Tool(call.id), content=result)` before the next request.

### `ToolDefinition` vs `ToolCall`

`ToolDefinition` and `ToolCall` are opposite sides of the same protocol step:

| Type             | Direction                                                                | Meaning                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `ToolDefinition` | Your code sends it to DeepSeek through `Client::chat(..., tools=[...])`. | A tool definition: name, description, and JSON Schema for arguments. It advertises a function the model may request later. |
| `ToolCall`       | DeepSeek returns it in `ChatResponse.tool_calls`.                        | A concrete tool invocation request: generated call id, function name, and raw JSON argument string.                        |

The usual sequence is:

1. Define available tools with `ToolDefinition(...)`.
2. Send them with `Client::chat(..., tools=[...])`.
3. Decode DeepSeek's response into `ToolCall` values.
4. Append `ChatMessage(Assistant, content=response.content,
   tool_calls=response.tool_calls)` so the conversation records the model's
   requested calls.
5. Execute each local function after parsing `ToolCall.arguments`.
6. Append each result as `ChatMessage(Tool(call.id), content=result)`.

```mermaid
sequenceDiagram
  participant Caller
  participant Encoder as encode_chat_request
  participant API as chat-completions provider
  participant Tool as local tool

  Caller->>Encoder: messages + ToolDefinition[]
  Encoder-->>Caller: request JSON with tools
  Caller->>API: chat completions request
  API-->>Caller: ChatResponse with ToolCall[]
  Caller->>Caller: append assistant tool-call echo
  loop each ToolCall
    Caller->>Tool: parse arguments and execute
    Tool-->>Caller: result text
    Caller->>Caller: append ChatMessage(Tool(call.id), content=result)
  end
  Caller->>API: next chat request with tool results
```

```moonbit check
///|
test "encode chat request values" {
  let body = @deepseek.encode_chat_request(model=Deepseek(V4Flash)) <| [
    ChatMessage(User, content="write a MoonBit test"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [{ "role": "user", "content": "write a MoonBit test" }],
    "stream": false,
  })
}
```

```moonbit check
///|
test "encode tool-enabled chat request" {
  let body = @deepseek.encode_chat_request(
    model=Deepseek(V4Flash),
    tools=[
      ToolDefinition("read", "Read a file.", {
        "type": "object",
        "properties": { "path": { "type": "string" } },
        "required": ["path"],
      }),
    ],
  ) <| [
    ChatMessage(User, content="read README.mbt.md"),
    ChatMessage(Assistant, content="", tool_calls=[
      ToolCall(
        id="call_1",
        name="read",
        arguments="{\"path\":\"README.mbt.md\"}",
      ),
    ]),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [
      { "role": "user", "content": "read README.mbt.md" },
      {
        "role": "assistant",
        "content": null,
        "tool_calls": [
          {
            "id": "call_1",
            "type": "function",
            "function": {
              "name": "read",
              "arguments": "{\"path\":\"README.mbt.md\"}",
            },
          },
        ],
      },
    ],
    "stream": false,
    "tools": [
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
```

```moonbit check
///|
test "encode json-object response request" {
  let body = @deepseek.encode_chat_request(
    model=Deepseek(V4Flash),
    response_format=JsonObject,
  ) <| [
    ChatMessage(User, content="return {\"ok\":true}"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [{ "role": "user", "content": "return {\"ok\":true}" }],
    "stream": false,
    "response_format": { "type": "json_object" },
  })
}
```

```moonbit check
///|
test "decode chat response values" {
  let response : @deepseek.ChatResponse = @json.from_json({
    "choices": [{ "message": { "content": "ok" } }],
  })
  debug_inspect(
    response,
    content=(
      #|{
      #|  content: "ok",
      #|  reasoning_content: "",
      #|  tool_calls: [],
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
```

```moonbit check
///|
test "decode native tool call values" {
  let response : @deepseek.ChatResponse = @json.from_json({
    "choices": [
      {
        "message": {
          "content": null,
          "tool_calls": [
            {
              "id": "call_1",
              "type": "function",
              "function": {
                "name": "read",
                "arguments": "{\"path\":\"README.mbt.md\"}",
              },
            },
          ],
        },
      },
    ],
  })
  debug_inspect(
    response,
    content=(
      #|{
      #|  content: "",
      #|  reasoning_content: "",
      #|  tool_calls: [
      #|    {
      #|      id: "call_1",
      #|      name: "read",
      #|      arguments: "{\"path\":\"README.mbt.md\"}",
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
```
