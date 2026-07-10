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
  // The engine numbers its steps; a build that does not still yields the
  // event, just without a counter.
  assert_true(
    decode_engine_event(event_fields({ "event": "agent_step", "step": 3 }))
    is Some(AgentStep(Some(3))),
  )
  assert_true(
    decode_engine_event(event_fields({ "event": "agent_step" }))
    is Some(AgentStep(None)),
  )
  // Older engines wrote `error` where current ones write `reason`; the
  // current name wins when both are present.
  assert_true(
    decode_engine_event(
      event_fields({ "event": "agent_aborted", "error": "boom" }),
    )
    is Some(AgentAborted("boom")),
  )
  assert_true(
    decode_engine_event(
      event_fields({ "event": "agent_aborted", "reason": "now", "error": "old" }),
    )
    is Some(AgentAborted("now")),
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
  // A usage event whose counters are not where the engine writes them is
  // malformed and dropped, never fabricated as zeros.
  assert_true(
    decode_engine_event(
      event_fields({
        "event": "usage",
        "prompt_tokens": 5,
        "completion_tokens": 7,
      }),
    )
    is None,
  )
  // A tool_result missing fields the engine emits unconditionally is
  // dropped too.
  assert_true(
    decode_engine_event(
      event_fields({ "event": "tool_result", "tool_name": "read" }),
    )
    is None,
  )
  // `brief` is the one genuinely optional field: absent when the tool
  // supplied none (or the call was skipped).
  assert_true(
    decode_engine_event(
      event_fields({
        "event": "tool_result",
        "tool_name": "read",
        "is_error": false,
        "content": "…",
        "brief": "read moon.mod",
      }),
    )
    is Some(ToolResult(brief=Some("read moon.mod"), ..)),
  )
  assert_true(
    decode_engine_event(
      event_fields({
        "event": "tool_result",
        "tool_name": "read",
        "is_error": false,
        "content": "…",
      }),
    )
    is Some(ToolResult(brief=None, ..)),
  )
  assert_true(decode_engine_event(event_fields({ "event": "novel" })) is None)
}

///|
test "decode maps background notices onto the runtime-update path" {
  // Current engines say `background_notice`; `runtime_update` is the same
  // event's legacy name. Both carry the watcher text verbatim.
  guard decode_engine_event(
      event_fields({
        "event": "background_notice",
        "content": "[moon_check update]",
      }),
    )
    is Some(RuntimeUpdate("[moon_check update]")) else {
    fail("background_notice not decoded")
  }
  guard decode_engine_event(
      event_fields({ "event": "runtime_update", "content": "notice" }),
    )
    is Some(RuntimeUpdate("notice")) else {
    fail("runtime_update not decoded")
  }
  // The engine's plan reminder is model-directed text, not a user notice.
  assert_true(
    decode_engine_event(
      event_fields({ "event": "plan_reminder", "content": "[plan reminder]" }),
    )
    is None,
  )
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
test "decode recognizes automatic checkpoint and context yield events" {
  guard decode_engine_event(
      event_fields({
        "event": "auto_compaction_finished",
        "summary": "checkpoint recap",
      }),
    )
    is Some(AutoCompactionFinished("checkpoint recap")) else {
    fail("auto_compaction_finished not decoded")
  }
  guard decode_engine_event(
      event_fields({
        "event": "context_yield",
        "answer": "[context ceiling] continue in a new turn",
      }),
    )
    is Some(ContextYield("[context ceiling] continue in a new turn")) else {
    fail("context_yield not decoded")
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
