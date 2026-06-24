///|
test "session items project to transcript items" {
  let shell_context =
    #|<user_shell_command>
    #|<command>
    #|ls
    #|</command>
    #|<result>
    #|exit=0
    #|_build
    #|</result>
    #|</user_shell_command>
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
  guard session_item(User(UserMessage(shell_context))) is Some(ToolCall(_)) else {
    fail("expected command user message to render as a tool")
  }
}
