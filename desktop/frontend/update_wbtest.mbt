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
  { ..test_conversation(), run: Open(run_id=7, stage=Opened) }
}

///|
fn test_model() -> Model {
  {
    ..initial_model(),
    bridge: Connected,
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
    Engine(7, AssistantDelta("Hello"), session=None),
    running_model(),
  )
  let (_, second) = update(
    dispatch,
    Engine(7, AssistantDelta(", world"), session=None),
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
  let (_, once) = update(
    dispatch,
    Engine(7, AssistantDelta("!"), session=None),
    model,
  )
  let (_, twice) = update(
    dispatch,
    Engine(7, AssistantDelta("!"), session=None),
    model,
  )
  inspect(once.active().streaming_response, content="partial!")
  inspect(twice.active().streaming_response, content="partial!")
}

///|
test "deltas from an unknown run are dropped" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Engine(99, AssistantDelta("stale"), session=None),
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
    Engine(7, ReasoningMessage("full thought"), session=None),
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
  let (_, next) = update(
    dispatch,
    Engine(7, AssistantMessage("answer"), session=None),
    model,
  )
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
  let (_, next) = update(
    dispatch,
    Engine(7, AgentStep(Some(2)), session=None),
    model,
  )
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
    Finished(run_id=7, status="finished", answer=Some("done")),
    model,
  )
  inspect(next.active().streaming_response, content="")
  inspect(next.active().is_running(), content="false")
}

///|
test "a finish the user watched leaves no unseen dot" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    Finished(run_id=7, status="finished", answer=Some("done")),
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
    Finished(run_id=7, status="finished", answer=Some("done")),
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
test "an idle background notice routes by the last run id" {
  let dispatch = test_dispatch()
  // The run already finished: `active_run_id` is cleared, only the last-run
  // memory ties the id back to its conversation.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: Some(7),
  })
  let notice = "[moon_check update]\nstatus=failed\nmain.mbt:1 error"
  let (_, next) = update(
    dispatch,
    Engine(7, RuntimeUpdate(notice), session=None),
    model,
  )
  inspect(next.active().watcher_status, content="failed")
  guard next.active().messages.get(0)
    is Some({ kind: Tool(name="moon_check failed", ..), .. }) else {
    fail("expected a runtime notice card")
  }
}

///|
test "new chat keeps the model intact until the rotation lands" {
  let dispatch = test_dispatch()
  let model = { ..running_model(), loading_session: "desktop-stale" }
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.active().is_running(), content="true")
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
  inspect(old.is_running(), content="true")
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
      title: Some("first question"),
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
    run: Open(run_id=9, stage=Opened),
    streaming_response: "mid-stream",
    messages: [{ kind: User, content: "background task" }],
  }
  let model = running_model().replace_conversation(background)
  let (_, once) = update(dispatch, OpenSession("desktop-bg"), model)
  let (_, twice) = update(dispatch, OpenSession("desktop-bg"), model)
  inspect(once.active_session, content="desktop-bg")
  // The live state survives the switch: no reload, nothing reset.
  inspect(once.active().streaming_response, content="mid-stream")
  inspect(once.active().is_running(), content="true")
  // The previous conversation is still running in the background.
  guard once.find_conversation("desktop-test") is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.is_running(), content="true")
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
  assert_true(once.active().cwd is None)
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
  inspect(live.is_running(), content="true")
  // A stale load reply for the running conversation itself is dropped.
  let model = { ..running_model(), loading_session: "desktop-test" }
  let (_, same) = update(
    dispatch,
    SessionLoaded(session="desktop-test", items~),
    model,
  )
  inspect(same.active().messages.length(), content="0")
  inspect(same.active().is_running(), content="true")
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
      cwd=Some(Absolute("/home/u/Documents/OpenSeek/desktop-test")),
    ),
    test_model(),
  )
  assert_true(
    next.active().cwd
    is Some(Absolute("/home/u/Documents/OpenSeek/desktop-test")),
  )
  inspect(next.active().is_running(), content="true")
  guard next.active().run is Open(run_id=7, ..) else {
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
      cwd=None,
    ),
    test_model(),
  )
  inspect(next.active().is_running(), content="false")
  inspect(next.conversations.length(), content="1")
}

