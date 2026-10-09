///|
test "selection offers actions before explicitly starting a reply" {
  let initial : SelectionState[String] = { open: None, batched: false, }
  let anchor : SelectionAnchor = {
    text: "Selected text",
    x: 300,
    y: 200,
    below: false,
  }
  let emit : @cmd.Emit[SelectionMsg] = @cmd.Emit(_ => @cmd.none)
  let deliver = (_ : QuoteReply[String]) => @cmd.none
  let (offered, _) = initial.update(
    Some("session"),
    Settled(anchor),
    emit,
    deliver,
  )
  let (again, _) = initial.update(
    Some("session"),
    Settled(anchor),
    emit,
    deliver,
  )
  assert_true(offered.open == again.open)
  assert_true(offered.watch() is Offer(_))
  assert_true(offered.open is Some({ stage: Offered, .. }))
  // These commands are constructed without a DOM; running update must not
  // focus the input or read the browser selection itself.
  let (reply, _) = offered.update(Some("session"), ReplyStarted, emit, deliver)
  let (reply_again, _) = offered.update(
    Some("session"),
    ReplyStarted,
    emit,
    deliver,
  )
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
  let (closed, _) = reply.update(Some("session"), Closed, emit, deliver)
  assert_true(closed.open is None)
  assert_true(closed.watch() is Idle)
  let (unavailable, _) = initial.update(None, Settled(anchor), emit, deliver)
  assert_true(unavailable.open is None)
}
