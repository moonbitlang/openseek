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
