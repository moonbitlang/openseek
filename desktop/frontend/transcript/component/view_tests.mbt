///|
fn tool_item(
  name : String,
  is_error? : Bool = false,
  brief? : String,
) -> @transcript.TranscriptItem {
  {
    kind: Tool(
      call_id=name,
      name~,
      arguments=Some("{\"fixture\":true}"),
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
#warnings("-alert_unstable")
test "the mbtx tool name stays lowercase in its row captions" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="mbtx-1",
      name="mbtx",
      arguments=Some("{\"source\":\"println(1)\"}"),
      has_result=true,
      is_error=false,
      brief=Some("mbtx (exit=0)"),
    ),
    content: "1",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(
    markup.contains("<span class=\"tool-call-text\">mbtx (exit=0)</span>"),
  )
  assert_false(markup.contains("Mbtx"))
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
    live_reasoning: None,
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
#warnings("-alert_unstable")
test "durable assistant sequences render as separate foldable steps" {
  let user : VisibleRow = {
    item: { kind: User, content: "question", ts: None, sequence: Some(1), },
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
    live_reasoning: None,
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
    on_open_session: _ => @cmd.none,
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
    item: { kind: User, content: "question", ts: None, sequence: Some(1), },
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
    streaming_identity="r7",
  )
  let live_renderer : TranscriptRenderer = {
    input: live_input,
    live_reasoning: Some("next thought"),
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
    on_open_session: _ => @cmd.none,
  }
  let live = live_renderer.stream_children()
  let first_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(live["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  // A tool-only step has no thought fold: its ordinal sits on a plain heading
  // line and the call itself is on display as its own row.
  assert_true(first_markup.contains("activity-heading"))
  assert_true(first_markup.contains("#1</span>"))
  assert_true(
    first_markup.contains("<span class=\"tool-call-text\">read moon.mod</span>"),
  )
  assert_false(first_markup.contains("<details class=\"activity\""))
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
  }
  let settled = {
    ..live_renderer,
    input: settled_input,
    live_reasoning: None,
  }.stream_children()
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
test "commit-first reasoning may temporarily show durable and live cards" {
  let rows : Array[VisibleRow] = [
    {
      item: { kind: User, content: "question", ts: None, sequence: Some(1), },
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
    streaming_identity="r7",
  )
  let children = (
    {
      input,
      live_reasoning: Some("complete"),
      on_open: _ => @cmd.none,
      on_jump: _ => @cmd.none,
      on_open_session: _ => @cmd.none,
    } : TranscriptRenderer).stream_children()
  let keys = children.to_array().map(pair => pair.0)
  assert_eq(keys, [
    "row\u{0}s1\u{0}o0", "rule\u{0}s1\u{0}o0", "activity\u{0}after\u{0}s1\u{0}o0",
    "row\u{0}s2\u{0}o1", "activity\u{0}after\u{0}s2\u{0}o1", "row\u{0}s3\u{0}o1",
    "activity\u{0}after\u{0}s3\u{0}o1",
  ])
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(markup.contains(step_summary(1, "Thought")))
  assert_true(markup.contains("<span class=\"tool-call-text\">read</span>"))
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
    item: { kind: User, content: "question", ts: None, sequence: Some(1), },
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
    streaming_identity="r7",
  )
  let live_renderer : TranscriptRenderer = {
    input: live_input,
    live_reasoning: Some("*unfinished*\nnext"),
    on_open: _ => @cmd.none,
    on_jump: _ => @cmd.none,
    on_open_session: _ => @cmd.none,
  }
  let live_children = live_renderer.stream_children()
  assert_true(live_children.get("activity\u{0}after\u{0}s1\u{0}o0") is Some(_))
  let live_markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(live_children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(live_markup.contains("*unfinished*\nnext"))
  assert_false(live_markup.contains("<em>unfinished</em>"))
  assert_true(live_markup.contains("<details class=\"activity\" open"))

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
  }
  let settled_renderer = {
    ..live_renderer,
    input: settled,
    live_reasoning: None,
  }
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
#warnings("-alert_unstable")
test "every tool request and result of a run is on display as its own row" {
  let rendered = activity_view(
    [
      tool_item("shell", brief="moon test"),
      tool_item("read", brief="read moon.mod"),
      tool_item("edit", is_error=true, brief="edit view.mbt"),
    ],
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  // One always-visible request and result row per exchange, no fold around the
  // run, and no synthetic category sentence standing in for the briefs.
  assert_true(markup.contains("activity-work"))
  assert_true(markup.contains("moon test"))
  assert_true(markup.contains("read moon.mod"))
  assert_true(markup.contains("edit view.mbt"))
  assert_false(markup.contains("activity-summary"))
  assert_false(markup.contains("Ran 1 command"))
  assert_eq(markup.split("<details class=\"tool-call").length(), 4)
  assert_eq(markup.split("<details class=\"tool-result").length(), 4)
  // The failed request and result stay folded like the other expandable rows,
  // and their state is a literal word rather than the red color alone.
  assert_true(markup.contains("<details class=\"tool-call error\">"))
  assert_true(markup.contains("<details class=\"tool-result error\">"))
  assert_false(markup.contains("<details class=\"tool-call error\" open"))
  assert_true(markup.contains("<span class=\"tool-call-failed\">failed</span>"))
  // Each summary carries its full label as a tooltip, so a brief the
  // stylesheet ellipsizes on a narrow pane stays reachable.
  assert_true(markup.contains("title=\"moon test\""))
}

///|
/// One Assistant event owns both requests, so its sequence is positive proof
/// that this is a parallel burst. As in the viz HTML renderer, both call rows
/// precede either result row.
#warnings("-alert_unstable")
test "one assistant event renders its call burst before its results" {
  let tools = [
    { ..tool_item("alpha", brief="first request"), sequence: Some(21), },
    { ..tool_item("beta", brief="second request"), sequence: Some(21), },
  ]
  let rows = tool_run_views(tools)
  assert_eq(rows.to_array().map(entry => entry.0), [
    "request\u{0}alpha\u{0}0", "request\u{0}beta\u{0}1", "result\u{0}alpha\u{0}0",
    "result\u{0}beta\u{0}1",
  ])
  let rendered = activity_view(tools, _ => @cmd.none)
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  guard (
      markup.find("first request"),
      markup.find("second request"),
      markup.find("Tool result · alpha"),
      markup.find("Tool result · beta"),
    )
    is (
      Some(first_call),
      Some(second_call),
      Some(first_result),
      Some(second_result),
    ) else {
    fail("expected both request and result rows")
  }
  assert_true(first_call < second_call)
  assert_true(second_call < first_result)
  assert_true(first_result < second_result)
}

///|
/// Different Assistant sequences are sequential calls even when a fallback
/// activity run places them next to each other. Keep each result beside its
/// request rather than visually turning them into a burst.
#warnings("-alert_unstable")
test "different assistant events keep each result beside its request" {
  let rendered = activity_view(
    [
      { ..tool_item("alpha", brief="first request"), sequence: Some(21), },
      { ..tool_item("beta", brief="second request"), sequence: Some(22), },
    ],
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  guard (
      markup.find("first request"),
      markup.find("Tool result · alpha"),
      markup.find("second request"),
      markup.find("Tool result · beta"),
    )
    is (
      Some(first_call),
      Some(first_result),
      Some(second_call),
      Some(second_result),
    ) else {
    fail("expected both request and result rows")
  }
  assert_true(first_call < first_result)
  assert_true(first_result < second_call)
  assert_true(second_call < second_result)
}

///|
/// Background runtime updates are result-shaped for layout, but they are not
/// responses to model tool calls and must retain their standalone status name.
#warnings("-alert_unstable")
test "a synthetic runtime update keeps its notice label" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="",
      name="moon_check passed",
      arguments=None,
      has_result=true,
      is_error=false,
      brief=None,
    ),
    content: "Finished.",
    ts: None,
    sequence: Some(21),
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("moon_check passed"))
  assert_false(markup.contains("Tool result"))
}

///|
/// Codex command executions stream output before their completed item arrives.
/// Keep that feedback visible as a distinct pending row without claiming the
/// tool has produced its final result.
#warnings("-alert_unstable")
test "a pending tool keeps its streamed output visible" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="command-1",
      name="shell",
      arguments=Some("{\"command\":\"moon test\"}"),
      has_result=false,
      is_error=false,
      brief=Some("moon test"),
    ),
    content: "package core: 12/20 tests passed",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("moon test"))
  assert_true(markup.contains("Tool output · shell"))
  assert_true(markup.contains("package core: 12/20 tests passed"))
  assert_true(markup.contains("<details class=\"tool-result pending\">"))
  assert_false(markup.contains("Tool result · shell"))
}

///|
#warnings("-alert_unstable")
test "a mixed activity keeps its call on display beside the thought fold" {
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
  // The fold holds only the thought; the call is its own visible row.
  assert_true(markup.contains("<span class=\"activity-text\">Thought</span>"))
  assert_true(markup.contains("checking the diff"))
  assert_true(
    markup.contains(
      "<span class=\"tool-call-text\">moon fmt · git diff</span>",
    ),
  )
  assert_true(markup.contains("<pre class=\"tool-call-output\">output</pre>"))
  assert_true(markup.contains("class=\"tool-result-summary\""))
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
test "a step is stamped to the second, from a real stamp only" {
  let render = items => {
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(
        activity_view(items, _ => @cmd.none, step_label="#1"),
      )
    })
  }
  let stamped : @transcript.TranscriptItem = {
    ..tool_item("read"),
    ts: Some(1781144351123),
    sequence: Some(2),
  }
  let markup = render([stamped])
  assert_true(markup.contains("activity-time"))
  // Ordinal, then instant. The order is the feature: the instants are read as
  // a column against the rows above and below, which only works with nothing
  // variable-width before them.
  let after_step = markup.split("activity-step").to_array()[1]
  assert_true(after_step.contains("activity-time"))
  // The gap after the ordinal is a real space, so it survives into the
  // accessible name and anything copied out of the row — a CSS margin would
  // have left "#1Committed 14:32:10".
  assert_true(markup.contains("#1</span> <span"))
  // A step led by reasoning keeps the same columns on its thought fold's
  // summary, with the separator introducing the label after the instant.
  let thought_markup = render([
    {
      kind: Reasoning,
      content: "thinking",
      ts: Some(1781144351123),
      sequence: Some(2),
    },
  ])
  assert_true(thought_markup.contains("activity-time"))
  assert_true(
    thought_markup.split("activity-time").to_array()[1].contains(" · Thought"),
  )
  // ...and without a stamp there is no stray space before the separator.
  assert_true(
    render([
      { kind: Reasoning, content: "thinking", ts: None, sequence: Some(2), },
    ]).contains("#1</span> · Thought"),
  )
  // A stampless tool-only step keeps the bare ordinal as its heading.
  assert_true(render([tool_item("read")]).contains("#1</span></div>"))
  // Seconds are there — the property, not its spelling. Counting `:` would
  // have pinned the viewer's locale: fi-FI and da-DK write the same instant
  // as `10.19.11`. Two instants a second apart rendering differently is the
  // same claim in a form every locale satisfies, since minute precision would
  // collapse them.
  assert_true(step_time_label(1781144351123) != step_time_label(1781144352123))
  // ...and the minute is still shared, so the difference really is the
  // seconds field rather than a rollover.
  assert_eq(clock_label(1781144351123), clock_label(1781144352123))
  assert_true(markup.contains("Committed "))
  // A step with no stamp, and the zero stamp old stores wrote for "no time
  // recorded", both keep the bare summary.
  assert_false(render([tool_item("read")]).contains("activity-time"))
  assert_false(
    render([{ ..tool_item("read"), ts: Some(0), }]).contains("activity-time"),
  )
  // A step still running has no committed instant to report.
  assert_false(
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(
        activity_view([], _ => @cmd.none, live_reasoning="thinking"),
      )
    }).contains("activity-time"),
  )
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
test "transcript errors use the unboxed status row" {
  let rendered = transcript_item_view(
    {
      kind: Assistant(is_danger=true),
      content: "agent failed: `ConnectionClosed`",
      ts: None,
      sequence: Some(2),
    },
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("class=\"msg transcript-error\""))
  assert_true(markup.contains("class=\"transcript-error-row\""))
  assert_true(markup.contains("class=\"transcript-error-icon\""))
  assert_true(markup.contains("class=\"msg-content transcript-error-message\""))
  assert_true(markup.contains("agent failed: "))
  assert_true(
    markup.contains("<code class=\"inline-code\">ConnectionClosed</code>"),
  )
  assert_false(markup.contains("msg-content danger"))
}