///|
test "concurrent conversations keep their streams apart" {
  let dispatch = test_dispatch()
  let second = {
    ..empty_conversation("desktop-second"),
    run: Open(run_id=8, stage=Opened),
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update(
    dispatch,
    Engine(8, AssistantDelta("for B"), session=None),
    model,
  )
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
    run: Open(run_id=8, stage=Opened),
    messages: [{ kind: User, content: "background ask" }],
  }
  let model = running_model().replace_conversation(second)
  let (_, next) = update(
    dispatch,
    Finished(run_id=8, status="finished", answer=Some("done")),
    model,
  )
  guard next.find_conversation("desktop-second") is Some(bg) else {
    fail("expected the background conversation")
  }
  inspect(bg.is_running(), content="false")
  assert_true(bg.run is NoRun(ended=Some(RunFinished(_))))
  inspect(bg.messages[1].content, content="done")
  // The conversation on screen is still running its own turn.
  inspect(next.active().is_running(), content="true")
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
  inspect(once.active().is_running(), content="true")
  inspect(twice.active().pending_steers.length(), content="1")
  inspect(twice.active().pending_steers[0], content="focus on the tests")
}

///|
test "a cancelling turn cannot be steered; the text stays in the composer" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    run: Open(run_id=7, stage=Cancelling),
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
  let (_, next) = update(
    dispatch,
    Engine(7, SteerApplied("go left"), session=None),
    model,
  )
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
  let (_, next) = update(
    dispatch,
    Engine(7, SteerDropped("go left"), session=None),
    model,
  )
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
  let (_, next) = update(
    dispatch,
    Engine(7, SteerApplied("again"), session=None),
    model,
  )
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
    Finished(run_id=7, status="finished", answer=Some("")),
    model,
  )
  inspect(next.active().pending_steers.length(), content="0")
  inspect(next.active().is_running(), content="false")
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
    Finished(run_id=7, status="finished", answer=Some("")),
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
      tree_layout="",
      update_channel="",
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
      tree_layout="",
      update_channel="",
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
      tree_layout="",
      update_channel="staging",
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
  assert_true(restored.update_channel is Staging)
  // An unknown stored corner or channel falls back to the default.
  assert_true(zero_config.notification_corner is BottomRight)
  assert_true(zero_config.update_channel is Production)
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
      tree_layout="",
      update_channel="",
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
test "the tree-layout setting parses its wire names" {
  let dispatch = test_dispatch()
  let (_, docked) = update(
    dispatch,
    TreeLayoutChanged("bottom-panel"),
    test_model(),
  )
  assert_true(docked.tree_layout is BottomPanel)
  // An unknown stored value falls back to the default right sidebar.
  let (_, unknown) = update(dispatch, TreeLayoutChanged("floating"), docked)
  assert_true(unknown.tree_layout is RightSidebar)
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
    BranchLoaded(session="desktop-test", branch=Some("feature/x")),
    test_model(),
  )
  assert_true(named.active().branch is Some("feature/x"))
  let (_, cleared) = update(
    dispatch,
    BranchLoaded(session="desktop-test", branch=Some("")),
    named,
  )
  assert_true(cleared.active().branch is Some(""))
  // A reply for an unknown session is dropped.
  let (_, ignored) = update(
    dispatch,
    BranchLoaded(session="desktop-gone", branch=Some("main")),
    test_model(),
  )
  assert_true(ignored.active().branch is None)
}

///|
fn archived_item(id : String) -> @transcript.SessionListItem {
  { id, title: Some(""), workspace: "", workspace_name: "" }
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
  let (_, next) = update(
    dispatch,
    Engine(7, AssistantDelta("more"), session=None),
    model,
  )
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
    ref_: Symbol(name="parse_hover", file="src/main.mbt", line=5),
    range: Some(@common.Range::Range(5, 1, 5, 12)),
  }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_true(next.file_panel.open)
  assert_true(next.file_panel.active is Some(Relative("src/main.mbt")))
}

