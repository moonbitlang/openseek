///|
fn sample_tool_call() -> @deepseek.ToolCall {
  ToolCall(id="call_1", name="read", arguments="{\"path\":\"README.md\"}")
}

///|
test "session append assigns monotonic sequence numbers immutably" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let next = session.append(User(UserMessage("hello")))
  assert_eq(session.events().length(), 0)
  assert_eq(next.events().length(), 1)
  assert_eq(next.events()[0].sequence(), 1)
  let after = next.append(Terminal(Finished("done")))
  assert_eq(after.events()[1].sequence(), 2)
  assert_eq(after.last_sequence(), 2)
}

///|
test "session append_event returns the durable event" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let (next, event) = session.append_event(User(UserMessage("hello")))
  assert_eq(session.events().length(), 0)
  assert_eq(next.events().length(), 1)
  assert_eq(event.sequence(), 1)
  assert_true(event.item() is User(_))
  assert_eq(next.events()[0].sequence(), event.sequence())
}

///|
test "event timestamps round trip through JSON" {
  // Key order is pinned because the store's event_log_length/hash markers
  // cover the exact serialized text.
  let stamped = @agent_session.Session(SessionId("s1"), system_prompt="p").append(
    User(UserMessage("hello")),
    unix_ms=1781144351123L,
  )
  let line = stamped.events()[0].to_json().stringify()
  assert_eq(
    line,
    (
      #|{"sequence":1,"ts":1781144351123,"item":{"kind":"user","payload":{"content":"hello"}}}
    ),
  )
  let decoded : @agent_session.SessionEvent = @json.from_json(@json.parse(line))
  assert_eq(decoded.unix_ms(), 1781144351123L)

  // Without a clock (purely in-memory appends), the stamp is the 0 sentinel.
  let unstamped = @agent_session.Session(SessionId("s2"), system_prompt="p").append(
    User(UserMessage("hi")),
  )
  assert_eq(unstamped.events()[0].unix_ms(), 0L)
}

///|
test "ToolResult brief is optional and backwards compatible" {
  // A record written before briefs existed (no `brief` key) must still decode,
  // with `brief` defaulting to None — old logs keep parsing.
  let legacy_json =
    #|{"tool_call_id":"call_1","tool_name":"read","content":"README","is_error":false}
  let legacy : @agent_session.ToolResult = @json.from_json(
    @json.parse(legacy_json),
  )
  guard legacy.brief() is None else { fail("legacy brief should be None") }
  assert_eq(legacy.content(), "README")
  // A brief round-trips when present.
  let with_brief = @agent_session.ToolResult(
    tool_call_id="call_2",
    tool_name="shell",
    content="exit=0\na\nb",
    brief="ran ls → 2 files",
  )
  let decoded : @agent_session.ToolResult = @json.from_json(
    with_brief.to_json(),
  )
  guard decoded.brief() is Some(text) else { fail("brief should round-trip") }
  assert_eq(text, "ran ls → 2 files")
}

///|
test "session projects to DeepSeek chat messages" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("inspect")))
    .append(
      Assistant(
        AssistantMessage(
          "",
          tool_calls=[sample_tool_call()],
          reasoning_content="need file",
        ),
      ),
    )
    .append(
      Tool(
        ToolResult(tool_call_id="call_1", tool_name="read", content="README"),
      ),
    )
    .append(Terminal(Finished("done")))
  // The projection is the documented contract: a leading System message, the
  // user/assistant/tool turns, and a trailing Assistant message carrying the
  // finish text. The snapshot pins every field of every message.
  debug_inspect(
    session.chat_messages(),
    content=(
      #|[
      #|  {
      #|    role: System,
      #|    content: "system",
      #|    tool_calls: [],
      #|    reasoning_content: None,
      #|  },
      #|  {
      #|    role: User,
      #|    content: "inspect",
      #|    tool_calls: [],
      #|    reasoning_content: None,
      #|  },
      #|  {
      #|    role: Assistant,
      #|    content: "",
      #|    tool_calls: [{ id: "call_1", name: "read", arguments: "{\"path\":\"README.md\"}" }],
      #|    reasoning_content: Some("need file"),
      #|  },
      #|  {
      #|    role: Tool("call_1"),
      #|    content: "README",
      #|    tool_calls: [],
      #|    reasoning_content: None,
      #|  },
      #|  {
      #|    role: Assistant,
      #|    content: "done",
      #|    tool_calls: [],
      #|    reasoning_content: None,
      #|  },
      #|]
    ),
  )
}