///|
#warnings("-alert_unstable")
test "only a terminal-confirmed assistant answer ends with actions" {
  let render = item => {
    @rabbita.render_to_string(() => {
      @rabbita.Val::constant(transcript_item_view(item, _ => @cmd.none))
    })
  }
  let kinds_without_actions : Array[@transcript.ItemKind] = [
    Assistant(is_danger=false),
    AssistantReplay,
    Assistant(is_danger=true),
  ]
  for kind in kinds_without_actions {
    let markup = render({
      kind,
      content: "**answer**",
      ts: None,
      sequence: None,
    })
    assert_false(markup.contains("assistant-message-actions"))
  }
  let stamped = render({
    kind: TerminalAnswer,
    content: "**answer**",
    ts: Some(1781144351123),
    sequence: Some(2),
  })
  assert_true(stamped.contains("<strong>answer</strong>"))
  assert_true(stamped.contains("class=\"assistant-message-actions\""))
  assert_true(stamped.contains("title=\"Copy Markdown\""))
  assert_true(
    stamped.contains("aria-label=\"Copy assistant message as Markdown\""),
  )
  assert_true(stamped.contains("assistant-message-time"))
  assert_true(stamped.contains("Completed "))
  assert_true(stamped.contains(":"))
  let after_copy = stamped.split("assistant-message-copy").to_array()[1]
  assert_true(after_copy.contains("assistant-message-time"))
  assert_false(
    render({
      kind: TerminalAnswer,
      content: "answer",
      ts: Some(0),
      sequence: Some(2),
    }).contains("assistant-message-time"),
  )
  let streaming = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(streaming_response_view("partial", _ => @cmd.none))
  })
  assert_false(streaming.contains("assistant-message-copy"))
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
test "an ordinary tool keeps its result out of the argument tabs" {
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
  assert_true(markup.contains("class=\"tool-call-tabs\""))
  assert_eq(markup.split("class=\"tool-call-tab-input\"").length(), 3)
  assert_true(markup.contains(">Arguments</label>"))
  assert_true(markup.contains(">Original JSON</label>"))
  assert_false(markup.contains(">Output</label>"))
  assert_true(markup.contains("cmd"))
  assert_true(markup.contains("moon test"))
  assert_true(markup.contains("test failed"))
  assert_true(markup.contains("tool-call-section-label\">Output"))
  assert_true(markup.contains("<details class=\"tool-call error\">"))
  assert_true(markup.contains("<details class=\"tool-result error\">"))
  assert_false(markup.contains("<details class=\"tool-call error\" open>"))
}

