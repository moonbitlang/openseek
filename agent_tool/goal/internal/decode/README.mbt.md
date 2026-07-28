# Goal Argument Decoder

`bobzhang/openseek/agent_tool/goal/internal/decode` converts raw JSON tool
arguments into a typed `GoalStatus` consumed by the parent `goal` package.
The parent maps it to its own public `GoalStatus`, which keeps sibling packages
from depending on this internal implementation package.

This package owns only argument-shape validation. It does not inspect or
change the standing goal, write durable markers, or control auto-continuation;
those stateful effects belong to the agent loop.

## API

- `GoalStatus` is `Met`, `Continuing(remaining)`, or `Blocked(reason)`.
- `decode(arguments)` returns `GoalStatus` or raises an actionable `Failure`.

## Decoding Rules

| `status` | Required companion field | Decoded value |
| --- | --- | --- |
| `"met"` | none | `Met` |
| `"continuing"` | non-blank string `remaining` | `Continuing(remaining)` |
| `"blocked"` | non-blank string `reason` | `Blocked(reason)` |

Blankness is checked after trimming, but successful text is preserved exactly
for the durable record. Extra fields are ignored by this decoder; the parent
tool's JSON schema declares them invalid for callers.

## Successful Verdicts

The snapshot shows the complete typed result for every supported status:

```mbt check
///|
test "decode supported goal verdicts" {
  debug_inspect(
    [
      @decode.decode({ "status": "met" }),
      @decode.decode({ "status": "continuing", "remaining": "wire the CLI" }),
      @decode.decode({
        "status": "blocked",
        "reason": "waiting for credentials",
      }),
    ],
    content=(
      #|[Met, Continuing("wire the CLI"), Blocked("waiting for credentials")]
    ),
  )
}
```

## Validation Errors

Failures say which field must be repaired, making the returned tool error
useful without parsing or pattern matching in the caller:

```mbt check
///|
test "decode actionable validation errors" {
  debug_inspect(
    [
      decode_error_for_docs({ "status": "continuing" }),
      decode_error_for_docs({ "status": "blocked", "reason": "  " }),
      decode_error_for_docs({ "status": "done" }),
      decode_error_for_docs({ "remaining": "wire the CLI" }),
    ],
    content=(
      #|[
      #|  "goal requires a string \"remaining\" when status is \"continuing\"",
      #|  "goal requires a non-blank \"reason\" when status is \"blocked\"",
      #|  "goal status must be \"met\", \"continuing\", or \"blocked\", got \"done\"",
      #|  "goal requires a string \"status\" field",
      #|]
    ),
  )
}

///|
fn decode_error_for_docs(arguments : Json) -> String {
  try @decode.decode(arguments) catch {
    error => @tool_error.failure_message("\{error}")
  } noraise {
    status => "unexpected success: \{Repr(status)}"
  }
}
```
