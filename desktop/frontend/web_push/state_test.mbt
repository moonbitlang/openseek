///|
let ctx : @web_push.Ctx = { token: "ts_1", locale: "en", }

///|
/// One update, run twice to show it is pure.
fn step(state : @web_push.State, msg : @web_push.Msg) -> @web_push.State raise {
  let emit : @cmd.Emit[@web_push.Msg] = Emit(_ => @cmd.none)
  let (once, _) = state.update(msg, ctx, emit)
  let (twice, _) = state.update(msg, ctx, emit)
  assert_eq(once, twice)
  once
}

///|
test "the first probe decides what the account area shows" {
  let checking = @web_push.State()
  assert_true(step(checking, Probed(NoPushApi)) is Unsupported)
  assert_true(step(checking, Probed(NoRelayKey)) is Unavailable)
  assert_true(
    step(checking, Probed(Ready(key="k", permission=Denied, subscribed=false)))
    is Blocked,
  )
  assert_true(
    step(checking, Probed(Ready(key="k", permission=Default, subscribed=false)))
    is Off(key="k", error=None),
  )
  // Granted without a subscription still needs the user's click.
  assert_true(
    step(checking, Probed(Ready(key="k", permission=Granted, subscribed=false)))
    is Off(key="k", error=None),
  )
  assert_true(
    step(checking, Probed(Ready(key="k", permission=Granted, subscribed=true)))
    is On(key="k", error=None),
  )
}

///|
test "turning on ends on, blocked, off, or off with the failure" {
  let off = step(
    @web_push.State(),
    Probed(Ready(key="k", permission=Default, subscribed=false)),
  )
  let working = step(off, TurnOn)
  assert_true(working is Working(key="k"))
  assert_true(step(working, TurnedOn) is On(key="k", error=None))
  assert_true(step(working, Denied) is Blocked)
  assert_true(step(working, Dismissed) is Off(key="k", error=None))
  assert_true(
    step(working, TurnOnFailed("HTTP 500"))
    is Off(key="k", error=Some("HTTP 500")),
  )
}

///|
test "an enabled device turns off or sends a test, keeping failures visible" {
  let on = step(
    @web_push.State(),
    Probed(Ready(key="k", permission=Granted, subscribed=true)),
  )
  let leaving = step(on, TurnOff)
  assert_true(leaving is Working(key="k"))
  assert_true(step(leaving, TurnedOff) is Off(key="k", error=None))
  assert_true(
    step(leaving, TurnOffFailed("offline"))
    is On(key="k", error=Some("offline")),
  )
  let testing = step(on, SendTest)
  assert_true(testing is Working(key="k"))
  assert_true(step(testing, TestSent) is On(key="k", error=None))
  assert_true(
    step(testing, TestFailed("HTTP 404")) is On(key="k", error=Some("HTTP 404")),
  )
}

///|
test "stale replies and hidden controls change nothing" {
  let on = step(
    @web_push.State(),
    Probed(Ready(key="k", permission=Granted, subscribed=true)),
  )
  // A second probe after the first settled.
  assert_eq(step(on, Probed(NoRelayKey)), on)
  // Controls that state does not offer.
  assert_eq(step(on, TurnOn), on)
  let off = step(on |> step(TurnOff), TurnedOff)
  assert_eq(step(off, TurnOff), off)
  assert_eq(step(off, SendTest), off)
  // A reply with nothing in flight.
  assert_eq(step(off, TurnedOn), off)
  let blocked = step(
    @web_push.State(),
    Probed(Ready(key="k", permission=Denied, subscribed=false)),
  )
  assert_eq(step(blocked, TurnOn), blocked)
  let unsupported = step(@web_push.State(), Probed(NoPushApi))
  assert_eq(step(unsupported, TurnOn), unsupported)
}