///|
#warnings("-alert_unstable")
test "JSON tool arguments render as readable fields with the original preserved" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="write",
      arguments=Some(
        "{\"path\":\"notes.txt\",\"content\":\"alpha\\nbeta\",\"overwrite\":true,\"retries\":2}",
      ),
      has_result=true,
      is_error=false,
      brief=Some("wrote notes.txt"),
    ),
    content: "",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("class=\"tool-call-tabs\""))
  assert_eq(markup.split("class=\"tool-call-tab-input\"").length(), 3)
  assert_true(markup.contains(">Arguments</label>"))
  assert_true(markup.contains(">Original JSON</label>"))
  assert_true(markup.contains("class=\"tool-call-arguments-friendly\""))
  assert_true(markup.contains("class=\"tool-argument-key\">path</span>"))
  assert_true(
    markup.contains(
      "class=\"tool-argument-value tool-argument-string\">notes.txt</span>",
    ),
  )
  assert_true(
    markup.contains("class=\"tool-argument-value-block\">alpha\nbeta</pre>"),
  )
  assert_true(
    markup.contains(
      "class=\"tool-argument-value tool-argument-boolean\">true</span>",
    ),
  )
  assert_true(
    markup.contains(
      "class=\"tool-argument-value tool-argument-number\">2</span>",
    ),
  )
  assert_true(markup.contains("Original JSON"))
  assert_true(markup.contains("alpha\\nbeta"))
}

