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
/// `multi_edit`, `write`, `remove`, `plan`, `goal`, `run_moonbit`, `job_output`,
/// `job_stop`, and `finish`. Commands are `run_moonbit`'s job — it compiles and
/// runs a MoonBit program that spawns processes through the shell-free
/// `bobzhang/myshell` EDSL, so there is no shell tool and no shell parsing
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
) -> @agent_tool.Tools {
  let workspace_root = runtime.workspace_root()
  // One session-scoped file-state map, shared by the file-writing tools so they
  // record which paths the agent created vs. modified this session — the record
  // `remove` reads to tell an agent-created file (safe to delete) from a
  // pre-existing one.
  let file_state = @agent_tool.FileStateMap::new()
  // One session temp dir, shared by the job runtime (which spills large job
  // output to disk) and run_moonbit (whose detached snippets outlive the call
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
  let bg_runtime = @bgjobs.BgJobRuntime::new(scope, spill_dir?, on_job_exit=snapshot => {
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
      // has somewhere to send the question. `ask_approval` is handed over as a
      // closure rather than the runtime itself, so the tool package keeps
      // knowing nothing about who answers.
      @run_moonbit.definition(
        workspace_root~,
        bg_runtime~,
        job_dir?=spill_dir,
        ask_approval?=if runtime.approval_available() {
          Some(ask => runtime.ask_approval(ask))
        } else {
          None
        },
      ),
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
    assert_true(names.contains("run_moonbit"))
    assert_true(names.contains("finish"))
    assert_false(names.contains("moon_check"))
    assert_false(names.contains("moon_cmd"))
    assert_false(names.contains("moon_ide"))
  }
}

///|
/// Commands go through `run_moonbit`, so the registry must not carry a shell
/// tool family — nor the background-job tools that only ever served it.
async test "the registry has no shell tool family" {
  @async.with_task_group() <| group => {
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    let names = [ for t in tools.function_tools() => t.name ]
    assert_false(names.contains("shell"))
    assert_false(names.contains("shell_output"))
    assert_false(names.contains("shell_stop"))
    guard tools.find("run_moonbit") is Some(run_moonbit) else {
      fail("run_moonbit tool missing")
    }
    // The command surface teaches the process EDSL rather than deferring to a
    // shell tool that is no longer there.
    assert_true(run_moonbit.description.contains("bobzhang/myshell"))
    // A job runtime is wired here, so the background argument must be OFFERED:
    // the schema is what decides whether the model can make the call at all.
    let JsonSchema(schema) = run_moonbit.schema
    guard schema is { "properties": Object(properties), .. } else {
      fail("expected an object schema")
    }
    let names = properties.keys().collect()
    assert_eq(names.length(), 5)
    for name in ["source", "target", "cwd", "warning", "run_in_background"] {
      assert_true(names.contains(name))
    }
  }
}

///|
/// A snippet that does not compile must report that HERE, not as a job the
/// model has to go read with `job_output` — and not with the throwaway temp
/// path in place of `source:LINE:COL`. The tool builds before it detaches.
async test "a background run that fails to compile reports the error inline" {
  @async.with_task_group(group => {
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    guard tools.find("run_moonbit") is Some(run_moonbit) else {
      fail("run_moonbit tool missing")
    }
    let action = match run_moonbit.execute {
      Async(execute) =>
        execute({
          "source": "fn main { let _x : Int = \"nope\" }",
          "run_in_background": true,
        })
      Sync(_) => fail("run_moonbit should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(output.content.contains("started background job"))
    assert_true(output.content.contains("did not compile"))
    // The diagnostic points at the model's own input.
    assert_true(output.content.contains("source:"))
    assert_false(output.content.contains("openseek-jobs-"))
  })
}

///|
/// A detached snippet must not inherit the engine's fd 0: under `serve` that
/// descriptor carries the JSONL commands, so a snippet reading stdin would
/// consume them. It gets an empty file (immediate EOF) like a foreground run.
async test "a background snippet reads EOF on stdin, not the engine's channel" {
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime()
    let mut woke = false
    let tools = build_tools(runtime, AgentTaskScope(group), on_background_wake=() => {
      woke = true
    })
    guard tools.find("run_moonbit") is Some(run_moonbit) else {
      fail("run_moonbit tool missing")
    }
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  let line = @stdio.stdin.read_until("\n")
      #|  @stdio.stdout.write("got=\{line is Some(_)}\n")
      #|}
    let action = match run_moonbit.execute {
      Async(execute) => execute({ "source": source, "run_in_background": true })
      Sync(_) => fail("run_moonbit should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    for _ in 0..<2400 {
      if woke {
        break
      }
      @async.sleep(25)
    }
    assert_true(woke)
    // The job read EOF rather than blocking on (or stealing from) fd 0.
    guard tools.find("job_output") is Some(job_output) else {
      fail("job_output tool missing")
    }
    guard output.content.split_once("background job ") is Some((_, rest)) else {
      fail("no job id in: \{output.content}")
    }
    guard rest.split_once(" ") is Some((job_id, _)) else {
      fail("no job id in: \{output.content}")
    }
    let read = match job_output.execute {
      Async(execute) => execute({ "job_id": job_id.to_owned() })
      Sync(_) => fail("job_output should be async")
    }
    guard read is Respond(job) else { fail("expected Respond") }
    assert_true(job.content.contains("got=false"))
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
    let bg_runtime = @bgjobs.BgJobRuntime::new(scope, spill_dir~)
    let run_moonbit = @run_moonbit.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      run_timeout_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  println("started")
      #|  @async.sleep(60_000)
      #|}
    let action = match run_moonbit.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("run_moonbit should be async")
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
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    guard tools.find("run_moonbit") is Some(run_moonbit) else {
      fail("run_moonbit tool missing")
    }
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
    let action = match run_moonbit.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("run_moonbit should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    // The real exit code, not the -1 an abandoned execution would report.
    assert_true(output.content.contains("exited 3"))
    assert_true(output.content.contains("non-UTF-8"))
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
    let bg_runtime = @bgjobs.BgJobRuntime::new(scope, spill_dir~)
    let run_moonbit = @run_moonbit.definition(
      workspace_root=".",
      bg_runtime~,
      job_dir=spill_dir,
      run_timeout_ms=1500,
    )
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  @stdio.stdout.write(b"\xff\xfe")
      #|  @async.sleep(60_000)
      #|}
    let action = match run_moonbit.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("run_moonbit should be async")
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
/// Background jobs survived the move off the shell tool: a detached
/// `run_moonbit` snippet still queues a completion notice and wakes an idle
/// controller when it exits.
async test "a finished background job queues a notice and wakes the controller" {
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime()
    let mut woke = false
    let tools = build_tools(runtime, AgentTaskScope(group), on_background_wake=() => {
      woke = true
    })
    guard tools.find("run_moonbit") is Some(run_moonbit) else {
      fail("run_moonbit tool missing")
    }
    let action = match run_moonbit.execute {
      Async(execute) =>
        execute({
          "source": "fn main { println(1) }",
          "run_in_background": true,
        })
      Sync(_) => fail("run_moonbit should be async")
    }
    guard action is Respond(output) else { fail("expected the job to start") }
    assert_false(output.is_error)
    // The job exits on its own → on_job_exit wakes the controller and queues a
    // completion notice. The budget is generous because the job compiles the
    // snippet before running it, on a machine that may be running the rest of
    // the suite in parallel; the loop leaves as soon as the wake lands, so a
    // fast machine pays none of it.
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
