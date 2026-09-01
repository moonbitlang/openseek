///|
/// `sample_session` round-tripped through the durable-log parse path with an
/// empty system prompt — the "clean parsed session" several render tests use.
fn clean_sample_session() -> @agent_session.Session {
  @viz.session_from_parse(
    @viz.parse_events(events_jsonl(sample_session())),
    id="demo",
    system_prompt="",
  )
}

///|
/// Build a session that exercises every event kind, then serialize it back to
/// the on-disk session-file event form so the parser is tested against exactly what
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
  let s4 = s3.append(Runtime(RuntimeNotice("plan reminder: run tests")))
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
/// Compact away the sequence-2 event (a tool result in these fixtures) with a
/// "covered" summary — the projection then heals the call with a synthetic
/// result the model never saw.
fn compact_second_event(
  session : @agent_session.Session,
) -> @agent_session.Session raise {
  session.compact(content="covered", from_sequence=2, to_sequence=2)
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
test "rendered_error_count matches the failures each view draws" {
  let failing = error_tool_session()
  inspect(@viz.rendered_error_count(failing, RawLog), content="1")
  inspect(@viz.rendered_error_count(failing, ModelView), content="1")
  let clean = clean_sample_session()
  inspect(@viz.rendered_error_count(clean, RawLog), content="0")
  inspect(@viz.rendered_error_count(clean, ModelView), content="0")
}

///|
test "mbtx activity and build-error counts follow durable events" {
  let build_failure = @agent_session.Session(
      SessionId("build-failure"),
      system_prompt="",
    )
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="b1",
            name="mbtx",
            arguments="{\"source\":\"fn main {  }\"}",
          ),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="b1",
          tool_name="mbtx",
          content="diag",
          is_error=true,
          brief="mbtx (build failed, exit=1)",
        ),
      ),
    )
  assert_true(@viz.session_has_mbtx_activity(build_failure))
  inspect(@viz.rendered_build_error_count(build_failure, RawLog), content="1")
  inspect(
    @viz.rendered_build_error_count(build_failure, ModelView),
    content="1",
  )

  let clean = clean_sample_session()
  assert_false(@viz.session_has_mbtx_activity(clean))
  inspect(@viz.rendered_build_error_count(clean, RawLog), content="0")

  // An orphan result is still durable and visible in Raw log mode, so it
  // keeps both the toolbar and its build-error count discoverable.
  let orphan = @agent_session.Session(
    SessionId("orphan-build-failure"),
    system_prompt="",
  ).append(
    Tool(
      ToolResult(
        tool_call_id="ghost",
        tool_name="mbtx",
        content="diag",
        is_error=true,
        brief="mbtx (build failed, exit=1)",
      ),
    ),
  )
  assert_true(@viz.session_has_mbtx_activity(orphan))
  inspect(@viz.rendered_build_error_count(orphan, RawLog), content="1")
}

///|
test "model error count excludes a compacted-away failure raw still shows" {
  let compacted = compact_second_event(error_tool_session())
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
