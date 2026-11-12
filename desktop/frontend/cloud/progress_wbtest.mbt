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
        {
          ..Conversation::empty(),
          loading: false,
          history_required: false,
          last_seq: Some(0),
        },
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
/// Answer the latest-page read currently in flight.
fn State::latest_read(self : State, history : History) -> State {
  metadata_update(
    self,
    Loaded(1, "session", self.conversations["session"].request, history),
  )
}

///|
/// Native events numbered from `first`, as a page after earlier turns has them.
fn native_turn(first : Int32, items : Array[Json]) -> @protocol.SessionDocument {
  @json.from_json({
    "events": Json(
      items.mapi((index, item) => {
        "sequence": Json(first + index),
        "ts": 100,
        "item": item,
      }),
    ),
  }) catch {
    _ => abort("invalid test document")
  }
}

///|
test "Cloud rereads a turn cached while running once the next turn is latest" {
  let question : Json = { "kind": "user", "payload": { "content": "question" } }
  let user : Record = {
    task_id: "task",
    kind: "user",
    data: {},
    created_at: 1,
    engine_sequence: Some(1),
  }
  let running : History = {
    offset: Some(0),
    etag: Some("running"),
    generating: true,
    prediction: None,
    session: native_turn(1, [question]),
    messages: [user],
  }
  let pending = progress_test_state()
    .progress_test_event(1, "task_started", {})
    .latest_read(running)
    .progress_test_event(2, "assistant_message", { "content": "First answer" })
    .progress_test_event(3, "agent_finished", { "answer": "First answer" })
  // A queued prompt starts the next turn before a read covers the reply.
  let next_user : Record = {
    ..user,
    task_id: "next",
    created_at: 3,
    engine_sequence: Some(3),
  }
  let moved = pending.latest_read({
    ..running,
    offset: Some(1),
    etag: Some("next"),
    session: native_turn(3, [
      { "kind": "user", "payload": { "content": "again" } },
    ]),
    messages: [next_user],
  })
  let conversation = moved.conversations["session"]
  guard conversation.history_turn_request is Some((request, 0)) else {
    fail("the turn cached while running is read again")
  }
  assert_eq(conversation.pending_assistants.length(), 1)
  // A failed reread keeps the preview and leaves the turn for the next read.
  let failed = metadata_update(
    moved,
    TurnFailed(1, "session", request, Unreachable),
  )
  assert_eq(failed.conversations["session"].pending_assistants.length(), 1)
  assert_true(failed.conversations["session"].history_turn_request is None)
  // A 304 for the next latest read still retries the stale turn.
  let validating = failed.load("session", Some("fixture"), _ => @cmd.none).0
  let retried = metadata_update(
    validating,
    HistoryUnchanged(
      1,
      "session",
      validating.conversations["session"].request,
      "next",
    ),
  )
  guard retried.conversations["session"].history_turn_request
    is Some((misplaced, 0)) else {
    fail("the next latest read retries the stale turn")
  }
  // A reply for another turn is not applied and does not ask again at once.
  let misplaced = metadata_update(
    retried,
    TurnLoaded(1, "session", misplaced, { ..running, offset: Some(4), }),
  )
  assert_true(misplaced.conversations["session"].history_turn_request is None)
  assert_eq(misplaced.sequence, retried.sequence)
  assert_eq(misplaced.conversations["session"].pending_assistants.length(), 1)
  let validating = misplaced.load("session", Some("fixture"), _ => @cmd.none).0
  let retried = metadata_update(
    validating,
    HistoryUnchanged(
      1,
      "session",
      validating.conversations["session"].request,
      "next",
    ),
  )
  guard retried.conversations["session"].history_turn_request
    is Some((request, 0)) else {
    fail("a later latest read retries the stale turn")
  }
  let settled = metadata_update(
    retried,
    TurnLoaded(1, "session", request, {
      ..running,
      session: native_turn(1, [
        question,
        { "kind": "assistant", "payload": { "content": "First answer" } },
      ]),
      messages: [
        user,
        {
          task_id: "task",
          kind: "assistant_message",
          data: {},
          created_at: 2,
          engine_sequence: Some(2),
        },
        {
          task_id: "task",
          kind: "task_finished",
          data: { "status": "completed" },
          created_at: 2,
          engine_sequence: None,
        },
      ],
    }),
  )
  let conversation = settled.conversations["session"]
  assert_true(conversation.pending_assistants.is_empty())
  assert_true(conversation.history_turn_request is None)
  assert_true(
    conversation.items(English)
    is [
      { kind: User(..), sequence: Some(1), .. },
      { kind: Assistant(prose=Some("First answer"), ..), sequence: Some(2), .. },
      { kind: User(..), sequence: Some(3), .. },
    ],
  )
}

