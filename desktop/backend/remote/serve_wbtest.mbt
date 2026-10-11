///|
/// One run-scoped agent event as `notification_for_client` sees it.
fn client_frame(event : @wire.Event) -> @protocol.Notification? {
  notification_for_client(
    AgentEvent({ run_id: None, session: "session-1", event, }),
  )
}

///|
fn expect_notification(
  value : @protocol.Notification?,
) -> @protocol.Notification raise {
  guard value is Some(notification) else { fail("expected a notification") }
  notification
}

///|
test "remote delivery omits only canonical transcript duplicates" {
  let events : Array[@wire.Event] = [
    ToolResult(
      tool_call_id="call-1",
      tool_name="read",
      is_error=false,
      content="result",
      brief=None,
    ),
    AutoCompactionFinished(from_sequence=1, to_sequence=2, summary="summary"),
    AgentFinished(answer="answer"),
    ContextYield(to_sequence=2, answer="answer"),
  ]
  for event in events {
    assert_true(client_frame(event) is None)
  }
}

///|
test "remote delivery retains streaming runtime and error events" {
  let events : Array[@wire.Event] = [
    AgentStep(step=1),
    AssistantDelta(content="delta"),
    ReasoningDelta(content="live reasoning"),
    ReasoningMessage(content="reasoning"),
    Usage(usage={
      prompt_tokens: 1,
      completion_tokens: 2,
      total_tokens: 3,
      prompt_cache_hit_tokens: 0,
      prompt_cache_miss_tokens: 1,
    }),
    ToolCallDecodeError(
      tool_call_id="call-1",
      tool_name="read",
      error="bad arguments",
    ),
    BackgroundNotice(content="notice"),
    GoalUpdated(goal=Some("goal")),
    SteerApplied(
      kind="prompt",
      content=Content([Text("steered")]),
      submission_id=None,
    ),
    SteerDropped(content=Content([Text("late")]), submission_id=None),
    AgentAborted(reason="cancelled"),
    MaxStepsExhausted,
    AgentSetupFailed(error="setup failed"),
    CompactionStarted(from_sequence=1, to_sequence=2),
    CompactionFailed(error="compact failed"),
  ]
  for event in events {
    assert_true(client_frame(event) is Some(_))
  }
  assert_true(
    notification_for_client(
      SessionEvent({
        session: "session-1",
        sequence: 1,
        event: {
          sequence: 1,
          ts: None,
          item: User({ content: Content([Text("test")]), submission_id: None, }),
        },
        session_root: "/sessions/global",
      }),
    )
    is Some(_),
  )
}

///|
test "remote lifecycle frames keep state without transcript text" {
  let started = expect_notification(
    notification_for_client(
      AgentStarted({
        run_id: "run-1",
        submission_id: None,
        engine: None,
        model: None,
        max_steps: None,
        session: "session-1",
        session_root: None,
      }),
    ),
  )
  assert_eq(started.params(), { "run_id": "run-1", "session": "session-1" })
  let finished = expect_notification(
    notification_for_client(
      AgentFinished({
        run_id: "run-1",
        status: "finished",
        answer: Some("large answer"),
        exit_code: None,
      }),
    ),
  )
  assert_eq(finished.params(), {
    "run_id": "run-1",
    "status": "finished",
    "answer": "large answer",
  })
  let compacted = expect_notification(
    client_frame(
      CompactionFinished(
        from_sequence=1,
        to_sequence=2,
        summary="large summary",
      ),
    ),
  )
  assert_eq(compacted.params(), {
    "session": "session-1",
    "event": {
      "event": "compaction_finished",
      "from_sequence": 1,
      "to_sequence": 2,
      "summary": "",
    },
  })
  let settled_events : Array[@wire.Event] = [
    ReasoningMessage(content="large content"),
    AssistantMessage(content="large content"),
  ]
  for event in settled_events {
    let settled = expect_notification(client_frame(event))
    let event_name = match event {
      ReasoningMessage(..) => "reasoning_message"
      AssistantMessage(..) => "assistant_message"
      _ => fail("expected a semantic message")
    }
    assert_eq(settled.params(), {
      "session": "session-1",
      "event": { "event": Json(event_name), "content": "" },
    })
  }
}
