// Behavioral tests through the public API: a real pump running in a task
// group, sessions spawning real PTY children. Process-specific cases are
// platform-gated; lifecycle cases use the platform's default shell.

///|
/// Collect pushes from a pump into a queue the test can await on.
fn new_push_queue() -> @async.Queue[@terminal.TerminalPush] {
  Queue(kind=Unbounded)
}

///|
/// The `TerminalError` message an open in the current directory refuses with;
/// `None` when it opened, or when it failed some other way.
async fn open_refusal(
  state : @terminal.TerminalState,
  command? : Array[String],
) -> String? {
  try {
    let _ = @terminal.open_terminal(state, cwd=".", cols=80, rows=24, command?)
    None
  } catch {
    @terminal.TerminalError(message) => Some(message)
    _ => None
  }
}

///|
#cfg(not(platform="windows"))
async fn wait_for_output(
  pushes : @async.Queue[@terminal.TerminalPush],
  needle : String,
) -> Unit {
  let mut seen = ""
  for ;; {
    if pushes.get() is Output(data~, ..) {
      seen += @utf8.decode_lossy(data)
      if seen.contains(needle) {
        break
      }
    }
  }
}

///|
#cfg(not(platform="windows"))
async fn wait_for_exit(pushes : @async.Queue[@terminal.TerminalPush]) -> Unit {
  for ;; {
    if pushes.get() is Exited(..) {
      break
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "terminal session round-trips output and reports exit" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    let id = @terminal.open_terminal(state, cwd="/tmp", cols=80, rows=24, command=[
      "/bin/cat",
    ])
    @terminal.write_terminal(state, id~, @utf8.encode("ping\n"))
    @async.with_timeout(5000, () => wait_for_output(pushes, "ping"))
    @terminal.resize_terminal(state, id~, cols=100, rows=30)
    @terminal.close_terminal(state, id~)
    @async.with_timeout(5000, () => wait_for_exit(pushes))
  })
}

///|
#cfg(not(platform="windows"))
async test "terminal session runs in the requested directory" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    ignore(
      @terminal.open_terminal(state, cwd="/tmp", cols=80, rows=24, command=[
        "/bin/sh", "-c", "pwd",
      ]),
    )
    // /tmp is a symlink to /private/tmp on macOS; match the suffix.
    @async.with_timeout(5000, () => wait_for_output(pushes, "tmp"))
    @async.with_timeout(5000, () => wait_for_exit(pushes))
  })
}

///|
/// Direct spawning reports a missing executable while opening the session,
/// instead of first opening a shell that later exits 127.
async test "a missing program fails while opening the session" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    let missing = ["openseek-terminal-test-program-that-does-not-exist"]
    let failed = open_refusal(state, command=missing) is Some(_)
    assert_true(failed)
  })
}

///|
async test "an empty command is rejected before spawning" {
  let state = @terminal.new_terminal_state()
  let failed = open_refusal(state, command=[]) is Some(_)
  assert_true(failed)
}

///|
/// Shutdown is the pump's normal stop signal. In particular, an idle pump
/// blocked on its request queue must let its owning task group finish.
async test "shutdown wakes an idle terminal pump" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let state = @terminal.new_terminal_state()
      let pushes = new_push_queue()
      group.spawn_bg(allow_failure=true, () => {
        @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
      })
      @async.pause()
      state.shutdown()
    })
  })
}

///|
/// An opener may already be waiting on its private reply when the connection
/// ends. Shutdown must reject that call, and all later opens, without a pump.
async test "shutdown rejects pending and later terminal opens" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    let pending_rejected : @async.Queue[Bool] = Queue(kind=Blocking(1))
    group.spawn_bg(allow_failure=true, () => {
      let rejected = open_refusal(state) is Some("terminal service is closed")
      pending_rejected.put(rejected)
    })
    @async.pause()
    state.shutdown()
    assert_true(@async.with_timeout(5000, () => pending_rejected.get()))
    let later_rejected = open_refusal(state)
      is Some("terminal service is closed")
    assert_true(later_rejected)
  })
}