///|
test "session JSON round trips typed events" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("hello")))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.PlanReminderPrefix}\nrun tests")),
    )
    .append(
      Summary(
        SessionSummary(
          content="we inspected files",
          from_sequence=1,
          to_sequence=2,
        ),
      ),
    )
    .append(Terminal(Finished("done")))
  let encoded = session.to_json()
  let decoded : @agent_session.Session = @json.from_json(encoded)
  assert_eq(decoded.id().value(), "s1")
  assert_eq(decoded.system_prompt(), "system")
  assert_eq(decoded.events().length(), 4)
  assert_eq(decoded.events()[3].sequence(), 4)
  guard decoded.events()[2].item() is Summary(summary) else {
    fail("expected summary")
  }
  assert_eq(summary.from_sequence(), 1)
  assert_eq(summary.to_sequence(), 2)
  assert_eq(summary.content(), "we inspected files")
}

///|
test "projection closes unresolved historical tool calls" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(Assistant(AssistantMessage("", tool_calls=[sample_tool_call()])))
    .append(User(UserMessage("continue")))
  let messages = session.chat_messages()
  assert_eq(messages.length(), 4)
  assert_true(messages[1].role is Assistant)
  assert_eq(messages[1].tool_calls.length(), 1)
  assert_true(messages[2].role is Tool("call_1"))
  assert_true(messages[2].content.contains("previous agent process exited"))
  assert_true(messages[3].role is User)
  assert_eq(messages[3].content, "continue")
}

///|
test "projection skips compacted assistant tool results" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("inspect")))
    .append(Assistant(AssistantMessage("", tool_calls=[sample_tool_call()])))
    .append(
      Tool(
        ToolResult(tool_call_id="call_1", tool_name="read", content="README"),
      ),
    )
    .append(
      Summary(
        SessionSummary(
          content="assistant inspected README",
          from_sequence=2,
          to_sequence=2,
        ),
      ),
    )
  let messages = session.chat_messages()
  assert_eq(messages.length(), 3)
  assert_true(messages[1].role is User)
  assert_eq(messages[1].content, "inspect")
  assert_true(messages[2].role is User)
  assert_true(messages[2].content.contains("assistant inspected README"))
}

///|
test "summary events compact covered model context" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("old user")))
    .append(Assistant(AssistantMessage("old assistant")))
    .append(User(UserMessage("recent user")))
    .append(
      Summary(
        SessionSummary(
          content="old user and assistant discussed README",
          from_sequence=1,
          to_sequence=2,
        ),
      ),
    )
  assert_eq(session.events().length(), 4)
  let messages = session.chat_messages()
  assert_eq(messages.length(), 3)
  assert_true(messages[1].role is User)
  assert_eq(messages[1].content, "recent user")
  assert_true(messages[2].role is User)
  assert_true(messages[2].content.contains("[conversation summary]"))
  assert_false(messages[2].content.contains("old user\n"))
  assert_true(messages[2].content.contains("old user and assistant"))
}

///|
test "later summary supersedes earlier summary in model context" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(
      Summary(
        SessionSummary(content="first summary", from_sequence=1, to_sequence=1),
      ),
    )
    .append(
      Summary(
        SessionSummary(
          content="superseding summary",
          from_sequence=1,
          to_sequence=2,
        ),
      ),
    )
  let messages = session.chat_messages()
  assert_eq(messages.length(), 2)
  assert_true(messages[1].content.contains("superseding summary"))
  assert_false(messages[1].content.contains("first summary"))
}

///|
test "compact validates and appends summary event" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(Assistant(AssistantMessage("second")))
  let compacted = session.compact(
    content="first two events",
    from_sequence=1,
    to_sequence=2,
  )
  assert_eq(compacted.events().length(), 3)
  guard compacted.events()[2].item() is Summary(summary) else {
    fail("expected summary")
  }
  assert_eq(summary.content(), "first two events")
  assert_eq(summary.from_sequence(), 1)
  assert_eq(summary.to_sequence(), 2)
  let _ = session.compact(content="", from_sequence=1, to_sequence=2) catch {
    error => {
      assert_true("\{error}".contains("content must not be empty"))
      return
    }
  }
  fail("empty summary accepted")
}

///|
test "generated session ids stamp the launcher prefix and UTC wall clock" {
  assert_eq(
    @agent_session.SessionId::generated(prefix="cli", now_ms=0).value(),
    "cli-19700101-000000-000",
  )
  // 2026-06-11T08:15:00.042Z, cross-checked against python datetime
  assert_eq(
    @agent_session.SessionId::generated(prefix="tui", now_ms=1781165700042).value(),
    "tui-20260611-081500-042",
  )
  // A salt keeps two same-millisecond launches apart.
  assert_eq(
    @agent_session.SessionId::generated(
      prefix="cli",
      now_ms=1781165700042,
      salt="1a2b3c4d",
    ).value(),
    "cli-20260611-081500-042-1a2b3c4d",
  )
}
