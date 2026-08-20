///|
/// The model's structured verdict about the standing session goal.
///
/// This public type is owned by the `goal` package because the agent loop
/// consumes it. Raw JSON decoding is delegated to `internal/decode` and mapped
/// into this package-owned API.
pub enum GoalStatus {
  /// The goal is fully achieved and verified.
  Met
  /// Work remains and can continue autonomously.
  Continuing(String)
  /// Progress requires user action or an external-state change.
  Blocked(String)
} derive(Debug)

///|
/// Decode and validate a `goal` verdict.
///
/// The argument-shape rules live in `internal/decode`; this facade keeps the
/// public result type owned by `agent_tool/goal` so sibling packages do not
/// depend on an internal implementation package.
pub fn decode_status(arguments : Json) -> GoalStatus raise {
  match @decode.decode(arguments) {
    Met => Met
    Continuing(remaining) => Continuing(remaining)
    Blocked(reason) => Blocked(reason)
  }
}

///|
/// Tool definition for `goal`: record the standing goal's status as
/// structured state instead of prose, so the engine can act on it — `met`
/// durably clears the goal (the auto-continue termination signal) and
/// `continuing` records what remains. `blocked` keeps the goal standing but
/// pauses auto-continuation until the user intervenes or work resumes.
///
/// The agent loop intercepts calls to this tool before execution: only the
/// loop knows whether a goal currently stands and owns the durable log, and
/// the clear must land at a batch-safe boundary. This stateless execute is
/// the fallback for registries dispatched outside the loop; it validates the
/// arguments and acknowledges without touching any state.
pub fn definition() -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="goal",
    description=(
      #|Record the status of the standing session goal. Call with status "met" only when the goal is fully achieved and verified — this durably clears it. Call with status "continuing" plus a short "remaining" summary when you finish a task while goal work remains; if the goal was previously marked "blocked" and you have resumed work, "continuing" clears that blocked status and resumes autonomous continuation. Call with status "blocked" plus a "reason" ONLY when real progress is impossible without user action or an external-state change (e.g. missing credentials or access, a required decision only the user can make, a genuinely unrecoverable dependency), or the goal has been superseded — NOT for a transient or recoverable problem you can work around yourself (a failed command, a tool error, a corrupted file you can rewrite). Blocking keeps the goal standing for the user but pauses autonomous continuation, so reserve it for when you truly cannot proceed. Only meaningful when a standing goal is set.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "status": { "type": "string", "enum": ["met", "continuing", "blocked"] },
        "remaining": {
          "type": "string",
          "description": "Required when status is \"continuing\": one or two lines on what is left to reach the goal.",
        },
        "reason": {
          "type": "string",
          "description": "Why the goal cannot proceed; required with status \"blocked\".",
        },
      },
      "required": ["status"],
      "additionalProperties": false,
    }),
    execute=Sync(execute),
    control=true,
  )
}

///|
fn execute(arguments : Json) -> @agent_tool.ToolAction {
  try @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      @agent_tool.ToolAction::respond("error: \{message}", is_error=true)
    }
  } noraise {
    _ => @agent_tool.ToolAction::respond("goal status recorded")
  }
}

///|
pub extend GoalStatus with Debug::{to_repr}
