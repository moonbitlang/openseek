///|
fn tool_item(
  name : String,
  is_error? : Bool = false,
  brief? : String,
) -> @transcript.TranscriptItem {
  {
    kind: Tool(
      call_id="",
      name~,
      arguments=None,
      has_result=true,
      is_error~,
      brief~,
    ),
    content: "output",
    ts: None,
    sequence: None,
  }
}

///|
/// A step summary as it reaches the DOM: the ordinal in its own span — it
/// carries the accent and the fixed numeral column — then the activity label.
/// The span's opening tag is deliberately left out, so these assertions prove
/// the ordinal is a separate element without pinning how attributes render.
fn step_summary(step : Int, label : String) -> String {
  "#\{step}</span> · \{label}"
}

///|
test "capitalize is Unicode-safe on a non-BMP first char" {
  inspect(capitalize("hello world"), content="Hello world")
  // 🎉 = U+1F389, a surrogate pair. The old text[1:] sliced into it — corrupt
  // on native, a panic on js. It must survive whole with the remainder intact.
  inspect(capitalize("🎉 done"), content="🎉 done")
  inspect(capitalize(""), content="")
}

///|
#warnings("-alert_unstable")
test "transcript markup exposes conversation identity" {
  guard @resource.of_path(
      @interop.ChannelId::Remote("relay-a"),
      "/work/project",
    )
    is Some(root) else {
    fail("expected a remote transcript root")
  }
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Remote("relay-a"),
    active_session="same-markup-chat",
    root=Some(root),
    submission_generation=7,
    items=[],
    streaming_response=None,
    streaming_identity="idle",
  )
  let rendered = transcript_view(
    input,
    pinned=true,
    overview=@transcript_overview.State::empty(),
    overview_emit=@cmd.Emit(_ => @cmd.none),
    _ => @cmd.none,
    _ => @cmd.none,
    on_jump_latest=@cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("data-transcript-channel=\"remote.relay-a\""))
  assert_true(markup.contains("data-transcript-session=\"same-markup-chat\""))
  assert_true(
    markup.contains(
      "data-transcript-root=\"openseek://remote.relay-a/work/project\"",
    ),
  )
  assert_true(markup.contains("data-transcript-submission=\"7\""))
}

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
    submission_generation=1,
    items=[
      {
        item: { kind: User, content: "question", ts: None, sequence: Some(41) },
        identity: "s41\u{0}o0",
      },
      { item: first_tool, identity: "s42\u{0}o0" },
    ],
    streaming_response=Some("partial answer"),
    streaming_identity="r7",
  )
  let renderer : TranscriptRenderer = {
    input,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
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
      { item: first_tool, identity: "s42\u{0}o1" },
    ],
  }
  let extended_renderer = { ..renderer, input: extended }
  let extended_keys = extended_renderer
    .stream_children()
    .to_array()
    .map(pair => pair.0)
  assert_eq(extended_keys, keys)
}

