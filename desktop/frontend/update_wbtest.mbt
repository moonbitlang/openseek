// Purity and state-transition tests for the update handlers that back the
// streaming, session, and multi-conversation integration. Commands are
// opaque, so the tests assert on the returned model only.

///|
fn test_dispatch() -> @cmd.Emit[Msg] {
  Emit(_ => @cmd.none)
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
test "a finish the user watched leaves no unseen dot" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Finished(run_id=7, status="finished", answer="done"),
    running_model(),
  )
  inspect(next.active().unseen_finish, content="false")
}

///|
test "a background finish marks its conversation until it is opened" {
  let dispatch = test_dispatch()
  // The run belongs to "desktop-test"; the user is looking at another chat.
  let model = { ..running_model(), active_session: "desktop-elsewhere" }
  let (_, next) = update(
    dispatch,
    Finished(run_id=7, status="finished", answer="done"),
    model,
  )
  guard next.find_conversation("desktop-test") is Some(conv) else {
    fail("conversation missing")
  }
  inspect(conv.unseen_finish, content="true")
  let opened = next.activate("desktop-test")
  guard opened.find_conversation("desktop-test") is Some(seen) else {
    fail("conversation missing after activate")
  }
  inspect(seen.unseen_finish, content="false")
}

///|
test "new chat keeps the model intact until the rotation lands" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), loading_session: "desktop-stale" }
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.active().running, content="true")
  inspect(next.loading_session, content="")
}

///|
test "generated session ids include a random suffix" {
  let id = generated_session_id()
  let parts : Array[String] = id
    .split("-")
    .map(piece => piece.to_owned())
    .collect()
  inspect(parts.length(), content="5")
  inspect(parts[0], content="desktop")
  inspect(parts[1].length(), content="8")
  inspect(parts[2].length(), content="6")
  inspect(parts[3].length(), content="3")
  inspect(parts[4].length(), content="9")
  let _ = @string.parse_int(parts[1]) catch {
    _ => fail("expected numeric date")
  }
  let _ = @string.parse_int(parts[2]) catch {
    _ => fail("expected numeric time")
  }
  let _ = @string.parse_int(parts[3]) catch {
    _ => fail("expected numeric millis")
  }
  let _ = @string.parse_int(parts[4]) catch {
    _ => fail("expected numeric salt")
  }
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
test "sessions loaded replaces the sidebar list" {
  let dispatch = test_dispatch()
  let items : Array[@transcript.SessionListItem] = [
    {
      id: "desktop-a",
      title: "first question",
      workspace: "",
      workspace_name: "",
    },
  ]
  let (_, once) = update(dispatch, SessionsLoaded(items), test_model())
  let (_, twice) = update(dispatch, SessionsLoaded(items), test_model())
  inspect(once.sessions.length(), content="1")
  inspect(once.sessions[0].id, content="desktop-a")
  inspect(twice.sessions.length(), content="1")
}

///|
test "sessions failure pops a toast without touching the transcript" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "hi" }],
  })
  let (_, next) = update(dispatch, SessionsFailed("engine exploded"), model)
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="Session list unavailable: engine exploded",
  )
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
test "open session tracks the latest load and ignores stale replies" {
  let dispatch = test_dispatch()
  let (_, loading_a) = update(dispatch, OpenSession("desktop-a"), test_model())
  inspect(loading_a.active_session, content="desktop-test")
  inspect(loading_a.loading_session, content="desktop-a")
  let (_, loading_b) = update(dispatch, OpenSession("desktop-b"), loading_a)
  inspect(loading_b.loading_session, content="desktop-b")
  let a_items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "old selection" },
  ]
  let (_, after_a) = update(
    dispatch,
    SessionLoaded(session="desktop-a", items=a_items),
    loading_b,
  )
  inspect(after_a.active_session, content="desktop-test")
  inspect(after_a.loading_session, content="desktop-b")
  let b_items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "latest selection" },
  ]
  let (_, after_b) = update(
    dispatch,
    SessionLoaded(session="desktop-b", items=b_items),
    after_a,
  )
  inspect(after_b.active_session, content="desktop-b")
  inspect(after_b.loading_session, content="")
  inspect(after_b.active().messages[0].content, content="latest selection")
}

