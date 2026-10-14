///|
test "maximize is pure and preserves the size preference while hidden" {
  let emit : @cmd.Emit[@terminal.Msg] = @cmd.Emit(_ => @cmd.none)
  let input = @terminal.Input(
    ctx=@terminal.Ctx(
      channel=@interop.Local,
      session="maximize-test",
      placement=Some(@interop.Scratch(root=None)),
      dark_mode=false,
      connected=false,
    ),
    live_channels=[],
    has_devices=true,
  )
  let closed = @terminal.State::empty()
  let (_, unchanged) = closed.handle(emit, @terminal.ToggleMaximized, input)
  assert_true(unchanged == closed)
  let (_, open) = closed.handle(emit, @terminal.ToggleTerminal, input)
  assert_true(open.is_open())
  assert_false(open.is_maximized())
  let (_, maximized) = open.handle(emit, @terminal.ToggleMaximized, input)
  let (_, repeated) = open.handle(emit, @terminal.ToggleMaximized, input)
  assert_true(maximized == repeated)
  assert_true(maximized.is_maximized())
  assert_false(open.is_maximized())
  let (_, hidden) = maximized.handle(emit, @terminal.ToggleTerminal, input)
  assert_false(hidden.is_open())
  assert_true(hidden.is_maximized())
  let (_, reopened) = hidden.handle(emit, @terminal.ToggleTerminal, input)
  assert_true(reopened == maximized)
  let (_, restored) = reopened.handle(emit, @terminal.ToggleMaximized, input)
  assert_true(restored == open)
}