///|
#warnings("-alert_unstable")
test "durable assistant sequences render as separate foldable steps" {
  let user : VisibleRow = {
    item: { kind: User, content: "question", ts: None, sequence: Some(1) },
    identity: "s1\u{0}o0",
  }
  let first_reasoning : VisibleRow = {
    item: {
      kind: Reasoning,
      content: "first thought",
      ts: None,
      sequence: Some(2),
    },
    identity: "s2\u{0}o0",
  }
  let first_tool : VisibleRow = {
    item: {
      kind: Tool(
        call_id="c1",
        name="read",
        arguments=Some("{}"),
        has_result=true,
        is_error=false,
        brief=Some("read moon.mod"),
      ),
      content: "result",
      ts: None,
      sequence: Some(2),
    },
    identity: "s2\u{0}o2",
  }
  let first_narration : VisibleRow = {
    item: {
      kind: Assistant(is_danger=false),
      content: "I will inspect the project.",
      ts: None,
      sequence: Some(2),
    },
    identity: "s2\u{0}o1",
  }
  let second_reasoning : VisibleRow = {
    item: {
      kind: Reasoning,
      content: "second thought",
      ts: None,
      sequence: Some(4),
    },
    identity: "s4\u{0}o0",
  }
  let goal_notice : VisibleRow = {
    item: {
      kind: Tool(
        call_id="",
        name="goal",
        arguments=None,
        has_result=true,
        is_error=false,
        brief=Some("Goal set"),
      ),
      content: "Ship it",
      ts: None,
      sequence: Some(3),
    },
    identity: "s3\u{0}o0",
  }
  let second_tool : VisibleRow = {
    item: {
      kind: Tool(
        call_id="c2",
        name="shell",
        arguments=Some("{}"),
        has_result=true,
        is_error=false,
        brief=Some("run moon check"),
      ),
      content: "ok",
      ts: None,
      sequence: Some(4),
    },
    identity: "s4\u{0}o1",
  }
  let answer : VisibleRow = {
    item: {
      kind: Assistant(is_danger=false),
      content: "done",
      ts: None,
      sequence: Some(4),
    },
    identity: "s4\u{0}o2",
  }
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=[
      user, first_reasoning, first_narration, first_tool, goal_notice, second_reasoning,
      answer, second_tool,
    ],
    streaming_response=None,
    streaming_identity="idle",
  )
  let renderer : TranscriptRenderer = {
    input,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
  }
  let children = renderer.stream_children()
  let keys = children.to_array().map(pair => pair.0)
  assert_eq(keys, [
    "row\u{0}s1\u{0}o0", "rule\u{0}s1\u{0}o0", "activity\u{0}after\u{0}s1\u{0}o0",
    "row\u{0}s2\u{0}o1", "activity\u{0}after\u{0}s2\u{0}o1", "activity\u{0}after\u{0}s3\u{0}o0",
    "row\u{0}s4\u{0}o2",
  ])
  let first_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  let second_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s3\u{0}o0"])
  })
  let notice_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s2\u{0}o1"])
  })
  assert_true(first_markup.contains(step_summary(1, "")))
  assert_true(first_markup.contains("first thought"))
  assert_false(first_markup.contains("second thought"))
  assert_true(second_markup.contains(step_summary(2, "")))
  assert_true(second_markup.contains("second thought"))
  assert_false(second_markup.contains("first thought"))
  assert_true(notice_markup.contains("Goal set"))
  assert_false(notice_markup.contains("second thought"))
  assert_false(second_markup.contains("Goal set"))
}

///|
#warnings("-alert_unstable")
test "live step hands off to its durable assistant card key" {
  let user : VisibleRow = {
    item: { kind: User, content: "question", ts: None, sequence: Some(1) },
    identity: "s1\u{0}o0",
  }
  let first : VisibleRow = {
    item: {
      kind: Tool(
        call_id="c1",
        name="read",
        arguments=Some("{}"),
        has_result=true,
        is_error=false,
        brief=Some("read moon.mod"),
      ),
      content: "result",
      ts: None,
      sequence: Some(2),
    },
    identity: "s2\u{0}o0",
  }
  let live_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=[user, first],
    streaming_response=None,
    streaming_reasoning="next thought",
    streaming_identity="r7",
  )
  let live_renderer : TranscriptRenderer = {
    input: live_input,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
  }
  let live = live_renderer.stream_children()
  let first_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(live["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(first_markup.contains(step_summary(1, "Read moon.mod")))
  assert_true(first_markup.contains("<details class=\"activity\""))
  let handoff_key = "activity\u{0}after\u{0}s2\u{0}o0"
  assert_true(live.get(handoff_key) is Some(_))
  let live_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(live[handoff_key])
  })
  assert_true(live_markup.contains(step_summary(2, "Thinking…")))
  assert_true(live_markup.contains("<details class=\"activity\" open"))

  let settled_input = {
    ..live_input,
    items: [
      user,
      first,
      {
        item: {
          kind: Reasoning,
          content: "next thought",
          ts: None,
          sequence: Some(4),
        },
        identity: "s4\u{0}o0",
      },
      {
        item: {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: Some(4),
        },
        identity: "s4\u{0}o1",
      },
    ],
    streaming_reasoning: None,
  }
  let settled = { ..live_renderer, input: settled_input }.stream_children()
  assert_true(settled.get(handoff_key) is Some(_))
  let settled_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(settled[handoff_key])
  })
  assert_true(settled_markup.contains(step_summary(2, "Thought")))
  assert_true(settled_markup.contains("next thought"))
  assert_false(settled_markup.contains("<details class=\"activity\" open"))
}

