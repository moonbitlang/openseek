///|
async fn dispatch(
  definition : @agent_tool.AgentToolDefinition,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match definition.execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("mbtx should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}
