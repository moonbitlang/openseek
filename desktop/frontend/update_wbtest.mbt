// Purity and state-transition tests for the update handlers that back the
// streaming, session, and multi-conversation integration. Commands are
// opaque, so the tests assert on the returned model only.

///|
fn test_dispatch() -> @cmd.Dispatch[Msg] {
  Dispatch(_ => @cmd.none)
}

///|
fn test_conversation() -> Conversation {
  empty_conversation("desktop-test")
}

///|
fn running_conversation() -> Conversation {
  {
    ..test_conversation(),
    running: true,
    active_run_id: Some(7),
    status: Running,
  }
}

///|
fn test_model() -> Model {
  {
    ..initial_model(),
    bridge_ready: true,
    api_key: "sk-test",
    setup_open: false,
    active_session: "desktop-test",
    conversations: [test_conversation()],
  }
}

///|
fn running_model() -> Model {
  test_model().replace_conversation(running_conversation())
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
  inspect(second.active().streaming_response, content="Hello, world")
  inspect(second.active().messages.length(), content="0")
}

///|
test "update is pure: replaying a delta on the same model is idempotent" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
  })
  let (_, once) = update(dispatch, Engine(7, AssistantDelta("!")), model)
  let (_, twice) = update(dispatch, Engine(7, AssistantDelta("!")), model)
  inspect(once.active().streaming_response, content="partial!")
  inspect(twice.active().streaming_response, content="partial!")
}

///|
test "deltas from an unknown run are dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Engine(99, AssistantDelta("stale")),
    running_model(),
  )
  inspect(next.active().streaming_response, content="")
}

///|
test "reasoning message commits a thinking item and clears its stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_reasoning: "thinking…",
  })
  let (_, next) = update(
    dispatch,
    Engine(7, ReasoningMessage("full thought")),
    model,
  )
  inspect(next.active().streaming_reasoning, content="")
  inspect(next.active().messages.length(), content="1")
  guard next.active().messages[0].kind is Reasoning else {
    fail("expected reasoning")
  }
  inspect(next.active().messages[0].content, content="full thought")
}

///|
test "assistant message replaces the live stream with a committed item" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "answ",
    streaming_reasoning: "thought",
  })
  let (_, next) = update(dispatch, Engine(7, AssistantMessage("answer")), model)
  inspect(next.active().streaming_response, content="")
  inspect(next.active().streaming_reasoning, content="")
  inspect(next.active().messages.length(), content="1")
  inspect(next.active().messages[0].content, content="answer")
}

///|
test "a new agent step clears both live streams" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "left",
    streaming_reasoning: "over",
  })
  let (_, next) = update(dispatch, Engine(7, AgentStep("2")), model)
  inspect(next.active().streaming_response, content="")
  inspect(next.active().streaming_reasoning, content="")
}

///|
test "finished run clears any leftover stream" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "leftover",
  })
  let (_, next) = update(
    dispatch,
    Finished(run_id=7, status="finished", answer="done"),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().running, content="false")
}

///|
test "new chat keeps the model intact until the rotation lands" {
  let dispatch = test_dispatch()
  let model = running_model()
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.active().running, content="true")
}

///|
test "session rotation activates a fresh conversation, keeping the old one" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..running_conversation(),
    messages: [{ kind: User, content: "hi" }],
  })
  let (_, next) = update(dispatch, SessionRotated("desktop-fresh"), model)
  inspect(next.active_session, content="desktop-fresh")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().usage_tokens, content="0")
  inspect(next.api_key, content="sk-test")
  assert_true(next.display_status() is Ready)
  // The previous conversation keeps running in the background.
  guard next.find_conversation("desktop-test") is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.running, content="true")
  inspect(old.messages.length(), content="1")
}

///|
test "session rotation prunes abandoned empty conversations" {
  let dispatch = test_dispatch()
  let (_, first) = update(dispatch, SessionRotated("desktop-a"), test_model())
  let (_, second) = update(dispatch, SessionRotated("desktop-b"), first)
  // "desktop-test" and "desktop-a" had no transcript, no draft, no run.
  inspect(second.conversations.length(), content="1")
  inspect(second.active_session, content="desktop-b")
}

///|
test "sessions loaded replaces the sidebar list and clears its error" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), sessions_error: "boom" }
  let items : Array[@transcript.SessionListItem] = [
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
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "hi" }],
  })
  let (_, next) = update(dispatch, SessionsFailed("engine exploded"), model)
  inspect(next.sessions_error, content="engine exploded")
  inspect(next.active().messages.length(), content="1")
}

