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
  let input = Input(
    focused=@interop.ChannelId::Remote("relay-a"),
    active_session="same-markup-chat",
    submission_generation=7,
    items=[],
    streaming_response="",
    subruns=[],
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
  assert_true(markup.contains("data-transcript-submission=\"7\""))
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