///|
test "abandoned session load failures are dropped" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, OpenSession("desktop-a"), test_model())
  let (_, abandoned) = update(dispatch, NewChat, loading)
  let (_, next) = update(
    dispatch,
    SessionLoadFailed(
      session="desktop-a",
      message="failed to load session desktop-a",
    ),
    abandoned,
  )
  inspect(next.loading_session, content="")
  inspect(next.active().messages.length(), content="0")
  inspect(next.notifications.length(), content="0")
}

///|
test "a live session load failure pops a toast, not a transcript bubble" {
  let dispatch = test_dispatch()
  let (_, loading) = update(dispatch, OpenSession("desktop-a"), test_model())
  let (_, next) = update(
    dispatch,
    SessionLoadFailed(
      session="desktop-a",
      message="failed to load session desktop-a: no such file",
    ),
    loading,
  )
  inspect(next.loading_session, content="")
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="failed to load session desktop-a: no such file",
  )
  // The conversation on screen keeps its transcript and status untouched.
  inspect(next.active().messages.length(), content="0")
  assert_true(next.display_status() is Ready)
}

///|
test "a host action failure pops a toast" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    HostActionFailed("open path failed: no opener"),
    test_model(),
  )
  inspect(next.notifications.length(), content="1")
  inspect(next.notifications[0].message, content="open path failed: no opener")
}

///|
test "session loaded swaps the active conversation onto the stored session" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      usage_tokens: 42,
      watcher_status: "running",
      streaming_response: "leftover",
      messages: [{ kind: User, content: "old chat" }],
    }),
    loading_session: "desktop-stored",
  }
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
  let model = { ..running_model(), loading_session: "desktop-stored" }
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
  let model = { ..running_model(), loading_session: "desktop-test" }
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
test "late undelivered steer is dropped after run-end sweep" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    pending_steers: ["lost"],
  })
  let (_, finished) = update(
    dispatch,
    Finished(run_id=7, status="finished", answer=""),
    model,
  )
  let (_, next) = update(
    dispatch,
    SteerUndelivered(session="desktop-test", text="lost"),
    finished,
  )
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().messages.length(), content="1")
  assert_true(next.active().messages[0].content.contains("lost"))
}

///|
test "the default provider needs no API key to be ready" {
  let model = { ..test_model(), api_key: "" }
  assert_true(model.api_ready())
  inspect(model.effective_api_url(), content=OpenseekApiUrl)
  inspect(model.effective_api_key(), content="")
}