///|
#warnings("-alert_unstable")
test "an ambiguous commit-first prefix keeps live reasoning visible" {
  let rows : Array[VisibleRow] = [
    {
      item: { kind: User, content: "question", ts: None, sequence: Some(1) },
      identity: "s1\u{0}o0",
    },
    {
      item: {
        kind: Reasoning,
        content: "complete thought",
        ts: None,
        sequence: Some(2),
      },
      identity: "s2\u{0}o0",
    },
    {
      item: {
        kind: Assistant(is_danger=false),
        content: "I will inspect it.",
        ts: None,
        sequence: Some(2),
      },
      identity: "s2\u{0}o1",
    },
    {
      item: {
        kind: Tool(
          call_id="c1",
          name="read",
          arguments=Some("{}"),
          has_result=false,
          is_error=false,
          brief=None,
        ),
        content: "",
        ts: None,
        sequence: Some(2),
      },
      identity: "s2\u{0}o2",
    },
    {
      item: {
        kind: Reasoning,
        content: "later thought",
        ts: None,
        sequence: Some(3),
      },
      identity: "s3\u{0}o0",
    },
    {
      item: {
        kind: Assistant(is_danger=false),
        content: "A later step also committed.",
        ts: None,
        sequence: Some(3),
      },
      identity: "s3\u{0}o1",
    },
  ]
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=rows,
    streaming_response=None,
    streaming_reasoning="complete",
    streaming_identity="r7",
  )
  let children = (
    { input, on_open: _ => @cmd.none, on_jump: _ => @cmd.none } :
    TranscriptRenderer).stream_children()
  let keys = children.to_array().map(pair => pair.0)
  assert_eq(keys, [
    "row\u{0}s1\u{0}o0", "rule\u{0}s1\u{0}o0", "activity\u{0}after\u{0}s1\u{0}o0",
    "row\u{0}s2\u{0}o1", "activity\u{0}after\u{0}s2\u{0}o1", "row\u{0}s3\u{0}o1",
    "activity\u{0}after\u{0}s3\u{0}o1",
  ])
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(markup.contains(step_summary(1, "Read")))
  assert_true(markup.contains("complete thought"))
  assert_false(markup.contains("activity-thinking-live"))
  assert_false(markup.contains("#2"))
  let later_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s2\u{0}o1"])
  })
  assert_true(later_markup.contains(step_summary(2, "Thought")))
  assert_true(later_markup.contains("later thought"))
  assert_false(later_markup.contains("activity-thinking-live"))
  assert_false(later_markup.contains("#3"))
  let live_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s3\u{0}o1"])
  })
  assert_true(live_markup.contains(step_summary(3, "Thinking…")))
  assert_true(live_markup.contains("complete"))
  assert_true(live_markup.contains("activity-thinking-live"))
}

