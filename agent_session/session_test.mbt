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
  let line = ToJson::to_json(stamped.events()[0]).stringify()
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
test "assistant checkpoint replay provenance is durable and sparse" {
  let ordinary = @agent_session.AssistantMessage("answer")
  assert_false(ordinary.is_replay())
  assert_false(ToJson::to_json(ordinary).stringify().contains("is_replay"))
  let replay = @agent_session.AssistantMessage(
    "answer",
    reasoning_content="thought",
    is_replay=true,
  )
  assert_true(replay.is_replay())
  let decoded : @agent_session.AssistantMessage = @json.from_json(
    ToJson::to_json(replay),
  )
  assert_true(decoded.is_replay())
  assert_eq(decoded.reasoning_content(), Some("thought"))
}

///|
test "ToolResult brief round-trips when present" {
  let with_brief = @agent_session.ToolResult(
    tool_call_id="call_2",
    tool_name="shell",
    content="exit=0\na\nb",
    brief="ran ls → 2 files",
  )
  let decoded : @agent_session.ToolResult = @json.from_json(
    ToJson::to_json(with_brief),
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
test "projection skips context-yield terminals" {
  // The full ceiling-yield shape: work, preserved steer, checkpoint
  // summary, synthetic yield terminal. The resumed model context must be
  // [system, summary, steer] — the yield status is run metadata, not an
  // assistant answer, and must never read as the reply to the steer.
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("build everything")))
    .append(User(UserMessage("preserved steer")))
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=1),
      ),
    )
    .append(
      Terminal(
        Finished(
          "\{@agent_session.ContextYieldAnswerPrefix} continue in a new turn",
        ),
      ),
    )
  let messages = session.chat_messages()
  assert_eq(messages.length(), 3)
  assert_true(messages[1].content.contains("checkpoint"))
  assert_true(messages[2].role is User)
  assert_eq(messages[2].content, "preserved steer")
}

///|
test "projection does not repeat a reasoning-bearing final answer" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("question")))
    .append(
      Assistant(
        AssistantMessage("answer", reasoning_content="consider the options"),
      ),
    )
    .append(Terminal(Finished("answer")))
  let messages = session.chat_messages()
  assert_eq(messages.length(), 3)
  assert_true(messages[1].role is User)
  assert_true(messages[2].role is Assistant)
  assert_eq(messages[2].content, "answer")
  assert_eq(messages[2].reasoning_content, Some("consider the options"))
}

///|
test "projection does not repeat a plain final preserved as an assistant" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("question")))
    .append(Assistant(AssistantMessage("answer")))
    .append(Terminal(Finished("answer")))
  let messages = session.chat_messages()
  assert_eq(messages.length(), 3)
  assert_true(messages[1].role is User)
  assert_true(messages[2].role is Assistant)
  assert_eq(messages[2].content, "answer")
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
  // The summary stands where the covered range stood, before the uncovered
  // recent user message — not at its own append position after it.
  assert_true(messages[1].role is User)
  assert_true(messages[1].content.contains("[conversation summary]"))
  assert_false(messages[1].content.contains("old user\n"))
  assert_true(messages[1].content.contains("old user and assistant"))
  assert_true(messages[2].role is User)
  assert_eq(messages[2].content, "recent user")
}

///|
test "summary appended mid-turn projects before the uncovered tail" {
  // The stage-one auto-compaction shape: the summary event lands after the
  // active turn's task but covers only the prior turn, so projection must
  // put its text where the prior turn stood, ahead of the task.
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("prior task")))
    .append(Terminal(Finished("prior answer")))
    .append(User(UserMessage("active task")))
    .append(
      Summary(
        SessionSummary(
          content="prior turn recap",
          from_sequence=1,
          to_sequence=2,
        ),
      ),
    )
    .append(Assistant(AssistantMessage("working on it")))
  let messages = session.chat_messages()
  assert_eq(messages.length(), 4)
  assert_true(messages[1].role is User)
  assert_true(messages[1].content.contains("prior turn recap"))
  assert_true(messages[2].role is User)
  assert_eq(messages[2].content, "active task")
  assert_true(messages[3].role is Assistant)
  assert_eq(messages[3].content, "working on it")
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
  try session.compact(content="", from_sequence=1, to_sequence=2) catch {
    error => assert_true("\{error}".contains("content must not be empty"))
  } noraise {
    _ => fail("empty summary accepted")
  }
}

///|
test "summary_item validates without appending" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("first")))
    .append(Assistant(AssistantMessage("second")))
  let item = session.summary_item(
    content="first two events",
    from_sequence=1,
    to_sequence=2,
  )
  assert_true(item is Summary(_))
  assert_eq(session.events().length(), 2)
  try session.summary_item(content="x", from_sequence=1, to_sequence=3) catch {
    error => assert_true("\{error}".contains("exceeds last sequence"))
  } noraise {
    _ => fail("out-of-range summary accepted")
  }
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

///|
test "a compacted-over set marker re-arms the turn-start reminder" {
  // A fresh set normally rides the next request verbatim, so no reminder —
  // but a summary covering the marker removes that verbatim text from the
  // projection, and the cadence must re-surface the goal instead of
  // trusting the lossy summary.
  let session = @agent_session.Session(SessionId("s1"), system_prompt="sys")
    .append(User(UserMessage("task")))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nbig objective")),
    )
    .append(
      Summary(SessionSummary(content="folded", from_sequence=1, to_sequence=2)),
    )
  guard session.current_goal() is Some(goal) else { fail("goal must stand") }
  assert_true(goal.answered_since_set())
}

///|
test "a summary of later events leaves a fresh set marker verbatim" {
  // The marker stays in the projection (the summary's range starts after
  // it), so the fresh-set suppression still applies: no extra reminder.
  let session = @agent_session.Session(SessionId("s2"), system_prompt="sys")
    .append(User(UserMessage("task one")))
    .append(User(UserMessage("task two")))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nbig objective")),
    )
    .append(
      Summary(SessionSummary(content="folded", from_sequence=1, to_sequence=2)),
    )
  guard session.current_goal() is Some(goal) else { fail("goal must stand") }
  assert_false(goal.answered_since_set())
}

///|
test "a blocked marker pauses the standing goal without clearing it" {
  let session = @agent_session.Session(SessionId("s3"), system_prompt="sys")
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nbig objective")),
    )
    .append(Terminal(Finished("earlier")))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalBlockedPrefix}\nneeds a key")),
    )
  guard session.current_goal() is Some(goal) else { fail("goal must stand") }
  assert_true(goal.blocked())
  // A NEWER set resets the pause.
  let session = session.append(
    Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nnew objective")),
  )
  guard session.current_goal() is Some(goal) else { fail("goal must stand") }
  assert_false(goal.blocked())
}
