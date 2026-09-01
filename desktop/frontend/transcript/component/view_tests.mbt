///|
fn stream_keys(input : Input) -> Array[String] {
  stream_blocks(input).to_array().map(block => block.key.wire())
}

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
        step_identity: None,
      },
      { item: response, identity: "s42", step_identity: None, },
    ],
    streaming_response=Some("partial answer"),
    streaming_identity="r7",
  )
  let keys = stream_keys(input)
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
        step_identity: None,
      },
    ],
  }
  assert_eq(stream_keys(settled), keys)
}

///|
test "Codex step identities label one row per step and the live successor" {
  let input = Input(
    source=Codex,
    focused=@interop.ChannelId::Local,
    active_session="thread-1",
    root=None,
    submission_generation=0,
    items=[
      {
        item: {
          kind: Assistant(
            reasoning=Some("Inspecting"),
            prose=None,
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
        identity: "reasoning-1",
        step_identity: Some("step-1"),
      },
      {
        item: {
          kind: Assistant(
            reasoning=None,
            prose=None,
            calls=[
              {
                call_id: "command-1",
                name: "shell",
                arguments: Some("moon check"),
                outcome: Done(content="ok", is_error=false, brief=None),
              },
            ],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: None,
        },
        identity: "command-1",
        step_identity: Some("step-1"),
      },
      {
        item: {
          kind: Assistant(
            reasoning=None,
            prose=Some("Done"),
            calls=[],
            replay=false,
            finished=true,
          ),
          ts: None,
          sequence: None,
        },
        identity: "agent-1",
        step_identity: Some("step-2"),
      },
    ],
    streaming_response=Some("One more thing"),
    streaming_identity="turn-2",
  )
  let blocks = stream_blocks(input).to_array()
  assert_eq(blocks.length(), 4)
  assert_true(blocks[0].content is Item(step_label=Some("#1"), ..))
  assert_true(blocks[1].content is Item(step_label=None, ..))
  assert_true(blocks[2].content is Item(step_label=Some("#2"), ..))
  assert_true(blocks[3].content is Live(step_label=Some("#3"), ..))
}

///|
test "the live response is one node, replaced by the durable one" {
  let user : VisibleRow = {
    item: { kind: User("question"), ts: None, sequence: Some(1), },
    identity: "s1",
    step_identity: None,
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
  let live_keys = stream_keys(live_input)
  assert_eq(live_keys, ["row\u{0}s1", "rule\u{0}s1", "live\u{0}r7"])
  // The answer streaming after the thought joins the same node.
  let answering = { ..live_input, streaming_response: Some("partial"), }
  assert_eq(stream_keys(answering), live_keys)
  // The durable commit is its own node; the preview is gone with the run.
  let settled = {
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
        step_identity: None,
      },
    ],
    streaming_reasoning: None,
  }
  assert_eq(stream_keys(settled), ["row\u{0}s1", "rule\u{0}s1", "row\u{0}s2"])
}

///|
test "a streaming delta changes only the live block" {
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=[
      {
        item: { kind: User("question"), ts: Some(1.0e12), sequence: Some(1), },
        identity: "s1",
        step_identity: None,
      },
      {
        item: {
          kind: Assistant(
            reasoning=Some("thinking"),
            prose=Some("I will check it."),
            calls=[],
            replay=false,
            finished=false,
          ),
          ts: None,
          sequence: Some(2),
        },
        identity: "s2",
        step_identity: None,
      },
    ],
    streaming_response=Some("partial"),
    streaming_identity="r7",
  )
  let before = stream_blocks(input).to_array()
  let after = stream_blocks({
    ..input,
    streaming_response: Some("partial answer"),
  }).to_array()
  assert_eq(after.length(), before.length())
  let changed : Array[String] = []
  for index, block in before {
    if block != after[index] {
      changed.push(block.key.wire())
    }
  }
  assert_eq(changed, ["live\u{0}r7"])
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
  // A block's memoized branch is scoped the same way: the same key in another
  // stream is another branch.
  assert_eq(
    stream_blocks(local_input).to_array().map(block => block.branch_key()),
    ["stream\u{0}openseek\u{0}local\u{0}desktop-test\u{0}empty"],
  )
  assert_eq(stream_blocks(remote).to_array().map(block => block.branch_key()), [
    "stream\u{0}openseek\u{0}remote.device-a\u{0}desktop-test\u{0}empty",
  ])
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