///|
test "open session is a no-op for the current session" {
  let dispatch = test_dispatch()
  let (_, next) = update(dispatch, OpenSession("desktop-test"), test_model())
  inspect(next.active_session, content="desktop-test")
  inspect(next.conversations.length(), content="1")
}

///|
test "open session switches to a live conversation without reloading it" {
  let dispatch = test_dispatch()
  let background = {
    ..empty_conversation("desktop-bg"),
    running: true,
    active_run_id: Some(9),
    status: Running,
    streaming_response: "mid-stream",
    messages: [{ kind: User, content: "background task" }],
  }
  let model = running_model().replace_conversation(background)
  let (_, once) = update(dispatch, OpenSession("desktop-bg"), model)
  let (_, twice) = update(dispatch, OpenSession("desktop-bg"), model)
  inspect(once.active_session, content="desktop-bg")
  // The live state survives the switch: no reload, nothing reset.
  inspect(once.active().streaming_response, content="mid-stream")
  inspect(once.active().running, content="true")
  // The previous conversation is still running in the background.
  guard once.find_conversation("desktop-test") is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.running, content="true")
  inspect(twice.active_session, content="desktop-bg")
}

///|
test "session loaded swaps the active conversation onto the stored session" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    usage_tokens: 42,
    watcher_status: "running",
    streaming_response: "leftover",
    messages: [{ kind: User, content: "old chat" }],
  })
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "stored question" },
    { kind: Assistant(false), content: "stored answer" },
  ]
  let (_, once) = update(
    dispatch,
    SessionLoaded(session="desktop-stored", items~),
    model,
  )
  let (_, twice) = update(
    dispatch,
    SessionLoaded(session="desktop-stored", items~),
    model,
  )
  inspect(once.active_session, content="desktop-stored")
  inspect(once.active().messages.length(), content="2")
  inspect(once.active().messages[0].content, content="stored question")
  inspect(once.active().streaming_response, content="")
  inspect(once.active().usage_tokens, content="0")
  inspect(once.active().watcher_status, content="")
  inspect(once.active().cwd, content="")
  assert_true(once.display_status() is Ready)
  inspect(twice.active().messages.length(), content="2")
}

///|
test "session loaded is dropped only when that conversation is running" {
  let dispatch = test_dispatch()
  let model = running_model()
  let items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "stored" },
  ]
  // The active conversation runs; loading some other stored session is fine.
  let (_, other) = update(
    dispatch,
    SessionLoaded(session="desktop-stored", items~),
    model,
  )
  inspect(other.active_session, content="desktop-stored")
  guard other.find_conversation("desktop-test") is Some(live) else {
    fail("expected the running conversation to survive")
  }
  inspect(live.running, content="true")
  // A stale load reply for the running conversation itself is dropped.
  let (_, same) = update(
    dispatch,
    SessionLoaded(session="desktop-test", items~),
    model,
  )
  inspect(same.active().messages.length(), content="0")
  inspect(same.active().running, content="true")
}

///|
test "started routes by session and records the host's workspace" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Started(
      run_id=7,
      session="desktop-test",
      model="deepseek-v4-pro",
      max_steps=1000,
      cwd="/home/u/Documents/OpenSeek/desktop-test",
    ),
    test_model(),
  )
  inspect(next.active().cwd, content="/home/u/Documents/OpenSeek/desktop-test")
  inspect(next.active().running, content="true")
  guard next.active().active_run_id is Some(7) else {
    fail("expected the run id to be recorded")
  }
}

///|
test "started for an unknown session leaves the model alone" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Started(
      run_id=7,
      session="desktop-ghost",
      model="deepseek-v4-pro",
      max_steps=1000,
      cwd="",
    ),
    test_model(),
  )
  inspect(next.active().running, content="false")
  inspect(next.conversations.length(), content="1")
}

///|
test "concurrent conversations keep their streams apart" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation("desktop-second"),
    running: true,
    active_run_id: Some(8),
    status: Running,
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update(dispatch, Engine(8, AssistantDelta("for B")), model)
  // Run 8 belongs to the background conversation; the active one is untouched.
  inspect(next.active().streaming_response, content="")
  guard next.find_conversation("desktop-second") is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.streaming_response, content="for B")
}

///|
test "a background run finishes without disturbing the conversation on screen" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation("desktop-second"),
    running: true,
    active_run_id: Some(8),
    status: Running,
    messages: [{ kind: User, content: "background ask" }],
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update(
    dispatch,
    Finished(run_id=8, status="finished", answer="done"),
    model,
  )
  guard next.find_conversation("desktop-second") is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.running, content="false")
  assert_true(bg.status is Finished(_))
  inspect(bg.messages[1].content, content="done")
  // The conversation on screen is still running its own turn.
  inspect(next.active().running, content="true")
  assert_true(next.display_status() is Running)
}

