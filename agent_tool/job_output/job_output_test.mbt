///|
/// Pinned moonx coordinates for the wasm CLI tools the tests spawn: the pin
/// keeps a registry release from silently changing test behavior, and the
/// wasm tools keep these tests runnable on Windows (no /bin/sh needed).
const CLI_SH : String = "cli/sh@0.1.1"

///|
const CLI_SEQ : String = "cli/seq@0.1.0"

///|
const CLI_PRINTF : String = "cli/printf@0.1.0"

///|
const CLI_SLEEP : String = "cli/sleep@0.1.0"

///|
const CLI_TRUE : String = "cli/true@0.1.0"

///|
/// Execute the job_output tool and unwrap its Respond output.
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
/// Poll until `id` leaves Running. Jobs run through `moonx`, which resolves
/// and caches the wasm tool on first use, so the budget (400 x 25ms) leaves
/// headroom for a cold registry cache.
async fn poll_bg_terminal(bg : @bgjobs.BgJobRuntime, id : String) -> Unit {
  for _ in 0..<400 {
    if bg.snapshot(id) is Some(s) && !(s.status is Running) {
      break
    }
    @async.sleep(25)
  }
}

///|
/// Poll until the job's captured output contains `needle`, on the same budget
/// as `poll_bg_terminal`. Replaces fixed sleeps: moonx startup is ~100ms warm
/// and unbounded cold, so a flat delay would flake.
async fn poll_bg_output(
  bg : @bgjobs.BgJobRuntime,
  id : String,
  needle : String,
) -> Unit {
  for _ in 0..<400 {
    if bg.read_output(id) is Some(o) && o.contains(needle) {
      break
    }
    @async.sleep(25)
  }
}

///|
async test "job_output returns a running job's output and status" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(
      program="moonx",
      args=[CLI_SH, "-c", "printf hi; sleep 30"],
      command="job",
    )
    poll_bg_output(bg, id, "hi")
    let output = run_job_output(bg, { "job_id": id })
    assert_false(output.is_error)
    assert_true(output.content.contains("hi"))
    assert_true(output.content.contains("running"))
    let _ = bg.stop(id)
  })
}

///|
async test "job_output reports a finished job's exit code" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(
      program="moonx",
      args=[CLI_SH, "-c", "exit 2"],
      command="job",
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_true(output.is_error)
    assert_true(output.content.contains("exit=2"))
  })
}

///|
async test "job_output windows a large job's output and notes truncation" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-test-")
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=dir)
    let id = bg.start(
      program="moonx",
      args=[CLI_SEQ, "1", "20000"],
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
async test "job_output flags dropped output for a memory-only job" {
  @async.with_task_group(group => {
    // Memory-only runtime (no spill dir): output past the budget is dropped.
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(
      program="moonx",
      args=[CLI_SEQ, "1", "2000"],
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
async test "job_output marks binary background output as a tool error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    // A background command with non-UTF-8 output that exits 0 must still be a
    // tool error when read, matching the foreground path.
    let id = bg.start(
      program="moonx",
      args=[CLI_PRINTF, "\\377"],
      command="binary",
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_true(output.is_error)
    assert_true(output.content.contains("binary_output"))
  })
}

///|
async test "job_output errors on an unknown job id" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let output = run_job_output(bg, { "job_id": "nope" })
    assert_true(output.is_error)
    assert_true(output.content.contains("no background job"))
  })
}

///|
async test "wait_ms blocks until the job finishes and returns its output" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(
      program="moonx",
      args=[CLI_SH, "-c", "sleep 1; echo WAITED-OK"],
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
async test "a wait_ms deadline on a still-running job is not an error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(program="moonx", args=[CLI_SLEEP, "30"], command="slow")
    let output = run_job_output(bg, { "job_id": id, "wait_ms": 200 })
    // Deadline expiry just reports the live status; the model can call again.
    assert_false(output.is_error)
    assert_true(output.content.contains("running"))
    let _ = bg.stop(id)
  })
}

