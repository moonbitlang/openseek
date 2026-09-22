# DeepSeek Client

This package is the effectful HTTP transport for DeepSeek-, Kimi-, and
Z.AI-compatible chat completions. It uses `moonbitlang/openseek/deepseek` for typed
models, messages, tool definitions, request JSON encoding, and response JSON
decoding.

Use this package when code needs to call a supported provider API. Keep pure
request/response tests in `moonbitlang/openseek/deepseek`; use this package for
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
- `StreamHandler(on_content_delta~, on_reasoning_delta?, on_retry?)`: receive
  non-empty content and reasoning deltas while a streaming chat request is in
  progress. `on_retry(attempt, max_attempts, reason)` opts into retrying an
  interrupted stream and is told about every retry before its backoff; the
  `StreamHandler` docstring states the contract.

`Client` implements `Debug` with the API key redacted.

## Image Uploads

`Client::upload_image(data, filename~, expires_after_seconds?, timeout_ms?)`
uploads PNG, JPEG, GIF, or WebP file bytes unchanged using multipart form data.
It returns `UploadedFile`, including the opaque `id`, byte count, creation time,
filename, and optional expiration time. The server performs full image
validation; the client checks signatures, the 64 MiB size limit, and metadata.
The filename is a display name, not a path, and must not contain quotes, path
separators, or ASCII control characters. Multipart framing and boundary
selection are handled by `moonbitlang/openseek/deepseek/client/internal/form_data`.

The upload uses the same API key and replaces the trailing `/chat/completions`
in `api_url` with `/files`, preserving prefixes such as `/v1`. The configured
endpoint must implement the DeepSeek Files API. It never redirects uploads to
a different configured provider. Files belong to the uploading API key.

Omitting `expires_after_seconds` requests permanent storage. Setting it to
3600..2592000 requests a lifetime from one hour through thirty days. The default
timeout is ten minutes for the complete operation. Upload POSTs are not retried
automatically because a lost response may already have created a remote file.
`FileUploadError` exposes concrete variants such as `UnsupportedImageFormat`,
`ImageTooLarge(bytes~, limit~)`, `InvalidExpirySeconds(Int)`, and
`FileByteCountMismatch(expected~, actual~)`. Match these variants rather than
parsing display messages. `MalformedResponseJson` and `InvalidResponseShape`
retain typed JSON errors; `HttpStatus(code, body)` retains the raw HTTP response,
including non-JSON error pages. Cancellation and transport errors propagate.

```mbt nocheck
///|
let client = @client.Client(api_key~, model=Deepseek(V4Flash))

///|
let uploaded = client.upload_image(
  image_bytes,
  filename="screenshot.png",
  expires_after_seconds=7 * 24 * 60 * 60,
)

///|
let message = @deepseek.ChatMessage(User, content=[
  Text("Describe this screenshot."),
  File(file_id=uploaded.id),
])

///|
let response = client.chat([message])
```