///|
test "send while running queues a steer instead of a prompt" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    task: "focus on the tests",
  })
  let (_, once) = update(dispatch, Send, model)
  let (_, twice) = update(dispatch, Send, model)
  inspect(once.active().task, content="")
  inspect(once.active().pending_steers.length(), content="1")
  inspect(once.active().pending_steers[0], content="focus on the tests")
  // The steer is pending, not part of the transcript yet.
  inspect(once.active().messages.length(), content="0")
  inspect(once.active().running, content="true")
  inspect(twice.active().pending_steers.length(), content="1")
  inspect(twice.active().pending_steers[0], content="focus on the tests")
}

///|
test "a cancelling turn cannot be steered; the text stays in the composer" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    status: Cancelling,
    task: "too late",
  })
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="too late")
  inspect(next.active().pending_steers.length(), content="0")
}

///|
test "the composer draft stays with its conversation across a switch" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..empty_conversation("desktop-second"),
    messages: [{ kind: User, content: "earlier" }],
  })
  let (_, drafted) = update(dispatch, TaskChanged("half a thought"), model)
  let (_, switched) = update(dispatch, OpenSession("desktop-second"), drafted)
  // The other conversation starts with its own (empty) draft …
  inspect(switched.active().task, content="")
  let (_, back) = update(dispatch, OpenSession("desktop-test"), switched)
  // … and the original draft is still waiting where it was typed.
  inspect(back.active().task, content="half a thought")
}

///|
test "steer_applied commits the pending steer as a user message" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    pending_steers: ["go left"],
  })
  let (_, next) = update(dispatch, Engine(7, SteerApplied("go left")), model)
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().messages.length(), content="1")
  guard next.active().messages[0].kind is User else {
    fail("expected a user item")
  }
  inspect(next.active().messages[0].content, content="go left")
}

///|
test "steer_dropped settles the pending steer with a visible notice" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    pending_steers: ["go left"],
  })
  let (_, next) = update(dispatch, Engine(7, SteerDropped("go left")), model)
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().messages.length(), content="1")
  guard next.active().messages[0].kind is Assistant(true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().messages[0].content.contains("go left"))
}

///|
test "an identical-text settle removes exactly one pending entry" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    pending_steers: ["again", "again"],
  })
  let (_, next) = update(dispatch, Engine(7, SteerApplied("again")), model)
  inspect(next.active().pending_steers.length(), content="1")
  inspect(next.active().pending_steers[0], content="again")
  inspect(next.active().messages.length(), content="1")
}

///|
test "an undelivered steer is reported instead of vanishing" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    pending_steers: ["lost"],
  })
  let (_, next) = update(
    dispatch,
    SteerUndelivered(session="desktop-test", text="lost"),
    model,
  )
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().messages.length(), content="1")
  guard next.active().messages[0].kind is Assistant(true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().messages[0].content.contains("lost"))
}

///|
test "a run that ends with steers in flight sweeps them into notices" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    pending_steers: ["orphaned"],
  })
  let (_, next) = update(
    dispatch,
    Finished(run_id=7, status="finished", answer=""),
    model,
  )
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().running, content="false")
  guard next.active().messages[0].kind is Assistant(true) else {
    fail("expected an error bubble")
  }
  assert_true(next.active().messages[0].content.contains("orphaned"))
}

///|
test "the default provider needs no API key to be ready" {
  let model = { ..test_model(), api_key: "" }
  assert_true(model.api_ready())
  inspect(model.effective_api_url(), content=OpenseekApiUrl)
  inspect(model.effective_api_key(), content="")
}

///|
test "the saved DeepSeek key is never sent to another endpoint" {
  let openseek = { ..test_model(), api_provider: Openseek }
  inspect(openseek.effective_api_key(), content="")
  let official = { ..test_model(), api_provider: Deepseek }
  inspect(official.effective_api_key(), content="sk-test")
}

///|
test "the official endpoint requires a key, a custom endpoint a URL" {
  let official = { ..test_model(), api_provider: Deepseek, api_key: "" }
  assert_false(official.api_ready())
  assert_true(official.display_status() is ApiKeyRequired)
  let custom = { ..test_model(), api_provider: Custom, custom_api_url: "" }
  assert_false(custom.api_ready())
  assert_true(custom.display_status() is SetupRequired)
  let configured = {
    ..custom,
    custom_api_url: "https://proxy.example/chat/completions",
  }
  assert_true(configured.api_ready())
  inspect(
    configured.effective_api_url(),
    content="https://proxy.example/chat/completions",
  )
}

