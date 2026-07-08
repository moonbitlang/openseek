///|
fn event_fields(json : Json) -> Map[String, Json] raise {
  guard json is Object(fields) else { fail("expected a JSON object") }
  fields
}

///|
test "decode recognizes the streaming events" {
  guard decode_engine_event(
      event_fields({ "event": "assistant_delta", "content": "abc" }),
    )
    is Some(AssistantDelta("abc")) else {
    fail("assistant_delta not decoded")
  }
  guard decode_engine_event(
      event_fields({ "event": "reasoning_delta", "content": "th" }),
    )
    is Some(ReasoningDelta("th")) else {
    fail("reasoning_delta not decoded")
  }
  guard decode_engine_event(
      event_fields({ "event": "reasoning_message", "content": "all" }),
    )
    is Some(ReasoningMessage("all")) else {
    fail("reasoning_message not decoded")
  }
}

///|
test "decode normalizes legacy names, numbers, and unknown events" {
  // Older engines wrote `step`/`error` where current ones write
  // `content`/`reason`; the current name wins when both are present.
  assert_true(
    decode_engine_event(event_fields({ "event": "agent_step", "step": "plan" }))
    is Some(AgentStep("plan")),
  )
  assert_true(
    decode_engine_event(
      event_fields({ "event": "agent_step", "content": "now", "step": "old" }),
    )
    is Some(AgentStep("now")),
  )
  assert_true(
    decode_engine_event(
      event_fields({ "event": "agent_aborted", "error": "boom" }),
    )
    is Some(AgentAborted("boom")),
  )
  assert_true(
    decode_engine_event(
      event_fields({
        "event": "usage",
        "usage": { "prompt_tokens": 5, "completion_tokens": 7 },
      }),
    )
    is Some(Usage(prompt_tokens=5, completion_tokens=7)),
  )
  // Older top-level counters are no longer read; a shape mismatch reads as
  // zero rather than being dropped.
  assert_true(
    decode_engine_event(
      event_fields({
        "event": "usage",
        "prompt_tokens": 5,
        "completion_tokens": 7,
      }),
    )
    is Some(Usage(prompt_tokens=0, completion_tokens=0)),
  )
  assert_true(
    decode_engine_event(
      event_fields({ "event": "tool_result", "tool_name": "read" }),
    )
    is Some(ToolResult(tool_name="read", is_error=false, content="", brief="")),
  )
  assert_true(
    decode_engine_event(
      event_fields({
        "event": "tool_result",
        "tool_name": "read",
        "brief": "read moon.mod",
      }),
    )
    is Some(ToolResult(brief="read moon.mod", ..)),
  )
  assert_true(decode_engine_event(event_fields({ "event": "novel" })) is None)
}

///|
test "decode recognizes the steer events" {
  guard decode_engine_event(
      event_fields({ "event": "steer_applied", "content": "left" }),
    )
    is Some(SteerApplied("left")) else {
    fail("steer_applied not decoded")
  }
  guard decode_engine_event(
      event_fields({ "event": "steer_dropped", "content": "left" }),
    )
    is Some(SteerDropped("left")) else {
    fail("steer_dropped not decoded")
  }
}

///|
test "decode recognizes the compaction lifecycle events" {
  guard decode_engine_event(event_fields({ "event": "compaction_started" }))
    is Some(CompactionStarted) else {
    fail("compaction_started not decoded")
  }
  guard decode_engine_event(
      event_fields({ "event": "compaction_finished", "summary": "recap" }),
    )
    is Some(CompactionFinished("recap")) else {
    fail("compaction_finished not decoded")
  }
  // The engine reports the failure reason under `error`.
  guard decode_engine_event(
      event_fields({ "event": "compaction_failed", "error": "empty summary" }),
    )
    is Some(CompactionFailed("empty summary")) else {
    fail("compaction_failed not decoded")
  }
}
