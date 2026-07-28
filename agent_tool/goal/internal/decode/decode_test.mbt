///|
test "decode all goal verdicts" {
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

///|
test "decode explains how to repair malformed arguments" {
  debug_inspect(
    [
      decode_error({ "status": "continuing" }),
      decode_error({ "status": "continuing", "remaining": "  " }),
      decode_error({ "status": "blocked" }),
      decode_error({ "status": "blocked", "reason": "\n" }),
      decode_error({ "status": "done" }),
      decode_error({ "remaining": "wire the CLI" }),
    ],
    content=(
      #|[
      #|  "goal requires a string \"remaining\" when status is \"continuing\"",
      #|  "goal requires a non-blank \"remaining\" when status is \"continuing\"",
      #|  "goal requires a string \"reason\" when status is \"blocked\"",
      #|  "goal requires a non-blank \"reason\" when status is \"blocked\"",
      #|  "goal status must be \"met\", \"continuing\", or \"blocked\", got \"done\"",
      #|  "goal requires a string \"status\" field",
      #|]
    ),
  )
}

///|
test "decode preserves actionable text exactly" {
  debug_inspect(
    @decode.decode({
      "status": "continuing",
      "remaining": "  keep the original spacing  ",
    }),
    content=(
      #|Continuing("  keep the original spacing  ")
    ),
  )
}

///|
fn decode_error(arguments : Json) -> String {
  try @decode.decode(arguments) catch {
    error => @tool_error.failure_message("\{error}")
  } noraise {
    status => "unexpected success: \{Repr(status)}"
  }
}
