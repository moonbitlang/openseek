///|
fn progress_test_state() -> State {
  let state = {
    ..State::empty(),
    user_id: Some("user"),
    epoch: 1,
    sessions: [live_test_session()],
    conversations: Map([
      (
        "session",
        { ..Conversation::empty(), loading: false, history_required: false, },
      ),
    ]),
  }
  update(
    state,
    Submit(@interop.Cloud(account="user", session="session"), {
      task: "question",
      images: [],
      mentions: [],
    }),
    _ => @cmd.none,
    token="ts_fixture",
    navigation=0,
  ).0
}

///|
fn State::progress_test_event(
  self : State,
  seq : Int32,
  kind : String,
  data : Json,
) -> State {
  if kind is ("task_started" | "task_finished") {
    return update(
        self,
        StreamEvent(1, "session", self.conversations["session"].request, {
          session_id: "session",
          task_id: "task",
          seq,
          kind,
          data,
        }),
        _ => @cmd.none,
        token="ts_fixture",
        navigation=0,
      ).0
  }
  guard data is Object(fields) else { abort("event object") }
  let fields = fields.copy()
  fields["event"] = Json(if kind == "step" { "agent_step" } else { kind })
  self.engine_event(
    "session",
    { session_id: "session", task_id: Some("task"), seq, data: Json(fields), },
    Some("ts_fixture"),
    _ => @cmd.none,
  ).0
}

///|
test "Cloud reasoning settles into one canonical assistant and rejects late fragments" {
  let started = progress_test_state().progress_test_event(1, "task_started", {})
  let partial = started
    .progress_test_event(2, "reasoning_delta", { "content": "Consider " })
    .progress_test_event(3, "reasoning_delta", { "content": "the input" })
  let conversation = partial.conversations["session"]
  assert_eq(
    conversation.live.reasoning.map(r => r.content),
    Some("Consider the input"),
  )
  assert_false(conversation.live.reasoning.map_or(false, r => r.complete))
  assert_true(conversation.items().is_empty())
  let settled = partial
    .progress_test_event(4, "reasoning_message", {
      "content": "Complete reasoning",
    })
    .progress_test_event(5, "reasoning_delta", { "content": "late" })
  assert_eq(
    settled.conversations["session"].live.reasoning.map(r => r.content),
    Some("Complete reasoning"),
  )
  assert_true(
    settled.conversations["session"].live.reasoning.map_or(false, r => {
      r.complete
    }),
  )
  let canonical = settled.progress_test_event(6, "assistant_message", {
    "content": "Answer",
    "reasoning_content": "Complete reasoning",
  })
  assert_true(canonical.conversations["session"].items().is_empty())
  let canonical = metadata_update(
    canonical,
    Loaded(1, "session", canonical.conversations["session"].request, {
      prediction: None,
      generating: true,
      session: native_document([
        { "kind": "user", "payload": { "content": "question" } },
        {
          "kind": "assistant",
          "payload": {
            "content": "Answer",
            "reasoning_content": "Complete reasoning",
          },
        },
      ]),
      messages: [
        {
          task_id: "task",
          kind: "user",
          data: { "content": "question" },
          engine_sequence: Some(1),
          created_at: 1,
        },
        {
          task_id: "task",
          kind: "assistant_message",
          data: {
            "content": "Answer",
            "reasoning_content": "Complete reasoning",
          },
          engine_sequence: None,
          created_at: 2,
        },
      ],
    }),
  )
  let conversation = canonical.conversations["session"]
  assert_true(conversation.live.reasoning.map(r => r.content) is None)
  assert_eq(conversation.items().length(), 2)
  assert_true(
    conversation.items()[1].kind
    is Assistant(reasoning=Some("Complete reasoning"), prose=Some("Answer"), ..),
  )
  let next = canonical
    .progress_test_event(7, "step", { "step": 2 })
    .progress_test_event(8, "reasoning_delta", { "content": "Next step" })
    .progress_test_event(9, "assistant_delta", { "content": "Next answer" })
    .progress_test_event(10, "reasoning_delta", { "content": "late" })
  assert_eq(
    next.conversations["session"].live.reasoning.map(r => r.content),
    Some("Next step"),
  )
  assert_true(
    next.conversations["session"].live.reasoning.map_or(false, r => r.complete),
  )
  let blank = next.progress_test_event(11, "reasoning_message", {
    "content": "",
  })
  assert_true(
    blank.conversations["session"].live.reasoning.map(r => r.content) is None,
  )
}

