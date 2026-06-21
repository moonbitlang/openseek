///|
/// Build a session that exercises every event kind, then serialize it back to
/// the on-disk `events.jsonl` form so the parser is tested against exactly what
/// the store writes.
fn sample_session() -> @agent_session.Session {
  let s0 = @agent_session.Session(
    SessionId("demo"),
    system_prompt="You are a helpful agent.",
  )
  let s1 = s0.append(User(UserMessage("list the files")))
  let s2 = s1.append(
    Assistant(
      AssistantMessage(
        "I'll run ls.",
        tool_calls=[
          ToolCall(id="call_1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ],
        reasoning_content="The user wants a directory listing.",
      ),
    ),
  )
  let s3 = s2.append(
    Tool(
      ToolResult(
        tool_call_id="call_1",
        tool_name="shell",
        content="README.md\nsrc",
      ),
    ),
  )
  let s4 = s3.append(Runtime(RuntimeNotice("moon check: 0 errors")))
  s4.append(Terminal(Finished("Here are your files: README.md, src.")))
}

///|
/// Serialize a session to the append-only JSONL text the store persists.
fn events_jsonl(session : @agent_session.Session) -> String {
  let out = StringBuilder()
  for event in session.events() {
    out <+ "\{event.to_json().stringify()}\n"
  }
  out.to_string()
}

///|
#warnings("-alert_unstable")
fn render(html : @html.Html) -> String {
  @rabbita.render_to_string(@rabbita.static_cell(html))
}

///|
/// A session whose tool result failed, plus a tool call with arguments and one
/// without, to exercise the fold/flag rendering.
fn error_tool_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("e"), system_prompt="")
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ToolCall(id="c2", name="noop", arguments="{}"),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="c1",
        tool_name="shell",
        content="boom",
        is_error=true,
      ),
    ),
  )
}

///|
fn multi_step_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("steps"), system_prompt="system")
  .append(User(UserMessage("start")))
  .append(
    Assistant(
      AssistantMessage("checking", tool_calls=[
        ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"pwd\"}"),
      ]),
    ),
  )
  .append(
    Tool(ToolResult(tool_call_id="c1", tool_name="shell", content="/repo")),
  )
  .append(Terminal(Finished("final answer")))
}

///|
fn occurrences(text : String, needle : String) -> Int {
  text.split(needle).collect().length() - 1
}

///|
fn finish_tool_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("finish"), system_prompt="system")
  .append(User(UserMessage("start")))
  .append(
    Assistant(
      AssistantMessage("", tool_calls=[
        ToolCall(
          id="finish_1",
          name="finish",
          arguments="{\"answer\":\"done\"}",
        ),
      ]),
    ),
  )
  .append(
    Tool(
      ToolResult(
        tool_call_id="finish_1",
        tool_name="finish",
        content="finished: done",
      ),
    ),
  )
  .append(Terminal(Finished("done")))
}

///|
test "tool calls fold their arguments, empty args stay flat" {
  let html = render(@viz.render_session(error_tool_session(), RawLog))
  // A call with arguments folds: the name becomes a <summary>, args hide in the
  // collapsed <details> (no `open` attribute) yet are still in the DOM.
  assert_true(html.contains("<details class=\"tool-call\">"))
  assert_true(html.contains("<summary class=\"tool-call-name\">"))
  assert_true(html.contains("shell"))
  assert_true(html.contains("cmd"))
  // A call with no meaningful arguments ({}) renders flat — nothing to fold.
  assert_true(
    html.contains("<div class=\"tool-call\"><div class=\"tool-call-name\">"),
  )
}

///|
test "failed tool result is folded and red-flagged" {
  let html = render(@viz.render_session(error_tool_session(), RawLog))
  // Folded by default (a <details> with no `open`), tagged as an error, and the
  // summary carries the red flag so a collapsed failure still stands out.
  assert_true(html.contains("<details class=\"card tool error\">"))
  assert_false(html.contains("<details class=\"card tool error\" open>"))
  assert_true(html.contains("class=\"tool-flag\">🚩 failed"))
  assert_true(html.contains("Tool error · shell"))
  assert_true(html.contains("boom"))
}

///|
test "model view recovers the error flag the projection drops" {
  // The model projection keys a tool message by id only and drops is_error, but
  // the view correlates back to the durable ToolResult, so a failed tool (e.g. a
  // non-zero exit) is red-flagged in the model view too — with its tool name.
  let model = render(@viz.render_session(error_tool_session(), ModelView))
  assert_true(model.contains("<details class=\"card tool error\">"))
  assert_true(model.contains("class=\"tool-flag\">🚩 failed"))
  assert_true(model.contains("Tool error · shell"))
}

