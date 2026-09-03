///|
test "transcript stream children use stable typed keys in display order" {
  let call : @transcript.ToolCall = {
    call_id: "c1",
    name: "shell",
    arguments: Some("{}"),
    outcome: Pending(output=None),
  }
  let response : @transcript.TranscriptItem = {
    kind: Assistant(
      reasoning=None,
      prose=Some("I will check it."),
      calls=[call],
      replay=false,
      finished=false,
    ),
    ts: None,
    sequence: Some(42),
  }
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=[
      {
        item: { kind: User("question"), ts: None, sequence: Some(41), },
        identity: "s41",
      },
      { item: response, identity: "s42", },
    ],
    streaming_response=Some("partial answer"),
    streaming_identity="r7",
  )
  let renderer : TranscriptRenderer = {
    input,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
    on_open_session: _ => @cmd.none,
  }
  let keys = renderer.stream_children().to_array().map(pair => pair.0)
  assert_eq(keys, ["row\u{0}s41", "rule\u{0}s41", "row\u{0}s42", "live\u{0}r7"])
  // The result filling the call, and the durable reasoning the same event
  // turns out to carry, change the response's node, never its identity: the
  // browser-owned disclosures inside it survive both.
  let settled = {
    ..input,
    items: [
      input.items[0],
      {
        item: {
          ..response,
          kind: Assistant(
            reasoning=Some("thinking"),
            prose=Some("I will check it."),
            calls=[
              {
                ..call,
                outcome: Done(content="output", is_error=false, brief=None),
              },
            ],
            replay=false,
            finished=false,
          ),
        },
        identity: "s42",
      },
    ],
  }
  let settled_renderer = { ..renderer, input: settled, }
  let settled_keys = settled_renderer
    .stream_children()
    .to_array()
    .map(pair => pair.0)
  assert_eq(settled_keys, keys)
}

///|
test "the live response is one node, replaced by the durable one" {
  let user : VisibleRow = {
    item: { kind: User("question"), ts: None, sequence: Some(1), },
    identity: "s1",
  }
  let live_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=[user],
    streaming_response=None,
    streaming_reasoning="next thought",
    streaming_identity="r7",
  )
  let renderer : TranscriptRenderer = {
    input: live_input,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
    on_open_session: _ => @cmd.none,
  }
  let live_keys = renderer.stream_children().to_array().map(pair => pair.0)
  assert_eq(live_keys, ["row\u{0}s1", "rule\u{0}s1", "live\u{0}r7"])
  // The answer streaming after the thought joins the same node.
  let answering = {
    ..renderer,
    input: { ..live_input, streaming_response: Some("partial"), },
  }
  assert_eq(
    answering.stream_children().to_array().map(pair => pair.0),
    live_keys,
  )
  // The durable commit is its own node; the preview is gone with the run.
  let settled = {
    ..renderer,
    input: {
      ..live_input,
      items: [
        user,
        {
          item: {
            kind: Assistant(
              reasoning=Some("next thought"),
              prose=Some("answer"),
              calls=[],
              replay=false,
              finished=false,
            ),
            ts: None,
            sequence: Some(2),
          },
          identity: "s2",
        },
      ],
      streaming_reasoning: None,
    },
  }
  assert_eq(settled.stream_children().to_array().map(pair => pair.0), [
    "row\u{0}s1", "rule\u{0}s1", "row\u{0}s2",
  ])
}

///|
test "transcript stream section key scopes equal session ids by channel" {
  let local_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=0,
    items=[],
    streaming_response=None,
    streaming_identity="idle",
  )
  let remote = {
    ..local_input,
    focused: @interop.ChannelId::Remote("device-a"),
  }
  assert_eq(
    TranscriptSectionKey::stream(local_input).wire(),
    "stream\u{0}openseek\u{0}local\u{0}desktop-test",
  )
  assert_eq(
    TranscriptSectionKey::stream(remote).wire(),
    "stream\u{0}openseek\u{0}remote.device-a\u{0}desktop-test",
  )
}

///|
test "tool output truncation keeps the head and tail around a skip marker" {
  let short = "a\nb\nc"
  inspect(truncate_output(short), content="a\nb\nc")
  let lines = [ for index in 0..<200 => "line \{index}" ]
  let clamped = [..truncate_output(lines.join("\n")).split("\n")]
  inspect(clamped.length(), content="101")
  inspect(clamped[0], content="line 0")
  inspect(clamped[59], content="line 59")
  inspect(clamped[60], content="⋯ 100 lines skipped ⋯")
  inspect(clamped[61], content="line 160")
  inspect(clamped[100], content="line 199")
  let one_line = "x".repeat(30_000)
  let bounded = truncate_output(one_line)
  assert_true(bounded.has_prefix("x".repeat(12_000)))
  assert_true(bounded.has_suffix("x".repeat(8_000)))
  assert_true(bounded.contains("10000 UTF-16 code units skipped"))
}