///|
test "Cloud stage and usage use validated per-response values rather than cumulative or missing counters" {
  let sending = progress_test_state()
  assert_true(
    sending.conversations["session"].heartbeat is Some({ stage: Starting, .. }),
  )
  let started = sending.progress_test_event(1, "task_started", {})
  assert_true(
    started.conversations["session"].heartbeat is Some({ stage: Thinking, .. }),
  )
  let step = started.progress_test_event(2, "step", { "step": 3 })
  let used = step.progress_test_event(3, "usage", {
    "usage": {
      "prompt_tokens": 100,
      "completion_tokens": 20,
      "total_tokens": 120,
      "prompt_cache_hit_tokens": 50,
      "prompt_cache_miss_tokens": 50,
    },
  })
  assert_true(
    used.conversations["session"].heartbeat
    is Some({ stage: AtStep(3), started_ms: None, tokens: 120, }),
  )
  let malformed_usage : Array[Json] = [
    { "usage": { "prompt_tokens": 200 } },
    {
      "usage": {
        "prompt_tokens": -1,
        "completion_tokens": 20,
        "total_tokens": 19,
        "prompt_cache_hit_tokens": 0,
        "prompt_cache_miss_tokens": 0,
      },
    },
  ]
  for data in malformed_usage {
    let malformed = used.progress_test_event(4, "usage", data)
    assert_eq(
      malformed.conversations["session"].heartbeat,
      used.conversations["session"].heartbeat,
    )
  }
  let retry = used.progress_test_event(5, "stream_retry", {
    "attempt": 1,
    "max_attempts": 3,
    "reason": "network",
  })
  assert_true(
    retry.conversations["session"].run_heartbeat()
    is Some(
      {
        stage: Retrying(attempt=1, max_attempts=3, reason="network"),
        tokens: 120,
        ..
      }
    ),
  )
  let response = retry.progress_test_event(6, "usage", {
    "usage": {
      "prompt_tokens": 200,
      "completion_tokens": 30,
      "total_tokens": 230,
      "prompt_cache_hit_tokens": 100,
      "prompt_cache_miss_tokens": 100,
    },
  })
  assert_true(
    response.conversations["session"].run_heartbeat()
    is Some({ stage: AtStep(3), tokens: 230, .. }),
  )
  assert_true(
    response.conversations["session"].heartbeat is Some({ tokens: 230, .. }),
  )
  let finished = response.progress_test_event(7, "task_finished", {
    "status": "completed",
    "result": { "usage": { "total_tokens": 350 }, "steps": 3 },
  })
  assert_true(finished.conversations["session"].heartbeat is None)
  assert_false(finished.conversations["session"].generating)
}

