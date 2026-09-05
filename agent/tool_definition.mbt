///|
/// The completion notice pushed to the model when a background job exits: its
/// id, terminal status, and how to read its output.
fn background_notice_text(snapshot : @bgjobs.BgJobSnapshot) -> String {
  let status = match snapshot.status {
    Exited(0) => "exit=0"
    Exited(code) => "exit=\{code}"
    Stopped =>
      if snapshot.killed_by_output_limit {
        "killed: flooded past the output cap"
      } else if snapshot.killed_by_time_limit {
        "killed: outlived the wall-clock cap"
      } else {
        "stopped"
      }
    Running => "running"
  }
  "background job \{snapshot.id} finished (\{status}): `\{snapshot.command}` — read its output with job_output (job_id=\"\{snapshot.id}\")."
}

///|
/// Build the agent's standard tool registry bound to `runtime` and `scope`.
///
/// The returned registry contains the built-in local tools: `read`, `edit`,
/// `multi_edit`, `write`, `remove`, `plan`, `goal`, `mbtx`, `job_output`,
/// `job_stop`, and `finish`. Commands are `mbtx`'s job — it compiles and
/// runs a MoonBit program that spawns processes through the shell-free
/// `moonbitlang/async/shell` API, so there is no shell tool and no shell parsing
/// anywhere in the registry. A snippet that would outlast the foreground bound
/// is detached as a background job, which `job_output` and `job_stop` then
/// watch.
/// Each tool lives in its own subpackage of `agent_tool` and exposes a
/// `definition()` constructor; this function bundles them into the `Tools`
/// value the loop dispatches against. File-oriented tools capture
/// `runtime.workspace_root()` when this function is called. The `scope`
/// parameter remains part of the API so future stateful tools can spawn bounded
/// background work under the caller-owned task scope.
///
/// Raises if the standard tool definitions contain duplicate names. Under the
/// checked-in registry that should be a programming error, not user input.
///
/// `on_background_wake`, when supplied, is called each time a background job
/// exits, so an idle controller can wake to surface the completion notice.
///
/// `extra_tools` are appended to the registry after the built-ins — the seam for
/// dynamically discovered tools (e.g. MCP servers' tools, namespaced so they do
/// not collide with the built-ins). The caller builds them (keeping this package
/// free of MCP dependencies); `Tools` still raises on any duplicate name.
pub async fn[X] build_tools(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
  on_background_wake? : () -> Unit,
  extra_tools? : Array[@agent_tool.AgentToolDefinition] = [],
  mbtx_subrun? : @host.SubrunInjection,
) -> @agent_tool.Tools {
  let workspace_root = runtime.workspace_root()
  // One session-scoped file-state map, shared by the file-writing tools so they
  // record which paths the agent created vs. modified this session — the record
  // `remove` reads to tell an agent-created file (safe to delete) from a
  // pre-existing one.
  let file_state = @agent_tool.FileStateMap()
  // One session temp dir, shared by the job runtime (which spills large job
  // output to disk) and mbtx (whose detached snippets outlive the call
  // that started them, so their directories cannot be reclaimed there).
  let spill_dir : String? = Some(@fs.tmpdir(prefix="openseek-jobs-")) catch {
    _ => None
  }
  // Remove the session temp dir when the owning scope ends, so `/tmp` cannot
  // accumulate spill files and snippet directories across turns or sessions.
  // A GROUP defer, not a plain one: `build_tools` returns immediately while
  // the dir must live as long as the session, and the group runs its defers
  // only after every child task has terminated — so a background job still
  // spilling output cannot have the directory pulled out from under it.
  // `protect_from_cancel` because a group cancelled from outside cancels the
  // async operations in its defers too.
  if spill_dir is Some(dir) {
    scope
    .group()
    .add_defer(() => {
      @async.protect_from_cancel(() => {
        @fs.rmdir(dir, recursive=true) catch {
          _ => ()
        }
      })
    })
  }
  // When a background job exits on its own, push a completion notice into the
  // loop's lossless steer queue (surfaced to the model at the next step, or
  // persisted while idle) and poke the controller so an idle engine wakes to
  // drain it instead of leaving it until the next prompt.
  let bg_runtime = @bgjobs.BgJobRuntime(scope, spill_dir?, on_job_exit=snapshot => {
    runtime.queue_steer(Notice(background_notice_text(snapshot)))
    if on_background_wake is Some(wake) {
      wake()
    }
  })
  Tools(
    [
      @read.definition(workspace_root~),
      @edit.definition(workspace_root~, file_state~),
      @multi_edit.definition(workspace_root~, file_state~),
      @write.definition(workspace_root~, file_state~),
      @remove.definition(workspace_root~, file_state~),
      @plan.definition(),
      @goal.definition(),
      // The escalation argument exists for this registry only when the runtime
      // has somewhere to send the question — and the channel IS that fact, so
      // it is passed straight through rather than tested and rebuilt. What the
      // tool package receives is the channel and nothing else: it can ask, and
      // knows nothing about who answers.
      // `mbtx_subrun`, when present, is what lets a snippet delegate to child
      // agents that are VISIBLE: it carries the engine's own path plus the
      // block of child session ids and journal paths this session reserved.
      // Absent for a conversation with no durable session, where a child
      // would have nowhere to leave a transcript.
      @mbtx.definition(
        workspace_root~,
        bg_runtime~,
        job_dir?=spill_dir,
        approval?=runtime.approval_channel(),
        subrun?=mbtx_subrun,
      ),
      // Deliberately NOT told about escalation. It reports a job that already
      // ran — a policy refusal reaches it after minutes of real work — and the
      // sanctioned retry is worded for a run that did not happen. Offering it
      // here would misdescribe the state the job left behind.
      @job_output.definition(bg_runtime),
      @job_stop.definition(bg_runtime),
      @finish.definition(),
    ] +
    extra_tools,
  )
}