///|
test "Cloud hides a sealed reasoning preview only after this step committed it" {
  let question : Json = { "kind": "user", "payload": { "content": "question" } }
  let earlier : Json = {
    "kind": "assistant",
    "payload": { "content": "Earlier", "reasoning_content": "Plan" },
  }
  let page : History = {
    offset: Some(0),
    etag: Some("page"),
    generating: true,
    prediction: None,
    session: native_document([question, earlier]),
    messages: [],
  }
  let streaming = progress_test_state()
    .progress_test_event(1, "task_started", {})
    .latest_read(page)
    // The step's read is still in flight when this step's reply is saved.
    .progress_test_event(3, "step", { "step": 2 })
    .progress_test_event(4, "reasoning_delta", { "content": "Plan" })
    .progress_test_event(5, "assistant_delta", { "content": "Answer" })
  let conversation = streaming.conversations["session"]
  assert_eq(conversation.reasoning_frontier, 2)
  // Identical reasoning from an earlier step is a different reply.
  assert_eq(
    conversation.visible_reasoning(conversation.items(English)),
    (Some("Plan"), true),
  )
  // The delayed read pinned the journal after this step was saved.
  let committed = streaming.latest_read({
    ..page,
    session: native_document([
      question,
      earlier,
      {
        "kind": "assistant",
        "payload": { "content": "Answer", "reasoning_content": "Plan" },
      },
    ]),
  })
  let conversation = committed.conversations["session"]
  assert_eq(
    conversation.visible_reasoning(conversation.items(English)),
    (None, true),
  )
}

