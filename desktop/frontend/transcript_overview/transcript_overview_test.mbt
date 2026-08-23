// The rail's public contract: the entry projection, the key round trip, the
// pure state machine, and the rendered markup's shape.

///|
fn item(
  kind : @transcript.ItemKind,
  content : String,
  sequence? : Int,
) -> @transcript.TranscriptItem {
  { kind, content, ts: None, sequence }
}

///|
test "entries pick user turns and pair each with its first answer" {
  let rows = @transcript_overview.entries(
    [
      item(User, "first question", sequence=1),
      item(Reasoning, "thinking", sequence=2),
      item(
        Tool(
          call_id="c1",
          name="read",
          arguments=None,
          has_result=true,
          is_error=false,
          brief=None,
        ),
        "",
        sequence=2,
      ),
      item(Assistant(is_danger=false), "first answer", sequence=2),
      item(Assistant(is_danger=false), "afterthought", sequence=3),
      item(User, "second question", sequence=4),
    ],
    display=text => text,
  )
  inspect(rows.length(), content="2")
  @debug.assert_eq(rows[0].key, @transcript_overview.Durable(1))
  inspect(rows[0].text, content="first question")
  // The first assistant row answers the turn; the afterthought does not
  // replace it, and the open second turn has no answer yet.
  @debug.assert_eq(rows[0].reply, Some("first answer"))
  @debug.assert_eq(rows[1].key, @transcript_overview.Durable(4))
  @debug.assert_eq(rows[1].reply, None)
}

///|
test "a turn marks failed for any tool error it contains, answered or not" {
  let tool = is_error => {
    @transcript.ItemKind::Tool(
      call_id="c1",
      name="shell",
      arguments=None,
      has_result=true,
      is_error~,
      brief=None,
    )
  }
  let rows = @transcript_overview.entries(
    [
      item(User, "first question", sequence=1),
      item(tool(true), "boom", sequence=2),
      item(Assistant(is_danger=false), "recovered", sequence=3),
      // A failure after the answer is still this turn's failure: the reply
      // search stops at the first answer, the failure scan must not.
      item(tool(true), "boom again", sequence=4),
      item(User, "second question", sequence=5),
      item(tool(false), "fine", sequence=6),
      item(Assistant(is_danger=false), "done", sequence=7),
    ],
    display=text => text,
  )
  // A turn that recovered still marks — it is still where a reader wants to
  // land — and a clean turn stays quiet.
  inspect(rows[0].failed, content="true")
  inspect(rows[1].failed, content="false")
  // The scan stops at the next prompt: turn one's failures are not turn two's.
  let single = @transcript_overview.entries(
    [item(User, "question", sequence=1), item(tool(true), "boom", sequence=2)],
    display=text => text,
  )
  inspect(single[0].failed, content="true")
}

///|
#warnings("-alert_unstable")
test "a failed turn's tick is marked in class and in words" {
  let entries = two_entries()
  let flagged = [{ ..entries[0], failed: true }, entries[1]]
  let markup = render(flagged, @transcript_overview.State::empty())
  assert_true(markup.contains("overview-tick failed"))
  // Colour is never the only carrier: the label says so too.
  assert_true(markup.contains("first question (had errors)"))
  // The clean turn keeps its plain class and its unadorned label.
  assert_true(markup.contains("second question"))
  assert_false(markup.contains("second question (had errors)"))
  assert_false(
    render(entries, @transcript_overview.State::empty()).contains(
      "overview-tick failed",
    ),
  )
}

///|
test "an abort bubble is the answer a turn got" {
  let rows = @transcript_overview.entries(
    [
      item(User, "question", sequence=1),
      item(Assistant(is_danger=true), "aborted", sequence=2),
    ],
    display=text => text,
  )
  @debug.assert_eq(rows[0].reply, Some("aborted"))
}

///|
test "a terminal-carried final is the answer a turn got" {
  let rows = @transcript_overview.entries(
    [
      item(User, "question", sequence=1),
      item(TerminalAnswer, "final answer", sequence=2),
    ],
    display=text => text,
  )
  @debug.assert_eq(rows[0].reply, Some("final answer"))
}

///|
test "a row without a sequence keys by its position" {
  let rows = @transcript_overview.entries(
    [item(Assistant(is_danger=false), "notice"), item(User, "local bubble")],
    display=text => text,
  )
  inspect(rows.length(), content="1")
  @debug.assert_eq(rows[0].key, @transcript_overview.Local(1))
}

///|
test "the display projection owns the prompt's shown form" {
  let rows = @transcript_overview.entries(
    [item(User, "raw envelope", sequence=1)],
    display=_ => "typed text $skill",
  )
  inspect(rows[0].text, content="typed text $skill")
}

