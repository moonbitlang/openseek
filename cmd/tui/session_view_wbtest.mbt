///|
test "session items project to transcript items" {
  guard session_item(User(UserMessage("hello"))) is Some(Input(Prompt(text))) else {
    fail("expected input")
  }
  assert_eq(text, "hello")
  guard session_item(Terminal(Finished("done"))) is Some(Response(answer)) else {
    fail("expected response")
  }
  assert_eq(answer, "done")
  guard session_item(
      Tool(ToolResult(tool_call_id="call_1", tool_name="read", content="ok")),
    )
    is Some(ToolCall(_)) else {
    fail("expected tool")
  }
}
