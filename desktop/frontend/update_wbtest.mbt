// Purity and state-transition tests for the update handlers that back the
// streaming and session integration. Commands are opaque, so the tests assert
// on the returned model only.

///|
fn test_dispatch() -> @cmd.Dispatch[Msg] {
  Dispatch(_ => @cmd.none)
}

///|
fn test_model() -> Model {
  {
    ..initial_model(),
    bridge_ready: true,
    api_key: "sk-test",
    setup_open: false,
    status: Ready,
    session_id: "desktop-test",
  }
}

///|
fn running_model() -> Model {
  { ..test_model(), running: true, active_run_id: Some(7), status: Running }
}

///|
test "assistant deltas accumulate into the streaming response" {
  let dispatch = test_dispatch()
  let (_, first) = update(
    dispatch,
    Engine(7, AssistantDelta("Hello")),
    running_model(),
  )
  let (_, second) = update(
    dispatch,
    Engine(7, AssistantDelta(", world")),
    first,
  )
  inspect(second.streaming_response, content="Hello, world")
  inspect(second.messages.length(), content="0")
}

///|
test "update is pure: replaying a delta on the same model is idempotent" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), streaming_response: "partial" }
  let (_, once) = update(dispatch, Engine(7, AssistantDelta("!")), model)
  let (_, twice) = update(dispatch, Engine(7, AssistantDelta("!")), model)
  inspect(once.streaming_response, content="partial!")
  inspect(twice.streaming_response, content="partial!")
}

///|
test "deltas from a stale run are dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Engine(99, AssistantDelta("stale")),
    running_model(),
  )
  inspect(next.streaming_response, content="")
}

///|
test "reasoning message commits a thinking item and clears its stream" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), streaming_reasoning: "thinking…" }
  let (_, next) = update(
    dispatch,
    Engine(7, ReasoningMessage("full thought")),
    model,
  )
  inspect(next.streaming_reasoning, content="")
  inspect(next.messages.length(), content="1")
  guard next.messages[0].kind is Reasoning else { fail("expected reasoning") }
  inspect(next.messages[0].content, content="full thought")
}

///|
test "assistant message replaces the live stream with a committed item" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model(),
    streaming_response: "answ",
    streaming_reasoning: "thought",
  }
  let (_, next) = update(dispatch, Engine(7, AssistantMessage("answer")), model)
  inspect(next.streaming_response, content="")
  inspect(next.streaming_reasoning, content="")
  inspect(next.messages.length(), content="1")
  inspect(next.messages[0].content, content="answer")
}

///|
test "a new agent step clears both live streams" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model(),
    streaming_response: "left",
    streaming_reasoning: "over",
  }
  let (_, next) = update(dispatch, Engine(7, AgentStep("2")), model)
  inspect(next.streaming_response, content="")
  inspect(next.streaming_reasoning, content="")
}

///|
test "finished run clears any leftover stream" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), streaming_response: "leftover" }
  let (_, next) = update(dispatch, Finished(7, "finished", "done", 0), model)
  inspect(next.streaming_response, content="")
  inspect(next.running, content="false")
}

///|
test "new chat resets the conversation but keeps settings" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    usage_tokens: 42,
    watcher_status: "running",
    status: Finished("finished"),
    messages: [
      { kind: User, content: "hi" },
      { kind: Assistant(false), content: "hello" },
    ],
  }
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.messages.length(), content="0")
  inspect(next.usage_tokens, content="0")
  inspect(next.watcher_status, content="")
  inspect(next.api_key, content="sk-test")
  assert_true(next.status is Ready)
}

///|
test "new chat is ignored while a run is active" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), messages: [{ kind: User, content: "hi" }] }
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.messages.length(), content="1")
  inspect(next.running, content="true")
}

///|
test "session rotation stores the generated id" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    SessionRotated("desktop-20260610-000000-000"),
    test_model(),
  )
  inspect(next.session_id, content="desktop-20260610-000000-000")
}