///|
/// `close_all_terminals` (the connect handshake's sweep) retires every live
/// session; each one still reports its exit.
#cfg(not(platform="windows"))
async test "close_all_terminals retires every live session" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    let first = @terminal.open_terminal(state, cwd=".", cols=80, rows=24)
    let second = @terminal.open_terminal(state, cwd=".", cols=80, rows=24)
    @terminal.close_all_terminals(state)
    let exited : Array[String] = []
    @async.with_timeout(5000, () => {
      while exited.length() < 2 {
        if pushes.get() is Exited(id~, ..) {
          exited.push(id)
        }
      }
    })
    exited.sort()
    let expected = [first, second]
    expected.sort()
    assert_eq(exited, expected)
  })
}

///|
/// An old page can disappear after its open request reaches the host but
/// before the pump starts it. The next connect handshake must reject that
/// queued request instead of starting a shell with no tab to own it.
async test "close_all_terminals cancels queued opens from an older page" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    let cancelled : @async.Queue[Bool] = Queue(kind=Blocking(1))
    group.spawn_bg(allow_failure=true, () => {
      let was_cancelled = open_refusal(state)
        is Some("terminal open was cancelled by reconnect")
      cancelled.put(was_cancelled)
    })
    // Let the opener enqueue its request and block on the reply before the
    // reconnect sweep advances the page connection.
    @async.pause()
    @terminal.close_all_terminals(state)
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    let was_cancelled = @async.with_timeout(5000, () => cancelled.get())
    assert_true(was_cancelled)
  })
}

///|
/// A later successful acknowledgement must cover earlier output requests that
/// did not reach the host and wake a reader stopped at the bounded window.
///
/// Skipped: this deadlocks on the Linux CI runners often enough to red-line
/// unrelated pull requests — 8 of the 40 main runs before 2026-08-08, on both
/// the stable and nightly native rows, always with this same signature (the
/// async runtime's deadlock detector fires, then SIGABRT). It does not
/// reproduce on macOS (0/20 locally).
///
/// The hang is in the harness, not in the flow control this test covers. The
/// detector reports live tasks spawned only within `run_terminal_pump`'s own
/// loop; the session's output reader and close watcher — spawned further down
/// in `run_session` — are already gone, so `run_session` never reached them.
/// `open_terminal` waits on its reply queue with no timeout while `run_session`
/// runs under `allow_failure=true`, so any failure or stall before
/// `request.reply.put(Ok(()))` is swallowed and the open blocks forever instead
/// of surfacing an error. That matches the ~25s of silence in the CI logs
/// before the detector trips.
///
/// Unskip once the open reply is bounded (a timeout there turns this class of
/// failure into a legible error) and the underlying stall — most likely in
/// `@pty.spawn` on the runner — is understood. The flake predates the pty
/// 0.3.2 upgrade in #692, so that is not the trigger.
#skip("deadlocks intermittently on Linux CI; see the note above")
#cfg(not(platform="windows"))
async test "a cumulative acknowledgement resumes terminal output" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    let id = @terminal.open_terminal(state, cwd=".", cols=80, rows=24, command=[
      "/usr/bin/yes", "flow-control",
    ])
    let chunks : Array[(Int, Int)] = []
    let mut received = 0
    // Match the host's high watermark. Once this much output has arrived, the
    // reader is parked until an acknowledgement makes window capacity.
    while received < 262144 {
      match pushes.get() {
        Output(id=output_id, sequence~, data~) =>
          if output_id == id {
            chunks.push((sequence, data.length()))
            received += data.length()
          }
        Exited(code~, ..) =>
          fail(
            "terminal exited before filling its flow-control window: \{code}",
          )
      }
    }
    guard chunks.last() is Some(last) else {
      fail("terminal produced no output chunks")
    }
    @terminal.ack_terminal(state, id~, sequence=last.0)
    let resumed = @async.with_timeout_opt(5000, () => pushes.get())
    assert_true(resumed is Some(Output(id=output_id, ..)) && output_id == id)
    @terminal.close_terminal(state, id~)
    @async.with_timeout(5000, () => wait_for_exit(pushes))
  })
}

///|
test "ops on unknown terminal ids degrade cleanly" {
  let state = @terminal.new_terminal_state()
  // ack and close are fire-and-forget: an id that already exited is fine.
  @terminal.ack_terminal(state, id="missing-terminal", sequence=1)
  @terminal.close_terminal(state, id="missing-terminal")
  let failed = try {
    @terminal.resize_terminal(state, id="missing-terminal", cols=80, rows=24)
    false
  } catch {
    @terminal.TerminalError(_) => true
    _ => false
  }
  assert_true(failed)
}