///|
async test "agent registers the expected tool names" {
  @async.with_task_group() <| group => {
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    let function_tools = tools.function_tools()
    assert_eq(function_tools.length(), 11)
    let names = [ for t in function_tools => t.name ]
    assert_true(names.contains("job_output"))
    assert_true(names.contains("job_stop"))
    assert_true(names.contains("read"))
    assert_true(names.contains("edit"))
    assert_true(names.contains("multi_edit"))
    assert_true(names.contains("write"))
    assert_true(names.contains("remove"))
    assert_true(names.contains("plan"))
    assert_true(names.contains("goal"))
    assert_true(names.contains("mbtx"))
    assert_true(names.contains("finish"))
    assert_false(names.contains("moon_check"))
    assert_false(names.contains("moon_cmd"))
    assert_false(names.contains("moon_ide"))
  }
}

///|
/// Commands go through `mbtx`, so the registry must not carry a shell
/// tool family — nor the background-job tools that only ever served it.
async test "the registry has no shell tool family" {
  @async.with_task_group() <| group => {
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    let names = [ for t in tools.function_tools() => t.name ]
    assert_false(names.contains("shell"))
    assert_false(names.contains("shell_output"))
    assert_false(names.contains("shell_stop"))
    guard tools.find("mbtx") is Some(mbtx) else { fail("mbtx tool missing") }
    // Background handoff is automatic, so the schema carries no duration-mode
    // choice for the model to make.
    let JsonSchema(schema) = mbtx.schema
    guard schema is { "properties": Object(properties), .. } else {
      fail("expected an object schema")
    }
    let names = properties.keys().collect()
    assert_eq(names.length(), 4)
    for name in ["source", "target", "cwd", "warning"] {
      assert_true(names.contains(name))
    }
    assert_false(mbtx.description.contains("run_in_background"))
    assert_true(mbtx.description.contains("AUTOMATICALLY"))
  }
}

