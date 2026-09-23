///|
/// Run `arguments` through `mbtx`, expect a handoff, wait for the job, and
/// check job_output reports the guest's policy-like text as ordinary output
/// rather than as a refusal from a policy that was not active.
#callsite(autofill(loc))
async fn assert_handoff_keeps_guest_marker(
  mbtx : @agent_tool.AgentToolDefinition,
  bg_runtime : @bgjobs.BgJobRuntime,
  arguments : Json,
  loc~ : SourceLoc,
) -> Unit {
  let action = run_async_tool(mbtx, arguments)
  guard action is Respond(output) else { fail("expected Respond", loc~) }
  assert_true(output.content.contains("moved to the background"), loc~)
  guard bg_runtime.list() is [job, ..] else { fail("no job registered", loc~) }
  @async.with_timeout(30_000, () => bg_runtime.wait_any([job.id]))
  let read = run_async_tool(@job_output.definition(bg_runtime), {
    "job_id": job.id,
  })
  guard read is Respond(result) else { fail("expected Respond", loc~) }
  assert_false(result.is_error, loc~)
  assert_true(result.content.contains("Sandbox policy blocked"), loc~)
  assert_false(result.content.contains("mbtx sandbox:"), loc~)
}

///|
/// The mbtx fixture these tests share: a session temp dir, a job runtime that
/// spills into it, and an mbtx bound to both. The temp dir is removed when the
/// group ends. The handoff bound is injected so a test does not have to outwait
/// the real one.
async fn[X] mbtx_fixture(
  group : @async.TaskGroup[X],
  prefix~ : String,
  auto_background_after_ms~ : Int,
  approval? : @agent_runtime.ApprovalChannel,
) -> (String, @bgjobs.BgJobRuntime, @agent_tool.AgentToolDefinition) {
  let spill_dir = @fs.tmpdir(prefix~)
  group.add_defer(() => {
    @async.protect_from_cancel(() => {
      @fs.rmdir(spill_dir, recursive=true) catch {
        _ => ()
      }
    })
  })
  let bg_runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir~)
  let mbtx = @mbtx.definition(
    workspace_root=".",
    bg_runtime~,
    job_dir=spill_dir,
    auto_background_after_ms~,
    approval?,
  )
  (spill_dir, bg_runtime, mbtx)
}

///|
/// Compilation can no longer cross the grace: the wasm build phase runs
/// synchronously by design — its time does not count against the run's
/// inline allowance — so even under the smallest possible handoff bound a
/// compile error is reported INLINE, labeled as the build's, naming the
/// submitted `source`, and no job is ever created for it. What the runtime
/// adopts is always a running program.
async test "a compile error never becomes a job, whatever the grace" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-compile-job-",
      auto_background_after_ms=1,
    )
    let action = run_async_tool(mbtx, {
      "source": "fn main { let _x : Int = \"nope\" }",
    })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(output.content.contains("moved to the background"))
    assert_true(output.content.contains("BUILD failed"))
    // The diagnostic points at the model's own input, not the throwaway dir.
    assert_true(output.content.contains("source:"))
    assert_false(output.content.contains("openseek-compile-job-"))
    assert_true(bg_runtime.list() is [])
  })
}

///|
/// A compile error reached inside the foreground grace reports inline, with
/// the throwaway path rewritten to `source:LINE:COL`.
async test "a compile error reached inside the grace reports inline" {
  @async.with_task_group(group => {
    let (_, _, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-compile-inline-",
      auto_background_after_ms=60_000,
    )
    let action = run_async_tool(mbtx, {
      "source": "fn main { let _x : Int = \"nope\" }",
    })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(output.content.contains("moved to the background"))
    // The diagnostic points at the model's own input.
    assert_true(output.content.contains("source:"))
    assert_false(output.content.contains("openseek-compile-inline-"))
  })
}

///|
/// A foreground run that outlives its bound is DETACHED, not killed: the shell
/// tool behaved that way, and a five-minute `moon test` that gets shot at the
/// deadline loses everything it was about to report. The bound is injected here
/// so the test does not have to outwait the real one.
async test "a foreground run past its deadline becomes a job instead of dying" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-jobs-test-",
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  println("started")
      #|  @async.sleep(60_000)
      #|}
    let action = run_async_tool(mbtx, { "source": source })
    guard action is Respond(output) else { fail("expected Respond") }
    // Not an error, and not a corpse: it is a job the model can still watch.
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background as job"))
    assert_true(output.content.contains("job_output"))
    guard bg_runtime.list() is [job, ..] else { fail("no job was registered") }
    assert_true(job.status is Running)
    let _ = bg_runtime.stop(job.id)
  })
}