///|
async test "a non-positive wait_ms is a tool error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(program="moonx", args=[CLI_TRUE], command="noop")
    let output = run_job_output(bg, { "job_id": id, "wait_ms": -5 })
    assert_true(output.is_error)
    assert_true(output.content.contains("wait_ms"))
  })
}

///|
async test "a non-numeric wait_ms is a tool error, not silently ignored" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(program="moonx", args=[CLI_TRUE], command="noop")
    let output = run_job_output(bg, { "job_id": id, "wait_ms": "30000" })
    assert_true(output.is_error)
    assert_true(output.content.contains("wait_ms must be a number"))
  })
}

///|
async test "job_output applies display rewrites supplied by the launcher" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(
      program="moonx",
      args=[CLI_PRINTF, "/tmp/mbtx/snippet.mbtx:1:2: error\\n"],
      command="compiler",
      output_rewrites=[("/tmp/mbtx/snippet.mbtx", "source")],
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_true(output.content.contains("source:1:2: error"))
    assert_false(output.content.contains("/tmp/mbtx"))
  })
}

///|
async test "a job with policy disabled does not invent a policy refusal" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    let id = bg.start(
      program="moonx",
      args=[CLI_PRINTF, "Sandbox policy blocked file write: example\\n"],
      command="unconfined",
      moonrun_policy_active=false,
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_false(output.is_error)
    assert_true(output.content.contains("Sandbox policy blocked"))
    assert_false(output.content.contains("mbtx sandbox:"))
  })
}

///|
async test "a terminal job finds a policy refusal before the displayed tail" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-job-policy-")
    let bg = @bgjobs.BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      spill_dir=dir,
    )
    let id = bg.start(
      program="moonx",
      args=[
        CLI_SH,
        "-c",
        "printf 'Sandbox policy blocked file write: example\\n'; seq 1 10000",
      ],
      command="policy then output",
      moonrun_policy_active=true,
    )
    poll_bg_terminal(bg, id)
    let output = run_job_output(bg, { "job_id": id })
    assert_true(output.is_error)
    assert_false(output.content.contains("Sandbox policy blocked"))
    assert_true(output.content.contains("mbtx sandbox:"))
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
async test "offset pages through retained output from the start" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-test-")
    let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir=dir)
    let id = bg.start(
      program="moonx",
      args=[CLI_SEQ, "1", "20000"],
      command="seq",
      max_output_chars=100,
    )
    poll_bg_terminal(bg, id)
    // The first page is the HEAD of the output, not the tail the default
    // shows, and the footer says which window this is.
    let head = run_job_output(bg, { "job_id": id, "offset": 0 })
    assert_false(head.is_error)
    assert_true(head.content.has_prefix("1\n2\n3\n"))
    assert_true(head.content.contains("window_offset=0"))
    assert_true(head.content.contains("truncated=true"))
    assert_false(head.content.contains("\n20000\n"))
    // The next page starts exactly where the first ended.
    let next = run_job_output(bg, { "job_id": id, "offset": 12000 })
    let full = bg.read_output(id).unwrap_or("")
    let expected = full.view(start_offset=12000, end_offset=12040).to_owned()
    assert_true(next.content.has_prefix(expected))
    assert_true(next.content.contains("window_offset=12000"))
    // Past the end: nothing but the footer. Negative: refused.
    let past = run_job_output(bg, { "job_id": id, "offset": 10_000_000 })
    assert_true(past.content.has_prefix("<system>"))
    let bad = run_job_output(bg, { "job_id": id, "offset": -1 })
    assert_true(bad.is_error)
    // Without offset the tail is still what a poll gets.
    let tail = run_job_output(bg, { "job_id": id })
    assert_true(tail.content.contains("\n20000\n"))
    assert_false(tail.content.contains("window_offset"))
  })
}
