///|
test "parse native tool call arguments" {
  let call = @agent_tool.AgentToolCall(
    ToolCall(id="call_123", name="shell", arguments="{\"cmd\":\"moon check\"}"),
  )
  assert_eq(call.name, "shell")
  guard call.arguments is { "cmd": String(cmd), .. } else {
    fail("missing cmd")
  }
  assert_eq(cmd, "moon check")
}

///|
test "reject invalid native tool call arguments" {
  let _ = @agent_tool.AgentToolCall(
    ToolCall(id="call_123", name="shell", arguments="{"),
  ) catch {
    error => {
      assert_true("\{error}".contains("shell arguments are not valid JSON"))
      return
    }
  }
  fail("invalid arguments parsed")
}
