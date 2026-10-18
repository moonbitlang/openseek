///|
/// Poll `id` until its snapshot is terminal, on a bounded budget.
async fn settled(
  rt : @bgjobs.BgJobRuntime,
  id : String,
) -> @bgjobs.BgJobSnapshot {
  for _ in 0..<400 {
    if rt.snapshot(id) is Some(snap) && !(snap.status is Running) {
      return snap
    }
    @async.sleep(25)
  }
  fail("job \{id} did not settle")
}

///|
fn subagent_info(
  outcome : @protocol.SubagentOutcome?,
) -> @protocol.SubagentInfo {
  {
    kind: "explore",
    label: "scout",
    session: "p-sr-1",
    launch: Direct,
    outcome,
    usage: None,
    report: None,
    workspace: InPlace,
  }
}

///|
#cfg(not(platform="windows"))
async test "the end hook learns a natural exit's code" {
  @async.with_task_group(group => {
    let rt = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let ends : Array[@bgjobs.JobEnd] = []
    let id = rt.start(program="sh", args=["-c", "exit 3"], command="exit 3", on_end=end => {
      ends.push(end)
    })
    let _ = settled(rt, id)
    assert_true(ends is [Exited(3)])
  })
}

///|
#cfg(not(platform="windows"))
async test "the end hook learns a requested stop" {
  @async.with_task_group(group => {
    let rt = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let ends : Array[@bgjobs.JobEnd] = []
    let id = rt.start(
      program="sh",
      args=["-c", "sleep 30"],
      command="sleep 30",
      on_end=end => ends.push(end),
    )
    assert_true(rt.stop(id))
    assert_true(ends is [Stopped])
  })
}

///|
/// A custom cancel handler is how the process is ended on a stop: here it
/// closes the child's stdin, which the child takes as its cue to finish, and
/// the child's last words are captured before the job settles.
#cfg(not(platform="windows"))
async test "a stop goes through the job's cancel handler" {
  @async.with_task_group(group => {
    let rt = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let (input, writer) = @process.write_to_process()
    defer writer.close()
    let handler = @process.CancellationHandler(_ => {
      writer.close()
      @async.sleep(2000)
    })
    let id = rt.start(
      program="sh",
      args=["-c", "cat >/dev/null; echo flushed"],
      command="graceful child",
      stdin=input,
      cancel_handler=handler,
    )
    assert_true(rt.stop(id))
    guard rt.read_output(id) is Some(output) else { fail("job vanished") }
    assert_true(output.contains("flushed"))
  })
}

///|
/// A job started with `reaped=false` outlives the runtime's wall-clock cap;
/// an ordinary one beside it is reaped.
#cfg(not(platform="windows"))
async test "an unreaped job outlives the wall-clock cap" {
  @async.with_task_group(group => {
    let rt = @bgjobs.BgJobRuntime(AgentTaskScope(group), hard_timeout_ms=100)
    let reaped = rt.start(
      program="sh",
      args=["-c", "sleep 5"],
      command="reaped",
    )
    let kept = rt.start(
      program="sh",
      args=["-c", "sleep 1; exit 0"],
      command="kept",
      reaped=false,
    )
    let reaped_snap = settled(rt, reaped)
    assert_true(reaped_snap.killed_by_time_limit)
    let kept_snap = settled(rt, kept)
    assert_true(kept_snap.status is Exited(0))
    assert_false(kept_snap.killed_by_time_limit)
  })
}

///|
/// The typed subagent part rides the job's record and snapshot, and is frozen
/// when the job settles: a later change to what the supplier would say does
/// not reach the terminal record.
#cfg(not(platform="windows"))
async test "a subagent supplier is recorded and frozen at the end" {
  @async.with_task_group(group => {
    let records : Array[@protocol.JobRecord] = []
    let rt = @bgjobs.BgJobRuntime(AgentTaskScope(group), on_job_event=(
      _,
      record,
    ) => records.push(record))
    let mut outcome : @protocol.SubagentOutcome? = None
    let id = rt.start(
      program="sh",
      args=["-c", "exit 0"],
      command="child",
      on_end=_ => outcome = Some(Captured),
      subagent=() => subagent_info(outcome),
    )
    let snap = settled(rt, id)
    assert_true(snap.subagent is Some({ outcome: Some(Captured), .. }))
    outcome = Some(Stopped)
    assert_true(
      rt.snapshot(id)
      is Some({ subagent: Some({ outcome: Some(Captured), .. }), .. }),
    )
    guard records is [first, .., last] else { fail("expected job events") }
    assert_true(first.subagent is Some({ outcome: None, .. }))
    assert_true(last.subagent is Some({ outcome: Some(Captured), .. }))
  })
}

///|
#cfg(not(platform="windows"))
async test "an ordinary job has no subagent part" {
  @async.with_task_group(group => {
    let rt = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = rt.start(program="sh", args=["-c", "exit 0"], command="plain")
    let snap = settled(rt, id)
    assert_true(snap.subagent is None)
    assert_true(rt.records() is [{ subagent: None, .. }])
  })
}
