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
    tail_command("//server/share/job.out"),
    "Get-Content -LiteralPath '//server/share/job.out' -Tail 100 -Wait",
  )
  assert_eq(
    tail_command("/tmp/a'b/log.out"),
    "tail -n 100 -f -- '/tmp/a'\\''b/log.out'",
  )
  assert_eq(
    tail_command("C:\\a'b\\log.out"),
    "Get-Content -LiteralPath 'C:\\a''b\\log.out' -Tail 100 -Wait",
  )
}

///|
test "bounded output does not split a surrogate pair at its leading edge" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let state = { ..State::empty(), text: "🙂", epoch: 1, read_serial: 2, }
  let page : @protocol.JobReadReply = {
    text: "x".repeat(262143),
    start_offset: 4L,
    next_offset: 262147L,
    size: 262147L,
    more: false,
    output_path: "/log",
  }
  let (_, next) = update(emit, Read(1, 2, Ok(page)), state)
  assert_eq(next.text, "x".repeat(262143))
}

///|
fn fixture_job(id : String, state : @wire.JobState) -> @protocol.JobView {
  {
    job: {
      generation: "runtime",
      id,
      state,
      revision: 2,
      command: "worker",
      description: None,
      cwd: None,
      started_at_ms: 1L,
      backgrounded_at_ms: 2L,
      finished_at_ms: None,
      last_output_at_ms: None,
      output_file: Some("job.out"),
      output_persistent: true,
      output_bytes: 0L,
      output_chars: 0,
      output_truncated: false,
      invalid_utf8: false,
      output_error: None,
      persistence_error: None,
      cleanup_error: None,
    },
    output_path: Some("/job.out"),
    controllable: !state.is_terminal(),
    error: None,
  }
}

///|
test "first-page polling refreshes a selected historical row while paused" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let old = fixture_job("old", Running)
  let current = fixture_job("new", Running)
  let state = {
    ..State::empty(),
    jobs: [current, old],
    selected: Some(("runtime", "old")),
    follow: false,
  }
  let reply : @protocol.JobsListReply = {
    jobs: [current],
    selected: Some(fixture_job("old", Stopped("user"))),
    next_offset: Some(100),
    errors: [],
  }
  let (_, next) = update(emit, Listed(0, 0, Ok(reply)), state)
  assert_true(
    selected_job(next) is Some(view) &&
    view.job.state is Stopped("user") &&
    !view.controllable,
  )
  assert_false(next.follow)
  let (_, page) = update(
    emit,
    Listed(
      0,
      100,
      Ok({
        ..reply,
        jobs: [fixture_job("old", Exited(7))],
        selected: None,
        next_offset: None,
      }),
    ),
    next,
  )
  assert_true(selected_job(page) is Some(view) && view.job.state is Exited(7))
}