///|
/// A compile error reached inside the foreground grace reports inline, with
/// the throwaway path rewritten to `source:LINE:COL`.
async test "a compile error reached inside the grace reports inline" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-compile-inline-")
    let bg_runtime = @bgjobs.BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      spill_dir~,
    )
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=60_000,
    )
    let action = match mbtx.execute {
      Async(execute) =>
        execute({ "source": "fn main { let _x : Int = \"nope\" }" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(output.content.contains("moved to the background"))
    // The diagnostic points at the model's own input.
    assert_true(output.content.contains("source:"))
    assert_false(output.content.contains("openseek-compile-inline-"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// A handed-off run still carries the build phase's voice: requested compiler
/// warnings exist only in the build capture, so the handoff response is their
/// one ride to the model — and the job's label says the build succeeded, so a
/// later nonzero exit reads as the program's own.
async test "a handoff carries build warnings and the build-ok label" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-handoff-warn-")
    let bg_runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir~)
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  let unused = 1
      #|  @async.sleep(60_000)
      #|}
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source, "warning": "on" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background"))
    assert_true(output.content.contains("Unused variable"))
    // Warnings name the model's `source`, not the throwaway build dir.
    assert_true(output.content.contains("source:"))
    guard bg_runtime.list() is [job, ..] else { fail("no job was registered") }
    assert_true(job.command.contains("build ok"))
    let _ = bg_runtime.stop(job.id)
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
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
    let spill_dir = @fs.tmpdir(prefix="openseek-compile-job-")
    let bg_runtime = @bgjobs.BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      spill_dir~,
    )
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=1,
    )
    let action = match mbtx.execute {
      Async(execute) =>
        execute({ "source": "fn main { let _x : Int = \"nope\" }" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(output.content.contains("moved to the background"))
    assert_true(output.content.contains("BUILD failed"))
    // The diagnostic points at the model's own input, not the throwaway dir.
    assert_true(output.content.contains("source:"))
    assert_false(output.content.contains("openseek-compile-job-"))
    assert_true(bg_runtime.list() is [])
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// A handed-off snippet may put a bulky result in its policy-owned temp area
/// and print the path. Terminal status reclaims compiler artifacts without
/// deleting that result before the completion notice can be acted on.
async test "a handed-off job cleans builds but keeps result files until teardown" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-job-result-")
    let bg_runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir~)
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=1,
    )
    let result_path = "\{spill_dir}/snippet-0/tmp/report.txt"
    let source = (
      #|import { "moonbitlang/async", "moonbitlang/async/fs" }
      #|
      #|async fn main {
      #|  @fs.write_file("RESULT_PATH", "kept", create_mode=CreateOrTruncate)
      #|  println("RESULT_PATH")
      #|}
    ).replace_all(old="RESULT_PATH", new=result_path)
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("moved to the background"))
    guard bg_runtime.list() is [job, ..] else { fail("no job registered") }
    let read = match @job_output.definition(bg_runtime).execute {
      Async(execute) => execute({ "job_id": job.id, "wait_ms": 120_000 })
      Sync(_) => fail("job_output should be async")
    }
    guard read is Respond(result) else { fail("expected Respond") }
    assert_false(result.is_error)
    assert_eq(@fs.read_file(result_path).text(), "kept")
    let build_dir = "\{spill_dir}/snippet-0/build"
    let mut build_reclaimed = !@fs.exists(build_dir)
    // job_output may observe the terminal state just before its cleanup callback
    // finishes, so wait for that callback rather than racing it.
    for _ in 0..<400 {
      if !@fs.exists(build_dir) {
        build_reclaimed = true
        break
      }
      @async.sleep(25)
    }
    assert_true(build_reclaimed)
    assert_true(@fs.exists("\{spill_dir}/snippet-0/tmp"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// Escalation removes the moonrun policy before launch. If that run hands off,
/// job_output must remember the absence rather than treating similar guest text
/// as a refusal from a policy that was not present.
async test "an escalated handed-off job does not invent a policy refusal" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-escalated-job-")
    let bg_runtime = @bgjobs.BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      spill_dir~,
    )
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
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
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source, "escalated": true })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("moved to the background"))
    guard bg_runtime.list() is [job, ..] else { fail("no job registered") }
    let read = match @job_output.definition(bg_runtime).execute {
      Async(execute) => execute({ "job_id": job.id, "wait_ms": 30_000 })
      Sync(_) => fail("job_output should be async")
    }
    guard read is Respond(result) else { fail("expected Respond") }
    assert_false(result.is_error)
    assert_true(result.content.contains("Sandbox policy blocked"))
    assert_false(result.content.contains("mbtx sandbox:"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// The moonrun policy is wired only for the wasm backend. A compute-only
/// backend printing the runtime's marker is ordinary guest output, not evidence
/// of a policy that was never active.
async test "a non-wasm handed-off job does not invent a policy refusal" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-js-job-")
    let bg_runtime = @bgjobs.BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      spill_dir~,
    )
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=1,
    )
    let source =
      #|fn main {
      #|  println("Sandbox policy blocked file write: example")
      #|}
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source, "target": "js" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("moved to the background"))
    guard bg_runtime.list() is [job, ..] else { fail("no job registered") }
    let read = match @job_output.definition(bg_runtime).execute {
      Async(execute) => execute({ "job_id": job.id, "wait_ms": 30_000 })
      Sync(_) => fail("job_output should be async")
    }
    guard read is Respond(result) else { fail("expected Respond") }
    assert_false(result.is_error)
    assert_true(result.content.contains("Sandbox policy blocked"))
    assert_false(result.content.contains("mbtx sandbox:"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// The same policy-active gate applies before handoff. Whether an ordinary
/// non-wasm run crosses the grace period must not change how its output is
/// classified.
async test "a non-wasm inline run does not invent a policy refusal" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-js-inline-")
    let bg_runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir~)
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=60_000,
    )
    assert_true(mbtx.description.contains("up to 60s"))
    let action = match mbtx.execute {
      Async(execute) =>
        execute({
          "source": "fn main { println(\"Sandbox policy blocked file write: example\") }",
          "target": "js",
        })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_false(output.content.contains("moved to the background"))
    assert_true(output.content.contains("Sandbox policy blocked"))
    assert_false(output.content.contains("mbtx sandbox:"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// An automatically handed-off snippet must not inherit the engine's fd 0:
/// under `serve` that descriptor carries JSONL commands. It gets immediate EOF
/// before continuing as a job.
async test "an automatically handed-off snippet reads EOF on stdin" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-jobs-stdin-")
    let bg_runtime = @bgjobs.BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      spill_dir~,
    )
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
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
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
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
    let read = match @job_output.definition(bg_runtime).execute {
      Async(execute) => execute({ "job_id": job.id })
      Sync(_) => fail("job_output should be async")
    }
    guard read is Respond(job) else { fail("expected Respond") }
    assert_true(job.content.contains("got=false"))
    let _ = bg_runtime.stop(bg_runtime.list()[0].id)
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// A foreground run that outlives its bound is DETACHED, not killed: the shell
/// tool behaved that way, and a five-minute `moon test` that gets shot at the
/// deadline loses everything it was about to report. The bound is injected here
/// so the test does not have to outwait the real one.
async test "a foreground run past its deadline becomes a job instead of dying" {
  @async.with_task_group(group => {
    let scope = @agent_runtime.AgentTaskScope(group)
    let spill_dir = @fs.tmpdir(prefix="openseek-jobs-test-")
    let bg_runtime = @bgjobs.BgJobRuntime(scope, spill_dir~)
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  println("started")
      #|  @async.sleep(60_000)
      #|}
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    // Not an error, and not a corpse: it is a job the model can still watch.
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background as job"))
    assert_true(output.content.contains("job_output"))
    guard bg_runtime.list() is [job, ..] else { fail("no job was registered") }
    assert_true(job.status is Running)
    let _ = bg_runtime.stop(job.id)
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// Non-UTF-8 output ends the retained wait EARLY, with the child still running.
/// Reporting at that moment would leave the process alive while the deferred
/// cleanup removes its build directory, and would invent an exit code — so the
/// tool waits out the real exit and says the rendering was lossy.
async test "binary output waits for the real exit instead of abandoning it" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-binary-inline-")
    let bg_runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir~)
    // This test is about waiting for the real exit, not the production 5s
    // handoff threshold. Keep cold dependency builds safely inside its premise.
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
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
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    // The real exit code, not the -1 an abandoned execution would report.
    assert_true(output.content.contains("exited 3"))
    assert_true(output.content.contains("non-UTF-8"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// The foreground output cap is fixed, so the failure must prevent a useless
/// identical retry and point directly at the file-redirection escape hatch.
/// Inline cleanup removes the snippet temp dir before the next tool call, so
/// the recovery must also say to read the reduced result inside that snippet.
async test "the inline output cap gives actionable retry guidance" {
  @async.with_task_group(group => {
    let spill_dir = @fs.tmpdir(prefix="openseek-inline-cap-")
    let bg_runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group), spill_dir~)
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=60_000,
    )
    let action = match mbtx.execute {
      Async(execute) =>
        execute({
          "source": "fn main { for _ in 0..<50_000 { println(\"x\") } }",
        })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("fixed 48000-byte inline limit"))
    assert_true(output.content.contains("Retrying the same call"))
    assert_true(output.content.contains("stdout=ToFile(path)"))
    assert_true(output.content.contains("same snippet read the file"))
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
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
    let scope = @agent_runtime.AgentTaskScope(group)
    let spill_dir = @fs.tmpdir(prefix="openseek-jobs-binary-")
    let bg_runtime = @bgjobs.BgJobRuntime(scope, spill_dir~)
    let mbtx = @mbtx.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      auto_background_after_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  @stdio.stdout.write(b"\xff\xfe")
      #|  @async.sleep(60_000)
      #|}
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("moved to the background as job"))
    guard bg_runtime.list() is [job, ..] else { fail("no job was registered") }
    let _ = bg_runtime.stop(job.id)
    @fs.rmdir(spill_dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
/// An automatic handoff still queues a completion notice and wakes an idle
/// controller when the adopted process exits.
async test "a finished background job queues a notice and wakes the controller" {
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime()
    let mut woke = false
    // Exercise the production registry wiring itself. Reproducing its
    // queue-steer + wake callback here would let that wiring regress while the
    // test continued to pass against its copy.
    let tools = build_tools(runtime, AgentTaskScope(group), on_background_wake=() => {
      woke = true
    })
    guard tools.find("mbtx") is Some(mbtx) else { fail("mbtx tool missing") }
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  @async.sleep(5_500)
      #|  println(1)
      #|}
    let action = match mbtx.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else {
      fail("expected the run to hand off")
    }
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background"))
    // The job exits on its own → on_job_exit wakes the controller and queues a
    // completion notice. The budget is generous because the job compiles the
    // snippet before running it, on a machine that may be running the rest of
    // the suite in parallel; the loop leaves as soon as the wake lands.
    for _ in 0..<2400 {
      if woke {
        break
      }
      @async.sleep(25)
    }
    assert_true(woke)
    let steers = runtime.drain_steers()
    assert_true(steers.any(s => s is Notice(_)))
  })
}

///|
/// A turn built by `run_turn_with_append` offers `escalated` only when the
/// caller hands it a channel — which is the plumbing best-of-N runs were
/// missing. `openseek run --concurrency N --approval always` parsed the flag,
/// discarded it, and built every attempt's runtime without one, so the
/// argument was never advertised and the option was silently inert.
///
/// The registry is what proves it: the field's presence in `mbtx`'s
/// schema is decided by the runtime's channel, so asserting on the schema
/// asserts the whole chain from this parameter down.
async test "a turn advertises escalation exactly when it is given a channel" {
  @async.with_task_group(group => {
    let confined = build_tools(AgentRuntime(), AgentTaskScope(group))
    guard confined.find("mbtx") is Some(tool) else { fail("mbtx tool missing") }
    let JsonSchema(schema) = tool.schema
    guard schema is { "properties": Object(properties), .. } else {
      fail("expected an object schema")
    }
    assert_false(properties.contains("escalated"))
    let asking = build_tools(
      AgentRuntime(approval=ApprovalChannel(_ => Rejected)),
      AgentTaskScope(group),
    )
    guard asking.find("mbtx") is Some(tool) else { fail("mbtx tool missing") }
    let JsonSchema(schema) = tool.schema
    guard schema is { "properties": Object(properties), .. } else {
      fail("expected an object schema")
    }
    assert_true(properties.contains("escalated"))
  })
}
