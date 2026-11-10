///|
test "selection offers actions before explicitly starting a reply" {
  let initial : SelectionState[String] = {
    open: None,
    batched: false,
    generation: 0,
  }
  let anchor : SelectionAnchor = {
    source: "column",
    text: "Selected text",
    x: 300,
    y: 200,
    below: false,
  }
  let targets = [{ source: "column", target: "session", side_chat: false, }]
  let emit : @cmd.Emit[SelectionMsg] = @cmd.Emit(_ => @cmd.none)
  let deliver = (_ : QuoteReply[String]) => @cmd.none
  let (offered, _) = initial.update(targets, Settled(anchor), emit, deliver)
  let (again, _) = initial.update(targets, Settled(anchor), emit, deliver)
  assert_true(offered.open == again.open)
  assert_true(offered.watch() is Offer(_))
  assert_true(offered.open is Some({ stage: Offered, .. }))
  // These commands are constructed without a DOM; running update must not
  // focus the input or read the browser selection itself.
  let (reply, _) = offered.update(targets, ReplyStarted, emit, deliver)
  let (reply_again, _) = offered.update(targets, ReplyStarted, emit, deliver)
  assert_true(reply.open == reply_again.open)
  assert_true(reply.watch() is Reply)
  assert_true(
    reply.open
    is Some(
      {
        stage: Replying(comment="", declined=false),
        anchor: { text: "Selected text", .. },
        ..
      }
    ),
  )
  let (closed, _) = reply.update(targets, Closed, emit, deliver)
  assert_true(closed.open is None)
  assert_true(closed.watch() is Idle)
  let (unavailable, _) = initial.update([], Settled(anchor), emit, deliver)
  assert_true(unavailable.open is None)
}

///|
test "a selection is offered to the composer of the transcript it is in" {
  let initial : SelectionState[String] = {
    open: None,
    batched: false,
    generation: 0,
  }
  let targets : Array[SelectionTarget[String]] = [
    { source: "column", target: "main", side_chat: true, },
    { source: "dock", target: "side", side_chat: false, },
  ]
  let emit : @cmd.Emit[SelectionMsg] = @cmd.Emit(_ => @cmd.none)
  let deliver = (_ : QuoteReply[String]) => @cmd.none
  let anchor : SelectionAnchor = {
    source: "dock",
    text: "Selected text",
    x: 300,
    y: 200,
    below: false,
  }
  let (in_dock, _) = initial.update(targets, Settled(anchor), emit, deliver)
  assert_true(in_dock.open is Some({ target: "side", .. }))
  let (in_column, _) = initial.update(
    targets,
    Settled({ ..anchor, source: "column", }),
    emit,
    deliver,
  )
  assert_true(in_column.open is Some({ target: "main", .. }))
  // A side chat starts only where the source allows one, and closes the bar.
  let started : Array[(String, String)] = []
  let side_chat = (target : String, quote : String) => {
    started.push((target, quote))
    @cmd.none
  }
  let (refused, _) = in_dock.update(
    targets,
    SideChatStarted,
    emit,
    deliver,
    side_chat~,
  )
  assert_true(refused.open == in_dock.open)
  let (closed, _) = in_column.update(
    targets,
    SideChatStarted,
    emit,
    deliver,
    side_chat~,
  )
  assert_true(closed.open is None)
  assert_eq(started, [("main", "Selected text")])
}
