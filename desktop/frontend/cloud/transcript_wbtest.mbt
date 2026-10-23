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
