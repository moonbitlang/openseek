///|
fn event_fields(json : Json) -> @protocol.Event raise {
  guard @protocol.parse(json) is Some(event) else {
    fail("expected a known engine event")
  }
  event
}

///|
test "decode recognizes the streaming events" {
  assert_true(
    @transcript.decode_engine_event(
      event_fields({
        "event": "stream_retry",
        "attempt": 2,
        "max_attempts": 5,
        "reason": "Stream ended before [DONE]",
      }),
    )
    is Some(
      @transcript.StreamRetry(
        attempt=2,
        max_attempts=5,
        reason="Stream ended before [DONE]"
      )
    ),
  )
  guard @transcript.decode_engine_event(
      event_fields({ "event": "assistant_delta", "content": "abc" }),
    )
    is Some(@transcript.AssistantDelta("abc")) else {
    fail("assistant_delta not decoded")
  }
  guard @transcript.decode_engine_event(
      event_fields({ "event": "reasoning_delta", "content": "live" }),
    )
    is Some(@transcript.ReasoningDelta("live")) else {
    fail("reasoning_delta not decoded")
  }
  guard @transcript.decode_engine_event(
      event_fields({ "event": "reasoning_message", "content": "all" }),
    )
    is Some(@transcript.ReasoningMessage("all")) else {
    fail("reasoning_message not decoded")
  }
}

///|
test "decode normalizes numbers and unknown events" {
  assert_true(
    @transcript.decode_engine_event(
      event_fields({ "event": "agent_step", "step": 3 }),
    )
    is Some(@transcript.AgentStep(Some(3))),
  )
  // `agent_aborted` has carried `reason` since it existed (1f761102); the
  // `error` spelling this decoder used to also accept was never emitted.
  assert_true(
    @transcript.decode_engine_event(
      event_fields({ "event": "agent_aborted", "reason": "now" }),
    )
    is Some(@transcript.AgentAborted("now")),
  )
  assert_true(
    @transcript.decode_engine_event(
      event_fields({
        "event": "usage",
        "usage": {
          "prompt_tokens": 5,
          "completion_tokens": 7,
          "total_tokens": 12,
          "prompt_cache_hit_tokens": 0,
          "prompt_cache_miss_tokens": 5,
        },
      }),
    )
    is Some(@transcript.Usage(prompt_tokens=5, completion_tokens=7)),
  )
  // Malformed wire events are rejected before the typed projection rather
  // than reaching it with fabricated defaults.
  assert_true(
    @protocol.parse({
      "event": "usage",
      "prompt_tokens": 5,
      "completion_tokens": 7,
    })
    is None,
  )
  assert_true(
    @protocol.parse({ "event": "tool_result", "tool_name": "read" }) is None,
  )
  // `brief` is the one genuinely optional field: absent when the tool
  // supplied none (or the call was skipped).
  assert_true(
    @transcript.decode_engine_event(
      event_fields({
        "event": "tool_result",
        "tool_call_id": "call_1",
        "tool_name": "read",
        "is_error": false,
        "content": "…",
        "brief": "read moon.mod",
      }),
    )
    is Some(@transcript.ToolResult(brief=Some("read moon.mod"), ..)),
  )
  assert_true(
    @transcript.decode_engine_event(
      event_fields({
        "event": "tool_result",
        "tool_call_id": "call_1",
        "tool_name": "read",
        "is_error": false,
        "content": "…",
      }),
    )
    is Some(@transcript.ToolResult(brief=None, ..)),
  )
}

///|
test "decode maps background notices onto the notice path" {
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "background_notice",
        "content": "background job bg-1 finished (exit=0)",
      }),
    )
    is Some(
      @transcript.BackgroundNotice("background job bg-1 finished (exit=0)")
    ) else {
    fail("background_notice not decoded")
  }
  // The engine's plan reminder is model-directed text, not a user notice.
  assert_true(
    @transcript.decode_engine_event(
      event_fields({ "event": "plan_reminder", "content": "[plan reminder]" }),
    )
    is None,
  )
}