///|
test "custom endpoints never reuse the saved DeepSeek key" {
  let openseek = { ..test_model(), api_provider: Openseek }
  inspect(openseek.effective_api_key(), content="")
  let official = { ..test_model(), api_provider: Deepseek }
  inspect(official.effective_api_key(), content="sk-test")
  let unauthenticated_custom = {
    ..test_model(),
    api_provider: Custom,
    custom_api_url: "https://proxy.example/v1/chat/completions",
  }
  inspect(unauthenticated_custom.effective_api_key(), content="")
  let authenticated_custom = {
    ..unauthenticated_custom,
    custom_api_key: "sk-custom",
  }
  inspect(authenticated_custom.effective_api_key(), content="sk-custom")
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
    SettingsLoaded(
      provider="",
      custom_url="",
      api_key="",
      custom_api_key="",
      wsl_enabled="",
      wsl_distro="",
      wsl_engine="",
      notification_corner="",
    ),
    test_model(),
  )
  assert_true(zero_config.screen is Chat)
  assert_true(zero_config.api_provider is Openseek)
  assert_true(zero_config.display_status() is Ready)
  let (_, keyless) = update(
    dispatch,
    SettingsLoaded(
      provider="deepseek",
      custom_url="",
      api_key="",
      custom_api_key="",
      wsl_enabled="",
      wsl_distro="",
      wsl_engine="",
      notification_corner="",
    ),
    test_model(),
  )
  assert_true(keyless.screen is Settings)
  assert_true(keyless.display_status() is ApiKeyRequired)
  let (_, restored) = update(
    dispatch,
    SettingsLoaded(
      provider="deepseek",
      custom_url="",
      api_key="sk-stored",
      custom_api_key="sk-custom-stored",
      wsl_enabled="1",
      wsl_distro=" Ubuntu ",
      wsl_engine="/usr/local/bin/openseek",
      notification_corner="top-left",
    ),
    test_model(),
  )
  assert_true(restored.screen is Chat)
  inspect(restored.api_key, content="sk-stored")
  inspect(restored.custom_api_key, content="sk-custom-stored")
  inspect(restored.wsl_enabled, content="true")
  inspect(restored.wsl_distro, content="Ubuntu")
  inspect(restored.wsl_engine, content="/usr/local/bin/openseek")
  assert_true(restored.notification_corner is TopLeft)
  // An unknown stored corner falls back to the default.
  assert_true(zero_config.notification_corner is BottomRight)
  let (_, custom) = update(
    dispatch,
    SettingsLoaded(
      provider="custom",
      custom_url="https://proxy.example/chat/completions",
      api_key="sk-deepseek",
      custom_api_key="sk-custom",
      wsl_enabled="",
      wsl_distro="",
      wsl_engine="",
      notification_corner="",
    ),
    test_model(),
  )
  assert_true(custom.screen is Chat)
  inspect(custom.effective_api_key(), content="sk-custom")
}

///|
test "the notification-corner setting parses its wire names" {
  let dispatch = test_dispatch()
  let (_, moved) = update(
    dispatch,
    NotificationCornerChanged("top-right"),
    test_model(),
  )
  assert_true(moved.notification_corner is TopRight)
  let (_, unknown) = update(
    dispatch,
    NotificationCornerChanged("nowhere"),
    moved,
  )
  assert_true(unknown.notification_corner is BottomRight)
}

///|
test "update is pure: a provider change is idempotent" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), api_key: "", setup_api_key: "typed" }
  let (_, once) = update(dispatch, ProviderChanged("deepseek"), model)
  let (_, twice) = update(dispatch, ProviderChanged("deepseek"), model)
  assert_true(once.api_provider is Deepseek)
  assert_true(twice.api_provider is Deepseek)
  inspect(once.setup_api_key, content="")
  inspect(twice.setup_api_key, content="")
  assert_true(once.display_status() is ApiKeyRequired)
  assert_true(twice.display_status() is ApiKeyRequired)
}

///|
test "saving a key writes the active provider credential only" {
  let dispatch = test_dispatch()
  let deepseek = {
    ..test_model(),
    api_provider: Deepseek,
    api_key: "sk-old",
    custom_api_key: "sk-custom-old",
    setup_api_key: "  sk-new  ",
    screen: Settings,
  }
  let (_, saved_deepseek) = update(dispatch, SaveApiKey, deepseek)
  inspect(saved_deepseek.api_key, content="sk-new")
  inspect(saved_deepseek.custom_api_key, content="sk-custom-old")
  assert_true(saved_deepseek.screen is Chat)
  let custom = {
    ..deepseek,
    api_provider: Custom,
    custom_api_url: "https://proxy.example/chat/completions",
    api_key: "sk-deepseek",
    setup_api_key: "  sk-custom-new  ",
  }
  let (_, saved_custom) = update(dispatch, SaveApiKey, custom)
  inspect(saved_custom.api_key, content="sk-deepseek")
  inspect(saved_custom.custom_api_key, content="sk-custom-new")
  inspect(saved_custom.effective_api_key(), content="sk-custom-new")
  assert_true(saved_custom.screen is Chat)
}

///|
test "changing settings mid-run leaves the run status alone" {
  let dispatch = test_dispatch()
  let (_, next) = update(dispatch, ProviderChanged("deepseek"), running_model())
  assert_true(next.display_status() is Running)
  assert_true(next.api_provider is Deepseek)
}

