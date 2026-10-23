///|
/// A version-1 session file as earlier builds wrote it. It is frozen: never
/// regenerate it from the current encoder. The store tests round-trip through
/// the encoder, so they would keep passing if an encoding changed; this file
/// pins the bytes already on users' disks, which every later build must load.
let legacy_v1_fixture = "agent_session/store/testdata/session-v1.jsonl"

///|
async test "a frozen version-1 session file still loads" {
  let store = @store.SessionStore(@fs.tmpdir(prefix="openseek-legacy-v1-"))
  defer @fs.rmdir(store.root(), recursive=true)
  @fs.mkdir("\{store.root()}/sessions/legacy", recursive=true)
  @fs.write_file(
    session_file(store, "legacy"),
    @fs.read_file(legacy_v1_fixture).text(),
    create_mode=CreateOrTruncate,
  )
  let loaded = store.load(SessionId("legacy"))
  assert_eq(loaded.system_prompt(), "You are a test agent.")
  assert_eq(loaded.last_sequence(), 18)
  let events = loaded.events()
  assert_eq(events[0].unix_ms(), 1758700001000L)
  assert_eq(events[17].unix_ms(), 1758700018000L)
  let expected : Array[@agent_session.SessionItem] = [
    User(UserMessage(Content([Text("read the readme")]), submission_id="sub-1")),
    Runtime(RuntimeNotice("[plan reminder] keep going")),
    Assistant(
      AssistantMessage(
        "",
        tool_calls=[
          ToolCall(
            id="call_1",
            name="read",
            arguments="{\"path\":\"README.md\"}",
          ),
        ],
        reasoning_content="look first",
      ),
    ),
    Tool(
      ToolResult(
        tool_call_id="call_1",
        tool_name="read",
        content=[Text("# Title")],
        brief="1 line",
        data={ "lines": 1 },
      ),
    ),
    Tool(
      ToolResult(
        tool_call_id="call_2",
        tool_name="read",
        content=[Text("no such file")],
        is_error=true,
      ),
    ),
    Assistant(AssistantMessage("The readme has a title.")),
    Terminal(Finished("The readme has a title.")),
    User(UserMessage(Content([Text("now do the big task")]))),
    Summary(
      SessionSummary(
        content="read the readme; it has a title",
        from_sequence=1,
        to_sequence=7,
      ),
    ),
    // A context-ceiling yield, saved as `finished` with the yield prefix.
    Terminal(
      ContextYield(
        "[context ceiling] This turn reached the model's context window and was checkpointed.",
      ),
    ),
    User(UserMessage(Content([Text("continue")]))),
    // Step exhaustion, saved as `failed` with this exact message.
    Terminal(MaxStepsExhausted),
    User(UserMessage(Content([Text("again")]))),
    Terminal(Failed("agent failed: boom")),
    User(UserMessage(Content([Text("stop it")]))),
    Terminal(Aborted("user asked to stop")),
    User(UserMessage(Content([Text("one more")]))),
    Terminal(Interrupted("cancelled")),
  ]
  assert_eq(events.iter().map(event => event.item()).collect(), expected)
}

///|
async test "the lenient log parser reads the frozen version-1 file cleanly" {
  let parsed = @session_log.parse_events(
    @fs.read_file(legacy_v1_fixture).text(),
  )
  assert_eq(
    parsed.header,
    Some({ id: "legacy", system_prompt: "You are a test agent.", }),
  )
  assert_eq(parsed.errors, [])
  assert_false(parsed.partial_tail)
  assert_eq(parsed.events.length(), 18)
}

///|
async test "a current terminal whose text matches an older encoding round-trips" {
  // A real answer may start with the yield prefix, and a real failure may
  // read "max steps exhausted". Reloading must not turn them into the
  // dedicated variants, or the store's stale-snapshot check rejects the
  // next append of the unchanged session.
  let store = @store.SessionStore(@fs.tmpdir(prefix="openseek-verbatim-"))
  defer @fs.rmdir(store.root(), recursive=true)
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage(Content([Text("echo the marker")]))))
    .append(Terminal(Finished("[context ceiling] echoed on request")))
    .append(User(UserMessage(Content([Text("fail on purpose")]))))
    .append(Terminal(Failed("max steps exhausted")))
  store.create(session)
  let loaded = @store.SessionStore(store.root()).load(SessionId("s1"))
  assert_eq(loaded.events(), session.events())
  let appended = @store.SessionStore(store.root()).append(
    session,
    User(UserMessage(Content([Text("next")]))),
  )
  assert_eq(appended.last_sequence(), 5)
}
