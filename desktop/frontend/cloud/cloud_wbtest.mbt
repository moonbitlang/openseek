///|
test "Cloud history reads message metadata without unused IDs or outcomes" {
  let history = decode_history({
    "messages": [
      {
        "task_id": "task-a",
        "kind": "user",
        "data": { "content": "hello" },
        "created_at": 1234,
      },
    ],
    "generating": false,
  })
  assert_eq(history.messages[0].task_id, "task-a")
  assert_eq(history.messages[0].created_at, 1234)
  let event = decode_event({
    "session_id": "session-a",
    "task_id": "task-b",
    "seq": 1,
    "kind": "assistant_message",
    "data": { "content": "您好" },
  })
  assert_eq(event.seq, 1)
  assert_eq(event.task_id, "task-b")
  let invalid = try {
    ignore(
      decode_history({ "messages": [], "generating": "false", "outcome": null }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(invalid)
}

///|
test "SSE dispatches only complete events and preserves multiline data" {
  let parser = SseParser::new()
  assert_true(parser.line(": keepalive") is None)
  assert_true(parser.line("event: assistant_message\r") is None)
  assert_true(parser.line("data: {\"content\":\"您好 🌙\",\r") is None)
  assert_true(parser.line("data: \"ok\":true}\r") is None)
  assert_eq(
    parser.line("\r"),
    Some("{\"content\":\"您好 🌙\",\n\"ok\":true}"),
  )
  assert_true(parser.line("") is None)
}

///|
test "Cloud list preserves nullable and long backend titles" {
  let title = "A backend title that must remain complete even when the sidebar displays an ellipsis instead of the whole sentence"
  let sessions = decode_sessions({
    "sessions": [
      { "id": "empty", "title": null, "updated_at": 1, "generating": false },
      {
        "id": "titled",
        "title": Json(title),
        "updated_at": 2,
        "generating": true,
      },
    ],
  })
  assert_true(sessions[0].title is None)
  assert_eq(sessions[1].title, Some(title))
}

///|
fn live_test_session() -> Session {
  {
    id: "session",
    title: None,
    updated_at: None,
    generating: false,
    archived: false,
  }
}

///|
test "Busy cannot allow another send before authoritative history recovers" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  let state = {
    ..State::empty(),
    user_id: Some("user"),
    epoch: 1,
    sessions: [live_test_session()],
  }
  let (opened, _, _) = update(
    state,
    Open("session"),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let request = opened.conversations["session"].request
  let (loaded, _, _) = update(
    opened,
    Loaded(1, "session", request, { messages: [], generating: false, }),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let owner = @interop.Cloud(account="user", session="session")
  let draft : @composer.Draft = { task: "question", images: [], mentions: [], }
  let (sending, _, _) = update(
    loaded,
    Submit(owner, draft),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let (busy, _, _) = update(
    sending,
    SendFailed(1, "session", sending.sequence, Busy),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let (failed, _, _) = update(
    busy,
    LoadFailed(1, "session", busy.sequence, Http(503)),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let (blocked, _, _) = update(
    failed,
    Submit(owner, draft),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  assert_true(blocked.conversations["session"].history_required)
  assert_false(blocked.conversations["session"].sending)
  assert_eq(blocked.sequence, failed.sequence)
  let (recovered, _, _) = update(
    blocked,
    Loaded(1, "session", blocked.sequence, { messages: [], generating: false, }),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let (accepted, _, _) = update(
    recovered,
    Submit(owner, draft),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  assert_true(accepted.conversations["session"].sending)
}

///|
test "history recovery clears a send error only when the pending submission was admitted" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
  for error in [Http(422), Unreachable] {
    for admitted in [false, true] {
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
            },
          ),
        ]),
      }
      let owner = @interop.Cloud(account="user", session="session")
      let draft : @composer.Draft = { task: "hello", images: [], mentions: [], }
      let (sending, _, _) = update(
        state,
        Submit(owner, draft),
        emit,
        token="ts_fixture",
        navigation=0,
      )
      let (failed, _, _) = update(
        sending,
        SendFailed(1, "session", sending.sequence, error),
        emit,
        token="ts_fixture",
        navigation=0,
      )
      let history : History = {
        messages: if admitted {
          [
            {
              task_id: "new-task",
              kind: "user",
              data: { "content": "hello" },
              created_at: 100,
            },
          ]
        } else {
          []
        },
        generating: false,
      }
      let (recovered, _, _) = update(
        failed,
        Loaded(1, "session", failed.sequence, history),
        emit,
        token="ts_fixture",
        navigation=0,
      )
      let conversation = recovered.conversations["session"]
      assert_true(
        conversation.pending is None && !conversation.history_required,
      )
      assert_eq(conversation.submission_sequence, if admitted { 1 } else { 0 })
      assert_eq(
        conversation.notice,
        if admitted {
          None
        } else {
          Some(error.label())
        },
      )
      assert_true(
        conversation.items().any(item => item.kind is Failure(_)) == !admitted,
      )
      let (retry, _, _) = update(
        recovered,
        Submit(owner, draft),
        emit,
        token="ts_fixture",
        navigation=0,
      )
      assert_true(retry.conversations["session"].sending)
      assert_true(retry.conversations["session"].notice is None)
    }
  }
}

///|
test "Cloud text previews stay response-scoped and terminal events fence late deltas" {
  let emit : @cmd.Emit[Msg] = _ => @cmd.none
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
  let owner = @interop.Cloud(account="user", session="session")
  let (sending, _, _) = update(
    state,
    Submit(owner, { task: "hello", images: [], mentions: [], }),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  let request = sending.conversations["session"].request
  let advance = (state : State, seq : Int32, kind : String, data : Json) => {
    update(
      state,
      StreamEvent(1, "session", request, {
        session_id: "session",
        task_id: "task",
        seq,
        kind,
        data,
      }),
      emit,
      token="ts_fixture",
      navigation=0,
    ).0
  }
  let started = advance(sending, 1, "task_started", {})
  let first = advance(started, 2, "assistant_delta", { "content": "你" })
  let second = advance(first, 3, "assistant_delta", { "content": "好 🌙" })
  assert_eq(first.conversations["session"].streaming_response, Some("你"))
  assert_eq(
    second.conversations["session"].streaming_response,
    Some("你好 🌙"),
  )
  assert_eq(
    first.conversations["session"].events.length(),
    second.conversations["session"].events.length(),
  )
  let full = advance(second, 4, "assistant_message", {
    "content": "你好 🌙",
  })
  assert_true(full.conversations["session"].streaming_response is None)
  assert_true(
    full.conversations["session"].items()[1].kind
    is Assistant(prose=Some("你好 🌙"), ..),
  )
  let tool = advance(full, 5, "tool_call", {
    "id": "call",
    "name": "read",
    "arguments": "{}",
  })
  let result = advance(tool, 6, "tool_result", {
    "tool_call_id": "call",
    "tool_name": "read",
    "content": "ok",
    "is_error": false,
  })
  let unfinished = advance(result, 7, "assistant_delta", {
    "content": "unfinished step",
  })
  let step = advance(unfinished, 8, "step", { "step": 2 })
  assert_true(step.conversations["session"].streaming_response is None)
  assert_eq(
    step.conversations["session"].events.length(),
    unfinished.conversations["session"].events.length(),
  )
  let failed_attempt = advance(step, 9, "assistant_delta", {
    "content": "discarded",
  })
  let retry = advance(failed_attempt, 10, "stream_retry", {
    "attempt": 2,
    "max_attempts": 3,
    "reason": "fixture",
  })
  assert_true(retry.conversations["session"].streaming_response is None)
  let replacement = advance(retry, 11, "assistant_delta", {
    "content": "replacement",
  })
  assert_eq(
    replacement.conversations["session"].streaming_response,
    Some("replacement"),
  )
  let completed = advance(replacement, 12, "assistant_message", {
    "content": "replacement",
  })
  let ended = advance(completed, 13, "task_finished", {
    "status": "completed",
    "result": { "output": { "answer": "replacement" } },
  })
  assert_true(ended.conversations["session"].streaming_response is None)
  assert_true(
    advance(ended, 14, "assistant_delta", { "content": "late" }) == ended,
  )
  let (disconnected, _, _) = update(
    replacement,
    StreamEnded(1, "session", request),
    emit,
    token="ts_fixture",
    navigation=0,
  )
  assert_true(disconnected.conversations["session"].streaming_response is None)
}
