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
