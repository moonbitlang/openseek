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

///|
fn reading_fixture() -> State {
  {
    ..State::empty(),
    owner: Some(fixture_owner("one")),
    active: true,
    jobs: [fixture_job("bg-1", Running)],
    selected: Some(("runtime", "bg-1")),
    reading: true,
    read_serial: 1,
    reading_state: Some(Running),
    read_budget: 3,
    cursor: Some(0L),
  }
}

///|
fn page_fixture(start : Int64, more : Bool) -> @protocol.JobReadReply {
  {
    text: "next",
    start_offset: start,
    next_offset: start + 4L,
    size: start + 8L,
    more,
    output_path: "/job.out",
  }
}

///|
test "bursts drain within a finite page budget and wait on incomplete UTF8" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let mut state = reading_fixture()
  for n in 0..<4 {
    let (_, next) = update(
      emit,
      Read(0, state.read_serial, Ok(page_fixture(n.to_int64() * 4L, true))),
      state,
    )
    state = next
  }
  assert_eq(state.cursor, Some(16L))
  assert_eq(state.read_budget, 0)
  assert_false(state.reading)
  assert_true(state.catching_up)
  let initial = reading_fixture()
  let partial = { ..page_fixture(0L, true), text: "", next_offset: 0L, }
  let (_, next) = update(emit, Read(0, 1, Ok(partial)), initial)
  assert_false(next.reading)
  assert_eq(next.read_budget, 3)
  assert_true(next.catching_up)
  let (_, failed) = update(emit, Read(0, 1, Err("missing file")), {
    ..reading_fixture(),
    catching_up: true,
  })
  assert_false(failed.catching_up)
  assert_true(failed.read_error is Some(_))
  let (_, polled) = update(emit, Poll, failed)
  assert_false(polled.reading)
}

///|
test "pause and resume keep the outstanding read accounted for" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let initial = reading_fixture()
  let (_, paused) = update(emit, Pause, initial)
  assert_true(paused.reading)
  let (_, resumed) = update(emit, ToggleFollow, paused)
  assert_true(resumed.reading)
  assert_eq(resumed.read_serial, initial.read_serial)
  let (_, ignored) = update(
    emit,
    Read(0, 1, Ok(page_fixture(0L, false))),
    paused,
  )
  assert_false(ignored.reading)
  assert_eq(ignored.cursor, Some(0L))
  let (_, resumed) = update(emit, ToggleFollow, ignored)
  assert_true(resumed.reading)
  assert_eq(resumed.read_serial, 2)
}

///|
test "reload queues behind an old read and can refresh a paused view" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let (_, pending) = update(emit, Reload, {
    ..reading_fixture(),
    follow: false,
  })
  assert_true(pending.reload_pending)
  assert_eq(pending.read_serial, 1)
  let (_, paused) = update(emit, Pause, pending)
  assert_false(paused.reload_pending)
  assert_false(paused.manual_read)
  let (_, hidden) = reconcile(emit, pending, pending.owner, false)
  assert_false(hidden.reload_pending)
  assert_false(hidden.manual_read)
  assert_false(hidden.reading)
  let (_, reading) = update(
    emit,
    Read(0, 1, Ok(page_fixture(100L, false))),
    pending,
  )
  assert_true(reading.reading)
  assert_false(reading.reload_pending)
  assert_eq(reading.text, "")
  assert_true(reading.cursor is None)
  let (_, result) = update(
    emit,
    Read(0, reading.read_serial, Ok(page_fixture(0L, false))),
    reading,
  )
  assert_eq(result.text, "next")
  assert_false(result.follow)
  assert_false(result.reading)
}

///|
test "terminal jobs drain remaining pages while paused then stop reading" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let view = fixture_job("bg-1", Exited(0))
  let state = {
    ..reading_fixture(),
    jobs: [{ ..view, job: { ..view.job, output_bytes: 8L, }, }],
    reading_state: Some(Exited(0)),
    follow: false,
  }
  let (_, next) = update(emit, Read(0, 1, Ok(page_fixture(0L, true))), state)
  assert_true(next.reading)
  assert_false(next.follow)
  let (_, finished) = update(
    emit,
    Read(0, next.read_serial, Ok(page_fixture(4L, false))),
    next,
  )
  assert_eq(finished.text, "nextnext")
  assert_false(finished.reading)
  assert_true(output_complete(finished, view.job))
  let (_, polled) = update(emit, Poll, finished)
  assert_false(polled.reading)
  assert_true(polled.listing)
  let (_, reload) = update(emit, Reload, polled)
  assert_true(reload.reading)
  assert_true(reload.cursor is None)
  // A later metadata refresh can expose bytes beyond a previously reached EOF.
  let (_, grown) = update(emit, Poll, {
    ..finished,
    jobs: [{ ..view, job: { ..view.job, output_bytes: 12L, }, }],
  })
  assert_true(grown.reading)
}