///|
test "JumpToMention is a no-op for a chip without a resolved location" {
  let dispatch = test_dispatch()
  let mention : Mention = { ref_: Skill(name="review-pr"), range: None }
  let model = test_model().replace_conversation({
    ..test_conversation(),
    mentions: [mention],
  })
  let (_, next) = update(dispatch, JumpToMention(0), model)
  assert_false(next.file_panel.open)
  assert_true(next.file_panel.active is None)
}

///|
test "EditorCommentAdded attaches a deduplicated annotation chip" {
  let dispatch = test_dispatch()
  let model = test_model()
  // The chip path arrives workspace-relative from the panel (recorded when
  // the file was shown); the resource URI only routes the bubble removal.
  let msg : Msg = FileEditor(
    EditorCommentAdded(
      resource=@fileeditor.ModelUri::of(Absolute("/work/project/src/main.mbt")),
      file=Relative("src/main.mbt"),
      range=@common.Range::Range(5, 1, 6, 3),
      quote="fn parse_hover() {",
      comment="rename this",
      feedback_id="viewer-feedback-0",
    ),
  )
  let (_, next) = update(dispatch, msg, model)
  let mentions = next.active().mentions
  assert_eq(mentions.length(), 1)
  assert_true(
    mentions[0].ref_
    is Annotation(file="src/main.mbt", start_line=5, end_line=6, ..),
  )
  // Submitting the identical comment again is a no-op, not a second chip.
  let (_, again) = update(dispatch, msg, next)
  assert_eq(again.active().mentions.length(), 1)
}

///|
test "chip jumps relativize legacy absolute paths against the roots" {
  let dispatch = test_dispatch()
  // Preferred root: the run-reported cwd.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    cwd: Some(Absolute("/work/project")),
  })
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range::Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(next.file_panel.active is Some(Relative("src/main.mbt")))
  // Before the first run reports cwd, the attached workspace serves as root.
  let model = test_model().replace_conversation({
    ..test_conversation(),
    workspace: Some(Absolute("/work/project")),
  })
  let (_, next) = update(
    dispatch,
    JumpToLocation(
      path="/work/project/src/main.mbt",
      range=Some(@common.Range::Range(5, 1, 5, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(next.file_panel.active is Some(Relative("src/main.mbt")))
  // An absolute path outside every root cannot be opened; the panel says so
  // instead of sending the host a bogus read.
  let (_, outside) = update(
    dispatch,
    JumpToLocation(
      path="/elsewhere/note.md",
      range=Some(@common.Range::Range(1, 1, 1, 1)),
      annotation=None,
    ),
    model,
  )
  assert_true(outside.file_panel.active is None)
  assert_false(outside.file_panel.error.is_empty())
}

///|
test "RevealDirectory(\"\") opens the tree pane without a highlight" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = {
    ..model.file_panel,
    open: true,
    session: "desktop-test",
    tree_open: false,
    active: Some(Relative("README.md")),
    highlighted: Some(Relative("src")),
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(@pathx.Relative::root())),
    { ..model, file_panel: panel },
  )
  // The active tab stays put — revealing the tree must not close the file.
  assert_true(next.file_panel.active is Some(Relative("README.md")))
  assert_true(next.file_panel.tree_open)
  assert_true(next.file_panel.highlighted is None)
}

///|
test "RevealDirectory expands an uncached ancestor and highlights the target" {
  let dispatch = test_dispatch()
  let model = test_model()
  let panel = { ..model.file_panel, open: true, session: "desktop-test" }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel },
  )
  assert_true(next.file_panel.expanded.contains(Relative("src")))
  assert_true(next.file_panel.loading.contains(Relative("src")))
  assert_true(next.file_panel.highlighted is Some(Relative("src/foo")))
}

///|
test "RevealDirectory on an already-cached ancestor needs no reload" {
  let dispatch = test_dispatch()
  let model = test_model()
  let children : Map[@pathx.Relative, Array[@fileeditor.FileEntry]] = Map([
    (Relative("src"), []),
  ])
  let panel = {
    ..model.file_panel,
    open: true,
    session: "desktop-test",
    children,
  }
  let (_, next) = update(
    dispatch,
    FileEditor(RevealDirectory(Relative("src/foo"))),
    { ..model, file_panel: panel },
  )
  assert_true(next.file_panel.expanded.contains(Relative("src")))
  assert_false(next.file_panel.loading.contains(Relative("src")))
}