///|
test "model view shows relative event timestamps" {
  let session = @agent_session.Session(
      SessionId("time"),
      system_prompt="system",
    )
    .append(User(UserMessage("inspect")), unix_ms=100000L)
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"moon test\"}"),
        ]),
      ),
      unix_ms=101500L,
    )
    .append(
      Tool(ToolResult(tool_call_id="c1", tool_name="shell", content="ok")),
      unix_ms=103200L,
    )
    .append(Terminal(Finished("done")), unix_ms=170300L)
  let html = render(@viz.render_session(session, ModelView))
  assert_true(html.contains("class=\"card-ts\">+0.0s"))
  assert_true(html.contains("class=\"card-ts\">+1.5s"))
  assert_true(html.contains("class=\"card-ts\">+3.2s"))
  assert_true(html.contains("class=\"card-ts\">+70.3s"))
  assert_false(html.contains("class=\"card-ts\">+1m 10.3s"))
}

///|
test "assistant cards show agent step progress" {
  let session = multi_step_session()
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("class=\"card-step\">Step 1/2"))
  assert_true(raw.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(raw, "class=\"card-step\""), content="2")
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("class=\"card-step\">Step 1/2"))
  assert_true(model.contains("class=\"card-step\">Step 2/2"))
  inspect(occurrences(model, "class=\"card-step\""), content="2")
  assert_false(model.contains("Step 3/2"))
}

///|
test "finish tool terminal does not add an extra step" {
  let session = finish_tool_session()
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("class=\"card-step\">Step 1/1"))
  inspect(occurrences(raw, "class=\"card-step\""), content="1")
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("class=\"card-step\">Step 1/1"))
  inspect(occurrences(model, "class=\"card-step\""), content="1")
  assert_false(model.contains("Step 2/2"))
}

///|
test "model view does not flag a result the projection skipped" {
  // Compact away only the tool result (seq 2): the projection then heals the
  // dangling call c1 with a synthetic error message, so the model never saw the
  // real "boom" result. The view must not attach that result's flag/name to the
  // synthetic message — it would misrepresent what the model was fed.
  let compacted = error_tool_session().compact(
    content="covered",
    from_sequence=2,
    to_sequence=2,
  )
  let model = render(@viz.render_session(compacted, ModelView))
  assert_true(model.contains("previous agent process exited"))
  assert_false(model.contains("tool-flag"))
  assert_false(model.contains("Tool error · shell"))
}

///|
test "successful tool result folds without a flag" {
  // sample_session's tool result is a success; it should fold but carry no flag.
  let session = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="",
  )
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("<details class=\"card tool\">"))
  assert_false(raw.contains("tool-flag"))
  // Model view folds its tool result too (no flag — the projection drops it).
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("<details class=\"card tool\">"))
  assert_true(model.contains("Tool result"))
}

///|
test "tool call shows the brief its result recorded" {
  let session = @agent_session.Session(SessionId("b"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="shell",
          content="exit=0\na",
          brief="ran ls → 1 file",
        ),
      ),
    )
  let raw = render(@viz.render_session(session, RawLog))
  assert_true(raw.contains("tool-call-brief"))
  assert_true(raw.contains("ran ls → 1 file"))
  let model = render(@viz.render_session(session, ModelView))
  assert_true(model.contains("ran ls → 1 file"))
  // A *successful* result with no brief produces no brief span on its call.
  let clean = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="",
  )
  assert_false(
    render(@viz.render_session(clean, RawLog)).contains("tool-call-brief"),
  )
}

///|
test "a failed tool call is flagged on the folded call line" {
  // error_tool_session: c1 (shell) failed with no brief -> flagged with 🚩.
  let raw = render(@viz.render_session(error_tool_session(), RawLog))
  assert_true(raw.contains("tool-call-brief"))
  assert_true(raw.contains("🚩"))
  // A failed result that carries a brief shows the brief and the flag, in both
  // views.
  let with_brief = @agent_session.Session(SessionId("fb"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="r1", name="read", arguments="{\"path\":\"x.txt\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="r1",
          tool_name="read",
          content="error reading x.txt: missing",
          is_error=true,
          brief="read x.txt",
        ),
      ),
    )
  assert_true(
    render(@viz.render_session(with_brief, RawLog)).contains("read x.txt 🚩"),
  )
  assert_true(
    render(@viz.render_session(with_brief, ModelView)).contains(
      "read x.txt 🚩",
    ),
  )
}

///|
test "model view omits a brief whose result was compacted away" {
  let session = @agent_session.Session(SessionId("cb"), system_prompt="")
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(id="c1", name="shell", arguments="{\"cmd\":\"ls\"}"),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="c1",
          tool_name="shell",
          content="files",
          brief="ran ls → 3 files",
        ),
      ),
    )
  // Compact away only the result (seq 2): the model projection heals the call
  // with a synthetic result, so the model never saw this brief.
  let compacted = session.compact(
    content="covered",
    from_sequence=2,
    to_sequence=2,
  )
  // Raw shows the durable brief on the call; the model view must not.
  assert_true(
    render(@viz.render_session(compacted, RawLog)).contains(
      "ran ls → 3 files",
    ),
  )
  assert_false(
    render(@viz.render_session(compacted, ModelView)).contains(
      "ran ls → 3 files",
    ),
  )
}

