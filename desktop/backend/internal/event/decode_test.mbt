///|
test "decode usage event" {
  // The engine nests the counters under a `usage` object, serialized from the
  // protocol's `Usage` struct — so all five are always present on the wire.
  let event = @event.decode_event({
    "event": "usage",
    "usage": {
      "prompt_tokens": 9,
      "completion_tokens": 3,
      "total_tokens": 12,
      "prompt_cache_hit_tokens": 0,
      "prompt_cache_miss_tokens": 9,
    },
  })
  match event {
    Some(Usage(info)) => assert_eq(info.total_tokens, 12)
    _ => fail("expected usage event")
  }
}

///|
test "decode assistant events" {
  match
    @event.decode_event({ "event": "assistant_message", "content": "hello" }) {
    Some(AssistantMessage(text)) => assert_eq(text, "hello")
    _ => fail("expected assistant message")
  }
  assert_true(
    @event.decode_event({ "event": "reasoning_delta", "content": "live" })
    is None,
  )
}

///|
test "decode steer acknowledgement events" {
  match
    @event.decode_event({ "event": "steer_applied", "content": "accepted" }) {
    Some(SteerApplied(text)) => assert_eq(text, "accepted")
    _ => fail("expected steer applied")
  }
  match @event.decode_event({ "event": "steer_dropped", "content": "late" }) {
    Some(SteerDropped(text)) => assert_eq(text, "late")
    _ => fail("expected steer dropped")
  }
}

///|
test "decode tool and terminal events" {
  match
    @event.decode_event({
      "event": "tool_result",
      "tool_call_id": "call_1",
      "tool_name": "shell",
      "content": "ok",
      "is_error": false,
    }) {
    Some(ToolResult(result)) => {
      assert_eq(result.name, "shell")
      assert_eq(result.content, "ok")
      assert_false(result.is_error)
    }
    _ => fail("expected tool result")
  }
  match @event.decode_event({ "event": "agent_finished", "answer": "done" }) {
    Some(AgentFinished(answer)) => assert_eq(answer, "done")
    _ => fail("expected finished event")
  }
}

///|
test "unknown events are ignored" {
  assert_true(
    @event.decode_event({ "event": "future_event", "value": 1 }) is None,
  )
  assert_true(@event.decode_event(Json(([] : Array[Json]))) is None)
}

///|
test "turn_failed is terminal for the run" {
  match @event.decode_event({ "event": "turn_failed", "error": "boom" }) {
    Some(AgentError(message)) => assert_eq(message, "turn failed: boom")
    _ => fail("expected agent error")
  }
}

///|
test "context_yield is its own run terminal" {
  match
    @event.decode_event({
      "event": "context_yield",
      "to_sequence": 41,
      "answer": "[context ceiling] checkpointed",
    }) {
    Some(ContextYield(answer)) =>
      assert_eq(answer, "[context ceiling] checkpointed")
    _ => fail("expected context yield")
  }
}

///|
test "subrun brackets are the webview's, not the host's" {
  // The outer run reads busy to the host throughout a sub-run; the webview
  // renders the brackets itself off the raw stream.
  assert_true(
    @event.decode_event({
      "event": "subrun_started",
      "id": "sr-1",
      "kind": "review",
      "label": "goal review",
    })
    is None,
  )
  assert_true(
    @event.decode_event({
      "event": "subrun_finished",
      "id": "sr-1",
      "status": "captured",
      "steps": 12,
      "prompt_tokens": 34000,
      "completion_tokens": 5600,
    })
    is None,
  )
}