///|
test "HighlightCleared only clears a highlight that still matches" {
  let dispatch = test_dispatch()
  let model = test_model()
  // Rooted in the active session, or the post-dispatch `sync` re-roots the
  // panel and clears the highlight itself.
  let panel = {
    ..model.file_panel,
    session: "desktop-test",
    highlighted: Some(Relative("src")),
  }
  let (_, stale) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("old"))),
    { ..model, file_panel: panel },
  )
  assert_true(stale.file_panel.highlighted is Some(Relative("src")))
  let (_, cleared) = update(
    dispatch,
    FileEditor(HighlightCleared(Relative("src"))),
    { ..model, file_panel: panel },
  )
  assert_true(cleared.file_panel.highlighted is None)
}

///|
/// A prompt submitted mid-compaction must not start: the serve engine would
/// queue it behind the compaction, out of Stop's reach. The draft stays put.
test "a prompt submitted during compaction stays in the composer" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Compacting,
    task: "do the thing",
  })
  let (_, next) = update(dispatch, Send, model)
  inspect(next.active().task, content="do the thing")
  inspect(next.active().messages.length(), content="0")
}

///|
/// A `/compact` sent mid-turn queues behind the open run in the engine. The
/// composer must say so immediately, swallow a duplicate, and keep the send
/// gate held through the gap between the turn's end and the engine's
/// compaction_started.
test "a mid-turn /compact stays visibly queued until compaction starts" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..running_conversation(),
    last_run_id: Some(7),
  })
  let (_, queued) = run_slash_command(dispatch, model, "compact")
  assert_true(queued.active().compaction is Queued)
  // One compaction at a time: the repeat is swallowed, not re-sent.
  let (_, again) = run_slash_command(dispatch, queued, "compact")
  assert_true(again.active().compaction is Queued)
  // The turn ends before compaction_started arrives; a prompt sent into
  // that gap would queue behind the compaction, out of Stop's reach.
  let (_, ended) = update(
    dispatch,
    Finished(run_id=7, status="completed", answer=None),
    again,
  )
  assert_true(ended.active().compaction is Queued)
  let drafted = ended.replace_conversation({
    ..ended.active(),
    task: "next prompt",
  })
  let (_, held) = update(dispatch, Send, drafted)
  inspect(held.active().task, content="next prompt")
  // The engine reaches the queued compaction: queued flips into compacting.
  let (_, started) = update(
    dispatch,
    Engine(7, CompactionStarted, session=None),
    held,
  )
  assert_true(started.active().compaction is Compacting)
}

///|
/// An idle `/compact` has no engine acknowledgment yet — the host may still
/// be spawning a serve engine for it (a resumed conversation compacted
/// before its first prompt) — but the request must hold the send gate
/// immediately: a prompt sent into that window would be consumed and
/// rejected by the host instead of held in the composer.
test "an idle /compact holds the send gate until the engine confirms" {
  let dispatch = test_dispatch()
  let (_, requested) = run_slash_command(dispatch, test_model(), "compact")
  assert_true(requested.active().compaction is Requested)
  // A repeat while the request is in flight is swallowed, not re-sent.
  let (_, again) = run_slash_command(dispatch, requested, "compact")
  assert_true(again.active().compaction is Requested)
  // A draft sent during the spawn/write window stays in the composer.
  let drafted = again.replace_conversation({
    ..again.active(),
    task: "next prompt",
  })
  let (_, held) = update(dispatch, Send, drafted)
  inspect(held.active().task, content="next prompt")
  inspect(held.active().messages.length(), content="0")
  // The engine confirms; the session stamp routes it (no run id exists yet).
  let (_, started) = update(
    dispatch,
    Engine(0, CompactionStarted, session=Some("desktop-test")),
    held,
  )
  assert_true(started.active().compaction is Compacting)
}

