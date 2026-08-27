///|
test "transcript stream children use stable typed keys in display order" {
  let first_tool : @transcript.TranscriptItem = {
    kind: Tool(
      call_id="c1",
      name="shell",
      arguments=None,
      has_result=true,
      is_error=false,
      brief=Some("moon check"),
    ),
    content: "output",
    ts: None,
    sequence: Some(42),
  }
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_sequence=1,
    items=[
      {
        item: { kind: User, content: "question", ts: None, sequence: Some(41), },
        identity: "s41\u{0}o0",
      },
      { item: first_tool, identity: "s42\u{0}o0", },
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
  assert_eq(keys, [
    "row\u{0}s41\u{0}o0", "rule\u{0}s41\u{0}o0", "activity\u{0}after\u{0}s41\u{0}o0",
    "streaming\u{0}r7",
  ])
  // A newly discovered row from the same durable Assistant step extends the
  // same card; it does not replace its browser-owned disclosure.
  let extended = {
    ..input,
    items: [
      input.items[0],
      {
        item: {
          kind: Reasoning,
          content: "thinking",
          ts: None,
          sequence: Some(42),
        },
        identity: "s42\u{0}o0",
      },
      { item: first_tool, identity: "s42\u{0}o1", },
    ],
  }
  let extended_renderer = { ..renderer, input: extended, }
  let extended_keys = extended_renderer
    .stream_children()
    .to_array()
    .map(pair => pair.0)
  assert_eq(extended_keys, keys)
}

///|
test "transcript stream section key scopes equal session ids by channel" {
  let local_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_sequence=0,
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