///|
#warnings("-alert_unstable")
test "live reasoning is plain text and keeps the durable activity key" {
  let user : VisibleRow = {
    item: { kind: User, content: "question", ts: None, sequence: Some(1) },
    identity: "s1\u{0}o0",
  }
  let live_input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    root=None,
    submission_generation=1,
    items=[user],
    streaming_response=None,
    streaming_reasoning="*unfinished*\nnext",
    streaming_identity="r7",
  )
  let live_renderer : TranscriptRenderer = {
    input: live_input,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
  }
  let live_children = live_renderer.stream_children()
  assert_true(live_children.get("activity\u{0}after\u{0}s1\u{0}o0") is Some(_))
  let live_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(live_children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(live_markup.contains("*unfinished*\nnext"))
  assert_false(live_markup.contains("<em>unfinished</em>"))
  assert_true(live_markup.contains("<details class=\"activity\" open"))

  let complete_renderer = {
    ..live_renderer,
    input: { ..live_input, reasoning_complete: true },
  }
  let complete_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      complete_renderer.stream_children()["activity\u{0}after\u{0}s1\u{0}o0"],
    )
  })
  assert_true(complete_markup.contains("<em>unfinished</em>"))

  let settled = {
    ..live_input,
    items: [
      user,
      {
        item: {
          kind: Reasoning,
          content: "*unfinished*\nnext",
          ts: None,
          sequence: Some(2),
        },
        identity: "s2\u{0}o0",
      },
      {
        item: {
          kind: Assistant(is_danger=false),
          content: "answer",
          ts: None,
          sequence: Some(2),
        },
        identity: "s2\u{0}o1",
      },
    ],
    streaming_reasoning: None,
  }
  let settled_renderer = { ..live_renderer, input: settled }
  let settled_children = settled_renderer.stream_children()
  assert_true(
    settled_children.get("activity\u{0}after\u{0}s1\u{0}o0") is Some(_),
  )
  let settled_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(settled_children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(settled_markup.contains("<em>unfinished</em>"))
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
test "a tool group's summary recognizes every cmd/openseek built-in" {
  inspect(tool_group_summary([tool_item("read")]), content="Read 1 file")
  inspect(
    tool_group_summary([
      tool_item("read"),
      tool_item("read"),
      tool_item("edit"),
      tool_item("multi_edit"),
      tool_item("write"),
      tool_item("remove"),
      tool_item("shell"),
      tool_item("moon_cmd"),
      tool_item("run_moonbit"),
      tool_item("shell_output"),
      tool_item("shell_stop"),
      tool_item("plan"),
      tool_item("goal"),
      tool_item("finish"),
      tool_item("moon_check compiling"),
      tool_item("mystery"),
    ]),
    content="Read 2 files, wrote 1 file, edited 2 files, removed 1 file, ran 3 commands, checked 1 background job, stopped 1 background job, 1 plan update, 1 goal update, finished, 1 check update, 1 tool call",
  )
  inspect(
    tool_group_summary([
      tool_item("remove"),
      tool_item("remove"),
      tool_item("shell_output"),
      tool_item("shell_output"),
      tool_item("shell_stop"),
      tool_item("shell_stop"),
      tool_item("plan"),
      tool_item("plan"),
      tool_item("goal"),
      tool_item("goal"),
      tool_item("finish"),
      tool_item("finish"),
    ]),
    content="Removed 2 files, checked 2 background jobs, stopped 2 background jobs, 2 plan updates, 2 goal updates, 2 finish calls",
  )
  inspect(
    tool_group_summary([tool_item("shell", is_error=true)]),
    content="Ran 1 command",
  )
}

///|
test "tool activity summaries promote recorded briefs" {
  inspect(
    tool_activity_summary([tool_item("shell", brief="moon test → exit 1")]),
    content="Moon test → exit 1",
  )
  inspect(
    tool_activity_summary([
      tool_item("read", brief="read moon.mod"),
      tool_item("edit", brief="edited view.mbt:42"),
      tool_item("shell", brief="moon test"),
      tool_item("shell"),
    ]),
    content="Read moon.mod · edited view.mbt:42 · +2 more",
  )
  // Older logs and pending calls have no result brief yet.
  inspect(tool_activity_summary([tool_item("shell")]), content="Ran 1 command")
}

///|
#warnings("-alert_unstable")
test "a completed singleton tool uses one brief disclosure" {
  let rendered = activity_view([tool_item("shell", brief="moon test")], _ => {
    @cmd.none
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains("<summary class=\"tool-call-summary\">Moon test</summary>"),
  )
  assert_false(markup.contains("Ran 1 command"))
  assert_false(markup.contains("tool-line-summary"))
  assert_false(markup.contains("activity-summary"))
}

///|
#warnings("-alert_unstable")
test "a mixed activity does not repeat its singleton tool disclosure" {
  let rendered = activity_view(
    [
      {
        kind: Reasoning,
        content: "checking the diff",
        ts: None,
        sequence: None,
      },
      tool_item("shell", brief="moon fmt · git diff"),
    ],
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains("<span class=\"activity-text\">Moon fmt · git diff</span>"),
  )
  assert_false(markup.contains("tool-call-summary"))
  assert_true(markup.contains("<pre class=\"tool-call-output\">output</pre>"))
}

///|
#warnings("-alert_unstable")
test "the turn rule dates itself only from a real stamp" {
  let render = rule => {
    @rabbita.render_to_string(() => @rabbita.Val::constant(rule))
  }
  // Locale and time zone are the viewer's, so the label's exact text is not
  // asserted — only that a stamped turn gets one and an unstamped turn does
  // not. A zero stamp is what old stores wrote for "no time recorded".
  let stamped = render(turn_rule_view(ts=1781144351123))
  assert_true(stamped.contains("turn-time"))
  assert_true(stamped.contains(":"))
  // A bare clock reads as a stray number without it.
  assert_true(stamped.contains("Sent "))
  assert_false(render(turn_rule_view()).contains("turn-time"))
  assert_false(render(turn_rule_view(ts=0)).contains("turn-time"))
}

///|
#warnings("-alert_unstable")
test "every message names its speaker to assistive technology" {
  let render = item => {
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(transcript_item_view(item, _ => @cmd.none))
    })
  }
  // The bubble, the alignment, and the rule are CSS only; the name has to
  // survive somewhere a screen reader reaches.
  let user = render({
    kind: User,
    content: "question",
    ts: None,
    sequence: None,
  })
  assert_true(user.contains("<span class=\"visually-hidden\">You</span>"))
  let assistant = render({
    kind: Assistant(is_danger=false),
    content: "answer",
    ts: None,
    sequence: None,
  })
  assert_true(
    assistant.contains("<span class=\"visually-hidden\">OpenSeek</span>"),
  )
  let terminal = render({
    kind: TerminalAnswer,
    content: "terminal answer",
    ts: None,
    sequence: None,
  })
  assert_true(
    terminal.contains("<span class=\"visually-hidden\">OpenSeek</span>"),
  )
  // An abort/failure notice is the agent talking too.
  let danger = render({
    kind: Assistant(is_danger=true),
    content: "failed",
    ts: None,
    sequence: None,
  })
  assert_true(
    danger.contains("<span class=\"visually-hidden\">OpenSeek</span>"),
  )
  let streaming = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(streaming_response_view("partial", _ => @cmd.none))
  })
  assert_true(
    streaming.contains("<span class=\"visually-hidden\">OpenSeek</span>"),
  )
}