///|
/// Rabbita purity: applying the automatic-checkpoint event twice to the same
/// input produces the same transcript and never mutates the manual compaction
/// lifecycle.
test "update is pure: automatic checkpoint appends a summary" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
  })
  let (_, once) = update(
    dispatch,
    Engine(7, AutoCompactionFinished("checkpoint recap"), session=None),
    model,
  )
  let (_, twice) = update(
    dispatch,
    Engine(7, AutoCompactionFinished("checkpoint recap"), session=None),
    model,
  )
  inspect(model.active().messages.length(), content="0")
  inspect(once.active().messages.length(), content="1")
  inspect(twice.active().messages.length(), content="1")
  guard once.active().messages.last() is Some(once_item) &&
    twice.active().messages.last() is Some(twice_item) else {
    fail("expected checkpoint summaries")
  }
  assert_true(once_item.kind is Summary && twice_item.kind is Summary)
  inspect(once_item.content, content="checkpoint recap")
  inspect(twice_item.content, content="checkpoint recap")
  inspect(once.active().streaming_response, content="partial")
  inspect(twice.active().streaming_response, content="partial")
  assert_true(
    once.active().compaction is NotCompacting &&
    twice.active().compaction is NotCompacting,
  )
}

///|
/// Rabbita purity: context-yield guidance is a deterministic model update.
/// The raw stream event clears partial streams but does not close the run;
/// the host's following Finished message owns that transition.
test "update is pure: context yield appends continuation guidance" {
  let dispatch = test_dispatch()
  let answer = "[context ceiling] continue in a new turn"
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "partial",
    streaming_reasoning: "thinking",
  })
  let (_, once) = update(
    dispatch,
    Engine(7, ContextYield(answer), session=None),
    model,
  )
  let (_, twice) = update(
    dispatch,
    Engine(7, ContextYield(answer), session=None),
    model,
  )
  inspect(model.active().messages.length(), content="0")
  inspect(once.active().messages.length(), content="1")
  inspect(twice.active().messages.length(), content="1")
  guard once.active().messages.last() is Some(once_item) &&
    twice.active().messages.last() is Some(twice_item) else {
    fail("expected context-yield guidance")
  }
  assert_true(
    once_item.kind is Assistant(false) && twice_item.kind is Assistant(false),
  )
  inspect(once_item.content, content="[context ceiling] continue in a new turn")
  inspect(
    twice_item.content,
    content="[context ceiling] continue in a new turn",
  )
  inspect(once.active().streaming_response, content="")
  inspect(twice.active().streaming_response, content="")
  inspect(once.active().streaming_reasoning, content="")
  inspect(twice.active().streaming_reasoning, content="")
  assert_true(once.active().is_running() && twice.active().is_running())
}

///|
/// The successful ceiling path is one automatic Summary, one continuation
/// notice, then a warning terminal that re-opens Send. It never enters the
/// manual compaction lifecycle.
test "context yield settles after its automatic checkpoint" {
  let dispatch = test_dispatch()
  let answer = "[context ceiling] continue in a new turn"
  let (_, checkpointed) = update(
    dispatch,
    Engine(7, AutoCompactionFinished("checkpoint recap"), session=None),
    running_model(),
  )
  let (_, yielded) = update(
    dispatch,
    Engine(7, ContextYield(answer), session=None),
    checkpointed,
  )
  assert_true(yielded.active().is_running())
  let (_, settled) = update(
    dispatch,
    Finished(run_id=7, status="context_yield", answer=Some(answer)),
    yielded,
  )
  inspect(settled.active().messages.length(), content="2")
  guard settled.active().messages.get(0) is Some(summary) &&
    settled.active().messages.get(1) is Some(guidance) else {
    fail("expected checkpoint and guidance")
  }
  assert_true(summary.kind is Summary)
  inspect(summary.content, content="checkpoint recap")
  assert_true(guidance.kind is Assistant(false))
  inspect(guidance.content, content="[context ceiling] continue in a new turn")
  assert_true(settled.active().compaction is NotCompacting)
  assert_false(settled.active().is_running())
  guard settled.display_status() is Finished(outcome) else {
    fail("expected a finished status")
  }
  assert_true(outcome is ContextYield)
  inspect(outcome.label(), content="Context limit reached")
  assert_true(settled.display_status().kind() is Warn)
}

