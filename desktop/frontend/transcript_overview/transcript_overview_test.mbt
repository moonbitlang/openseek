// The rail's public contract: the entry projection, the key round trip, the
// pure state machine, and the rendered markup's shape.

///|
fn item(
  kind : @transcript.ItemKind,
  sequence? : Int,
) -> @transcript.TranscriptItem {
  { kind, ts: None, sequence, }
}

///|
/// A provider response: prose alone unless it thought or called tools.
fn response(
  reasoning? : String,
  prose? : String,
  calls? : Array[@transcript.ToolCall] = [],
) -> @transcript.ItemKind {
  Assistant(reasoning~, prose~, calls~, replay=false, finished=false)
}

///|
fn shell_call(is_error : Bool) -> @transcript.ToolCall {
  {
    call_id: "c1",
    name: "shell",
    arguments: Some("{}"),
    outcome: Done(
      content=if is_error { "boom" } else { "fine" },
      is_error~,
      brief=None,
    ),
  }
}

///|
test "entries pick user turns and pair each with its first answer" {
  let rows = @transcript_overview.entries(
    [
      item(User("first question"), sequence=1),
      // A response that only thought and read is not an answer yet.
      item(
        response(reasoning="thinking", calls=[
          { ..shell_call(false), name: "read", },
        ]),
        sequence=2,
      ),
      item(response(prose="first answer"), sequence=3),
      item(response(prose="afterthought"), sequence=4),
      item(User("second question"), sequence=5),
    ],
    display=text => text,
  )
  inspect(rows.length(), content="2")
  @debug.assert_eq(rows[0].key, @transcript_overview.Durable(1))
  inspect(rows[0].text, content="first question")
  // The first prose answers the turn; the afterthought does not replace it,
  // and the open second turn has no answer yet.
  @debug.assert_eq(rows[0].reply, Some("first answer"))
  @debug.assert_eq(rows[1].key, @transcript_overview.Durable(5))
  @debug.assert_eq(rows[1].reply, None)
}

///|
test "a turn marks failed for any tool error it contains, answered or not" {
  let rows = @transcript_overview.entries(
    [
      item(User("first question"), sequence=1),
      item(response(calls=[shell_call(true)]), sequence=2),
      item(response(prose="recovered"), sequence=3),
      // A failure after the answer is still this turn's failure: the reply
      // search stops at the first answer, the failure scan must not.
      item(response(calls=[shell_call(true)]), sequence=4),
      item(User("second question"), sequence=5),
      item(response(calls=[shell_call(false)]), sequence=6),
      item(response(prose="done"), sequence=7),
    ],
    display=text => text,
  )
  // A turn that recovered still marks — it is still where a reader wants to
  // land — and a clean turn stays quiet.
  inspect(rows[0].failed, content="true")
  inspect(rows[1].failed, content="false")
  // The scan stops at the next prompt: turn one's failures are not turn two's.
  let single = @transcript_overview.entries(
    [
      item(User("question"), sequence=1),
      item(response(calls=[shell_call(true)]), sequence=2),
    ],
    display=text => text,
  )
  inspect(single[0].failed, content="true")
  // A blocked goal is the turn's failure too.
  let blocked = @transcript_overview.entries(
    [
      item(User("question"), sequence=1),
      item(
        Notice(
          label="goal",
          brief=Some("Goal blocked: why"),
          is_error=true,
          body=None,
        ),
        sequence=2,
      ),
    ],
    display=text => text,
  )
  inspect(blocked[0].failed, content="true")
}

///|
test "an abort bubble is the answer a turn got" {
  let rows = @transcript_overview.entries(
    [item(User("question"), sequence=1), item(Failure("aborted"), sequence=2)],
    display=text => text,
  )
  @debug.assert_eq(rows[0].reply, Some("aborted"))
}

///|
test "a terminal-carried final is the answer a turn got" {
  let rows = @transcript_overview.entries(
    [
      item(User("question"), sequence=1),
      item(Answer("final answer"), sequence=2),
    ],
    display=text => text,
  )
  @debug.assert_eq(rows[0].reply, Some("final answer"))
}

///|
test "a row without a sequence keys by its position" {
  let rows = @transcript_overview.entries(
    [item(response(prose="notice")), item(User("local bubble"))],
    display=text => text,
  )
  inspect(rows.length(), content="1")
  @debug.assert_eq(rows[0].key, @transcript_overview.Local(1))
}

///|
test "the display projection owns the prompt's shown form" {
  let rows = @transcript_overview.entries(
    [item(User("raw envelope"), sequence=1)],
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
  @debug.assert_eq(state.hover, Some({ key, flip: true, anchor: 132, }))
  let clicked = @transcript_overview.update(
    @transcript_overview.Clicked(key),
    state,
  )
  // The click highlights eagerly and keeps the popover: the pointer is
  // still on the tick.
  @debug.assert_eq(clicked.active, Some(key))
  @debug.assert_eq(clicked.hover, Some({ key, flip: true, anchor: 132, }))
  let left = @transcript_overview.update(@transcript_overview.Left, clicked)
  @debug.assert_eq(left.hover, None)
  @debug.assert_eq(left.active, Some(key))
}