///|
#warnings("-alert_unstable")
test "nested JSON arguments retain their object and array hierarchy" {
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="batch",
      arguments=Some(
        "{\"options\":{\"cwd\":\"src\",\"limit\":null},\"steps\":[{\"op\":\"read\",\"path\":\"a.mbt\"},{\"op\":\"write\",\"path\":\"b.mbt\"}]}",
      ),
      has_result=false,
      is_error=false,
      brief=None,
    ),
    content: "",
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("class=\"tool-call-tabs\""))
  assert_eq(markup.split("class=\"tool-call-tab-input\"").length(), 3)
  assert_true(markup.contains(">Arguments</label>"))
  assert_true(markup.contains(">Original JSON</label>"))
  assert_true(markup.contains("class=\"tool-argument-object\""))
  assert_true(markup.contains("class=\"tool-argument-array\""))
  assert_eq(markup.split("class=\"tool-argument-item\"").length(), 3)
  assert_true(markup.contains("class=\"tool-argument-key\">cwd</span>"))
  assert_true(markup.contains("class=\"tool-argument-key\">op</span>"))
  assert_true(
    markup.contains(
      "class=\"tool-argument-value tool-argument-null\">null</span>",
    ),
  )
}

///|
#warnings("-alert_unstable")
test "non-object and malformed arguments keep the preformatted fallback" {
  for arguments in ["[1,2,3]", "not json"] {
    let rendered = tool_call_view({
      kind: Tool(
        call_id="c1",
        name="batch",
        arguments=Some(arguments),
        has_result=false,
        is_error=false,
        brief=None,
      ),
      content: "",
      ts: None,
      sequence: None,
    })
    let markup = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(rendered)
    })
    assert_true(markup.contains("<pre class=\"tool-call-arguments\">"))
    assert_false(markup.contains("tool-call-arguments-friendly"))
    assert_false(markup.contains("Original JSON"))
    assert_false(markup.contains("tool-call-tabs"))
  }
}

