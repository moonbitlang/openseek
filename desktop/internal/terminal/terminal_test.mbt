// Behavioral tests through the public API: a real pump running in a task
// group, sessions spawning real PTY children. Process-specific cases are
// platform-gated; lifecycle cases use the platform's default shell.

///|
/// Collect pushes from a pump into a queue the test can await on.
fn new_push_queue() -> @async.Queue[@terminal.TerminalPush] {
  Queue(kind=Unbounded)
}

///|
async fn wait_for_output(
  pushes : @async.Queue[@terminal.TerminalPush],
  needle : String,
) -> Unit {
  let mut seen = ""
  for ;; {
    if pushes.get() is Output(data~, ..) {
      seen = seen + @utf8.decode_lossy(data)
      if seen.contains(needle) {
        break
      }
    }
  }
}

///|
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
    let failed = try {
      let _ = @terminal.open_terminal(state, cwd=".", cols=80, rows=24, command=[
        "openseek-terminal-test-program-that-does-not-exist",
      ])
      false
    } catch {
      @terminal.TerminalError(_) => true
      _ => false
    }
    assert_true(failed)
  })
}

///|
async test "an empty command is rejected before spawning" {
  let state = @terminal.new_terminal_state()
  let failed = try {
    let _ = @terminal.open_terminal(state, cwd=".", cols=80, rows=24, command=[])
    false
  } catch {
    @terminal.TerminalError(_) => true
    _ => false
  }
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
      let rejected = try {
        let _ = @terminal.open_terminal(state, cwd=".", cols=80, rows=24)
        false
      } catch {
        @terminal.TerminalError("terminal service is closed") => true
        _ => false
      }
      pending_rejected.put(rejected)
    })
    @async.pause()
    state.shutdown()
    assert_true(@async.with_timeout(5000, () => pending_rejected.get()))
    let later_rejected = try {
      let _ = @terminal.open_terminal(state, cwd=".", cols=80, rows=24)
      false
    } catch {
      @terminal.TerminalError("terminal service is closed") => true
      _ => false
    }
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
    let exited : Array[Int] = []
    @async.with_timeout(5000, () => {
      while exited.length() < 2 {
        if pushes.get() is Exited(id~, ..) {
          exited.push(id)
        }
      }
    })
    exited.sort()
    assert_eq(exited, [first, second])
  })
}

///|
/// Closing a shell must also stop descendants that inherited its PTY slave.
/// Otherwise the reader never observes EOF after the shell itself is killed.
#cfg(not(platform="windows"))
async test "closing a terminal wakes a read held open by descendants" {
  @async.with_task_group(group => {
    let state = @terminal.new_terminal_state()
    defer state.shutdown()
    let pushes = new_push_queue()
    group.spawn_bg(allow_failure=true, () => {
      @terminal.run_terminal_pump(state, async fn(push) { pushes.put(push) })
    })
    let id = @terminal.open_terminal(state, cwd=".", cols=80, rows=24, command=[
      "/bin/sh", "-c", "trap '' HUP; sleep 30 & child=$!; echo ready; wait $child",
    ])
    // Seeing the marker proves the descendant exists before shutdown starts.
    @async.with_timeout(5000, () => wait_for_output(pushes, "ready"))
    @terminal.close_terminal(state, id~)
    @async.with_timeout(5000, () => wait_for_exit(pushes))
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
      let was_cancelled = try {
        let _ = @terminal.open_terminal(state, cwd=".", cols=80, rows=24)
        false
      } catch {
        @terminal.TerminalError("terminal open was cancelled by reconnect") =>
          true
        _ => false
      }
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
/// A bridge timeout can make the webview retry an acknowledgement whose first
/// request already reached the host. Repeating that sequence must not release
/// any other chunks or wake the paused reader prematurely.
#cfg(not(platform="windows"))
async test "duplicate acknowledgements release an output chunk only once" {
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
    // reader is parked until unique acknowledgements drain below its low mark.
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
    guard chunks.get(0) is Some(first) else {
      fail("terminal produced no output chunks")
    }
    for _ in 0..<32 {
      @terminal.ack_terminal(state, id~, sequence=first.0)
    }
    let prematurely_resumed = @async.with_timeout_opt(500, () => pushes.get())
    assert_true(prematurely_resumed is None)
    for chunk in chunks {
      @terminal.ack_terminal(state, id~, sequence=chunk.0)
    }
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
  @terminal.ack_terminal(state, id=99, sequence=1)
  @terminal.close_terminal(state, id=99)
  let failed = try {
    @terminal.resize_terminal(state, id=99, cols=80, rows=24)
    false
  } catch {
    @terminal.TerminalError(_) => true
    _ => false
  }
  assert_true(failed)
}
