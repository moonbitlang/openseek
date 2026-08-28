# DeepSeek Client

This package is the effectful HTTP transport for DeepSeek-, Kimi-, and
Z.AI-compatible chat completions. It uses `bobzhang/openseek/deepseek` for typed
models, messages, tool definitions, request JSON encoding, and response JSON
decoding.

Use this package when code needs to call a supported provider API. Keep pure
request/response tests in `bobzhang/openseek/deepseek`; use this package for
transport behavior such as retries, HTTP errors, and streaming.

The package depends on `moonbitlang/async/http` and is native-only.

## API Shape

- `Client(api_key~, model?, api_url?, thinking?, retry_attempts?,
  retry_backoff_ms?)`: configure the API key, endpoint, model, thinking mode,
  and retry budget.
- `Client::chat(messages, tools?, response_format?, stream?)`: send a request
  and decode the response as `@deepseek.ChatResponse`. Without `stream`, this
  is a normal JSON response. With `stream=StreamHandler(...)`, it uses SSE and
  still returns the accumulated response.
- `StreamHandler(on_content_delta~, on_reasoning_delta?)`: receive non-empty
  content and reasoning deltas while a streaming chat request is in progress.

`Client` implements `Debug` with the API key redacted.

## Configuration

The default endpoint is `https://api.deepseek.com/chat/completions`, the default
model is `deepseek-v4-pro`, and `thinking=No` is sent unless a different mode is
provided. Kimi K2.7 Code models default to
`https://api.moonshot.cn/v1/chat/completions` and omit DeepSeek-specific
thinking fields when the request body is encoded.
Z.AI GLM models default to `https://api.z.ai/api/paas/v4/chat/completions`.

Retries cover transient failures: transport errors, HTTP 429, and HTTP 5xx.
Other HTTP 4xx responses fail immediately. `retry_attempts` counts total tries;
`retry_backoff_ms` is the first exponential-backoff delay, capped internally at
60 seconds.

```moonbit check
///|
test "construct DeepSeek client configuration" {
  let client = @client.Client(
    api_key="test-key",
    model=Deepseek(V4Flash),
    thinking=Max,
    retry_attempts=5,
    retry_backoff_ms=200,
  )
  debug_inspect(
    client,
    content=(
      #|{
      #|  api_key: ...,
      #|  model: Deepseek(V4Flash),
      #|  api_url: "https://api.deepseek.com/chat/completions",
      #|  thinking: Max,
      #|  retry_attempts: 5,
      #|  retry_backoff_ms: 200,
      #|  idle_timeout_ms: 120000,
      #|}
    ),
  )
}
```

## Non-Streaming Chat

Without `stream`, `Client::chat` builds the same JSON body as
`@deepseek.encode_chat_request`, using the client's `model` and `thinking`
configuration, then posts it to `api_url` with `Content-Type:
application/json` and bearer authorization.

Use `tools=[...]` when the model may request native function calls.
Use `response_format=JsonObject` only when the assistant content itself must be
a JSON object.

At runtime:

```moonbit nocheck
///|
let client = @client.Client(api_key~, thinking=Max)

///|
let response = client.chat(
  [@deepseek.ChatMessage(User, content="Return {\"ok\":true}.")],
  response_format=JsonObject,
)
```

The request body has this shape:

```moonbit check
///|
test "Client::chat request body shape" {
  let client = @client.Client(
    api_key="test-key",
    model=Deepseek(V4Flash),
    thinking=Max,
  )
  let tool = @deepseek.ToolDefinition("read", "Read a file.", {
    "type": "object",
    "properties": { "path": { "type": "string" } },
    "required": ["path"],
  })
  let body = @deepseek.encode_chat_request(
    model=client.model,
    thinking=client.thinking,
    tools=[tool],
    response_format=JsonObject,
  ) <| [
    ChatMessage(User, content="read README.mbt.md"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-flash",
    "messages": [{ "role": "user", "content": "read README.mbt.md" }],
    "stream": false,
    "response_format": { "type": "json_object" },
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
    "thinking": { "type": "enabled" },
    "reasoning_effort": "max",
  })
}
```

If a response contains tool calls, append the assistant tool-call echo first,
then append one `Tool(call.id)` result message per call before the next request.

## Streaming Chat

Pass `stream=StreamHandler(...)` to `Client::chat` to send `stream=true` plus
`stream_options={"include_usage":true}` for usage-bearing streams. The transport
pins `Accept-Encoding: identity` so a gzip-compressing intermediary cannot
buffer and re-batch SSE deltas.

The stream reader:

- calls `on_content_delta` for each non-empty `delta.content`
- calls `on_reasoning_delta` for each non-empty `delta.reasoning_content`
- accumulates content, reasoning, tool-call fragments, and final usage
- returns the accumulated value as a normal `@deepseek.ChatResponse`

Streaming calls retry only until the first SSE event is produced. After any
event - text, reasoning, tool-call, or usage - retrying could duplicate or
change the completion, so later failures surface directly.

At runtime:

```moonbit nocheck
///|
let stream = @client.StreamHandler(on_content_delta=delta => print(delta), on_reasoning_delta=reasoning => {
  log_reasoning(reasoning)
})

///|
let response = client.chat(
  [@deepseek.ChatMessage(User, content="Explain this briefly.")],
  stream~,
)
```

The request body has this shape:

```moonbit check
///|
test "Client::chat streaming request body shape" {
  let client = @client.Client(api_key="test-key")
  let body = @deepseek.encode_chat_request(
    model=client.model,
    thinking=client.thinking,
    stream=true,
  ) <| [
    ChatMessage(User, content="stream this"),
  ]
  json_inspect(body, content={
    "model": "deepseek-v4-pro",
    "messages": [{ "role": "user", "content": "stream this" }],
    "stream": true,
    "stream_options": { "include_usage": true },
    "thinking": { "type": "disabled" },
  })
}
```

## Errors

HTTP statuses outside `200..<300` fail with
`DeepSeek API error <status>: <body>`. A successful HTTP response that is not
valid JSON fails with `DeepSeek response is not JSON`; a valid JSON response
that does not match the expected DeepSeek envelope fails with
`DeepSeek response decode error`.

## Tests

Run the package tests with:

```bash
moon test deepseek/client
```

The blackbox test suite includes a real DeepSeek API smoke test when `DEEPSEEK`
is set. Kimi smoke tests are opt-in: set `KIMI` to a Kimi API key. The normal
Kimi smoke also uses `OPENSEEK_MODEL` to choose the Kimi model; streaming,
tool-call, and multi-turn reasoning-content smokes use `kimi-k2.7-code`.
Without those environment variables, the smoke tests print skip messages and
return successfully.
