///|
async fn async_echo(args : Json) -> ToolAction {
  @async.pause()
  match args {
    { "value": String(v), .. } => respond(v)
    _ => respond("no value", is_error=true)
  }
}

///|
/// One minimal registry entry for the dispatch tests. The privileges
/// (`control`, `concurrent_safe`) are the constructor's own defaults, so no
/// test below has to restate them just to build an ordinary tool.
fn test_tool(
  name? : String = "echo",
  description? : String = "Echo.",
  schema? : Json = { "type": "object" },
  execute? : ToolExecutor = Sync(_args => respond("ok")),
) -> AgentToolDefinition {
  AgentToolDefinition(name~, description~, schema=JsonSchema(schema), execute~)
}

///|
test "Tools::Tools raises on duplicate tool names" {
  let _ = Tools([
    test_tool(description="First.", execute=Sync(_args => respond("first"))),
    test_tool(description="Second.", execute=Sync(_args => respond("second"))),
  ]) catch {
    error => {
      assert_true("\{error}".contains("duplicate tool name: echo"))
      return
    }
  }
  fail("expected duplicate to raise")
}

///|
test "Tools::find returns the registered definition by name" {
  let tools = Tools([test_tool()])
  guard tools.find("echo") is Some(definition) else { fail("missing echo") }
  assert_eq(definition.name, "echo")
  assert_true(tools.find("ghost") is None)
}

///|
test "Tools::function_tools preserves description and schema" {
  let tools = Tools([
    test_tool(description="Echo what comes in.", schema={
      "type": "object",
      "properties": Json::empty_object(),
    }),
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools.length(), 1)
  assert_eq(function_tools[0].name, "echo")
  assert_eq(function_tools[0].description, "Echo what comes in.")
  let text = function_tools[0].parameters.stringify()
  assert_true(text.contains("\"type\":\"object\""))
  assert_true(text.contains("\"properties\""))
}

///|
test "Tools::function_tools yields one entry per definition" {
  let tools = Tools([
    test_tool(
      name="first",
      description="First.",
      execute=Sync(_args => respond("1")),
    ),
    test_tool(
      name="second",
      description="Second.",
      execute=Sync(_args => respond("2")),
    ),
    test_tool(
      name="third",
      description="Third.",
      execute=Sync(_args => respond("3")),
    ),
  ])
  let function_tools = tools.function_tools()
  assert_eq(function_tools.length(), 3)
  let names = [ for t in function_tools => t.name ]
  assert_true(names.contains("first"))
  assert_true(names.contains("second"))
  assert_true(names.contains("third"))
}

///|
async test "execute_tool_call dispatches to async executor" {
  let tools = Tools([
    test_tool(description="Async echo.", execute=Async(async_echo)),
  ])
  let call = AgentToolCall(
    ToolCall(id="call_1", name="echo", arguments="{\"value\":\"async-hi\"}"),
  )
  let result = execute_tool_call(call, tools)
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "async-hi")
  assert_false(output.is_error)
}

///|
async test "execute_tool_call dispatches to registered executor" {
  let tools = Tools([
    test_tool(
      execute=Sync(args => {
        match args {
          { "value": String(v), .. } => respond(v)
          _ => respond("no value", is_error=true)
        }
      }),
    ),
  ])
  let call = AgentToolCall(
    ToolCall(id="call_1", name="echo", arguments="{\"value\":\"hi\"}"),
  )
  let result = execute_tool_call(call, tools)
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "hi")
  assert_false(output.is_error)
}

///|
async test "execute_tool_call turns a tool failure into a recoverable error result" {
  // Local to the test on purpose: an always-failing executor must not be
  // callable from anywhere else in the package.
  async fn async_boom(_args : Json) -> ToolAction {
    @async.pause()
    fail("disk on fire")
  }

  let tools = Tools([
    test_tool(
      name="boom",
      description="Always fails.",
      execute=Async(async_boom),
    ),
  ])
  let call = AgentToolCall(ToolCall(id="call_1", name="boom", arguments="{}"))
  // The tool's failure is caught at the dispatch boundary and returned as an
  // error action the model can react to — the turn is NOT aborted.
  let result = execute_tool_call(call, tools)
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("boom failed"))
}

///|
async test "execute_tool_call reports a cancelled child task as a tool error" {
  // `Task::wait` on a task someone else cancelled raises the ordinary
  // `TaskCancelled` error; the caller itself is not cancelled, so the tool
  // failed and the turn goes on.
  async fn wait_cancelled_child(_args : Json) -> ToolAction {
    @async.with_task_group(group => {
      let child = group.spawn(() => @async.sleep(10_000))
      child.cancel()
      child.wait()
      respond("unreachable")
    })
  }

  let tools = Tools([
    test_tool(name="child", execute=Async(wait_cancelled_child)),
  ])
  let call = AgentToolCall(ToolCall(id="call_1", name="child", arguments="{}"))
  guard execute_tool_call(call, tools) is Respond(output) else {
    fail("expected Respond")
  }
  assert_true(output.is_error)
  assert_true(output.content.contains("TaskCancelled"))
}

///|
async test "execute_tool_call stays interruptible by its caller" {
  let unwound = Ref(false)
  let tools = Tools([
    test_tool(
      name="slow",
      execute=Async(_args => {
        defer {
          unwound.val = true
        }
        @async.sleep(10_000)
        respond("unreachable")
      }),
    ),
  ])
  let call = AgentToolCall(ToolCall(id="call_1", name="slow", arguments="{}"))
  let result = @async.with_timeout_opt(10, () => execute_tool_call(call, tools))
  assert_true(result is None)
  assert_true(unwound.val)
}