///|
#warnings("-alert_unstable")
test "assistant UML exposes the shared diagram viewport marker" {
  let rendered = transcript_item_view(
    {
      kind: Assistant(is_danger=false),
      content: "```uml\n@startuml\nparticipant Alice\nAlice -> Bob : hello\n@enduml\n```",
      ts: None,
      sequence: None,
    },
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  // TranscriptObservers hands this exact wrapper to DiagramViewports. Keep
  // both markers stable so the shared package can discover the direct SVG.
  assert_true(
    markup.contains(
      "class=\"chat-markdown-diagram moonbit-viewer-markdown-diagram\"",
    ),
  )
  assert_true(markup.contains("data-diagram-language=\"uml\""))
  assert_true(markup.contains("<svg"))
}

///|
#warnings("-alert_unstable")
test "user message URLs are clickable but inline code stays inert" {
  let rendered = transcript_item_view(
    {
      kind: User,
      content: "open https://example.com/docs, not `https://code.example`",
      ts: None,
      sequence: None,
    },
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("href=\"https://example.com/docs\""))
  assert_true(
    markup.contains("<code class=\"inline-code\">https://code.example</code>"),
  )
  assert_false(markup.contains("href=\"https://code.example\""))
}

///|
#warnings("-alert_unstable")
test "a tool row renders recorded arguments before its result" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="shell",
      arguments=Some("{\"cmd\":\"moon test\"}"),
      has_result=true,
      is_error=true,
      brief=Some("ran moon test → exit 1"),
    ),
    content: "test failed",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  guard markup.split_once("Arguments") is Some((_, after_arguments)) else {
    fail("expected an arguments section")
  }
  assert_true(after_arguments.contains("cmd"))
  assert_true(after_arguments.contains("moon test"))
  assert_true(after_arguments.contains("Output"))
  assert_true(markup.contains("test failed"))
  assert_true(markup.contains("<details class=\"tool-call error\" open>"))
}

