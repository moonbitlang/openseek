///|
test "chat message constructor keeps labeled fields" {
  let call = @deepseek.ToolCall(
    id="call_123",
    name="shell",
    arguments="{\"cmd\":\"moon test\"}",
  )
  let message = @deepseek.ChatMessage(
    Assistant,
    content=[Text("")],
    tool_calls=[call],
    reasoning_content="run tests first",
  )
  assert_eq(message.tool_calls.length(), 1)
  assert_true(message.reasoning_content is Some("run tests first"))
}
