# DeepSeek Client

This package contains the effectful DeepSeek HTTP transport. It depends on the
pure `bobzhang/openseek/deepseek` package for models, roles, messages, JSON
encoding, and response decoding.

Use this package when you need to send chat requests to the real DeepSeek API.
The package depends on `moonbitlang/async/http` and is native-only.

## API Shape

- `Client(api_key~, model?, api_url?, thinking?, reasoning_effort?)`: configure
  the API key, typed model, optional endpoint override, and optional DeepSeek V4
  thinking controls.
- `Client::chat(messages, tools?, response_format?)`: send typed chat messages,
  optionally with native DeepSeek function tools, and decode the response.

`Client` implements `Debug` with the API key redacted.

## Request Behavior

`Client::chat` builds a private request envelope with the client's configured
model, thinking mode, and reasoning effort, then sends it to `api_url` as JSON.
It sends `stream=false` and leaves assistant content unconstrained by default.
Pass `response_format=JsonObject` only for callers that explicitly want the
assistant content constrained to a JSON object.

Use `tools=[...]` when the model should call native DeepSeek function tools.
Tool call results should be appended as `@deepseek.ChatMessage(Tool(call.id),
content=text)` before sending the next request.

HTTP status codes outside `200..<300` raise with the status code and response
body. Successful responses are parsed and decoded as `@deepseek.ChatResponse`.

## Configuration

The default endpoint is `https://api.deepseek.com/chat/completions`, and the
default model is `deepseek-v4-pro`. Tests and examples use placeholder API
keys unless explicitly marked as real API smoke tests. Pass
`thinking=Some(Enabled)` and `reasoning_effort=Some(Max)` for explicit
thinking-mode agent requests.

```moonbit check
///|
test "construct DeepSeek client" {
  let client = @client.Client(
    api_key="test-key",
    model=V4Pro,
    thinking=Some(Enabled),
    reasoning_effort=Some(Max),
  )
  inspect(client.model, content="deepseek-v4-pro")
  assert_eq(client.api_url, "https://api.deepseek.com/chat/completions")
  debug_inspect(client.reasoning_effort, content="Some(Max)")

  let message = @deepseek.ChatMessage(User, content="ping")
  inspect(message.role, content="user")
  assert_eq(message.content, "ping")
}
```

```moonbit check
///|
test "prepare tool-enabled client request values" {
  let tool = @deepseek.ToolDefinition("read", "Read a file.", {
    "type": "object",
    "properties": { "path": { "type": "string" } },
    "required": ["path"],
  })
  let messages = [@deepseek.ChatMessage(User, content="read README.mbt.md")]
  let body = @deepseek.encode_chat_request(V4Flash, messages, tools=[tool]).stringify()
  assert_eq(messages.length(), 1)
  assert_true(body.contains("\"type\":\"function\""))
  assert_true(body.contains("\"name\":\"read\""))
}
```

## Tests

Run the package tests with:

```bash
moon test deepseek/client
```

The blackbox test suite includes a real API smoke test when `DEEPSEEK` is set.
Without that environment variable, the smoke test prints a skip message and
returns successfully.