///|
#warnings("-alert_unstable")
test "a MoonBit read highlights source without coloring its gutter or footer" {
  // More than the generic 100-line display limit proves the read protocol is
  // decoded before the plain-text fallback inserts skip markers.
  let source = [
    for index in 0..<101 => "\{index + 1} |let value_\{index} = \{index}"
  ]
  let content = source.join("\n") +
    "\n<system>start_line=1 shown_lines=101 total_lines=101 truncated=false</system>"
  let rendered = tool_call_view({
    kind: Tool(
      call_id="c1",
      name="read",
      arguments=Some("{\"path\":\"src/main.mbt\"}"),
      has_result=true,
      is_error=false,
      brief=Some("read main.mbt"),
    ),
    content,
    ts: None,
    sequence: None,
  })
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  assert_true(markup.contains("class=\"tool-call-tabs\""))
  assert_eq(markup.split("class=\"tool-call-tab-input\"").length(), 5)
  assert_true(markup.contains(">Arguments</label>"))
  assert_true(markup.contains(">Original JSON</label>"))
  assert_true(markup.contains(">Output</label>"))
  assert_true(markup.contains(">Original output</label>"))
  assert_true(markup.contains("read-moonbit-output"))
  assert_true(markup.contains("class=\"read-moonbit-gutter\">1</span>"))
  assert_true(markup.contains("<span class=\"mtk3\">let</span>"))
  assert_true(markup.contains("class=\"read-moonbit-status\""))
  assert_false(markup.contains("class=\"mtk3\">&lt;system&gt;"))
  assert_false(markup.contains("lines skipped"))
  assert_true(markup.contains("Original output"))
  assert_true(markup.contains("1 |let value_0 = 0"))
  assert_false(markup.contains("<details class=\"tool-card-original\""))
}

