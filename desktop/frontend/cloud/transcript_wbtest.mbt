///|
fn native_document(items : Array[Json]) -> @protocol.SessionDocument {
  @json.from_json({
    "events": Json(
      items.mapi((index, item) => {
        "sequence": Json(index + 1),
        "ts": 100,
        "item": item,
      }),
    ),
  }) catch {
    _ => abort("invalid test document")
  }
}

///|
test "Cloud renders native history through the Local projector including goals and summaries" {
  let document = native_document([
    { "kind": "user", "payload": { "content": "  hello  " } },
    {
      "kind": "assistant",
      "payload": {
        "content": "answer",
        "reasoning_content": "Thinking",
        "tool_calls": [{ "id": "call", "name": "mbtx", "arguments": "{}" }],
      },
    },
    {
      "kind": "tool_result",
      "payload": {
        "tool_call_id": "call",
        "tool_name": "mbtx",
        "content": "result",
        "is_error": false,
      },
    },
    { "kind": "runtime_notice", "payload": { "content": "[goal]\nShip it" } },
    {
      "kind": "summary",
      "payload": {
        "content": "Earlier context",
        "from_sequence": 1,
        "to_sequence": 3,
      },
    },
    {
      "kind": "terminal",
      "payload": { "kind": "finished", "message": "Final" },
    },
  ])
  let conversation = { ..Conversation::empty(), document, }
  let shared = @transcript.session_from_reply({
    session: document,
    watermark: None,
    prediction: None,
  })
  assert_true(conversation.items() == shared.items)
  assert_true(
    conversation.items()[0].kind is User(content=Content([Text("hello")])),
  )
  assert_true(
    conversation.items()[1].kind
    is Assistant(
      reasoning=Some("Thinking"),
      calls=[{ outcome: Done(..), .. }],
      ..
    ),
  )
  assert_true(
    conversation.items().any(item => item.kind is Summary("Earlier context")),
  )
  assert_true(
    conversation.restore_goal(document).goal.standing
    is Some({ text: "Ship it", .. }),
  )
  // Repeated snapshots replace canonical history; they never append equal text.
  let state = controls_fixture().replace("session", {
    ..conversation,
    request: 9,
  })
  let history : History = {
    session: document,
    messages: [],
    generating: false,
  }
  let once = metadata_update(state, Loaded(1, "session", 9, history))
  let twice = metadata_update(once, Loaded(1, "session", 9, history))
  assert_true(
    once.conversations["session"].items() ==
    twice.conversations["session"].items(),
  )
}