`ChatMessage` accepts an array of parts and wraps it in `Content`. Use
`message.content.text()` to concatenate all text fragments without separators,
skipping images and files, and `message.content.iter()` to inspect the ordered parts.
Text-only comparisons can additionally require `content.is_text_only()` so
file references are not silently discarded. A single text part
encodes as a plain string for compatibility with existing requests. Other
user/tool content encodes as an array of content parts. Each `Text(...)`
part produces `{"type":"text","text":...}`; each `File(file_id=...)` produces
`{"type":"file","file_id":...}`. `ImageUrl(url=...)` produces
`{"type":"image_url","image_url":{"url":...}}` and accepts a base64 data URL
or an image URL. Parts retain their order, so text and images
can be interleaved. File-only arrays are supported, and tool messages retain
`tool_call_id`. System/assistant messages concatenate their text parts without
separators, since those roles require a string. Empty text with assistant tool
calls still encodes as `null`. Request encoding rejects images/files on
system/assistant messages and blank file IDs or image URLs with
`ChatMessageError` before network IO.
This matches the [Chat Completions content schema](https://api-docs.deepseek.com/api/create-chat-completion/).
For inline images, pass `ImageUrl(url="data:image/png;base64,...")` directly;
this requires no Files API upload or remote file lifetime management.

The caller must select an image-capable model and an endpoint accepting file
references; file IDs are scoped to the uploading API key.
This package does not resize images, cache file IDs, delete uploads, or fall
back to base64. Callers own local image retention and remote file lifetimes.
Limits follow the [DeepSeek Files API documentation](https://api-docs.deepseek.com/zh-cn/guides/files_api/).

## Configuration

The default endpoint is `https://api.deepseek.com/chat/completions`, the default
model is `deepseek-v4-pro`, and `thinking=No` is sent unless a different mode is
provided. Kimi K2.7 Code models default to
`https://api.moonshot.cn/v1/chat/completions` and omit DeepSeek-specific
thinking fields when the request body is encoded.
Z.AI GLM models default to `https://api.z.ai/api/paas/v4/chat/completions`;
GLM 5.3 always reasons, so `thinking=No` maps to `reasoning_effort=low`.

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

When `api_url` is OpenRouter's canonical
`https://openrouter.ai/api/v1/chat/completions` endpoint, the client maps
DeepSeek V4 models to OpenRouter's namespaced ids and translates the configured
thinking effort to OpenRouter's portable `reasoning` object. Both
`reasoning_content` and OpenRouter's `reasoning` response field are normalized
into `ChatResponse::reasoning_content`.

| DeepSeek model    | OpenRouter ids                 |
|-------------------|--------------------------------|
| `deepseek-flash`  | `deepseek/deepseek-v4.1-flash` |
| `deepseek-v4-pro` | `deepseek/deepseek-v4-pro`     |

The flash tier is one model: it encodes as `deepseek/deepseek-v4.1-flash` on
OpenRouter, which is the id that serves the canonical `deepseek-flash` wire
name. The retired `deepseek/deepseek-v4-flash-0731` snapshot id is no longer
sent.

Use `tools=[...]` when the model may request native function calls.
Use `response_format=JsonObject` only when the assistant content itself must be
a JSON object.

At runtime:

```moonbit nocheck
///|
let client = @client.Client(api_key~, thinking=Max)

///|
let response = client.chat(
  [@deepseek.ChatMessage(User, content=[Text("Return {\"ok\":true}.")])],
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
    ChatMessage(User, content=[Text("read README.mbt.md")]),
  ]
  json_inspect(body, content={
    "model": "deepseek-flash",
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
change the completion, so later failures surface directly. A handler that
supplies `on_retry` opts out of that rule for socket, EOF, and idle-timeout
failures: the callback runs when the retry is decided, before the backoff
sleep, so the consumer can discard the failed attempt's output and show that
a retry is pending.

At runtime:

```moonbit nocheck
///|
let stream = @client.StreamHandler(on_content_delta=delta => print(delta), on_reasoning_delta=reasoning => {
  log_reasoning(reasoning)
})

///|
let response = client.chat(
  [@deepseek.ChatMessage(User, content=[Text("Explain this briefly.")])],
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
    ChatMessage(User, content=[Text("stream this")]),
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

The blackbox test suite includes real text and image DeepSeek API smoke tests
when `DEEPSEEK` is set. The image smoke reads `testdata/two-colors.png`, uploads it
with a one-hour expiry, sends its returned file ID to `deepseek-flash`, and checks
that the model identifies the two colored halves. The filename and prompt do not reveal
the expected colors. It uses real API quota and has a two-minute timeout.
Multipart and error-path tests continue to use a local mock HTTP server.

To run only the real image smoke after loading `DEEPSEEK` into the environment:

```bash
moon test deepseek/client --target native --filter 'realworld DeepSeek image upload and recognition'
```

Kimi smoke tests are opt-in: set `KIMI` to a Kimi API key. The normal
Kimi smoke also uses `OPENSEEK_MODEL` to choose the Kimi model; streaming,
tool-call, and multi-turn reasoning-content smokes use `kimi-k2.7-code`.
The GLM streaming tool-call smoke test runs when `GLM` is set.
Without those environment variables, the smoke tests print skip messages and
return successfully.
