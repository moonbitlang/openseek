///|
async test "agent registers the expected tool names" {
  @async.with_task_group() <| group => {
    let tools = @agent.build_tools(AgentRuntime(), AgentTaskScope(group))
    assert_eq([ for t in tools.function_tools() => t.name ], [
      "edit", "multi_edit", "write", "remove", "plan", "goal", "mbtx", "job_output",
      "job_stop", "job_wait", "finish",
    ])
  }
}

///|
/// A turn built by `run_turn_with_append` offers `escalated` only when the
/// caller hands it a channel — which is the plumbing best-of-N runs were
/// missing. `openseek run --concurrency N --approval always` parsed the flag,
/// discarded it, and built every attempt's runtime without one, so the
/// argument was never advertised and the option was silently inert.
///
/// The registry is what proves it: the field's presence in `mbtx`'s
/// schema is decided by the runtime's channel, so asserting on the schema
/// asserts the whole chain from this parameter down.
async test "a turn advertises escalation exactly when it is given a channel" {
  @async.with_task_group(group => {
    let confined = @agent.build_tools(AgentRuntime(), AgentTaskScope(group))
    guard confined.find("mbtx") is Some(tool) else { fail("mbtx tool missing") }
    let JsonSchema(schema) = tool.schema
    guard schema is { "properties": Object(properties), .. } else {
      fail("expected an object schema")
    }
    assert_false(properties.contains("escalated"))
    let asking = @agent.build_tools(
      AgentRuntime(approval=ApprovalChannel(_ => Rejected)),
      AgentTaskScope(group),
    )
    guard asking.find("mbtx") is Some(tool) else { fail("mbtx tool missing") }
    let JsonSchema(schema) = tool.schema
    guard schema is { "properties": Object(properties), .. } else {
      fail("expected an object schema")
    }
    assert_true(properties.contains("escalated"))
  })
}
