///|
/// The completion notice pushed to the model when a background job exits: its
/// id, terminal status, and how to read its output.
fn background_notice_text(snapshot : @bgjobs.BgJobSnapshot) -> String {
  let status = if snapshot.cleanup_error is Some(error) {
    "cleanup failed: \{error}"
  } else {
    match snapshot.status {
      Exited(code) => "exit=\{code}"
      Stopped =>
        if snapshot.output_error is Some(error) {
          "output capture failed: \{error}"
        } else if snapshot.killed_by_output_limit {
          "killed: flooded past the output cap"
        } else if snapshot.killed_by_time_limit {
          "killed: outlived the wall-clock cap"
        } else {
          "stopped"
        }
      Running => "running"
    }
  }
  let label = match snapshot.description {
    Some(description) => "\{description} · \{snapshot.command}"
    None => snapshot.command
  }
  "background job \{snapshot.id} finished (\{status}): `\{label}` — read its output with job_output (job_id=\"\{snapshot.id}\")."
}

///|
/// Build the agent's standard tool registry bound to `runtime` and `scope`.
///
/// The returned registry contains the built-in local tools: `edit`,
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
  job_log_dir? : String,
  extra_tools? : Array[@agent_tool.AgentToolDefinition] = [],
  mbtx_subrun? : @host.SubrunInjection,
) -> @agent_tool.Tools {
  let workspace_root = runtime.workspace_root()
  // One session-scoped file-state map, shared by the file-writing tools so they
  // record which paths the agent created vs. modified this session — the record
  // `remove` reads to tell an agent-created file (safe to delete) from a
  // pre-existing one.
  let file_state = @agent_tool.FileStateMap()
  // Scratch files follow the scope. Adopted job logs use separate storage so
  // removing compiler/snippet scratch space cannot remove a user's log.
  let scratch = @fs.tmpdir(prefix="openseek-jobs-") catch {
    error =>
      fail(
        "cannot create background-job scratch directory; check temporary-directory space and permissions: \{error}",
      )
  }
  scope
  .group()
  .add_defer(() => {
    @async.protect_from_cancel(() => {
      @fs.rmdir(scratch, recursive=true) catch {
        _ => ()
      }
    })
  })
  let spill_dir = match job_log_dir {
    Some(root) => {
      // tmpdir already reserved this unique runtime name. mkdir below is
      // exclusive too: an unexpected collision fails rather than overwrites.
      let normalized = scratch.replace_all(old="\\", new="/")
      let parts = normalized.split("/").to_array()
      guard parts.last() is Some(generation) else {
        fail("missing runtime directory name")
      }
      "\{root}/\{generation}"
    }
    None => scratch
  }
  // When a background job exits on its own, push a completion notice into the
  // loop's lossless steer queue (surfaced to the model at the next step, or
  // persisted while idle) and poke the controller so an idle engine wakes to
  // drain it instead of leaving it until the next prompt.
  let mut owner : @fs.File? = None
  let prepare_output_dir : (async () -> String)? = match job_log_dir {
    None => None
    Some(root) =>
      Some(() => {
        @fs.mkdir(root, recursive=true, permission=0o700) catch {
          @os_error.OSError(_) as error if error.is_EEXIST() => {
            guard @fs.kind(root) is Directory else { raise error }
          }
          error => raise error
        }
        // Exclusive creation: a collision never reuses another engine's logs.
        @fs.mkdir(spill_dir, permission=0o700)
        errdefer @async.protect_from_cancel(() => {
          @fs.rmdir(spill_dir, recursive=true) catch {
            _ => ()
          }
        })
        let canonical = @fs.realpath(spill_dir)
        let file = @fs.open(
          "\{canonical}/owner.lock",
          mode=ReadWrite,
          create_mode=CreateNew,
          permission=0o600,
        )
        errdefer file.close()
        file.lock(Exclusive)
        owner = Some(file)
        canonical
      })
  }
  let bg_runtime = @bgjobs.BgJobRuntime(
    scope,
    spill_dir~,
    persistent_logs=job_log_dir is Some(_),
    prepare_output_dir?,
    on_job_event=(kind, job) => @emit.emit(JobChanged(kind~, job~)),
    on_job_exit=snapshot => {
      runtime.queue_steer(Notice(background_notice_text(snapshot)))
      if on_background_wake is Some(wake) {
        wake()
      }
    },
  )

  scope
  .group()
  .add_defer(() => {
    defer (if owner is Some(file) { file.close() })
    @async.protect_from_cancel(() => {
      bg_runtime.finalize()
      // No adopted execution means this generation owns no retained job log.
      // Do not infer that from missing JSON: metadata persistence can fail.
      if bg_runtime.list().is_empty() && owner is Some(file) {
        file.close()
        owner = None
        try {
          if @fs.readdir(spill_dir) == ["owner.lock"] {
            @fs.remove("\{spill_dir}/owner.lock")
            @fs.rmdir(spill_dir)
          }
        } catch {
          _ => () // Best effort; never remove unexpected files recursively.
        }
      }
    })
  })
  let file_tools = [
    @edit.definition(workspace_root~, file_state~),
    @multi_edit.definition(workspace_root~, file_state~),
    @write.definition(workspace_root~, file_state~),
  ].map(tool => file_state.serialize(tool))
  // Remove owns two short locked phases, with approval outside the gate.
  file_tools.push(
    @remove.definition(
      workspace_root~,
      file_state~,
      approval?=runtime.approval_channel(),
    ),
  )
  let extras = extra_tools.map(tool => {
    if tool.is_concurrent_safe() {
      tool
    } else {
      file_state.serialize(tool)
    }
  })
  let program_tools = @agent_tool.Tools(file_tools + extras)
  let program_service = @ptc.Service::start(scope.group(), program_tools)
  let program_trace : Ref[Json?] = Ref(None)
  Tools(
    [
      ..file_tools,
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
        file_state~,
        bg_runtime~,
        job_dir=scratch,
        approval?=runtime.approval_channel(),
        subrun?=mbtx_subrun,
        program_service~,
        on_program_trace=data => program_trace.val = Some(data),
      ),
      // Deliberately NOT told about escalation. It reports a job that already
      // ran — a policy refusal reaches it after minutes of real work — and the
      // sanctioned retry is worded for a run that did not happen. Offering it
      // here would misdescribe the state the job left behind.
      @job_output.definition(bg_runtime),
      @job_stop.definition(bg_runtime),
      @job_wait.definition(),
      @finish.definition(),
      ..extras,
    ],
    background_jobs=bg_runtime,
    program_trace~,
  )
}

///|
/// Run a tool definition's async executor, failing the test when the tool was
/// registered with a synchronous one.
async fn run_async_tool(
  tool : @agent_tool.AgentToolDefinition,
  arguments : Json,
) -> @agent_tool.ToolAction {
  match tool.execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("\{tool.name} should be async")
  }
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
    let action = run_async_tool(mbtx, { "source": source })
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