///|
/// A handed-off snippet may put a bulky result in its policy-owned temp area
/// and print the path. Terminal status reclaims compiler artifacts without
/// deleting that result before the completion notice can be acted on.
async test "a handed-off job cleans builds but keeps result files until teardown" {
  @async.with_task_group(group => {
    let (spill_dir, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-job-result-",
      auto_background_after_ms=1,
    )
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/fs" }
      #|
      #|async fn main {
      #|  @async.sleep(100)
      #|  let path = "\{@fs.tmpdir(prefix="result-")}/report.txt"
      #|  @fs.write_file(path, "kept", create_mode=CreateOrTruncate)
      #|  println(path)
      #|}
    let action = run_async_tool(mbtx, { "source": source })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(
      output.content.contains("moved to the background"),
      msg=output.content,
    )
    guard bg_runtime.list() is [job, ..] else { fail("no job registered") }
    @async.with_timeout(120_000, () => bg_runtime.wait_any([job.id]))
    let read = run_async_tool(@job_output.definition(bg_runtime), {
      "job_id": job.id,
    })
    guard read is Respond(result) else { fail("expected Respond") }
    assert_false(result.is_error)
    let dirs = @fs.readdir(spill_dir).filter(name => name.has_prefix("snippet-"))
    assert_eq(dirs.length(), 1)
    let call_dir = "\{spill_dir}/\{dirs[0]}"
    let results = @fs.readdir("\{call_dir}/tmp")
    assert_eq(results.length(), 1)
    let result_path = "\{call_dir}/tmp/\{results[0]}/report.txt"
    assert_eq(@fs.read_file(result_path).text(), "kept")
    let build_dir = "\{call_dir}/build"
    // wait_any includes launcher cleanup and completion publication.
    assert_false(@fs.exists(build_dir))
    assert_true(@fs.exists("\{call_dir}/tmp"))
  })
}

///|
/// A handed-off run still carries the build phase's voice: requested compiler
/// warnings exist only in the build capture, so the handoff response is their
/// one ride to the model — and the job's label says the build succeeded, so a
/// later nonzero exit reads as the program's own.
async test "a handoff carries build warnings and the build-ok label" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-handoff-warn-",
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  let unused = 1
      #|  @async.sleep(60_000)
      #|}
    let action = run_async_tool(mbtx, {
      "source": source,
      "warning": "on",
      "description": "Check compiler warnings",
    })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background"))
    assert_true(output.content.contains("Unused variable"))
    // Warnings name the model's `source`, not the throwaway build dir.
    assert_true(output.content.contains("source:"))
    guard bg_runtime.list() is [job, ..] else { fail("no job was registered") }
    assert_true(job.command.contains("build ok"))
    assert_eq(job.description, Some("Check compiler warnings"))
    assert_true(background_notice_text(job).contains("Check compiler warnings"))
    let _ = bg_runtime.stop(job.id)
  })
}

///|
/// The moonrun policy is wired only for the wasm backend. A compute-only
/// backend printing the runtime's marker is ordinary guest output, not evidence
/// of a policy that was never active.
async test "a non-wasm handed-off job does not invent a policy refusal" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-js-job-",
      auto_background_after_ms=1,
    )
    let source =
      #|fn main {
      #|  println("Sandbox policy blocked file write: example")
      #|}
    assert_handoff_keeps_guest_marker(mbtx, bg_runtime, {
      "source": source,
      "target": "js",
    })
  })
}

///|
/// The same policy-active gate applies before handoff. Whether an ordinary
/// non-wasm run crosses the grace period must not change how its output is
/// classified.
async test "a non-wasm inline run does not invent a policy refusal" {
  @async.with_task_group(group => {
    let (_, _, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-js-inline-",
      auto_background_after_ms=60_000,
    )
    assert_true(mbtx.description.contains("up to 60s"))
    let action = run_async_tool(mbtx, {
      "source": "fn main { println(\"Sandbox policy blocked file write: example\") }",
      "target": "js",
    })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_false(output.content.contains("moved to the background"))
    assert_true(output.content.contains("Sandbox policy blocked"))
    assert_false(output.content.contains("mbtx sandbox:"))
  })
}

