// Behavioral tests of the portable session table and pump through the public
// API. None of them reaches a pseudo-terminal spawn, and this package installs
// no spawner, so they run wherever the package builds. Tests that spawn real
// PTY children live with the native spawner in `terminal_pty`.

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
        @terminal.run_terminal_pump(state, push => pushes.put(push))
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
      @terminal.run_terminal_pump(state, push => pushes.put(push))
    })
    let was_cancelled = @async.with_timeout(5000, () => cancelled.get())
    assert_true(was_cancelled)
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

///|
/// A build that installs no pseudo-terminal spawner still runs the pump, but
/// every open fails through `TerminalError` instead of leaving its caller
/// parked or publishing a session.
async test "an open without an installed spawner fails as unavailable" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, push => pushes.put(push))
    })
    let refusal = @async.with_timeout(5000, () => open_refusal(state))
    assert_eq(
      refusal,
      Some("terminal is unavailable: this build has no pseudo-terminal support"),
    )
    assert_true(pushes.try_get() is None)
  })
}
