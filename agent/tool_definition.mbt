///|
/// The agent's local tool registry. Each tool lives in its own subpackage of
/// `agent_tool` and exposes a `definition()` constructor; this function bundles
/// them into the `Tools` value the loop dispatches against. Raises if two
/// definitions share a name.
fn[X] tool_definitions(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
) -> @agent_tool.Tools raise {
  // The task scope is plumbed through for stateful tools; none currently need
  // it (moon_check — the watcher tool — was removed in favor of plain
  // `moon check` through shell).
  ignore(scope)
  let workspace_root = runtime.workspace_root()
  // One seen-set shared by the file tools for this session: `read` and `edit`
  // record what the agent has looked at, and `write` uses it to flag an
  // overwrite of a file that was never read this session.
  let read_state = @read_state.ReadState::ReadState()
  Tools([
    @shell.definition(workspace_root~),
    @read.definition(workspace_root~, read_state~),
    @edit.definition(workspace_root~),
    @write.definition(workspace_root~, read_state~),
    @finish.definition(),
  ])
}

///|
async test "agent registers the expected tool names" {
  @async.with_task_group() <| group => {
    let tools = tool_definitions(AgentRuntime(), AgentTaskScope(group))
    let function_tools = tools.function_tools()
    assert_eq(function_tools.length(), 5)
    let names = [ for t in function_tools => t.name ]
    assert_true(names.contains("shell"))
    assert_true(names.contains("read"))
    assert_true(names.contains("edit"))
    assert_true(names.contains("write"))
    assert_true(names.contains("finish"))
    assert_false(names.contains("moon_check"))
    assert_false(names.contains("moon_cmd"))
    assert_false(names.contains("moon_ide"))
  }
}