///|
/// Several calls emitted by one durable assistant event share its sequence.
/// Their unique call ids must still produce independent radio groups, or the
/// browser unchecks every tabbed read except one and their panels disappear.
#warnings("-alert_unstable")
test "tabbed reads from one event keep independent radio groups" {
  let output = "1 |fn main {}\n<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>"
  let rendered = activity_view(
    [
      {
        kind: Tool(
          call_id="read-a",
          name="read",
          arguments=Some("{\"path\":\"a.mbt\"}"),
          has_result=true,
          is_error=false,
          brief=Some("read a.mbt"),
        ),
        content: output,
        ts: None,
        sequence: Some(21),
      },
      {
        kind: Tool(
          call_id="read-b",
          name="read",
          arguments=Some("{\"path\":\"b.mbt\"}"),
          has_result=true,
          is_error=false,
          brief=Some("read b.mbt"),
        ),
        content: output,
        ts: None,
        sequence: Some(21),
      },
    ],
    _ => @cmd.none,
  )
  let markup = @rabbita.render_to_string(() => @rabbita.Val::constant(rendered))
  let first_group = "tool-call-tabs-call-\{"read-a".hash()}"
  let second_group = "tool-call-tabs-call-\{"read-b".hash()}"
  assert_true(first_group != second_group)
  // Two request tabs and two result tabs per read, isolated from both the
  // other call and the other half of this exchange.
  assert_eq(markup.split("name=\"\{first_group}\"").length(), 3)
  assert_eq(markup.split("name=\"\{first_group}-result\"").length(), 3)
  assert_eq(markup.split("name=\"\{second_group}\"").length(), 3)
  assert_eq(markup.split("name=\"\{second_group}-result\"").length(), 3)
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
  assert_false(markup.contains("tool-call-tabs"))
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

///|
/// One durable model step whose only tool call is a sub-run result.
fn subrun_step(session~ : String, source~ : Source) -> Map[String, @html.Html] {
  let rows : Array[VisibleRow] = [
    {
      item: { kind: User, content: "find it", ts: None, sequence: Some(1), },
      identity: "s1\u{0}o0",
    },
    {
      item: {
        kind: Tool(
          call_id="c1",
          name="explore",
          arguments=Some("{}"),
          has_result=true,
          is_error=false,
          brief=Some("explore sr-2 (1 citation(s), 7 step(s))"),
        ),
        content: "report",
        ts: None,
        sequence: Some(2),
      },
      identity: "s2\u{0}o0",
    },
  ]
  let input = Input(
    source~,
    focused=@interop.ChannelId::Local,
    active_session=session,
    root=None,
    submission_generation=1,
    items=rows,
    streaming_response=None,
    streaming_identity="idle",
  )
  (
    {
      input,
      live_reasoning: None,
      on_open: _ => @cmd.none,
      on_jump: _ => @cmd.none,
      on_open_session: _ => @cmd.none,
    } : TranscriptRenderer).stream_children()
}

///|
#warnings("-alert_unstable")
test "a sub-run card links the child transcript it names" {
  let children = subrun_step(session="run", source=OpenSeek)
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(markup.contains("subrun-chip"))
  // The child id is the parent's plus the brief's `sr-N`, and it reaches the
  // reader as the button's title — the chip's own text names no session.
  assert_true(markup.contains("run-sr-2"))
}

///|
#warnings("-alert_unstable")
test "only an OpenSeek transcript can name a sub-run child" {
  // Codex writes no `<parent>-sr-N` records, so a brief that happens to read
  // like one must not offer a link to a session that cannot exist.
  let children = subrun_step(session="run", source=Codex)
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_false(markup.contains("subrun-chip"))
}

///|
#warnings("-alert_unstable")
test "an ordinary tool card carries no sub-run link" {
  let rows : Array[VisibleRow] = [
    {
      item: { kind: User, content: "read it", ts: None, sequence: Some(1), },
      identity: "s1\u{0}o0",
    },
    {
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
    },
  ]
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="run",
    root=None,
    submission_generation=1,
    items=rows,
    streaming_response=None,
    streaming_identity="idle",
  )
  let children = (
    {
      input,
      live_reasoning: None,
      on_open: _ => @cmd.none,
      on_jump: _ => @cmd.none,
      on_open_session: _ => @cmd.none,
    } : TranscriptRenderer).stream_children()
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_false(markup.contains("subrun-chip"))
}

///|
#warnings("-alert_unstable")
test "a subtask launch card links every worker it started" {
  // The launch brief leads with a slice COUNT and nests the per-worker briefs
  // inside it, so this card names two children and neither at token 1.
  let rows : Array[VisibleRow] = [
    {
      item: { kind: User, content: "split it", ts: None, sequence: Some(1), },
      identity: "s1\u{0}o0",
    },
    {
      item: {
        kind: Tool(
          call_id="c1",
          name="subtask",
          arguments=Some("{}"),
          has_result=true,
          is_error=false,
          brief=Some(
            "subtask 2 slices (subtask sr-3 a (captured), subtask sr-4 b (captured))",
          ),
        ),
        content: "report",
        ts: None,
        sequence: Some(2),
      },
      identity: "s2\u{0}o0",
    },
  ]
  let input = Input(
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="run",
    root=None,
    submission_generation=1,
    items=rows,
    streaming_response=None,
    streaming_identity="idle",
  )
  let children = (
    {
      input,
      live_reasoning: None,
      on_open: _ => @cmd.none,
      on_jump: _ => @cmd.none,
      on_open_session: _ => @cmd.none,
    } : TranscriptRenderer).stream_children()
  let markup = @rabbita.render_to_string(() => {
    @rabbita.Val::constant(children["activity\u{0}after\u{0}s1\u{0}o0"])
  })
  assert_true(markup.contains("run-sr-3"))
  assert_true(markup.contains("run-sr-4"))
}