///|
/// An automatically handed-off snippet must not inherit the engine's fd 0:
/// under `serve` that descriptor carries JSONL commands. It gets immediate EOF
/// before continuing as a job.
async test "an automatically handed-off snippet reads EOF on stdin" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-jobs-stdin-",
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  let line = @stdio.stdin.read_until("\n")
      #|  @stdio.stdout.write("got=\{line is Some(_)}\n")
      #|  @async.sleep(60_000)
      #|}
    let action = run_async_tool(mbtx, { "source": source })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background"))
    // The job read EOF rather than blocking on (or stealing from) fd 0.
    guard bg_runtime.list() is [job, ..] else { fail("no job registered") }
    let mut saw_eof = false
    // Handoff can happen while a cold dependency build is still running. Wait
    // for the first program output instead of racing the compiler.
    for _ in 0..<2400 {
      let recent = bg_runtime.read_output_tail(job.id, 12000).unwrap_or("")
      if recent.contains("got=false") {
        saw_eof = true
        break
      }
      @async.sleep(25)
    }
    assert_true(saw_eof)
    let read = run_async_tool(@job_output.definition(bg_runtime), {
      "job_id": job.id,
    })
    guard read is Respond(job) else { fail("expected Respond") }
    assert_true(job.content.contains("got=false"))
    let _ = bg_runtime.stop(bg_runtime.list()[0].id)
  })
}

///|
/// Escalation removes the moonrun policy before launch. If that run hands off,
/// job_output must remember the absence rather than treating similar guest text
/// as a refusal from a policy that was not present.
async test "an escalated handed-off job does not invent a policy refusal" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-escalated-job-",
      auto_background_after_ms=1,
      approval=ApprovalChannel(_ => AllowedOnce),
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  @async.sleep(100)
      #|  println("Sandbox policy blocked file write: example")
      #|}
    assert_handoff_keeps_guest_marker(mbtx, bg_runtime, {
      "source": source,
      "escalated": true,
    })
  })
}

///|
/// ...and that wait is bounded. It used to run with no deadline of its own, so a
/// program that emitted one invalid byte and then kept going — a watcher, a test
/// printing raw bytes — held the turn for its whole lifetime, with the detach
/// below skipped for exactly this case. Both waits share the bound now, and
/// expiry detaches like any other long run.
async test "binary output does not escape the deadline" {
  @async.with_task_group(group => {
    let (_, bg_runtime, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-jobs-binary-",
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  @stdio.stdout.write(b"\xff\xfe")
      #|  @async.sleep(60_000)
      #|}
    let action = run_async_tool(mbtx, { "source": source })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("moved to the background as job"))
    guard bg_runtime.list() is [job, ..] else { fail("no job was registered") }
    let _ = bg_runtime.stop(job.id)
  })
}

///|
/// Non-UTF-8 output ends the retained wait EARLY, with the child still running.
/// Reporting at that moment would leave the process alive while the deferred
/// cleanup removes its build directory, and would invent an exit code — so the
/// tool waits out the real exit and says the rendering was lossy.
async test "binary output waits for the real exit instead of abandoning it" {
  @async.with_task_group(group => {
    // This test is about waiting for the real exit, not the production 5s
    // handoff threshold. Keep cold dependency builds safely inside its premise.
    let (_, _, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-binary-inline-",
      auto_background_after_ms=60_000,
    )
    // Emit an invalid UTF-8 byte, then keep working briefly before exiting 3.
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/stdio", "moonbitlang/x/sys" }
      #|
      #|async fn main {
      #|  @stdio.stdout.write(b"\xff\xfe")
      #|  @async.sleep(300)
      #|  println("done")
      #|  @sys.exit(3)
      #|}
    let action = run_async_tool(mbtx, { "source": source })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    // The real exit code, not the -1 an abandoned execution would report.
    assert_true(output.content.contains("exited 3"))
    assert_true(output.content.contains("non-UTF-8"))
  })
}

///|
/// The foreground output cap is fixed, so the failure must prevent a useless
/// identical retry and point directly at the file-redirection escape hatch.
/// Inline cleanup removes the snippet temp dir before the next tool call, so
/// the recovery must also say to read the reduced result inside that snippet.
async test "the inline output cap gives actionable retry guidance" {
  @async.with_task_group(group => {
    let (_, _, mbtx) = mbtx_fixture(
      group,
      prefix="openseek-inline-cap-",
      auto_background_after_ms=60_000,
    )
    let action = run_async_tool(mbtx, {
      "source": "fn main { for _ in 0..<50_000 { println(\"x\") } }",
    })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("fixed 48000-byte inline limit"))
    assert_true(output.content.contains("Retrying the same call"))
    assert_true(output.content.contains("stdout=ToFile(path)"))
    assert_true(output.content.contains("same snippet read the file"))
  })
}