///|
/// The Settings page has no Done button — the sidebar is the only way out,
/// even while the endpoint is unusable (the composer blocks sending then).
test "sidebar navigation leaves the settings page" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    api_provider: Deepseek,
    api_key: "",
    screen: Settings,
  }
  let (_, next) = update(dispatch, SessionRotated("s-fresh"), model)
  assert_true(next.screen is Chat)
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
test "a branch reply lands on its conversation and an empty one hides it" {
  let dispatch = test_dispatch()
  let (_, named) = update(
    dispatch,
    BranchLoaded(session="desktop-test", branch="feature/x"),
    test_model(),
  )
  inspect(named.active().branch, content="feature/x")
  let (_, cleared) = update(
    dispatch,
    BranchLoaded(session="desktop-test", branch=""),
    named,
  )
  inspect(cleared.active().branch, content="")
  // A reply for an unknown session is dropped.
  let (_, ignored) = update(
    dispatch,
    BranchLoaded(session="desktop-gone", branch="main"),
    test_model(),
  )
  inspect(ignored.active().branch, content="")
}

///|
fn archived_item(id : String) -> @transcript.SessionListItem {
  { id, title: "", workspace: "", workspace_name: "" }
}

///|
test "an archived background session drops its live state, active stays" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    conversations: [test_conversation(), empty_conversation("desktop-old")],
  }
  let (_, next) = update(
    dispatch,
    ArchivedLoaded([archived_item("desktop-old")]),
    model,
  )
  inspect(next.archived.length(), content="1")
  inspect(next.archived[0].id, content="desktop-old")
  assert_true(next.find_conversation("desktop-old") is None)
  inspect(next.active_session, content="desktop-test")
}

///|
test "archiving the active conversation clears it for the rotation" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    ArchivedLoaded([archived_item("desktop-test")]),
    test_model(),
  )
  assert_true(next.find_conversation("desktop-test") is None)
  inspect(next.archived[0].id, content="desktop-test")
}

///|
test "an archive failure pops a toast that a click or its timer dismisses" {
  let dispatch = test_dispatch()
  let (_, failed) = update(dispatch, ArchiveFailed("zip missing"), test_model())
  inspect(failed.notifications.length(), content="1")
  inspect(
    failed.notifications[0].message,
    content="Archive failed: zip missing",
  )
  let id = failed.notifications[0].id
  // A stale timer (the toast is already gone) must not touch a later toast.
  let (_, dismissed) = update(dispatch, DismissNotification(id), failed)
  inspect(dismissed.notifications.length(), content="0")
  let (_, again) = update(dispatch, ArchiveFailed("still missing"), dismissed)
  let (_, expired) = update(dispatch, NotificationExpired(id), again)
  inspect(expired.notifications.length(), content="1")
  inspect(
    expired.notifications[0].message,
    content="Archive failed: still missing",
  )
}

///|
test "toast ids only ever grow, so timers and toasts stay paired" {
  let dispatch = test_dispatch()
  let (_, first) = update(dispatch, ArchiveFailed("one"), test_model())
  let (_, second) = update(dispatch, SessionsFailed("two"), first)
  inspect(second.notifications.length(), content="2")
  assert_true(second.notifications[0].id != second.notifications[1].id)
  inspect(second.notification_seq, content="2")
}

///|
test "the color-scheme watcher's report lands on the model" {
  let dispatch = test_dispatch()
  let (_, dark) = update(dispatch, ColorSchemeChanged(true), test_model())
  inspect(dark.dark_mode, content="true")
  let (_, light) = update(dispatch, ColorSchemeChanged(false), dark)
  inspect(light.dark_mode, content="false")
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
    { ..test_model(), transcript_pinned: false, loading_session: "desktop-old" },
  )
  inspect(loaded.transcript_pinned, content="true")
  let (_, rotated) = update(dispatch, SessionRotated("desktop-fresh"), {
    ..test_model(),
    transcript_pinned: false,
  })
  inspect(rotated.transcript_pinned, content="true")
}

