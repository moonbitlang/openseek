///|
fn fixture_owner(session : String) -> Owner {
  {
    channel: Remote("device-a"),
    scope: { session, workspace: Some("/workspace"), archived: false, },
  }
}

///|
test "scope and selection changes reject stale log replies" {
  let owner = fixture_owner("one")
  let state = {
    ..State::empty(),
    owner: Some(owner),
    active: true,
    epoch: 1,
    read_serial: 3,
    reading: true,
  }
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let (_, switched) = reconcile(emit, state, Some(fixture_owner("two")), true)
  let page : @protocol.JobReadReply = {
    text: "stale",
    start_offset: 0L,
    next_offset: 5L,
    size: 5L,
    more: false,
    output_path: "/log",
  }
  let (_, ignored) = update(emit, Read(1, 3, Ok(page)), switched)
  assert_eq(ignored.text, "")
  let (_, paused) = update(emit, Pause, state)
  let (_, ignored) = update(emit, Read(1, 3, Ok(page)), paused)
  assert_eq(ignored.text, "")
  assert_true(ignored.cursor is None)
  let (_, hidden) = reconcile(emit, state, Some(owner), false)
  let (_, ignored) = update(emit, Read(1, 3, Ok(page)), hidden)
  assert_eq(ignored.text, "")
  assert_false(ignored.active)
}

///|
test "display buffer stays bounded and advances the absolute byte cursor" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let state = {
    ..State::empty(),
    text: "x".repeat(262140),
    epoch: 1,
    read_serial: 2,
  }
  let page : @protocol.JobReadReply = {
    text: "你好🙂tail",
    start_offset: 900000L,
    next_offset: 900014L,
    size: 900014L,
    more: false,
    output_path: "/log",
  }
  let (_, next) = update(emit, Read(1, 2, Ok(page)), state)
  assert_eq(next.text.length(), 262144)
  assert_true(next.text.has_suffix("你好🙂tail"))
  assert_eq(next.cursor, Some(900014L))
  assert_true(next.clipped)
}

///|
test "tail command safely quotes host filesystem paths" {
  assert_eq(
    tail_command("/tmp/a'b/log.out"),
    "tail -n 100 -f -- '/tmp/a'\\''b/log.out'",
  )
  assert_eq(
    tail_command("C:\\a'b\\log.out"),
    "Get-Content -LiteralPath 'C:\\a''b\\log.out' -Tail 100 -Wait",
  )
}
