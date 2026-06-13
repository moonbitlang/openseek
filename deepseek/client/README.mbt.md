# DeepSeek Client

This package is the effectful HTTP transport for DeepSeek chat completions. It
uses `bobzhang/openseek/deepseek` for typed models, messages, tool definitions,
request JSON encoding, and response JSON decoding.

Use this package when code needs to call the real DeepSeek API. Keep pure
request/response tests in `bobzhang/openseek/deepseek`; use this package for
transport behavior such as retries, HTTP errors, and streaming.

The package depends on `moonbitlang/async/http` and is native-only.

## API Shape

- `Client(api_key~, model?, api_url?, thinking?, retry_attempts?,
  retry_backoff_ms?)`: configure the API key, endpoint, model, thinking mode,
  and retry budget.
- `Client::chat(messages, tools?, response_format?)`: send a non-streaming
  request and decode the response as `@deepseek.ChatResponse`.
- `Client::chat_stream(messages, on_content_delta~, on_reasoning_delta?,
  tools?, response_format?)`: send the same request in SSE streaming mode,
  deliver non-empty content/reasoning deltas through callbacks, and return the
  fully accumulated `@deepseek.ChatResponse`.

`Client` implements `Debug` with the API key redacted.

## Configuration

The default endpoint is `https://api.deepseek.com/chat/completions`, the default
model is `deepseek-v4-pro`, and `thinking=No` is sent unless a different mode is provided. Pass `thinking=Max` for explicit max-effort thinking-mode
requests.

Retries cover transient failures: transport errors, HTTP 429, and HTTP 5xx.
Other HTTP 4xx responses fail immediately. `retry_attempts` counts total tries;
`retry_backoff_ms` is the first exponential-backoff delay, capped internally at
60 seconds.

```moonbit check
///|
test "construct DeepSeek client configuration" {
  let client = @client.Client(
    api_key="test-key",
    model=V4Flash,
    thinking=Max,
    retry_attempts=5,
    retry_backoff_ms=200,
  )
  debug_inspect(
    client,
    content=(
      #|{
      #|  api_key: ...,
      #|  model: V4Flash,
      #|  api_url: "https://api.deepseek.com/chat/completions",
      #|  thinking: Max,
      #|  retry_attempts: 5,
      #|  retry_backoff_ms: 200,
      #|}
    ),
  )
}
```

## Non-Streaming Chat

`Client::chat` builds the same JSON body as `@deepseek.encode_chat_request`,
using the client's `model` and `thinking` configuration, then posts it to
`api_url` with `Content-Type: application/json` and bearer authorization.

Use `tools=[...]` when the model may request native DeepSeek function calls.
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
  let client = @client.Client(api_key="test-key", model=V4Flash, thinking=Max)
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

`Client::chat_stream` sends `stream=true` plus
`stream_options={"include_usage":true}`. The transport pins
`Accept-Encoding: identity` so a gzip-compressing intermediary cannot buffer and
re-batch SSE deltas.

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
let response = client.chat_stream(
  [@deepseek.ChatMessage(User, content="Explain this briefly.")],
  on_content_delta=delta => print(delta),
  on_reasoning_delta=reasoning => log_reasoning(reasoning),
)
```

The request body has this shape:

```moonbit check
///|
test "Client::chat_stream request body shape" {
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

The blackbox test suite includes a real API smoke test when `DEEPSEEK` is set.
Without that environment variable, the smoke test prints a skip message and
returns successfully.
