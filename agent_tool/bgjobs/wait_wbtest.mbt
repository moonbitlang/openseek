///|
#cfg(not(platform="windows"))
async test "wait_any ignores unrelated completions and validates all ids" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let jobs = BgJobRuntime(AgentTaskScope(group))
      let (input, release) = @process.write_to_process()
      defer release.close()
      let first = jobs.start(
        program="/bin/cat",
        args=[],
        command="first",
        stdin=input,
      )
      let (other_input, other_release) = @process.write_to_process()
      defer other_release.close()
      let other = jobs.start(
        program="/bin/cat",
        args=[],
        command="other",
        stdin=other_input,
      )
      let mut woke = false
      let waiter = group.spawn(() => {
        jobs.wait_any([first])
        woke = true
      })
      other_release.close()
      jobs.wait_any([other])
      @async.pause()
      assert_false(woke)
      // Even with a completed job, an invalid sibling must be rejected.
      try jobs.wait_any([other, "unknown"]) catch {
        _ => ()
      } noraise {
        _ => fail("unknown id was ignored")
      }
      release.close()
      waiter.wait()
      assert_true(woke)
      jobs.wait_any([first, other]) // Already completed: no new signal needed.
      assert_true(jobs.pending().is_empty())
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "pending covers terminal cleanup and notice publication" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let entered : @async.Queue[Unit] = Queue(kind=Unbounded)
      let release : @async.Queue[Unit] = Queue(kind=Unbounded)
      let mut notices = 0
      let jobs = BgJobRuntime(AgentTaskScope(group), on_job_exit=_ => {
        notices += 1
      })
      let exec = @shell_exec.ShellExecution::start(
        AgentTaskScope(group),
        program="/usr/bin/true",
        args=[],
      )
      let id = jobs.adopt(exec, command="cleanup gate", on_terminal=() => {
        entered.put(())
        release.get()
      })
      entered.get()
      assert_true(jobs.snapshot(id) is Some(job) && job.status is Exited(0))
      assert_eq(jobs.pending().length(), 1)
      assert_eq(notices, 0)
      release.put(())
      jobs.wait_any([id])
      assert_eq(notices, 1)
      assert_true(jobs.pending().is_empty())
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "cancelled wait does not cancel a job or consume later completion" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let jobs = BgJobRuntime(AgentTaskScope(group))
      let (input, release) = @process.write_to_process()
      defer release.close()
      let id = jobs.start(
        program="/bin/cat",
        args=[],
        command="alive",
        stdin=input,
      )
      let waiter = group.spawn(() => jobs.wait_any([id]), allow_failure=true)
      @async.pause()
      waiter.cancel()
      waiter.wait() catch {
        _ => ()
      }
      assert_true(jobs.snapshot(id) is Some(job) && job.status is Running)
      release.close()
      jobs.wait_any([id])
      assert_true(jobs.snapshot(id) is Some(job) && job.status is Exited(0))
    })
  })
}