///|
test "turn header badges failed tools" {
  let html = render(@viz.render_session(error_tool_session(), RawLog))
  assert_true(html.contains("turn-error-badge"))
  assert_true(html.contains("🚩 1 error"))
}

///|
test "rendered_error_count matches the failures each view draws" {
  let failing = error_tool_session()
  inspect(@viz.rendered_error_count(failing, RawLog), content="1")
  inspect(@viz.rendered_error_count(failing, ModelView), content="1")
  let clean = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="",
  )
  inspect(@viz.rendered_error_count(clean, RawLog), content="0")
  inspect(@viz.rendered_error_count(clean, ModelView), content="0")
}

///|
test "model error count excludes a compacted-away failure raw still shows" {
  let compacted = error_tool_session().compact(
    content="covered",
    from_sequence=2,
    to_sequence=2,
  )
  // Raw still renders the durable errored result; the model view healed the
  // dangling call, so it has no error card to count.
  inspect(@viz.rendered_error_count(compacted, RawLog), content="1")
  inspect(@viz.rendered_error_count(compacted, ModelView), content="0")
}

///|
test "parse round-trips every event kind" {
  let text = events_jsonl(sample_session())
  let parsed = @viz.parse_events(text)
  inspect(parsed.events.length(), content="5")
  inspect(parsed.errors.length(), content="0")
  inspect(parsed.partial_tail, content="false")
}

///|
test "parse tolerates a truncated final line" {
  let text = "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"assi"
  let parsed = @viz.parse_events(text)
  inspect(parsed.events.length(), content="1")
  inspect(parsed.errors.length(), content="0")
  inspect(parsed.partial_tail, content="true")
}

///|
test "parse records a bad interior line without aborting" {
  let text = "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\nnot json at all\n{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"done\"}}}\n"
  let parsed = @viz.parse_events(text)
  inspect(parsed.events.length(), content="2")
  inspect(parsed.errors.length(), content="1")
  inspect(parsed.errors[0].line_number, content="2")
  inspect(parsed.partial_tail, content="false")
}

///|
test "raw view renders each event kind" {
  let session = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="You are a helpful agent.",
  )
  let html = render(@viz.render_session(session, RawLog))
  assert_true(html.contains("Turn 1"))
  assert_true(html.contains("class=\"card user\""))
  assert_true(html.contains("class=\"card assistant\""))
  assert_true(html.contains("reasoning"))
  assert_true(html.contains("shell"))
  assert_true(html.contains("Tool result"))
  assert_true(html.contains("Runtime notice"))
  assert_true(html.contains("badge-finished"))
}

///|
test "model view substitutes a summary for the events it covers" {
  // A session whose summary covers the first two events: the model projection
  // should show the summary text and drop the covered user/assistant content.
  let base = @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="SYS-PROMPT-MARKER",
  )
  let compacted = base.compact(
    content="SUMMARY-MARKER: user asked for files; agent planned ls.",
    from_sequence=1,
    to_sequence=2,
  )
  let model_html = render(@viz.render_session(compacted, ModelView))
  assert_true(model_html.contains("System prompt"))
  assert_true(model_html.contains("SYS-PROMPT-MARKER"))
  assert_true(model_html.contains("SUMMARY-MARKER"))
  // The assistant's planning line is covered by the summary, so the model view
  // must not replay it.
  assert_true(!model_html.contains("I'll run ls."))
  // The raw view still shows everything, including the covered line.
  let raw_html = render(@viz.render_session(compacted, RawLog))
  assert_true(raw_html.contains("I'll run ls."))
  assert_true(raw_html.contains("Summary"))
}

///|
test "notices surface partial tails and bad lines" {
  let parsed = @viz.parse_events(
    "garbage line\n{\"sequence\":1,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n{bad tail",
  )
  let html = render(@viz.render_notices(parsed))
  assert_true(html.contains("could not be decoded"))
  assert_true(html.contains("trailing partial line"))
}

///|
/// Stamped events render relative offsets and a turn duration; unstamped
/// events (the 0 sentinel) render no time chips at all.
test "raw view shows total-second offsets and turn duration from ts" {
  let stamped = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(User(UserMessage("go")), unix_ms=1781151318110L)
    .append(Runtime(RuntimeNotice("working")), unix_ms=1781151319242L)
    .append(Terminal(Finished("done")), unix_ms=1781151443650L)
  let html = render(@viz.render_session(stamped, RawLog))
  assert_true(html.contains("+0.0s"))
  assert_true(html.contains("+1.1s"))
  assert_true(html.contains("+125.5s"))
  assert_true(html.contains("· 125.5s"))
  assert_false(html.contains("+2m 05.5s"))
  let unstamped = @agent_session.Session(SessionId("u"), system_prompt="")
    .append(User(UserMessage("go")))
    .append(Terminal(Finished("done")))
  let plain = render(@viz.render_session(unstamped, RawLog))
  assert_false(plain.contains("card-ts"))
}
