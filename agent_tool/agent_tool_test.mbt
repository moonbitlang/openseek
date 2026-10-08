///|
test "foreground program output distinguishes absence from an empty result and is consumed once" {
  let program_output : Ref[@bgjobs.ImageOutput?] = Ref(None)
  let tools = @agent_tool.Tools([], program_output~)
  assert_true(tools.take_program_output() is None)
  program_output.val = Some({ content: "", images: [], })
  assert_true(tools.take_program_output() is Some({ content: "", images: [], }))
  assert_true(program_output.val is None)
  assert_true(tools.take_program_output() is None)
}

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