///|
test "Cloud retry ends on same-step progress without waiting for another step" {
  let retry = progress_test_state()
    .progress_test_event(1, "task_started", {})
    .progress_test_event(2, "step", { "step": 3 })
    .progress_test_event(3, "stream_retry", {
      "attempt": 1,
      "max_attempts": 3,
      "reason": "network",
    })
  assert_true(
    retry.conversations["session"].run_heartbeat()
    is Some({ stage: Retrying(..), .. }),
  )
  let background = retry.progress_test_event(4, "auto_compaction_started", {
    "from_sequence": 1,
    "to_sequence": 3,
  })
  assert_true(
    background.conversations["session"].run_heartbeat()
    is Some({ stage: Retrying(..), .. }),
  )
  let progress : Array[(String, Json)] = [
    ("reasoning_delta", { "content": "thinking" }),
    ("reasoning_message", { "content": "thought" }),
    ("assistant_delta", { "content": "answer" }),
    ("assistant_message", { "content": "answer" }),
    (
      "tool_result",
      {
        "tool_call_id": "call",
        "tool_name": "read",
        "content": "result",
        "is_error": false,
      },
    ),
  ]
  for (kind, data) in progress {
    let recovered = retry.progress_test_event(4, kind, data)
    assert_true(
      recovered.conversations["session"].run_heartbeat()
      is Some({ stage: AtStep(3), .. }),
    )
  }
}

///|
test "Cloud compaction follows native lifecycle without treating failure as a task result" {
  let started = progress_test_state().progress_test_event(1, "task_started", {})
  let started = started.replace("session", {
    ..started.conversations["session"],
    history_required: false,
  })
  assert_false(started.conversations["session"].controls.is_compacting())
  for prefix in ["compaction", "auto_compaction"] {
    let compacting = started.progress_test_event(2, prefix + "_started", {
      "from_sequence": 1,
      "to_sequence": 10,
    })
    assert_true(compacting.conversations["session"].controls.is_compacting())
    let finished = compacting.progress_test_event(3, prefix + "_finished", {
      "from_sequence": 1,
      "to_sequence": 10,
      "summary": "Earlier work",
    })
    assert_false(finished.conversations["session"].controls.is_compacting())
    assert_true(finished.conversations["session"].items().is_empty())
    let failed = compacting.progress_test_event(3, prefix + "_failed", {
      "error": "Compaction failed",
    })
    assert_false(failed.conversations["session"].controls.is_compacting())
    assert_true(failed.conversations["session"].notice is None)
    assert_true(failed.conversations["session"].generating)
    assert_true(failed.conversations["session"].items().is_empty())
  }
}

///|
test "Cloud stream boundaries clear provisional reasoning and fence terminal callbacks" {
  let live = progress_test_state()
    .progress_test_event(1, "task_started", {})
    .progress_test_event(2, "reasoning_delta", {
      "content": "Partial reasoning",
    })
  let request = live.conversations["session"].request
  let stream = StreamLease::new()
  let live = live.replace("session", {
    ..live.conversations["session"],
    stream: Some(stream),
  })
  let (late_http, _, _) = update(
    live,
    SendFailed(1, "session", request, Unreachable),
    _ => @cmd.none,
    token="ts_fixture",
    navigation=0,
  )
  assert_true(late_http == live)
  let (disconnected, _, _) = update(
    live,
    WatchEnded(1, "session", stream, Some(Unreachable)),
    _ => @cmd.none,
    token="ts_fixture",
    navigation=0,
  )
  assert_true(
    disconnected.conversations["session"].live.reasoning.map(r => r.content)
    is None,
  )
  assert_true(disconnected.conversations["session"].heartbeat is None)
  assert_false(
    disconnected.conversations["session"].live.reasoning.map_or(false, r => {
      r.complete
    }),
  )
  let retry = live.progress_test_event(3, "stream_retry", {
    "attempt": 1,
    "max_attempts": 3,
    "reason": "retry",
  })
  assert_true(
    retry.conversations["session"].live.reasoning.map(r => r.content) is None,
  )
  let terminal = live.progress_test_event(3, "task_finished", {
    "status": "failed",
  })
  assert_true(
    terminal.conversations["session"].live.reasoning.map(r => r.content) is None,
  )
  let late = terminal.progress_test_event(4, "reasoning_delta", {
    "content": "late",
  })
  assert_true(
    late.conversations["session"].live.reasoning.map(r => r.content) is None,
  )
  assert_false(late.conversations["session"].generating)
}
