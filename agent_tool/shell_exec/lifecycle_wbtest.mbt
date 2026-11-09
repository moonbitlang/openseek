///|
/// Pinned moonx coordinate for the wasm sleeper these tests spawn: the pin keeps
/// a registry release from silently changing test behavior, and the wasm tool
/// keeps the tests runnable on Windows (no `/bin/sh` needed).
const CLI_SLEEP : String = "cli/sleep@0.1.0"

///|
async test "execution revokes dependents at stop before waiting and accepts late observers" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="moonx", args=[
      CLI_SLEEP,
      "10",
    ])
    let mut calls = 0
    exec.on_ending(() => calls += 1)
    exec.request_stop()
    assert_eq(calls, 1)
    exec.request_stop()
    assert_eq(calls, 1)
    exec.on_ending(() => calls += 1)
    assert_eq(calls, 2)
    exec.wait()
    assert_eq(calls, 2)
  })
}

///|
/// The direct child exits while the descendant it spawned still holds the
/// output pipe, so the monitor must publish the exit without waiting for the
/// pipe. Leaving that descendant needs a real POSIX `sh`: `moonx cli/sh` has
/// no `&`, and no wasm tool can leave a process running after it exits, so
/// this test stays gated to non-Windows.
#cfg(not(platform="windows"))
async test "execution observes process exit before draining descendant-held output" {
  @async.with_timeout(1500, () => {
    @async.with_task_group(group => {
      let exec = ShellExecution::start(AgentTaskScope(group), program="sh", args=[
        "-c", "sleep 3 & printf tail; exit 0",
      ])
      let observed : Ref[ExecStatus?] = Ref(None)
      exec.on_ending(() => observed.val = Some(exec.status()))
      exec.wait()
      assert_true(observed.val is Some(Running))
      assert_true(exec.status() is Exited(0))
      assert_eq(exec.head(), "tail")
      assert_eq(exec.output_error(), None)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "stop ends output draining after the direct child has exited" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let exec = ShellExecution::start(AgentTaskScope(group), program="sh", args=[
        "-c", "(while printf x; do :; done) 2>/dev/null & exit 0",
      ])
      assert_eq(exec.process.wait(), 0)
      // Stop only once the monitor has seen the natural exit; the descendant
      // keeps the pipe busy, so the drain is still running.
      for _ in 0..<100 {
        if exec.exited_on_its_own {
          break
        }
        @async.sleep(10)
      }
      assert_true(exec.exited_on_its_own)
      assert_true(exec.status() is Running)
      exec.request_stop()
      exec.wait()
      // The stop ends the drain; the natural exit seen first still stands.
      assert_true(exec.status() is Exited(0))
      assert_true(exec.stop_cause() is None)
      assert_eq(exec.output_error(), None)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "output cap ends draining a continuously writing descendant" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let exec = ShellExecution::start(
        AgentTaskScope(group),
        program="sh",
        args=["-c", "(while printf x; do :; done) 2>/dev/null & exit 0"],
        inline_cap=4096,
        hard_cap=4096,
        kill_at_hard_cap=true,
      )
      exec.wait()
      // The cap may be reached before or after the shell's own exit is seen;
      // a natural exit seen first stands.
      if exec.exited_on_its_own {
        assert_true(exec.status() is Exited(0))
      } else {
        assert_true(exec.status() is Killed)
      }
      assert_true(exec.killed_by_output_limit())
      assert_true(exec.output_truncated())
      assert_eq(exec.output_error(), None)
    })
  })
}

///|
/// Session teardown cancels the monitor while the child is still running. The
/// hook must fire on that path too, before the output reader is joined and
/// before the terminal status lands.
async test "session cancellation fires the ending hook before output cleanup" {
  @async.with_timeout(3000, () => {
    let mut observed : ExecStatus? = None
    let mut calls = 0
    @async.with_task_group(outer => {
      // The inner group plays the session: failing its body cancels the
      // monitor spawned on it.
      let session = outer.spawn(allow_failure=true, () => {
        @async.with_task_group(group => {
          let exec = ShellExecution::start(
            AgentTaskScope(group),
            program="moonx",
            args=[CLI_SLEEP, "10"],
          )
          exec.on_ending(() => {
            calls += 1
            observed = Some(exec.status())
          })
          @async.sleep(50)
          fail("session shutdown")
        })
      })
      session.wait() catch {
        _ => ()
      }
    })
    assert_eq(calls, 1)
    assert_true(observed is Some(Running))
  })
}

///|
/// The first reason a stop was requested is the one kept: trouble during
/// the wind-down, or a later request, does not replace it.
async test "the first stop cause is kept" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="moonx", args=[
      CLI_SLEEP,
      "10",
    ])
    assert_true(exec.stop_cause() is None)
    exec.request_stop()
    exec.sink.failure = Some("disk full")
    exec.killed_by_output_limit = true
    exec.request_stop()
    assert_true(exec.stop_cause() is Some(Requested))
    exec.wait()
  })
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="moonx", args=[
      CLI_SLEEP,
      "10",
    ])
    exec.kill_for_time_limit()
    exec.request_stop()
    assert_true(exec.stop_cause() is Some(TimeLimit))
    exec.wait()
  })
}

///|
/// Teardown cancels the process without requesting a stop; the handler
/// wrapper records it as the first cause, so trouble while the child winds
/// down does not replace it.
async test "teardown is recorded as the first stop cause" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(
      AgentTaskScope(group),
      program="moonx",
      args=[CLI_SLEEP, "10"],
      cancel_handler=CancellationHandler(_ => @async.sleep(10_000)),
    )
    // What the group's cancellation does to the process task.
    exec.process.cancel()
    for _ in 0..<100 {
      if exec.stop_cause() is Some(_) {
        break
      }
      @async.sleep(10)
    }
    assert_true(exec.stop_cause() is Some(Requested))
    exec.sink.failure = Some("disk full")
    exec.request_stop()
    assert_true(exec.stop_cause() is Some(Requested))
  })
}

///|
/// A child seen to exit on its own was not ended by a stop requested
/// afterwards.
async test "a stop after a natural exit records no cause" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="moonx", args=[
      CLI_SLEEP,
      "0",
    ])
    exec.wait()
    assert_true(exec.status() is Exited(0))
    exec.request_stop()
    assert_true(exec.stop_cause() is None)
  })
}
