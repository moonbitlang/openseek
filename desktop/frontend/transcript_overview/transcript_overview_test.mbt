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
        @transcript_overview.Entered(@transcript_overview.Durable(3)),
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
    @transcript_overview.Entered(key),
    @transcript_overview.State::empty(),
  )
  @debug.assert_eq(state.hover, Some(key))
  let clicked = @transcript_overview.update(
    @transcript_overview.Clicked(key),
    state,
  )
  // The click highlights eagerly and keeps the popover: the pointer is
  // still on the tick.
  @debug.assert_eq(clicked.active, Some(key))
  @debug.assert_eq(clicked.hover, Some(key))
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
    },
    {
      key: @transcript_overview.Durable(4),
      text: "second question",
      ts: None,
      reply: None,
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
    hover: Some(@transcript_overview.Durable(1)),
    active: Some(@transcript_overview.Durable(4)),
  }
  let marked = render(two_entries(), state)
  assert_true(marked.contains("overview-tick active"))
  assert_true(marked.contains("overview-tick hovered"))
  assert_true(marked.contains("first question"))
  assert_true(marked.contains("10:00"))
  assert_true(marked.contains("overview-preview-reply"))
  assert_true(marked.contains("first answer"))
  // The unhovered second turn renders no popover of its own.
  assert_false(marked.contains("second question</div>"))
}

///|
test "only a long rail's bottom-half ticks open their preview upward" {
  // A short rail floats mid-viewport with room below — no flipping.
  let bottom_of_two = render(two_entries(), {
    hover: Some(@transcript_overview.Durable(4)),
    active: None,
  })
  assert_true(bottom_of_two.contains("overview-preview"))
  assert_false(bottom_of_two.contains("overview-preview flip"))
  let many : Array[@transcript_overview.Entry] = []
  for index in 0..<24 {
    many.push({
      key: @transcript_overview.Durable(index),
      text: "turn \{index}",
      ts: None,
      reply: None,
    })
  }
  let top_of_many = render(many, {
    hover: Some(@transcript_overview.Durable(0)),
    active: None,
  })
  assert_false(top_of_many.contains("overview-preview flip"))
  let bottom_of_many = render(many, {
    hover: Some(@transcript_overview.Durable(23)),
    active: None,
  })
  assert_true(bottom_of_many.contains("overview-preview flip"))
}