///|
fn test_market_item() -> @transcript.MarketSkillItem {
  {
    name: "acme/widget",
    module_name: "acme/widget",
    package_path: "",
    version: "1.0.0",
    description: "Build widgets fast.",
    author: "acme",
    repository: "",
  }
}

///|
test "opening the skills page fetches the catalog once" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, OpenSkills, test_model())
  assert_true(opened.screen is Skills)
  assert_true(opened.skills_catalog is CatalogLoading)

  // Reopening with a loaded catalog keeps it; only a failure refetches.
  let loaded = { ..test_model(), skills_catalog: CatalogReady([]) }
  let (_, reopened) = update(dispatch, OpenSkills, loaded)
  assert_true(reopened.skills_catalog is CatalogReady(_))
  let failed = {
    ..test_model(),
    skills_catalog: CatalogFailed("offline"),
    skills_notice: "stale",
  }
  let (_, retried) = update(dispatch, OpenSkills, failed)
  assert_true(retried.skills_catalog is CatalogLoading)
  inspect(retried.skills_notice, content="")
}

///|
test "selecting a conversation returns from the skills page to the chat" {
  let dispatch = test_dispatch()
  let (_, opened) = update(dispatch, OpenSkills, test_model())
  assert_true(opened.screen is Skills)

  // Re-selecting the active conversation is enough to switch back…
  let (_, back) = update(dispatch, OpenSession("desktop-test"), opened)
  assert_true(back.screen is Chat)

  // …and so is rotating to a fresh one.
  let (_, rotated) = update(dispatch, SessionRotated("desktop-fresh"), opened)
  assert_true(rotated.screen is Chat)
}

///|
test "update is pure: opening the skills page twice is idempotent" {
  let dispatch = test_dispatch()
  let model = test_model()
  let (_, once) = update(dispatch, OpenSkills, model)
  let (_, twice) = update(dispatch, OpenSkills, model)
  assert_true(once.screen is Skills)
  assert_true(twice.screen is Skills)
  assert_true(once.skills_catalog is CatalogLoading)
  assert_true(twice.skills_catalog is CatalogLoading)
}

///|
test "the skills search query lands on the model" {
  let dispatch = test_dispatch()
  let (_, typed) = update(dispatch, SkillsQueryChanged("widget"), test_model())
  inspect(typed.skills_query, content="widget")
}

///|
test "an install marks its entry busy exactly once" {
  let dispatch = test_dispatch()
  let (_, busy) = update(
    dispatch,
    InstallSkill(test_market_item()),
    test_model(),
  )
  inspect(busy.skills_busy.length(), content="1")
  inspect(busy.skills_busy[0], content="acme/widget@1.0.0")

  // A second click while in flight is a no-op.
  let (_, again) = update(dispatch, InstallSkill(test_market_item()), busy)
  inspect(again.skills_busy.length(), content="1")
}

///|
test "a settled action releases its busy entry" {
  let dispatch = test_dispatch()
  let busy = { ..test_model(), skills_busy: ["acme/widget@1.0.0", "other"] }
  let (_, done) = update(
    dispatch,
    SkillActionDone(key="acme/widget@1.0.0", error=""),
    busy,
  )
  inspect(done.skills_busy.length(), content="1")
  inspect(done.skills_busy[0], content="other")
  inspect(done.skills_notice, content="")

  // A failure surfaces as the panel notice instead.
  let (_, failed) = update(
    dispatch,
    SkillActionDone(key="other", error="digest mismatch"),
    done,
  )
  inspect(failed.skills_busy.length(), content="0")
  inspect(failed.skills_notice, content="digest mismatch")
}

///|
test "uninstall is keyed by the library id and deduplicated" {
  let dispatch = test_dispatch()
  let (_, busy) = update(dispatch, UninstallSkill("acme-widget"), test_model())
  inspect(busy.skills_busy.length(), content="1")
  inspect(busy.skills_busy[0], content="acme-widget")
  let (_, again) = update(dispatch, UninstallSkill("acme-widget"), busy)
  inspect(again.skills_busy.length(), content="1")
}