///|
test "decode recognizes the steer events" {
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "steer_applied",
        "content": "left",
        "submission_id": "input-7",
      }),
    )
    is Some(
      @transcript.SteerApplied(
        content=Content([Text("left")]),
        submission_id=Some("input-7")
      )
    ) else {
    fail("steer_applied not decoded")
  }
  guard @transcript.decode_engine_event(
      event_fields({ "event": "steer_dropped", "content": "left" }),
    )
    is Some(
      @transcript.SteerDropped(
        content=Content([Text("left")]),
        submission_id=None
      )
    ) else {
    fail("steer_dropped not decoded")
  }
  let image = @protocol.Image::from_base64(
    media_type="image/png",
    "iVBORw0KGgo=",
  )
  let content = @protocol.Content([Text("look"), Image(image), Text("here")])
  for event in ["steer_applied", "steer_dropped"] {
    let stream = event_fields({
      "event": event,
      "kind": "prompt",
      "content": content,
      "submission_id": "image-steer",
    })
    let forwarded = event_fields(stream.to_json())
    assert_true(
      @transcript.decode_engine_event(forwarded)
      is Some(
        @transcript.SteerApplied(
          content=actual,
          submission_id=Some("image-steer")
        )
        | @transcript.SteerDropped(
          content=actual,
          submission_id=Some("image-steer")
        )
      ) &&
      actual == content,
    )
  }
}

///|
test "decode recognizes automatic checkpoint and context yield events" {
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "auto_compaction_finished",
        "from_sequence": 1,
        "to_sequence": 12,
        "summary": "checkpoint recap",
      }),
    )
    is Some(@transcript.AutoCompactionFinished("checkpoint recap")) else {
    fail("auto_compaction_finished not decoded")
  }
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "context_yield",
        "to_sequence": 30,
        "answer": "[context ceiling] continue in a new turn",
      }),
    )
    is Some(
      @transcript.ContextYield("[context ceiling] continue in a new turn")
    ) else {
    fail("context_yield not decoded")
  }
}

///|
test "decode recognizes the compaction lifecycle events" {
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "compaction_started",
        "from_sequence": 1,
        "to_sequence": 9,
      }),
    )
    is Some(@transcript.CompactionStarted) else {
    fail("compaction_started not decoded")
  }
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "compaction_finished",
        "from_sequence": 1,
        "to_sequence": 9,
        "summary": "recap",
      }),
    )
    is Some(@transcript.CompactionFinished("recap")) else {
    fail("compaction_finished not decoded")
  }
  // The engine reports the failure reason under `error`.
  guard @transcript.decode_engine_event(
      event_fields({ "event": "compaction_failed", "error": "empty summary" }),
    )
    is Some(@transcript.CompactionFailed("empty summary")) else {
    fail("compaction_failed not decoded")
  }
}

///|
test "decode surfaces a failed durable append off the raw stream" {
  // The engine's only report that an idle-time append did not happen. The
  // host has no use for it and drops it, so if this arm went missing the
  // failure would reach nobody — and whatever was waiting on that append
  // would wait on a commit that is never coming.
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "session_error",
        "error": "failed to append goal update: disk full",
      }),
    )
    is Some(
      @transcript.SessionAppendFailed("failed to append goal update: disk full")
    ) else {
    fail("session_error not decoded")
  }
}

///|
test "decode maps subrun brackets onto the lane's open and close" {
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "subrun_started",
        "id": "sr-1",
        "kind": "review",
        "label": "goal review",
      }),
    )
    is Some(
      @transcript.SubrunOpened(id="sr-1", kind="review", label="goal review")
    ) else {
    fail("subrun_started not decoded")
  }
  // The finish is where a sub-run's cost is reported, so both token
  // directions survive decoding as their sum.
  guard @transcript.decode_engine_event(
      event_fields({
        "event": "subrun_finished",
        "id": "sr-1",
        "status": "captured",
        "steps": 12,
        "prompt_tokens": 34000,
        "completion_tokens": 5600,
      }),
    )
    is Some(
      @transcript.SubrunClosed(
        id="sr-1",
        status="captured",
        steps=12,
        tokens=39600
      )
    ) else {
    fail("subrun_finished not decoded")
  }
}
