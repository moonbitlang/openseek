///|
/// Execute the job_output tool and unwrap its Respond output.
#cfg(not(platform="windows"))
async fn run_job_output(
  bg : @bgjobs.BgJobRuntime,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match @job_output.definition(bg).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("job_output should be async")
  }
  guard action is Respond(output) else { fail("expected a Respond action") }
  output
}

///|
/// Poll until `id` leaves Running, on the same 200 x 25ms budget every test
/// used inline (timing-sensitive: keep in lockstep with the old loops).
#cfg(not(platform="windows"))
async fn poll_bg_terminal(bg : @bgjobs.BgJobRuntime, id : String) -> Unit {
  for _ in 0..<200 {
    if bg.snapshot(id) is Some(s) && !(s.status is Running) {
      break
    }
    @async.sleep(25)
  }
}

///|
#cfg(not(platform="windows"))
async test "job_output returns a running job's output and status" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(
      program="sh",
      args=["-c", "printf hi; sleep 30"],
      command="job",
    )
    @async.sleep(100)
    let output = run_job_output(bg, { "job_id": id })
    assert_false(output.is_error)
    assert_true(output.content.contains("hi"))
    assert_true(output.content.contains("running"))
    let _ = bg.stop(id)
  })
}

///|
#cfg(not(platform="windows"))
async test "job_output reports a finished job's exit code" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(program="sh", args=["-c", "exit 2"], command="job")
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_true(output.is_error)
    assert_true(output.content.contains("exit=2"))
  })
}

///|
#cfg(not(platform="windows"))
async test "job_output windows a large job's output and notes truncation" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-test-")
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group), spill_dir=dir)
    let id = bg.start(
      program="sh",
      args=["-c", "seq 1 20000"],
      command="seq",
      max_output_chars=100,
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    // Bounded to the window, with truncation metadata, but still showing the
    // recent (tail) output — here the end of the sequence.
    assert_true(output.content.contains("truncated=true"))
    assert_true(output.content.contains("20000"))
    assert_true(output.content.char_length() < 80000)
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
#cfg(not(platform="windows"))
async test "job_output flags dropped output for a memory-only job" {
  @async.with_task_group(group => {
    // Memory-only runtime (no spill dir): output past the budget is dropped.
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(
      program="sh",
      args=["-c", "seq 1 2000"],
      command="seq",
      max_output_chars=100,
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    // Only ~100 chars retained but the job produced far more — must not present
    // the prefix as complete.
    assert_true(output.content.contains("truncated=true"))
  })
}

///|
#cfg(not(platform="windows"))
async test "job_output marks binary background output as a tool error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    // A background command with non-UTF-8 output that exits 0 must still be a
    // tool error when read, matching the foreground path.
    let id = bg.start(
      program="sh",
      args=["-c", "printf '\\377'"],
      command="binary",
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_true(output.is_error)
    assert_true(output.content.contains("binary_output"))
  })
}

///|
#cfg(not(platform="windows"))
async test "job_output errors on an unknown job id" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let output = run_job_output(bg, { "job_id": "nope" })
    assert_true(output.is_error)
    assert_true(output.content.contains("no background job"))
  })
}

///|
#cfg(not(platform="windows"))
async test "wait_ms blocks until the job finishes and returns its output" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(
      program="sh",
      args=["-c", "sleep 1; echo WAITED-OK"],
      command="waited",
    )
    // No polling loop: a single call awaits the exit and returns the result.
    let output = run_job_output(bg, { "job_id": id, "wait_ms": 30000 })
    assert_false(output.is_error)
    assert_true(output.content.contains("WAITED-OK"))
    assert_true(output.content.contains("exit=0"))
  })
}

///|
#cfg(not(platform="windows"))
async test "a wait_ms deadline on a still-running job is not an error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(program="sh", args=["-c", "sleep 30"], command="slow")
    let output = run_job_output(bg, { "job_id": id, "wait_ms": 200 })
    // Deadline expiry just reports the live status; the model can call again.
    assert_false(output.is_error)
    assert_true(output.content.contains("running"))
    let _ = bg.stop(id)
  })
}

///|
#cfg(not(platform="windows"))
async test "a non-positive wait_ms is a tool error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(program="sh", args=["-c", "true"], command="noop")
    let output = run_job_output(bg, { "job_id": id, "wait_ms": -5 })
    assert_true(output.is_error)
    assert_true(output.content.contains("wait_ms"))
  })
}

///|
#cfg(not(platform="windows"))
async test "a non-numeric wait_ms is a tool error, not silently ignored" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let id = bg.start(program="sh", args=["-c", "true"], command="noop")
    let output = run_job_output(bg, { "job_id": id, "wait_ms": "30000" })
    assert_true(output.is_error)
    assert_true(output.content.contains("wait_ms must be a number"))
  })
}

///|
/// Mark the platform-gated test imports as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_test_imports : Unit = {
  ignore(@agent_runtime.default_agent_event_capacity)
  ignore(@async.sleep)
  ignore(@fs.exists)
}