///|
/// The compaction summary lands as its own Summary item — never a tool call
/// the transcript loop would fold into the preceding turn's activity card
/// (which would also swallow that turn's answer bubble into the fold).
test "compaction_finished appends a standalone summary item" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Compacting,
    last_run_id: Some(7),
  })
  let (_, next) = update(
    dispatch,
    Engine(7, CompactionFinished("earlier turns compacted"), session=None),
    model,
  )
  guard next.active().messages.last() is Some(item) && item.kind is Summary else {
    fail("expected a summary item")
  }
  inspect(item.content, content="earlier turns compacted")
  assert_true(next.active().compaction is NotCompacting)
}

///|
/// A conversation resumed and compacted before its first prompt of this
/// app-lifetime has no run id anywhere — the spawned engine stamps run 0 and
/// the conversation's `last_run_id` is still `None` — so compaction events
/// must route by the session the host stamps on them.
test "compaction events route by session when no run id matches" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    last_run_id: None,
  })
  let (_, started) = update(
    dispatch,
    Engine(0, CompactionStarted, session=Some("desktop-test")),
    model,
  )
  assert_true(started.active().compaction is Compacting)
  let (_, next) = update(
    dispatch,
    Engine(
      0,
      CompactionFinished("earlier turns compacted"),
      session=Some("desktop-test"),
    ),
    started,
  )
  guard next.active().messages.last() is Some(item) && item.kind is Summary else {
    fail("expected a summary item")
  }
  assert_true(next.active().compaction is NotCompacting)
}

///|
/// The host synthesizes compaction_failed when the engine dies with a
/// compaction still queued behind the dead turn; that terminal event must
/// settle the queued notice like any other compaction failure.
test "compaction_failed settles a still-queued compaction" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Queued,
    last_run_id: Some(7),
  })
  let (_, next) = update(
    dispatch,
    Engine(7, CompactionFailed("engine exited"), session=None),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
  inspect(next.active().messages.length(), content="1")
}

///|
/// A rejected compact request (no engine, host error) never produces
/// compaction events, so the rejection itself clears the queued notice and
/// lands the error in the transcript.
test "CompactRejected clears the queued notice and reports the error" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    compaction: Queued,
  })
  let (_, next) = update(
    dispatch,
    CompactRejected(session="desktop-test", message="no engine"),
    model,
  )
  assert_true(next.active().compaction is NotCompacting)
  inspect(next.active().messages.length(), content="1")
}

///|
test "a startup check surfaces an installable release as the Update button" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckFound(version="0.2.0", installable=true),
      explicit=false,
    ),
    test_model(),
  )
  assert_true(
    model.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
  assert_eq(model.notifications.length(), 0)
}

///|
test "quiet startup outcomes leave no trace; explicit ones answer" {
  let dispatch = test_dispatch()
  for
    result in [
      CheckUpToDate,
      CheckUnreachable(reason="offline"),
      CheckMalformed(reason="not json"),
    ] {
    let (_, silent) = update(
      dispatch,
      UpdateCheckFinished(result~, explicit=false),
      test_model(),
    )
    assert_true(silent.update_ux is UpdateUnknown)
    assert_eq(silent.notifications.length(), 0)
  }
  let (_, ok) = update(
    dispatch,
    UpdateCheckFinished(result=CheckUpToDate, explicit=true),
    test_model(),
  )
  assert_true(ok.update_ux is UpToDate)
  let (_, offline) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckUnreachable(reason="offline"),
      explicit=true,
    ),
    test_model(),
  )
  assert_true(
    offline.update_ux is UpdateCheckFailed(..) &&
    offline.update_ux is UpdateCheckFailed(message~) &&
    message.contains("offline"),
  )
}

///|
test "a broken package entry is loud even when the app asked" {
  let dispatch = test_dispatch()
  let (_, model) = update(
    dispatch,
    UpdateCheckFinished(
      result=CheckBroken(version="0.2.0", reason="url is not https"),
      explicit=false,
    ),
    test_model(),
  )
  assert_eq(model.notifications.length(), 1)
  assert_true(model.notifications[0].message.contains("url is not https"))
  assert_true(model.update_ux is UpdateCheckFailed(..))
}