///|
#warnings("-alert_unstable")
test "a MoonBit read highlights source without coloring its gutter or footer" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="read",
      arguments=Some("{\"path\":\"src/main.mbt\"}"),
      has_result=true,
      is_error=false,
      brief=Some("read main.mbt"),
    ),
    content: (
      #|1 |fn main {
      #|2 |  println("hi")
      #|3 |}
      #|<system>start_line=1 shown_lines=3 total_lines=3 truncated=false</system>
    ),
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("class=\"read-moonbit-output\""))
  assert_true(markup.contains("class=\"read-moonbit-gutter\">1 |"))
  assert_true(markup.contains("<span class=\"mtk3\">fn</span>"))
  assert_true(markup.contains("class=\"read-moonbit-status\""))
  assert_false(markup.contains("class=\"mtk3\">&lt;system&gt;"))
}

///|
#warnings("-alert_unstable")
test "a plan row renders its checklist instead of the arguments JSON" {
  let arguments = "{\"steps\":[{\"title\":\"fix the parser\",\"status\":\"in_progress\"},{\"title\":\"run moon test\",\"status\":\"pending\"}]}"
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="plan",
      arguments=Some(arguments),
      has_result=true,
      is_error=false,
      brief=Some("plan 0/2 · fix the parser"),
    ),
    content: "Plan updated: 0/2 done · in progress: fix the parser.",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("plan-steps"))
  assert_true(markup.contains("plan-progress-count\">0/2"))
  assert_false(markup.contains("Arguments"))
  // A call the tool rejected keeps the raw payload: what the model actually
  // sent is the point, and a checklist would report a plan that never applied.
  let failed = tool_call_view({
    kind: Tool(
      call_id="c2",
      name="plan",
      arguments=Some("{\"steps\":[{\"title\":\"one\",\"status\":\"doing\"}]}"),
      has_result=true,
      is_error=true,
      brief=None,
    ),
    content: "error: plan requires arguments.steps[0].status to be one of pending|in_progress|completed",
    ts: None,
    sequence: None,
  })
  let failed_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(failed)
  })
  assert_true(failed_markup.contains("Arguments"))
  assert_false(failed_markup.contains("plan-steps"))
}

///|
#warnings("-alert_unstable")
test "a folded run carries the plan it ended on" {
  let plan_item : @transcript.TranscriptItem = {
    kind: Tool(
      call_id="c1",
      name="plan",
      arguments=Some(
        "{\"steps\":[{\"title\":\"fix the parser\",\"status\":\"completed\"},{\"title\":\"run moon test\",\"status\":\"in_progress\"}]}",
      ),
      has_result=true,
      is_error=false,
      brief=Some("plan 1/2 · run moon test"),
    ),
    content: "",
    ts: None,
    sequence: None,
  }
  let rendered = activity_view([tool_item("read"), plan_item], _ => @cmd.none)
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("plan-progress mini"))
  assert_true(markup.contains("plan-progress-count\">1/2"))
  // A run that touched no plan adds nothing to its summary line.
  let plainer = activity_view([tool_item("read")], _ => @cmd.none)
  let plain_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(plainer)
  })
  assert_false(plain_markup.contains("plan-progress"))
}

///|
#warnings("-alert_unstable")
test "a tool row clamps large arguments before rendering" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="write",
      arguments=Some("{\"content\":\"\{"x".repeat(30_000)}\"}"),
      has_result=true,
      is_error=false,
      brief=Some("wrote a large file"),
    ),
    content: "",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("UTF-16 code units skipped"))
  // The source payload is 30k code units; bounding before parse keeps the
  // collapsed row well below that size even after HTML escaping.
  assert_true(markup.length() < 25_000)
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