///|
test "catalog and library replies land on the model" {
  let dispatch = test_dispatch()
  let (_, ready) = update(
    dispatch,
    SkillsCatalogLoaded([test_market_item()]),
    test_model(),
  )
  guard ready.skills_catalog is CatalogReady(items) else {
    fail("catalog should be ready")
  }
  inspect(items.length(), content="1")
  assert_false(ready.skill_installed("acme/widget@1.0.0"))
  let (_, failed) = update(dispatch, SkillsCatalogFailed("offline"), ready)
  assert_true(failed.skills_catalog is CatalogFailed(_))
  let installed : Array[@transcript.InstalledSkillItem] = [
    {
      id: "acme-widget",
      name: "widget",
      description: "",
      source: "acme/widget@1.0.0",
    },
  ]
  let (_, listed) = update(dispatch, InstalledSkillsLoaded(installed), ready)
  assert_true(listed.skill_installed("acme/widget@1.0.0"))
  let (_, noticed) = update(
    dispatch,
    SkillsNotice("library unreadable"),
    listed,
  )
  inspect(noticed.skills_notice, content="library unreadable")
}

///|
test "JumpToMention opens the editor panel and selects the mention's file" {
  let dispatch = test_dispatch()
  let mention : Mention = {
    kind: SymbolMention,
    label: "parse_hover",
    expand: "`parse_hover` — src/main.mbt:5 ",
    path: Some("src/main.mbt"),
    range: Some(@common.Range::Range(5, 1, 5, 12)),
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_true(next.file_panel.open)
  assert_true(next.file_panel.selected is Some("src/main.mbt"))
}

///|
test "JumpToMention is a no-op for a chip without a resolved location" {
  let dispatch = test_dispatch()
  let mention : Mention = {
    kind: SkillMention,
    label: "review-pr",
    expand: "review-pr ",
    path: None,
    range: None,
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_false(next.file_panel.open)
  assert_true(next.file_panel.selected is None)
}

///|
test "RevealDirectory(\"\") returns to the tree without a highlight" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = {
    ..model.file_panel,
    open: true,
    session: "desktop-test",
    selected: Some("README.md"),
    highlighted: Some("src"),
  }
  let (_, next) = update(dispatch, RevealDirectory(""), {
    ..model,
    file_panel: panel,
  })
  assert_true(next.file_panel.selected is None)
  assert_true(next.file_panel.highlighted is None)
}

///|
test "RevealDirectory expands an uncached ancestor and highlights the target" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = { ..model.file_panel, open: true, session: "desktop-test" }
  let (_, next) = update(dispatch, RevealDirectory("src/foo"), {
    ..model,
    file_panel: panel,
  })
  assert_true(next.file_panel.expanded.contains("src"))
  assert_true(next.file_panel.loading.contains("src"))
  assert_true(next.file_panel.selected is None)
  assert_true(next.file_panel.highlighted is Some("src/foo"))
}

///|
test "RevealDirectory on an already-cached ancestor needs no reload" {
  let dispatch = test_dispatch()
  let model = test_model()
  let children : Map[String, Array[FileEntry]] = { "src": [] }
  let panel = {
    ..model.file_panel,
    open: true,
    session: "desktop-test",
    children,
  }
  let (_, next) = update(dispatch, RevealDirectory("src/foo"), {
    ..model,
    file_panel: panel,
  })
  assert_true(next.file_panel.expanded.contains("src"))
  assert_false(next.file_panel.loading.contains("src"))
}

///|
test "HighlightCleared only clears a highlight that still matches" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = { ..model.file_panel, highlighted: Some("src") }
  let (_, stale) = update(dispatch, HighlightCleared("old"), {
    ..model,
    file_panel: panel,
  })
  assert_true(stale.file_panel.highlighted is Some("src"))
  let (_, cleared) = update(dispatch, HighlightCleared("src"), {
    ..model,
    file_panel: panel,
  })
  assert_true(cleared.file_panel.highlighted is None)
}