///|
test "sessions loaded replaces the sidebar list and clears its error" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), sessions_error: "boom" }
  let items : Array[SessionListItem] = [
    { id: "desktop-a", title: "first question" },
  ]
  let (_, once) = update(dispatch, SessionsLoaded(items), model)
  let (_, twice) = update(dispatch, SessionsLoaded(items), model)
  inspect(once.sessions.length(), content="1")
  inspect(once.sessions[0].id, content="desktop-a")
  inspect(once.sessions_error, content="")
  inspect(twice.sessions.length(), content="1")
}

///|
test "sessions failure is recorded without touching the transcript" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), messages: [{ kind: User, content: "hi" }] }
  let (_, next) = update(dispatch, SessionsFailed("engine exploded"), model)
  inspect(next.sessions_error, content="engine exploded")
  inspect(next.messages.length(), content="1")
}

///|
test "open session is ignored while running or for the current session" {
  let dispatch = test_dispatch()
  let (_, while_running) = update(
    dispatch,
    OpenSession("desktop-other"),
    running_model(),
  )
  inspect(while_running.running, content="true")
  let (_, same_session) = update(
    dispatch,
    OpenSession("desktop-test"),
    test_model(),
  )
  inspect(same_session.session_id, content="desktop-test")
  inspect(same_session.messages.length(), content="0")
}

///|
test "session loaded swaps the conversation onto the stored session" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    usage_tokens: 42,
    watcher_status: "running",
    streaming_response: "leftover",
    messages: [{ kind: User, content: "old chat" }],
  }
  let items : Array[TranscriptItem] = [
    { kind: User, content: "stored question" },
    { kind: Assistant(false), content: "stored answer" },
  ]
  let (_, once) = update(
    dispatch,
    SessionLoaded("desktop-stored", items),
    model,
  )
  let (_, twice) = update(
    dispatch,
    SessionLoaded("desktop-stored", items),
    model,
  )
  inspect(once.session_id, content="desktop-stored")
  inspect(once.messages.length(), content="2")
  inspect(once.messages[0].content, content="stored question")
  inspect(once.streaming_response, content="")
  inspect(once.usage_tokens, content="0")
  inspect(once.watcher_status, content="")
  assert_true(once.status is Ready)
  inspect(twice.messages.length(), content="2")
}

///|
test "session loaded is dropped while a run is active" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), messages: [{ kind: User, content: "live" }] }
  let items : Array[TranscriptItem] = [{ kind: User, content: "stored" }]
  let (_, next) = update(
    dispatch,
    SessionLoaded("desktop-stored", items),
    model,
  )
  inspect(next.messages[0].content, content="live")
  inspect(next.session_id, content="desktop-test")
}

///|
test "decode recognizes the streaming events" {
  guard decode_engine_event("assistant_delta", "abc", "", false, 0, 0, "", "")
    is Some(AssistantDelta("abc")) else {
    fail("assistant_delta not decoded")
  }
  guard decode_engine_event("reasoning_delta", "th", "", false, 0, 0, "", "")
    is Some(ReasoningDelta("th")) else {
    fail("reasoning_delta not decoded")
  }
  guard decode_engine_event("reasoning_message", "all", "", false, 0, 0, "", "")
    is Some(ReasoningMessage("all")) else {
    fail("reasoning_message not decoded")
  }
}

///|
test "started records the host's workspace for display" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Started(
      7, "task", "openseek", "deepseek-v4-pro", 1000, "/home/u/Documents/OpenSeek/desktop-test",
    ),
    test_model(),
  )
  inspect(
    next.cwd,
    content="/home/u/Documents/OpenSeek/desktop-test",
  )
}

///|
test "switching conversations clears the stale workspace" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), cwd: "/somewhere/old" }
  let (_, fresh) = update(dispatch, NewChat, model)
  inspect(fresh.cwd, content="")
  let (_, resumed) = update(dispatch, SessionLoaded("desktop-other", []), model)
  inspect(resumed.cwd, content="")
}
