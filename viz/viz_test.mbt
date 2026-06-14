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
fn render(html : @html.Html) -> String {
  @rabbita.render_to_string(@rabbita.static_cell(html))
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
test "raw view shows per-event offsets and turn duration from ts" {
  let stamped = @agent_session.Session(SessionId("t"), system_prompt="")
    .append(User(UserMessage("go")), unix_ms=1781151318110L)
    .append(Runtime(RuntimeNotice("working")), unix_ms=1781151319242L)
    .append(Terminal(Finished("done")), unix_ms=1781151443650L)
  let html = render(@viz.render_session(stamped, RawLog))
  assert_true(html.contains("+0.0s"))
  assert_true(html.contains("+1.1s"))
  assert_true(html.contains("+2m 05.5s"))
  assert_true(html.contains("· 2m 05.5s"))
  let unstamped = @agent_session.Session(SessionId("u"), system_prompt="")
    .append(User(UserMessage("go")))
    .append(Terminal(Finished("done")))
  let plain = render(@viz.render_session(unstamped, RawLog))
  assert_false(plain.contains("card-ts"))
}
