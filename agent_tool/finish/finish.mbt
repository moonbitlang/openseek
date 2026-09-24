///|
/// Tool definition for `finish`: ends the agent loop with `arguments.answer`
/// as the final response surfaced to the user.
///
/// ## Arguments
/// - `answer` (string, required): the final answer text.
///
/// ## Result
/// - `Control(Finish(<answer>))` — stops the loop and returns the string.
///   Missing or non-string `answer` produces `Control(Finish(""))`.
///
/// Explicit completion is respected even with live background jobs. Pending
/// steering and existing goal/ceiling checks may still continue the turn.
pub fn definition() -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="finish",
    description="End the task with arguments.answer.",
    schema=JsonSchema({
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "required": ["answer"],
    }),
    execute=Sync(execute),
    control=true,
  )
}

///|
fn execute(arguments : Json) -> @agent_tool.ToolAction {
  @agent_tool.ToolAction::finish(@decode.decode(arguments).answer)
}
