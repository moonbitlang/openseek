///|
#cfg(not(platform="windows"))
async test "execution revokes dependents at stop before waiting and accepts late observers" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="sh", args=[
      "-c", "sleep 10",
    ])
    let calls = Ref(0)
    exec.on_ending(() => calls.val += 1)
    exec.request_stop()
    assert_eq(calls.val, 1)
    exec.request_stop()
    assert_eq(calls.val, 1)
    exec.on_ending(() => calls.val += 1)
    assert_eq(calls.val, 2)
    exec.wait()
    assert_eq(calls.val, 2)
  })
}

///|
#cfg(not(platform="windows"))
async test "execution observes process exit before draining descendant-held output" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let exec = ShellExecution::start(AgentTaskScope(group), program="sh", args=[
        "-c", "sleep 0.5 & exit 0",
      ])
      let observed : Ref[ExecStatus?] = Ref(None)
      exec.on_ending(() => observed.val = Some(exec.status()))
      exec.wait()
      assert_true(observed.val is Some(Running))
      assert_true(exec.status() is Exited(0))
    })
  })
}

///|
/// Session teardown cancels the monitor while the child is still running. The
/// hook must fire on that path too, before the output reader is joined and
/// before the terminal status lands.
#cfg(not(platform="windows"))
async test "session cancellation fires the ending hook before output cleanup" {
  @async.with_timeout(3000, () => {
    let observed : Ref[ExecStatus?] = Ref(None)
    let calls = Ref(0)
    @async.with_task_group(outer => {
      // The inner group plays the session: failing its body cancels the
      // monitor spawned on it.
      let session = outer.spawn(allow_failure=true, () => {
        @async.with_task_group(group => {
          let exec = ShellExecution::start(
            AgentTaskScope(group),
            program="sh",
            args=["-c", "sleep 10"],
          )
          exec.on_ending(() => {
            calls.val += 1
            observed.val = Some(exec.status())
          })
          @async.sleep(50)
          fail("session shutdown")
        })
      })
      session.wait() catch {
        _ => ()
      }
    })
    assert_eq(calls.val, 1)
    assert_true(observed.val is Some(Running))
  })
}
