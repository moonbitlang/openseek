///|
test "decode usage event" {
  // The engine nests the counters under a `usage` object (`print_usage`
  // serializes the DeepSeek `Usage` struct verbatim).
  let event = @event.decode_event({
    "event": "usage",
    "usage": { "prompt_tokens": 9, "completion_tokens": 3, "total_tokens": 12 },
  })
  match event {
    Some(Usage(info)) => assert_eq(info.total_tokens, 12)
    _ => fail("expected usage event")
  }
}

///|
test "decode assistant and runtime events" {
  match
    @event.decode_event({ "event": "assistant_message", "content": "hello" }) {
    Some(AssistantMessage(text)) => assert_eq(text, "hello")
    _ => fail("expected assistant message")
  }
  match
    @event.decode_event({ "event": "runtime_update", "content": "watch update" }) {
    Some(RuntimeUpdate(text)) => assert_eq(text, "watch update")
    _ => fail("expected runtime update")
  }
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
  assert_true(@event.decode_event(Json::array([])) is None)
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