///|
test "loaded settings open the popup only when incomplete" {
  let dispatch = test_dispatch()
  let (_, zero_config) = update(
    dispatch,
    SettingsLoaded(provider="", custom_url="", api_key=""),
    test_model(),
  )
  inspect(zero_config.setup_open, content="false")
  assert_true(zero_config.api_provider is Openseek)
  assert_true(zero_config.display_status() is Ready)
  let (_, keyless) = update(
    dispatch,
    SettingsLoaded(provider="deepseek", custom_url="", api_key=""),
    test_model(),
  )
  inspect(keyless.setup_open, content="true")
  assert_true(keyless.display_status() is ApiKeyRequired)
  let (_, restored) = update(
    dispatch,
    SettingsLoaded(provider="deepseek", custom_url="", api_key="sk-stored"),
    test_model(),
  )
  inspect(restored.setup_open, content="false")
  inspect(restored.api_key, content="sk-stored")
}

///|
test "update is pure: a provider change is idempotent" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), api_key: "" }
  let (_, once) = update(dispatch, ProviderChanged("deepseek"), model)
  let (_, twice) = update(dispatch, ProviderChanged("deepseek"), model)
  assert_true(once.api_provider is Deepseek)
  assert_true(twice.api_provider is Deepseek)
  assert_true(once.display_status() is ApiKeyRequired)
  assert_true(twice.display_status() is ApiKeyRequired)
}

///|
test "changing settings mid-run leaves the run status alone" {
  let dispatch = test_dispatch()
  let (_, next) = update(dispatch, ProviderChanged("deepseek"), running_model())
  assert_true(next.display_status() is Running)
  assert_true(next.api_provider is Deepseek)
}

///|
test "the popup cannot close while the endpoint is unusable" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    api_provider: Deepseek,
    api_key: "",
    setup_open: true,
  }
  let (_, stuck) = update(dispatch, CloseSetup, model)
  inspect(stuck.setup_open, content="true")
  let (_, closed) = update(dispatch, CloseSetup, {
    ..model,
    api_provider: Openseek,
  })
  inspect(closed.setup_open, content="false")
}

///|
test "the scroll watcher's report lands on the model" {
  let dispatch = test_dispatch()
  let (_, away) = update(dispatch, TranscriptPinned(false), test_model())
  inspect(away.transcript_pinned, content="false")
  let (_, back) = update(dispatch, TranscriptPinned(true), away)
  inspect(back.transcript_pinned, content="true")
}

///|
test "update is pure: a pinned-state change is idempotent" {
  let dispatch = test_dispatch()
  let (_, first) = update(dispatch, TranscriptPinned(false), test_model())
  let (_, second) = update(dispatch, TranscriptPinned(false), test_model())
  inspect(first.transcript_pinned, content="false")
  inspect(second.transcript_pinned, content="false")
}

///|
test "an unpinned transcript stays unpinned while a stream grows" {
  // The pinned flag is the scroll gate; a delta to the active conversation
  // must not flip it back, or the next render would yank the reader down.
  let dispatch = test_dispatch()
  let model = { ..running_model(), transcript_pinned: false }
  let (_, next) = update(dispatch, Engine(7, AssistantDelta("more")), model)
  inspect(next.transcript_pinned, content="false")
  inspect(next.active().streaming_response, content="more")
}

///|
test "explicit user actions re-pin the transcript" {
  let dispatch = test_dispatch()

  // Sending a prompt jumps to the tail.
  let unpinned = {
    ..test_model().replace_conversation({ ..test_conversation(), task: "do it" }),
    transcript_pinned: false,
  }
  let (_, sent) = update(dispatch, Send, unpinned)
  inspect(sent.transcript_pinned, content="true")

  // Steering a running turn does too.
  let steering = {
    ..running_model().replace_conversation({
      ..running_conversation(),
      task: "and this",
    }),
    transcript_pinned: false,
  }
  let (_, steered) = update(dispatch, Send, steering)
  inspect(steered.transcript_pinned, content="true")

  // Switching to a conversation that has live state lands at its tail.
  let two = {
    ..test_model().replace_conversation(empty_conversation("desktop-other")),
    transcript_pinned: false,
  }
  let (_, switched) = update(dispatch, OpenSession("desktop-other"), two)
  inspect(switched.transcript_pinned, content="true")

  // So does loading a stored session or rotating to a fresh one.
  let (_, loaded) = update(
    dispatch,
    SessionLoaded(session="desktop-old", items=[]),
    { ..test_model(), transcript_pinned: false },
  )
  inspect(loaded.transcript_pinned, content="true")
  let (_, rotated) = update(dispatch, SessionRotated("desktop-fresh"), {
    ..test_model(),
    transcript_pinned: false,
  })
  inspect(rotated.transcript_pinned, content="true")
}