///|
test "an empty terminal log is read once and read failures require reload" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let state = {
    ..reading_fixture(),
    jobs: [fixture_job("bg-1", Interrupted)],
    reading: false,
    cursor: None,
    follow: false,
  }
  let (_, started) = update(emit, Poll, state)
  assert_true(started.reading)
  let (_, failed) = update(
    emit,
    Read(0, started.read_serial, Err("unreadable")),
    started,
  )
  let (_, polled) = update(emit, Poll, failed)
  assert_false(polled.reading)
  let (_, reload) = update(emit, Reload, polled)
  let empty = {
    ..page_fixture(0L, false),
    text: "",
    next_offset: 0L,
    size: 0L,
  }
  let (_, finished) = update(
    emit,
    Read(0, reload.read_serial, Ok(empty)),
    reload,
  )
  let (_, polled) = update(emit, Poll, finished)
  assert_false(polled.reading)
  assert_eq(polled.cursor, Some(0L))
}

///|
test "stopping and terminal jobs reject repeat stop even if controllable" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let states : Array[@wire.JobState] = [
    Stopping,
    Exited(0),
    Stopped("user"),
    Interrupted,
  ]
  for status in states {
    let view = { ..fixture_job("bg-1", status), controllable: true, }
    let (_, next) = update(emit, Stop, { ..reading_fixture(), jobs: [view], })
    assert_false(next.stopping)
  }
}

///|
test "initial selection prefers an active job and preserves selected history" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let reply : @protocol.JobsListReply = {
    jobs: [fixture_job("done", Exited(0)), fixture_job("live", Running)],
    selected: None,
    next_offset: None,
    errors: [],
  }
  let (_, initial) = update(emit, Listed(0, 0, Ok(reply)), State::empty())
  assert_eq(initial.selected, Some(("runtime", "live")))
  let (_, history) = update(emit, Select("runtime", "done"), initial)
  let (_, refreshed) = update(emit, Listed(0, 0, Ok(reply)), history)
  assert_eq(refreshed.selected, Some(("runtime", "done")))
  let (_, history_only) = update(
    emit,
    Listed(0, 0, Ok({ ..reply, jobs: [reply.jobs[0]], })),
    State::empty(),
  )
  assert_eq(history_only.selected, Some(("runtime", "done")))
}

///|
test "historical tail commands do not wait for more output" {
  assert_eq(
    tail_command("/tmp/a'b.out", follow=false),
    "tail -n 100 -- '/tmp/a'\\''b.out'",
  )
  assert_eq(
    tail_command("C:\\a'b.out", follow=false),
    "Get-Content -LiteralPath 'C:\\a''b.out' -Tail 100",
  )
  assert_eq(
    job_timing(fixture_job("old", Interrupted).job),
    "End time unavailable",
  )
}

///|
test "interruption requires a fresh EOF even when persisted bytes trail the cursor" {
  let emit : @cmd.Emit[Msg] = Emit(_ => @cmd.none)
  let live = fixture_job("bg-1", Running)
  let state = {
    ..reading_fixture(),
    jobs: [{ ..live, job: { ..live.job, output_bytes: 5L, }, }],
    cursor: Some(10L),
    eof_state: Some(Running),
  }
  let interrupted = {
    ..live,
    job: { ..live.job, state: Interrupted, output_bytes: 5L, },
  }
  let reply : @protocol.JobsListReply = {
    jobs: [interrupted],
    selected: None,
    next_offset: None,
    errors: [],
  }
  let (_, ended) = update(emit, Listed(0, 0, Ok(reply)), state)
  assert_false(output_complete(ended, interrupted.job))
  // A pre-interruption read can arrive late with an old EOF; it cannot finish draining.
  let stale_eof = {
    ..page_fixture(10L, false),
    text: "",
    next_offset: 10L,
    size: 10L,
  }
  let (_, stale) = update(emit, Read(0, 1, Ok(stale_eof)), ended)
  assert_false(output_complete(stale, interrupted.job))
  let (_, polled) = update(emit, Poll, { ..stale, follow: false, })
  assert_true(polled.reading)
  let final_page = {
    ..page_fixture(10L, false),
    text: "last error",
    next_offset: 20L,
    size: 20L,
  }
  let (_, drained) = update(
    emit,
    Read(0, polled.read_serial, Ok(final_page)),
    polled,
  )
  assert_eq(drained.text, "last error")
  assert_true(output_complete(drained, interrupted.job))
  let (_, polled) = update(emit, Poll, drained)
  assert_false(polled.reading)
  let (_, selected) = update(emit, Select("runtime", "bg-1"), drained)
  assert_true(selected.reading)
  assert_true(selected.eof_state is None)
}
