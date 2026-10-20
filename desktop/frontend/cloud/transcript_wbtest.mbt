///|
test "Cloud history and SSE use the shared message projector with rich tool results" {
  let events : Array[(String, Json)] = [
    ("user", { "content": "  hello  " }),
    ("assistant_message", { "content": "  answer  " }),
    (
      "tool_call",
      { "id": "call", "function": { "name": "mbtx", "arguments": "{}" } },
    ),
    (
      "tool_result",
      {
        "tool_call_id": "call",
        "tool_name": "mbtx",
        "content": "first",
        "is_error": false,
      },
    ),
    ("tool_call", { "id": "call", "name": "mbtx", "arguments": "{}" }),
    (
      "tool_result",
      {
        "tool_call_id": "call",
        "tool_name": "mbtx",
        "content": [{ "type": "text", "text": "second" }],
        "is_error": true,
        "brief": "ran script",
        "data": {
          "ptc_calls": [
            {
              "name": "read",
              "arguments": { "path": "moon.mod" },
              "status": "done",
              "result": { "content": "module", "is_error": false },
            },
          ],
        },
      },
    ),
  ]
  let records = events.map(event => {
    task_id: "task",
    kind: event.0,
    data: event.1,
    created_at: 100,
  })
  let history = { ..Conversation::empty(), records, }.items()
  let stream = {
    ..Conversation::empty(),
    events: events.mapi((index, event) => {
      session_id: "session",
      task_id: "task",
      seq: index + 1,
      kind: event.0,
      data: event.1,
    }),
  }.items()
  assert_true(history.map(item => item.kind) == stream.map(item => item.kind))
  assert_true(
    history[0].kind is @transcript.User(content=Content([Text("hello")])),
  )
  assert_true(
    history[1].kind is @transcript.Assistant(prose=Some("answer"), ..),
  )
  assert_true(
    history[2].kind
    is @transcript.Assistant(
      calls=[
        {
          outcome: @transcript.Done(
            content=Content([Text("first")]),
            brief=None,
            ..
          ),
          ..
        },
      ],
      ..
    ),
  )
  assert_true(
    history[3].kind
    is @transcript.Assistant(
      calls=[
        {
          outcome: @transcript.Done(
            content=Content([Text("second")]),
            brief=Some("ran script"),
            is_error=true
          ),
          children: [{ name: "read", .. }],
          ..
        },
      ],
      ..
    ),
  )
  assert_true(
    history.all(item => item.ts == Some(100) && item.sequence is None),
  )
  assert_true(stream.all(item => item.ts is None && item.sequence is None))
}

///|
test "Cloud task status and unknown events remain visible without inventing messages" {
  let items : Array[@transcript.TranscriptItem] = []
  append_item(items, "task_finished", { "status": "completed" }, None)
  append_item(items, "task_finished", { "status": "failed" }, None)
  append_item(items, "future_event", { "value": 1 }, None)
  assert_true(items[0].kind is @transcript.TurnEnd)
  assert_true(
    items[1].kind is @transcript.Notice(label="Task failed", is_error=true, ..),
  )
  assert_true(
    items[2].kind is @transcript.Notice(label="future_event", body=Some(_), ..),
  )
}

///|
test "Cloud completion uses only the actual result answer and avoids duplicate prose" {
  let items : Array[@transcript.TranscriptItem] = []
  append_item(
    items,
    "assistant_message",
    { "content": "final answer" },
    Some(100),
  )
  append_item(
    items,
    "task_finished",
    {
      "status": "completed",
      "result": { "output": { "answer": "final answer" } },
    },
    Some(200),
  )
  assert_eq(items.length(), 1)
  assert_true(
    items[0].kind
    is @transcript.Assistant(prose=Some("final answer"), finished=true, ..),
  )
  assert_true(items[0].ts == Some(100))
  append_item(
    items,
    "task_finished",
    {
      "status": "completed",
      "result": { "output": { "answer": "completion tool answer" } },
    },
    Some(300),
  )
  assert_true(items[1].kind is @transcript.Answer("completion tool answer"))
}

///|
test "Cloud export preserves committed text, tool arguments, results and failures" {
  let records : Array[Record] = [
    {
      task_id: "task",
      kind: "user",
      data: { "content": "Question </script>" },
      created_at: 100,
    },
    {
      task_id: "task",
      kind: "tool_call",
      data: {
        "id": "call",
        "function": { "name": "mbtx", "arguments": "{\"source\":\"script\"}" },
      },
      created_at: 101,
    },
    {
      task_id: "task",
      kind: "tool_result",
      data: {
        "tool_call_id": "call",
        "tool_name": "mbtx",
        "content": "result",
        "is_error": true,
        "data": { "extra": "retained" },
      },
      created_at: 102,
    },
    {
      task_id: "task",
      kind: "task_finished",
      data: { "status": "failed" },
      created_at: 103,
    },
  ]
  let exported = history_record({ messages: records, generating: false, })
  let lines = [ for line in exported.split("\n") if !line.is_empty() => line ]
  assert_eq(lines.length(), 4)
  let call = @json.parse(lines[1])
  assert_true(
    call
    is {
      "sequence": 2,
      "ts": 101,
      "item": {
        "kind": "assistant",
        "payload": {
          "tool_calls": [
            {
              "id": "call",
              "name": "mbtx",
              "arguments": "{\"source\":\"script\"}",
              ..
            },
          ],
          ..
        },
        ..
      },
      ..
    },
  )
  assert_true(
    @json.parse(lines[2])
    is {
      "item": {
        "kind": "tool_result",
        "payload": {
          "content": "result",
          "is_error": true,
          "data": { "extra": "retained", .. },
          ..
        },
        ..
      },
      ..
    },
  )
  assert_true(
    @json.parse(lines[3])
    is {
      "item": { "kind": "terminal", "payload": { "kind": "failed", .. }, .. },
      ..
    },
  )
}

///|
test "downloaded assistant history decodes through the visualizer log parser" {
  let history = decode_history({
    "messages": [
      {
        "task_id": "task-example",
        "kind": "assistant_message",
        "data": { "content": "Visible answer" },
        "created_at": 100,
      },
    ],
    "generating": false,
  })
  let parsed = @session_log.parse_events(history_record(history))
  assert_eq(parsed.errors.length(), 0)
  assert_eq(parsed.events.length(), 1)
}

///|
test "Cloud history preserves reasoning-only assistant messages without a separate reasoning row" {
  let history = decode_history({
    "messages": [
      {
        "task_id": "task",
        "kind": "assistant_message",
        "data": { "content": "", "reasoning_content": "Consider the input" },
        "created_at": 100,
      },
    ],
    "generating": false,
  })
  let items = { ..Conversation::empty(), records: history.messages, }.items()
  assert_eq(items.length(), 1)
  assert_true(
    items[0].kind
    is Assistant(reasoning=Some("Consider the input"), prose=None, calls=[], ..),
  )
  let parsed = @session_log.parse_events(history_record(history))
  assert_eq(parsed.errors.length(), 0)
  assert_eq(parsed.events.length(), 1)
}