///|
test "clicking Update goes straight to download when nothing runs" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, clicked) = update(dispatch, UpdateClicked, available)
  assert_true(clicked.update_ux is DownloadingUpdate(version="0.2.0"))
  // Downloaded hands off to apply and marks the restart.
  let (_, done) = update(dispatch, UpdateDownloaded, clicked)
  assert_true(done.update_ux is RestartingForUpdate(version="0.2.0"))
}

///|
test "clicking Update asks first while a conversation runs" {
  let dispatch = test_dispatch()
  let busy = {
    ..test_model().replace_conversation({ ..test_conversation(), run: Starting }),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, asked) = update(dispatch, UpdateClicked, busy)
  assert_true(asked.update_ux is ConfirmingRestart(version="0.2.0"))
  // Cancel restores the offer; confirm starts the download.
  let (_, kept) = update(dispatch, CancelUpdateRestart, asked)
  assert_true(
    kept.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
  let (_, confirmed) = update(dispatch, ConfirmUpdateRestart, asked)
  assert_true(confirmed.update_ux is DownloadingUpdate(version="0.2.0"))
}

///|
test "a failed download says why and restores the offer" {
  let dispatch = test_dispatch()
  let downloading = {
    ..test_model(),
    update_ux: DownloadingUpdate(version="0.2.0"),
  }
  let (_, failed) = update(
    dispatch,
    UpdateFailed(message="digest mismatch"),
    downloading,
  )
  assert_eq(failed.notifications.length(), 1)
  assert_true(failed.notifications[0].message.contains("digest mismatch"))
  assert_true(
    failed.update_ux is UpdateAvailable(version="0.2.0", installable=true),
  )
}

///|
test "a stale check reply cannot clobber a download in flight" {
  let dispatch = test_dispatch()
  let downloading = {
    ..test_model(),
    update_ux: DownloadingUpdate(version="0.2.0"),
  }
  let (_, next) = update(
    dispatch,
    UpdateCheckFinished(result=CheckUpToDate, explicit=false),
    downloading,
  )
  assert_true(next.update_ux is DownloadingUpdate(version="0.2.0"))
}

///|
test "switching the update channel forgets the previous answer" {
  let dispatch = test_dispatch()
  let available = {
    ..test_model(),
    update_ux: UpdateAvailable(version="0.2.0", installable=true),
  }
  let (_, switched) = update(
    dispatch,
    UpdateChannelChanged("staging"),
    available,
  )
  assert_true(switched.update_channel is Staging)
  assert_true(switched.update_ux is UpdateUnknown)
}

///|
test "check_update replies decode by kind" {
  assert_true(
    decode_update_check("{\"kind\":\"up_to_date\"}") is Some(CheckUpToDate),
  )
  assert_true(
    decode_update_check(
      "{\"kind\":\"available\",\"version\":\"0.2.0\",\"installable\":true}",
    )
    is Some(CheckFound(version="0.2.0", installable=true)),
  )
  // The host always writes `installable` on an `available` reply; one
  // without it is malformed rather than "not installable".
  assert_true(
    decode_update_check("{\"kind\":\"available\",\"version\":\"0.2.0\"}")
    is None,
  )
  assert_true(
    decode_update_check("{\"kind\":\"unreachable\",\"reason\":\"offline\"}")
    is Some(CheckUnreachable(reason="offline")),
  )
  assert_true(
    decode_update_check("{\"kind\":\"malformed\",\"reason\":\"not json\"}")
    is Some(CheckMalformed(reason="not json")),
  )
  assert_true(
    decode_update_check(
      "{\"kind\":\"broken\",\"version\":\"0.2.0\",\"reason\":\"bad url\"}",
    )
    is Some(CheckBroken(version="0.2.0", reason="bad url")),
  )
  // Unknown kinds and structurally unusable replies are indecipherable.
  assert_true(decode_update_check("{\"kind\":\"available\"}") is None)
  assert_true(decode_update_check("{\"kind\":\"surprise\"}") is None)
  assert_true(decode_update_check("garbage") is None)
}
