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

///|
async test "registered remove uses approval without holding the shared file gate" {
  @async.with_timeout(5000, () => {
    let dir = @fs.tmpdir(prefix="openseek-remove-approval-")
    defer @fs.rmdir(dir, recursive=true)
    @async.with_task_group(group => {
      let registered : Ref[@agent_tool.Tools?] = Ref(None)
      let mut asks = 0
      let runtime = @agent_runtime.AgentRuntime(
        workspace_root=dir,
        approval=ApprovalChannel(ask => {
          assert_eq(ask.tool_name, "remove")
          asks += 1
          guard registered.val is Some(tools) else { fail("registry missing") }
          // Use the actual serialized write tool while remove is awaiting its
          // answer. An outer serialize around remove would deadlock here.
          let path = if asks == 1 { "other.txt" } else { "target.txt" }
          let changed = @agent_tool.execute_tool_call(
            @agent_tool.AgentToolCall::from_arguments("write", {
              "path": path,
              "content": "written while waiting",
            }),
            tools,
          )
          guard changed is Respond(out) else { fail("expected write response") }
          assert_false(out.is_error, msg=out.content)
          AllowedOnce
        }),
      )
      let tools = @agent.build_tools(runtime, AgentTaskScope(group))
      registered.val = Some(tools)
      for should_delete in [true, false] {
        @fs.write_file("\{dir}/target.txt", "existing", create_mode=CreateNew)
        let result = @agent_tool.execute_tool_call(
          @agent_tool.AgentToolCall::from_arguments("remove", {
            "path": "target.txt",
            "reason": "remove obsolete file",
          }),
          tools,
        )
        guard result is Respond(out) else { fail("expected remove response") }
        assert_eq(out.is_error, !should_delete, msg=out.content)
        assert_eq(@fs.exists("\{dir}/target.txt"), !should_delete)
        if !should_delete {
          assert_true(out.content.contains("changed while awaiting approval"))
          assert_eq(
            @fs.read_file("\{dir}/target.txt").text(),
            "written while waiting",
          )
        }
      }
      assert_eq(asks, 2)
      assert_eq(
        @fs.read_file("\{dir}/other.txt").text(),
        "written while waiting",
      )
    })
  })
}