///|
test "Cloud keeps an assistant preview when the latest page moves past its turn" {
  let pending = progress_test_state()
    .progress_test_event(1, "task_started", {})
    .progress_test_event(2, "assistant_message", { "content": "First answer" })
    .progress_test_event(3, "task_finished", { "status": "completed" })
  let request = pending.conversations["session"].request
  let answer : Record = {
    task_id: "task",
    kind: "assistant_message",
    data: {},
    created_at: 1,
    engine_sequence: Some(1),
  }
  let first : History = {
    offset: Some(0),
    prediction: None,
    generating: false,
    session: native_document([
      { "kind": "assistant", "payload": { "content": "First answer" } },
    ]),
    etag: None,
    messages: [answer],
  }
  let next = metadata_update(
    pending,
    Loaded(1, "session", request, {
      ..first,
      offset: Some(1),
      session: native_document([]),
      etag: Some("latest"),
      messages: [{ ..answer, task_id: "next", }],
    }),
  )
  let rechecking = next.load("session", Some("fixture"), _ => @cmd.none).0
  let validated = metadata_update(
    rechecking,
    HistoryUnchanged(1, "session", rechecking.sequence, "latest"),
  )
  assert_true(
    validated.conversations["session"].items(English)
    is [{ kind: Assistant(prose=Some("First answer"), ..), sequence: None, .. }],
  )
  let older = metadata_update(validated, LoadOlder("session"))
  let settled = metadata_update(
    older,
    OlderLoaded(1, "session", older.sequence, first),
  )
  assert_true(
    settled.conversations["session"].items(English)
    is [
      { kind: Assistant(prose=Some("First answer"), ..), sequence: Some(_), .. },
    ],
  )
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
  assert_true(conversation.items(English).is_empty())
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
  let pending = settled.progress_test_event(6, "assistant_message", {
    "content": "Answer",
    "reasoning_content": "Complete reasoning",
  })
  assert_true(
    pending.conversations["session"].items(English)
    is [
      {
        kind: Assistant(
          reasoning=Some("Complete reasoning"),
          prose=Some("Answer"),
          ..
        ),
        sequence: None,
        ..
      },
    ],
  )
  let committed : History = {
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
    etag: None,
    offset: None,
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
        data: { "content": "Answer", "reasoning_content": "Complete reasoning" },
        engine_sequence: None,
        created_at: 2,
      },
    ],
  }
  // The task start's read began before the reply's notification, but its
  // snapshot holds the record. This connection saw the task start, so every
  // reply of the task has a preview and the read hands this one off at once.
  let canonical = pending.latest_read(committed)
  assert_false(canonical.conversations["session"].history_reading)
  let conversation = canonical.conversations["session"]
  assert_true(conversation.live.reasoning.map(r => r.content) is None)
  assert_eq(conversation.items(English).length(), 2)
  assert_true(
    conversation.items(English)[1].kind
    is Assistant(reasoning=Some("Complete reasoning"), prose=Some("Answer"), ..),
  )
  let next = canonical
    .progress_test_event(8, "step", { "step": 2 })
    .progress_test_event(9, "reasoning_delta", { "content": "Next step" })
    .progress_test_event(10, "assistant_delta", { "content": "Next answer" })
    .progress_test_event(11, "reasoning_delta", { "content": "late" })
  assert_eq(
    next.conversations["session"].live.reasoning.map(r => r.content),
    Some("Next step"),
  )
  assert_true(
    next.conversations["session"].live.reasoning.map_or(false, r => r.complete),
  )
  let blank = next.progress_test_event(12, "reasoning_message", {
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
    assert_true(finished.conversations["session"].items(English).is_empty())
    let failed = compacting.progress_test_event(3, prefix + "_failed", {
      "error": "Compaction failed",
    })
    assert_false(failed.conversations["session"].controls.is_compacting())
    assert_true(failed.conversations["session"].notice is None)
    assert_true(failed.conversations["session"].generating)
    assert_true(failed.conversations["session"].items(English).is_empty())
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

///|
fn hello_page(items : Array[Json], markers : Array[Int32]) -> History {
  {
    offset: Some(0),
    etag: Some("hello-\{items.length()}"),
    generating: true,
    prediction: None,
    session: native_document(items),
    messages: markers.map(sequence => {
      task_id: "task",
      kind: "assistant_message",
      data: {},
      created_at: 2,
      engine_sequence: Some(sequence),
    }),
  }
}

///|
test "Cloud hands a reply to a read that began before its notification when the task was observed from its start" {
  let question : Json = { "kind": "user", "payload": { "content": "Hello" } }
  let reply : Json = { "kind": "assistant", "payload": { "content": "Hello!" } }
  // The task start's read is in flight when the first step begins, so the
  // step's read follows it and is still in flight when the reply arrives.
  let stepping = progress_test_state()
    .progress_test_event(1, "task_started", {})
    .progress_test_event(2, "step", { "step": 1 })
    .latest_read(hello_page([question], []))
  assert_true(stepping.conversations["session"].history_reading)
  let replied = stepping.progress_test_event(3, "assistant_message", {
    "content": "Hello!",
  })
  // That read's snapshot was taken after the reply was saved. Showing the
  // record while keeping the preview would render the reply twice.
  let settled = replied.latest_read(hello_page([question, reply], [2]))
  let conversation = settled.conversations["session"]
  assert_true(conversation.pending_assistants.is_empty())
  assert_true(
    conversation.items(English)
    is [
      { kind: User(..), sequence: Some(1), .. },
      { kind: Assistant(prose=Some("Hello!"), ..), sequence: Some(2), .. },
    ],
  )
  // A record read before its notification arrives is handed off when the
  // notification creates the preview, without waiting for another read.
  let early = stepping.latest_read(hello_page([question, reply], [2]))
  let notified = early.progress_test_event(3, "assistant_message", {
    "content": "Hello!",
  })
  let conversation = notified.conversations["session"]
  assert_true(conversation.pending_assistants.is_empty())
  assert_true(
    conversation.items(English)
    is [
      { kind: User(..), sequence: Some(1), .. },
      { kind: Assistant(prose=Some("Hello!"), ..), sequence: Some(2), .. },
    ],
  )
}

///|
test "Cloud tool loop hands identical replies to their own native records" {
  let reply : Json = {
    "kind": "assistant",
    "payload": { "content": "Repeated" },
  }
  let tool : Json = {
    "kind": "tool_result",
    "payload": {
      "tool_call_id": "call",
      "tool_name": "read",
      "content": "ok",
      "is_error": false,
    },
  }
  let marker : Record = {
    task_id: "task",
    kind: "assistant_message",
    data: {},
    engine_sequence: Some(1),
    created_at: 1,
  }
  let page : History = {
    offset: Some(0),
    etag: Some("page"),
    generating: true,
    prediction: None,
    session: native_document([]),
    messages: [],
  }
  // The task start began a read. Reply and tool events are previews, but the
  // next step's barrier arrives while that read is in flight and waits for it.
  let started = progress_test_state().progress_test_event(1, "task_started", {})
  let reading = started.conversations["session"].request
  let first = started
    .progress_test_event(2, "assistant_message", { "content": "Repeated" })
    .progress_test_event(3, "tool_result", {
      "tool_call_id": "call",
      "tool_name": "read",
      "content": "ok",
      "is_error": false,
    })
  assert_eq(first.sequence, started.sequence)
  let first = first.progress_test_event(4, "step", { "step": 2 })
  assert_eq(first.conversations["session"].request, reading)
  let first = first.latest_read(page)
  assert_true(first.conversations["session"].request > reading)
  assert_eq(first.conversations["session"].pending_assistants.length(), 1)
  // The second reply's notification arrives while the follow-up read is in
  // flight. The record is saved soon after, so the read already covers it.
  // This connection saw the task start, so the read hands it off at once.
  let looped = first.progress_test_event(5, "assistant_message", {
    "content": "Repeated",
  })
  assert_eq(
    looped.conversations["session"].request,
    first.conversations["session"].request,
  )
  let covered = looped.latest_read({
    ..page,
    session: native_document([reply, tool, reply]),
    messages: [marker, { ..marker, engine_sequence: Some(3), }],
  })
  let conversation = covered.conversations["session"]
  assert_false(conversation.history_reading)
  assert_true(conversation.pending_assistants.is_empty())
  assert_true(
    conversation.items(English)
    is [
      { kind: Assistant(prose=Some("Repeated"), ..), sequence: Some(1), .. },
      { kind: Assistant(prose=Some("Repeated"), ..), sequence: Some(3), .. },
    ],
  )
}

///|
test "Cloud keeps a joined task's preview until a read that began after its notification" {
  let reply : Json = {
    "kind": "assistant",
    "payload": { "content": "Repeated" },
  }
  let started = progress_test_state().progress_test_event(1, "task_started", {})
  // Join the running task without its start, as after a reconnect. An older
  // identical reply may then have no preview of its own.
  let joined = started.replace("session", {
    ..started.conversations["session"],
    live_task: None,
  })
  let replied = joined.progress_test_event(2, "assistant_message", {
    "content": "Repeated",
  })
  // The read in flight began before the notification. Its matching record is
  // no proof of ownership, so the preview stays.
  let cached = replied.latest_read(hello_page([reply], [1]))
  assert_eq(cached.conversations["session"].pending_assistants.length(), 1)
  // The terminal barrier's read gets a 304. The cached page it validates holds
  // the record, so the preview hands off in the same update.
  let finishing = cached.progress_test_event(3, "agent_finished", {
    "answer": "Repeated",
  })
  let validated = metadata_update(
    finishing,
    HistoryUnchanged(
      1,
      "session",
      finishing.conversations["session"].request,
      "hello-1",
    ),
  )
  let conversation = validated.conversations["session"]
  assert_true(conversation.pending_assistants.is_empty())
  assert_true(
    conversation.items(English)
    is [{ kind: Assistant(prose=Some("Repeated"), ..), sequence: Some(1), .. }],
  )
}