///|
test "anchor ids round-trip through the DOM" {
  for key in [@transcript_overview.Durable(12), @transcript_overview.Local(0)] {
    @debug.assert_eq(
      @transcript_overview.TurnKey::from_anchor(key.anchor()),
      Some(key),
    )
  }
  @debug.assert_eq(@transcript_overview.TurnKey::from_anchor("stream"), None)
  // A mangled ordinal is nobody's key, not a crash.
  @debug.assert_eq(@transcript_overview.TurnKey::from_anchor("turn-s12x"), None)
  @debug.assert_eq(@transcript_overview.TurnKey::from_anchor("turn-s"), None)
}

///|
test "the state machine's transitions are idempotent" {
  let initial = @transcript_overview.State::empty()
  for
    msg in (
      [
        @transcript_overview.Entered(
          @transcript_overview.Durable(3),
          flip=false,
          anchor=48,
        ),
        @transcript_overview.Left,
        @transcript_overview.Clicked(@transcript_overview.Local(2)),
        @transcript_overview.ActiveChanged(
          Some(@transcript_overview.Durable(9)),
        ),
        @transcript_overview.ActiveChanged(None),
      ] : Array[@transcript_overview.Msg]) {
    let once = @transcript_overview.update(msg, initial)
    @debug.assert_eq(@transcript_overview.update(msg, once), once)
  }
}

///|
test "hover opens on enter, survives a click, and closes on leaving the rail" {
  let key = @transcript_overview.Durable(7)
  let state = @transcript_overview.update(
    @transcript_overview.Entered(key, flip=true, anchor=132),
    @transcript_overview.State::empty(),
  )
  // The enter-time flip and anchor measurements ride along with the hover.
  @debug.assert_eq(state.hover, Some({ key, flip: true, anchor: 132 }))
  let clicked = @transcript_overview.update(
    @transcript_overview.Clicked(key),
    state,
  )
  // The click highlights eagerly and keeps the popover: the pointer is
  // still on the tick.
  @debug.assert_eq(clicked.active, Some(key))
  @debug.assert_eq(clicked.hover, Some({ key, flip: true, anchor: 132 }))
  let left = @transcript_overview.update(@transcript_overview.Left, clicked)
  @debug.assert_eq(left.hover, None)
  @debug.assert_eq(left.active, Some(key))
}

///|
fn two_entries() -> Array[@transcript_overview.Entry] {
  [
    {
      key: @transcript_overview.Durable(1),
      text: "first question",
      ts: Some(1781144351123),
      reply: Some("first answer"),
      failed: false,
    },
    {
      key: @transcript_overview.Durable(4),
      text: "second question",
      ts: None,
      reply: None,
      failed: false,
    },
  ]
}

///|
#warnings("-alert_unstable")
fn render(
  entries : Array[@transcript_overview.Entry],
  state : @transcript_overview.State,
) -> String {
  @rabbita.render_to_string(() => {
    @rabbita.Val::constant(
      @transcript_overview.rail(entries, state, @cmd.Emit(_ => @cmd.none), clock=_ => {
        "10:00"
      }),
    )
  })
}

///|
test "the rail hides below two turns" {
  let entries = two_entries()
  let one = render([entries[0]], @transcript_overview.State::empty())
  assert_true(one.contains("hidden"))
  let two = render(entries, @transcript_overview.State::empty())
  assert_false(two.contains("hidden"))
}

///|
test "the active turn's tick is marked and the popover renders only hovered" {
  let plain = render(two_entries(), @transcript_overview.State::empty())
  assert_false(plain.contains("overview-tick active"))
  assert_false(plain.contains("overview-preview"))
  let state : @transcript_overview.State = {
    hover: Some({
      key: @transcript_overview.Durable(1),
      flip: false,
      anchor: 24,
    }),
    active: Some(@transcript_overview.Durable(4)),
  }
  let marked = render(two_entries(), state)
  assert_true(marked.contains("overview-tick active"))
  assert_true(marked.contains("overview-tick hovered"))
  assert_true(marked.contains("first question"))
  assert_true(marked.contains("10:00"))
  assert_true(marked.contains("overview-preview-reply"))
  assert_true(marked.contains("first answer"))
  assert_false(marked.contains("overview-preview flip"))
  // The popover carries its enter-time anchor: it renders outside the
  // scrollable rail, so the tick's position cannot place it.
  assert_true(marked.contains("--overview-preview-anchor: 24px"))
  // The unhovered second turn renders no popover of its own.
  assert_false(marked.contains("second question</div>"))
}

///|
test "a hover measured out of downward room opens its preview upward" {
  let state : @transcript_overview.State = {
    hover: Some({
      key: @transcript_overview.Durable(1),
      flip: true,
      anchor: 300,
    }),
    active: None,
  }
  let markup = render(two_entries(), state)
  assert_true(markup.contains("overview-preview flip"))
}
