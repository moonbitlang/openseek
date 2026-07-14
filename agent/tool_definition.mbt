///|
/// The completion notice pushed to the model when a background job exits: its
/// id, terminal status, command, and how to read its output.
#cfg(not(platform="windows"))
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
  "background job \{snapshot.id} finished (\{status}): `\{snapshot.command}` — read its output with shell_output (job_id=\"\{snapshot.id}\")."
}

///|
/// The shell tool family for the standard registry.
///
/// Off Windows: the shell tool wired to a session `BgJobRuntime` (background
/// jobs, detach-on-timeout, push-completion notices) plus `shell_output` and
/// `shell_stop`. The runtime spills large job output into a session temp dir
/// (removed at scope teardown) and pushes a `Notice` steer + the
/// `on_background_wake` poke when a job exits on its own.
#cfg(not(platform="windows"))
async fn[X] shell_tools(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
  on_background_wake? : () -> Unit,
) -> Array[@agent_tool.AgentToolDefinition] {
  // One background-job runtime per session, owned by `scope.group()`, shared by
  // the shell tools so a job started via `run_in_background` (or a command moved
  // to the background on timeout) is visible to shell_output / shell_stop. A
  // session temp dir makes large background-job output file-backed (full output
  // on disk via the sink); a tmpdir failure degrades to memory-only jobs.
  let spill_dir : String? = Some(@fs.tmpdir(prefix="openseek-shell-")) catch {
    _ => None
  }
  // Remove the session spill dir (and every job's spill file in it) when the
  // owning scope ends, so `/tmp/openseek-shell-*` cannot accumulate across turns
  // or sessions. A task parks on a never-fed queue until group teardown cancels
  // it, then removes the dir shielded from that cancellation (rmdir is async, so
  // it cannot run in a `defer`).
  if spill_dir is Some(dir) {
    scope.group().spawn_bg(no_wait=true, allow_failure=true) <| () => {
      let parked : @async.Queue[Unit] = Queue(kind=Unbounded)
      try parked.get() |> ignore catch {
        _ =>
          @async.protect_from_cancel(() => {
            @fs.rmdir(dir, recursive=true) catch {
              _ => ()
            }
          })
      }
    }
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
  [
    @shell.definition(workspace_root=runtime.workspace_root(), bg_runtime~),
    @shell_output.definition(bg_runtime),
    @shell_stop.definition(bg_runtime),
  ]
}

///|
/// Windows graceful fallback: background jobs are unverified there (no Windows
/// CI, and detached long-lived processes / hard-cancel semantics have never been
/// exercised), so the registry keeps the pre-series shell — the per-call
/// collection path, where a timed-out command is cancelled and reported as a
/// tool error. With no runtime wired, the shell tool's schema and description
/// automatically omit `run_in_background` and state the kill-on-timeout
/// semantics, so the model is never taught a workflow the platform does not
/// deliver. Enabling Windows later is this one function: build the runtime here
/// once background jobs have been exercised on Windows.
#cfg(platform="windows")
async fn[X] shell_tools(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
  on_background_wake? : () -> Unit,
) -> Array[@agent_tool.AgentToolDefinition] {
  ignore(scope)
  ignore(on_background_wake)
  [@shell.definition(workspace_root=runtime.workspace_root())]
}

///|
/// Build the agent's standard tool registry bound to `runtime` and `scope`.
///
/// The returned registry contains the built-in local tools: `shell` (plus
/// `shell_output` and `shell_stop` where background jobs are supported — see
/// `shell_tools`), `read`, `edit`, `multi_edit`, `write`, `remove`, `plan`, and
/// `finish`.
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
  Tools(
    shell_tools(runtime, scope, on_background_wake?) +
    [
      @read.definition(workspace_root~),
      @edit.definition(workspace_root~, file_state~),
      @multi_edit.definition(workspace_root~, file_state~),
      @write.definition(workspace_root~, file_state~),
      @remove.definition(workspace_root~, file_state~),
      @plan.definition(),
      @goal.definition(),
      @finish.definition(),
    ] +
    extra_tools,
  )
}

///|
#cfg(not(platform="windows"))
async test "agent registers the expected tool names" {
  @async.with_task_group() <| group => {
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    let function_tools = tools.function_tools()
    assert_eq(function_tools.length(), 11)
    let names = [ for t in function_tools => t.name ]
    assert_true(names.contains("shell"))
    assert_true(names.contains("shell_output"))
    assert_true(names.contains("shell_stop"))
    assert_true(names.contains("read"))
    assert_true(names.contains("edit"))
    assert_true(names.contains("multi_edit"))
    assert_true(names.contains("write"))
    assert_true(names.contains("remove"))
    assert_true(names.contains("plan"))
    assert_true(names.contains("goal"))
    assert_true(names.contains("finish"))
    assert_false(names.contains("moon_check"))
    assert_false(names.contains("moon_cmd"))
    assert_false(names.contains("moon_ide"))
  }
}

///|
/// Windows keeps the pre-series shell (no background jobs — see `shell_tools`),
/// so the registry omits shell_output/shell_stop and the shell tool itself must
/// not advertise `run_in_background`.
#cfg(platform="windows")
async test "agent registers the expected tool names on windows" {
  @async.with_task_group() <| group => {
    let tools = build_tools(AgentRuntime(), AgentTaskScope(group))
    let function_tools = tools.function_tools()
    assert_eq(function_tools.length(), 9)
    let names = [ for t in function_tools => t.name ]
    assert_true(names.contains("shell"))
    assert_false(names.contains("shell_output"))
    assert_false(names.contains("shell_stop"))
    assert_true(names.contains("read"))
    assert_true(names.contains("edit"))
    assert_true(names.contains("multi_edit"))
    assert_true(names.contains("write"))
    assert_true(names.contains("remove"))
    assert_true(names.contains("plan"))
    assert_true(names.contains("goal"))
    assert_true(names.contains("finish"))
    guard tools.find("shell") is Some(shell) else { fail("shell tool missing") }
    assert_false(shell.description.contains("run_in_background"))
  }
}

///|
#cfg(not(platform="windows"))
async test "a finished background job queues a notice and wakes the controller" {
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime()
    let mut woke = false
    let tools = build_tools(runtime, AgentTaskScope(group), on_background_wake=() => {
      woke = true
    })
    guard tools.find("shell") is Some(shell) else { fail("shell tool missing") }
    // Start a fast background job through the shell tool.
    let action = match shell.execute {
      Async(execute) => execute({ "cmd": "true", "run_in_background": true })
      Sync(_) => fail("shell should be async")
    }
    guard action is Respond(_) else { fail("expected the job to start") }
    // The job exits on its own → on_job_exit wakes the controller and queues a
    // completion notice.
    for _ in 0..<200 {
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
