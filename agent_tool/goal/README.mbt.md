# Goal Tool

`goal` reports a structured verdict about the standing session goal. The
agent loop uses that verdict to decide whether to stop autonomous work,
continue it in another turn, or pause for the user. It never has to infer goal
state from prose in the assistant response.

The tool is registered only while a goal stands. Calling it without a standing
goal is a semantic error handled by the agent loop.

## Arguments

| `status` | Required companion field | Meaning |
| --- | --- | --- |
| `"met"` | none | The goal is fully achieved and verified. |
| `"continuing"` | `remaining` (non-blank string) | Work remains and can continue autonomously. |
| `"blocked"` | `reason` (non-blank string) | Progress requires user action or an external-state change. |

`blocked` is for a genuine impasse, not a failed command or another recoverable
problem. A later `continuing` verdict resumes a blocked goal.

The JSON schema declares unknown fields invalid. Conditional requirements for
`remaining` and `reason` are enforced by the decoder in
`agent_tool/goal/internal/decode`.

## Lifecycle Effects

- `met` clears the standing goal. The loop writes a durable `[goal cleared]`
  marker at the next batch-safe boundary; under auto-continuation, that marker
  is the structural stop signal.
- `continuing` records the actionable remainder and satisfies the finish check
  for the current turn. The goal remains standing. If it was blocked, the loop
  also records `[goal unblocked]` and resumes auto-continuation.
- `blocked` records why work cannot proceed and writes `[goal blocked]`. The
  goal remains standing for the user, but auto-continuation pauses.

The agent loop intercepts `goal` calls because it owns the standing state and
durable log. The definition's executor is only a stateless fallback for direct
registry dispatch: it validates the arguments and responds without changing
goal state.

## Schema

This checked example doubles as a readable snapshot of the tool's public JSON
contract:

```mbt check
///|
test "goal tool schema" {
  let tool = @goal.definition()
  assert_eq(tool.name, "goal")
  assert_true(tool.control)
  json_inspect(tool.schema.0, content={
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
  })
}
```

## Decoded Verdicts

`decode_status` is the public facade used by the agent loop. It preserves the
package-owned `GoalStatus` type while delegating raw JSON validation to the
internal decoder:

```mbt check
///|
test "decode every goal verdict" {
  debug_inspect(
    [
      @goal.decode_status({ "status": "met" }),
      @goal.decode_status({
        "status": "continuing",
        "remaining": "run the integration tests",
      }),
      @goal.decode_status({
        "status": "blocked",
        "reason": "waiting for repository access",
      }),
    ],
    content=(
      #|[
      #|  Met,
      #|  Continuing("run the integration tests"),
      #|  Blocked("waiting for repository access"),
      #|]
    ),
  )
}
```

## Stateless Fallback

Normal agent-loop dispatch intercepts `goal` and performs the lifecycle effects
described above. Direct registry dispatch uses the definition's stateless
fallback instead: valid arguments receive an acknowledgment, while malformed
arguments receive an actionable error without changing standing-goal state.

```mbt check
///|
async test "goal fallback validates registry calls" {
  let tools = @agent_tool.Tools([@goal.definition()])
  let accepted = @agent_tool.AgentToolCall(
    ToolCall(
      id="call_goal_met",
      name="goal",
      arguments=(
        #|{ "status": "met" }
      ),
    ),
  )
  let rejected = @agent_tool.AgentToolCall(
    ToolCall(
      id="call_goal_continuing",
      name="goal",
      arguments=(
        #|{ "status": "continuing" }
      ),
    ),
  )
  debug_inspect(
    [
      @agent_tool.execute_tool_call(accepted, tools),
      @agent_tool.execute_tool_call(rejected, tools),
    ],
    content=(
      #|[
      #|  Respond(
      #|    {
      #|      content: "goal status recorded",
      #|      is_error: false,
      #|      brief: None,
      #|      data: None,
      #|    },
      #|  ),
      #|  Respond(
      #|    {
      #|      content: "error: goal requires a string \"remaining\" when status is \"continuing\"",
      #|      is_error: true,
      #|      brief: None,
      #|      data: None,
      #|    },
      #|  ),
      #|]
    ),
  )
}
```