///|
test "Cloud requires the native session document and preserves reasoning-only records" {
  let history = decode_history({
    "messages": [],
    "generating": false,
    "session": {
      "events": [
        {
          "sequence": 1,
          "item": {
            "kind": "assistant",
            "payload": {
              "content": "",
              "reasoning_content": "Consider the input",
            },
          },
        },
      ],
    },
  })
  let items = { ..Conversation::empty(), document: history.session, }.items()
  assert_true(
    items
    is [
      {
        kind: Assistant(
          reasoning=Some("Consider the input"),
          prose=None,
          calls=[],
          ..
        ),
        ..
      },
    ],
  )
  let rejected = try {
    ignore(decode_history({ "messages": [], "generating": false }))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "Cloud preserves submitted input and startup failure when the native log is empty" {
  let base = controls_fixture()
  let history : History = {
    session: native_document([]),
    generating: false,
    messages: [
      {
        task_id: "failed-start",
        kind: "user",
        data: { "content": "Please check this" },
        created_at: 100,
      },
      {
        task_id: "failed-start",
        kind: "task_finished",
        data: { "status": "failed", "reason": "Engine could not start" },
        created_at: 101,
      },
    ],
  }
  let loaded = metadata_update(
    base,
    Loaded(1, "session", base.conversations["session"].request, history),
  )
  let items = loaded.conversations["session"].items()
  assert_true(
    items
    is [
      { kind: User(content=Content([Text("Please check this")])), .. },
      { kind: Failure("Engine could not start"), .. },
    ],
  )
  // A fresh frontend must recover both records from the same history reply.
  let reopened = metadata_update(
    controls_fixture(),
    Loaded(1, "session", 0, history),
  )
  assert_true(reopened.conversations["session"].items() == items)
}

///|
test "Cloud supplements a failed service turn after native history and removes the supplement when records arrive" {
  let document = native_document([
    { "kind": "user", "payload": { "content": "Earlier" } },
    { "kind": "assistant", "payload": { "content": "Earlier answer" } },
    {
      "kind": "terminal",
      "payload": { "kind": "finished", "message": "Earlier answer" },
    },
  ])
  let records : Array[Record] = [
    {
      task_id: "old",
      kind: "user",
      data: { "content": "Earlier" },
      created_at: 100,
    },
    {
      task_id: "failed",
      kind: "user",
      data: { "content": "Check the build", "submission_id": "input-2" },
      created_at: 101,
    },
    {
      task_id: "failed",
      kind: "task_finished",
      data: { "status": "failed", "reason": "Engine could not start" },
      created_at: 102,
    },
  ]
  let conversation = { ..Conversation::empty(), document, records, }
  assert_true(
    conversation.items()
    is [
      { kind: User(content=Content([Text("Earlier")])), .. },
      { kind: Assistant(prose=Some("Earlier answer"), ..), .. },
      {
        kind: User(content=Content([Text("Check the build")])),
        sequence: None,
        ..
      },
      { kind: Failure("Engine could not start"), sequence: None, .. },
    ],
  )
  let document = native_document([
    { "kind": "user", "payload": { "content": "Earlier" } },
    { "kind": "assistant", "payload": { "content": "Earlier answer" } },
    {
      "kind": "terminal",
      "payload": { "kind": "finished", "message": "Earlier answer" },
    },
    {
      "kind": "user",
      "payload": { "content": "Check the build", "submission_id": "input-2" },
    },
    {
      "kind": "terminal",
      "payload": { "kind": "failed", "message": "Engine could not start" },
    },
  ])
  let caught_up = { ..conversation, document, }
  let shared = caught_up.session_view().items
  assert_true(caught_up.items() == shared)
}

///|
test "Cloud service supplements preserve repeated and rich inputs without deduplicating distinct submissions" {
  let content : Json = [
    { "type": "text", "text": "Same" },
    { "type": "image", "media_type": "image/png", "data": "iVBORw0KGgo=" },
  ]
  let document = native_document([
    {
      "kind": "user",
      "payload": { "content": content, "submission_id": "first" },
    },
    {
      "kind": "terminal",
      "payload": { "kind": "finished", "message": "First answer" },
    },
  ])
  let conversation = {
    ..Conversation::empty(),
    document,
    records: [
      {
        task_id: "first-task",
        kind: "user",
        data: { "content": content, "submission_id": "first" },
        created_at: 100,
      },
      {
        task_id: "second-task",
        kind: "user",
        data: { "content": content, "submission_id": "second" },
        created_at: 101,
      },
      {
        task_id: "second-task",
        kind: "task_finished",
        data: { "status": "failed", "error": "Spawn failed" },
        created_at: 102,
      },
    ],
  }
  let items = conversation.items()
  assert_eq(items.filter(item => item.kind is User(..)).length(), 2)
  assert_true(
    items[2].kind
    is User(
      content=Content(
        [Text("Same"), ImageUrl(url="data:image/png;base64,iVBORw0KGgo=")]
      )
    ),
  )
  assert_true(items[3].kind is Failure("Spawn failed"))
  // Untagged older prompts are matched by occurrence, never by a text set.
  let repeated = {
    ..Conversation::empty(),
    document: native_document([
      { "kind": "user", "payload": { "content": "Same" } },
    ]),
    records: [
      {
        task_id: "a",
        kind: "user",
        data: { "content": "Same" },
        created_at: 100,
      },
      {
        task_id: "b",
        kind: "user",
        data: { "content": "Same" },
        created_at: 101,
      },
    ],
  }
  assert_eq(repeated.items().filter(item => item.kind is User(..)).length(), 2)
}

///|
test "Cloud shows a live service failure before the next history read without duplicating a saved result" {
  let conversation = {
    ..Conversation::empty(),
    records: [
      {
        task_id: "task",
        kind: "user",
        data: { "content": "Start" },
        created_at: 100,
      },
    ],
    events: [
      {
        session_id: "session",
        task_id: "task",
        seq: 4,
        kind: "task_finished",
        data: { "status": "failed", "reason": "Start failed" },
      },
    ],
  }
  assert_true(
    conversation.items()
    is [{ kind: User(..), .. }, { kind: Failure("Start failed"), .. }],
  )
  let saved = {
    ..conversation,
    records: conversation.records +
    [
      {
        task_id: "task",
        kind: "task_finished",
        data: { "status": "failed", "reason": "Start failed" },
        created_at: 101,
      },
    ],
  }
  assert_true(
    saved.items() ==
    conversation
    .items()
    .mapi((index, item) => {
      if index == 1 {
        { ..item, ts: Some(101), }
      } else {
        item
      }
    }),
  )
}
