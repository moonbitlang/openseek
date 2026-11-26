///|
async test "cancelling a spawn caller interrupts launch and releases its owner" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let launching : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let mut launch_finished = false
      let mut hook_called = false
      let starter = group.spawn(allow_failure=true, () => {
        spawn_with(
          group,
          _ => {
            defer {
              launch_finished = true
            }
            launching.put(())
            @async.sleep(10000)
            fail("cancelled launch continued")
          },
          on_cancel=_ => hook_called = true,
        )
      })
      launching.get()
      starter.cancel()
      let cancelled = try {
        ignore(starter.wait())
        false
      } catch {
        @async.WaitedTaskAlreadyCancelled::_ => true
        error => raise error
      }
      assert_true(cancelled)
      assert_true(launch_finished)
      assert_false(hook_called)
      // The owner must finish even though this group itself was never cancelled.
      assert_eq(group.spawn(() => 42).wait(), 42)
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "cancellation after core observed exit does not invoke the hook" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let mut calls = 0
      let child = spawn_with(
        group,
        owned => {
          let process = @process.spawn(owned, "sh", ["-c", "exit 7"])
          assert_eq(process.wait(), 7)
          process
        },
        on_cancel=_ => calls += 1,
      )
      child.cancel()
      assert_eq(child.wait(), 7)
      assert_eq(calls, 0)
    })
  })
}
