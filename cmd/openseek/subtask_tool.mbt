///|
/// The parent-facing `subtask` tool: delegate ONE slice of write-capable
/// work to a confined worker subagent in its own git worktree, then
/// integrate the validated result. Launching provisions the worktree,
/// spawns `subrun worker`, and CAPTURES the outcome from git evidence
/// (never the child's claims); `integrate`/`integrate_continue`/
/// `integrate_abort`/`discard` drive the committed branch's lifecycle.
/// Lives in the CLI (like the review tool) because it needs the session's
/// self-exe, model, and durable-session plumbing.
let max_active_workers : Int = 4

///|
let worker_slots : @async.Semaphore = Semaphore(max_active_workers)

///|
/// The session plumbing every `subtask` path needs to launch a worker child:
/// how to re-exec this binary, which model and endpoint the child talks to,
/// the workspace it operates in, the parent turn's remaining subrun budget,
/// and the durable child-session seam. Threaded as one value because no path
/// picks a subset — they all forward the whole bundle.
priv struct SubtaskEnv {
  self_exe : String
  model : @deepseek.Model
  workspace_root : String
  budget : @agent_subrun.SubrunBudget
  api_url : String?
  child_session : @agent_subrun.ChildSession?
}

///|
fn subtask_tool_definition(
  self_exe~ : String,
  model~ : @deepseek.Model,
  workspace_root~ : String,
  budget~ : @agent_subrun.SubrunBudget,
  api_url? : String,
  child_session? : @agent_subrun.ChildSession,
) -> @agent_tool.AgentToolDefinition {
  let env = { self_exe, model, workspace_root, budget, api_url, child_session, }
  AgentToolDefinition(
    name="subtask",
    concurrent_safe=true,
    description=(
      #|Delegate ONE slice of write-capable work to a confined worker subagent in its own
      #|git worktree, or drive a finished slice's integration. LAUNCH: pass name (a short
      #|slug), task (the self-contained work order — the worker sees nothing else of this
      #|conversation), and allowed_paths (the repo-relative path prefixes this slice may
      #|change; partitions must be DISJOINT across active subtasks — overlapping launches
      #|are refused). The worker edits only inside its worktree and allowed paths, cannot
      #|commit, and its changes are validated against allowed_paths from git evidence and
      #|committed on a branch. Then INTEGRATE one subtask at a time: pass integrate=<name>
      #|to merge its branch here (re-run your checks after each); on a conflict, resolve
      #|the markers with the file tools, then integrate_continue=<name> (or
      #|integrate_abort=<name>); discard=<name> abandons a slice and frees its paths.
      #|CONTINUE: continue=<name> plus a fresh task (the remainder work order)
      #|relaunches a NEW worker on a truncated or NOT-mergeable slice's kept worktree;
      #|its cumulative changes are re-captured on the same branch — prefer this over
      #|finishing a truncated slice yourself.
      #|PARALLELISM: to run several slices at once, pass them as `slices`: an ARRAY of
      #|{name, task, allowed_paths, context?} objects in ONE call — they are launched
      #|concurrently and reported together (2-4 per call; at most 4 run at once). Prefer
      #|this over issuing separate calls, which the loop can only overlap when they land
      #|in the same step. Commit your own work first: workers fork this repository's HEAD.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "slices": {
          "type": "array",
          "description": "Parallel launch: several {name, task, allowed_paths, context?} slices run CONCURRENTLY from this one call (at most 4 — the worker-slot cap). Their allowed_paths must be disjoint from each other and from any active subtask.",
          "maxItems": 4,
          "items": {
            "type": "object",
            "properties": {
              "name": { "type": "string" },
              "task": { "type": "string" },
              "allowed_paths": {
                "type": "array",
                "items": { "type": "string" },
              },
              "context": { "type": "string" },
            },
            "required": ["name", "task", "allowed_paths"],
          },
        },
        "name": {
          "type": "string",
          "description": "Single launch: short lowercase slug naming the slice (becomes the branch and worktree name).",
        },
        "task": {
          "type": "string",
          "description": "Launch: the self-contained work order, incl. what to verify.",
        },
        "allowed_paths": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Launch: repo-relative path prefixes this slice may change (component-wise; disjoint from other active subtasks).",
        },
        "context": {
          "type": "string",
          "description": "Launch: optional extra pointers for the worker.",
        },
        "integrate": {
          "type": "string",
          "description": "Merge the named committed subtask's branch into this checkout.",
        },
        "integrate_continue": {
          "type": "string",
          "description": "After resolving a conflicted integration's markers: commit it.",
        },
        "integrate_abort": {
          "type": "string",
          "description": "Abort a conflicted integration; the branch and worktree survive.",
        },
        "discard": {
          "type": "string",
          "description": "Abandon the named subtask: remove its worktree and branch, free its paths.",
        },
        "continue": {
          "type": "string",
          "description": "Relaunch a fresh worker on the named slice's kept worktree to finish or repair it. Requires `task` (the remainder work order); accepts `context`. New work is captured cumulatively on the same branch.",
        },
      },
    }),
    execute=Async(arguments => subtask_execute(env, arguments)),
  )
}

///|
let max_task_chars : Int = 4_000

///|
let max_context_chars : Int = 2_000

///|
async fn subtask_execute(
  env : SubtaskEnv,
  arguments : Json,
) -> @agent_tool.ToolAction {
  // Lifecycle actions first: exactly one of them may be present.
  match arguments {
    { "continue": String(name), .. } if !name.is_blank() =>
      return subtask_continue(env, arguments, name)
    { "integrate": String(name), .. } if !name.is_blank() =>
      return subtask_lifecycle(env.workspace_root, "integrate", name)
    { "integrate_continue": String(name), .. } if !name.is_blank() =>
      return subtask_lifecycle(env.workspace_root, "integrate_continue", name)
    { "integrate_abort": String(name), .. } if !name.is_blank() =>
      return subtask_lifecycle(env.workspace_root, "integrate_abort", name)
    { "discard": String(name), .. } if !name.is_blank() =>
      return subtask_lifecycle(env.workspace_root, "discard", name)
    _ => ()
  }
  // `slices` launches several confined workers CONCURRENTLY from one call;
  // a bare name/task/allowed_paths object is the single-slice form.
  let specs : Array[LaunchSpec] = []
  match arguments {
    { "slices": Array(entries), .. } => {
      guard !entries.is_empty() else {
        return @agent_tool.respond(
          "error: subtask `slices` must not be empty",
          is_error=true,
        )
      }
      // Refuse rather than silently drop: slots are taken with
      // try_acquire, so entries past the cap would fail as "slots full"
      // while the call still looked accepted.
      guard entries.length() <= max_active_workers else {
        return @agent_tool.respond(
          "error: subtask `slices` accepts at most \{max_active_workers} slices per call (got \{entries.length()}) — send the rest in a follow-up call once these integrate",
          is_error=true,
        )
      }
      for entry in entries {
        match decode_launch(entry) {
          Ok(spec) => specs.push(spec)
          Err(reason) =>
            return @agent_tool.respond("error: \{reason}", is_error=true)
        }
      }
    }
    _ =>
      match decode_launch(arguments) {
        Ok(spec) => specs.push(spec)
        Err(reason) =>
          return @agent_tool.respond("error: \{reason}", is_error=true)
      }
  }
  subtask_launch_many(env, specs)
}

///|
async fn subtask_lifecycle(
  workspace_root : String,
  action : String,
  name : String,
) -> @agent_tool.ToolAction {
  let geometry = match @subtask.resolve_geometry(workspace_root) {
    Ok(geometry) => geometry
    Err(reason) =>
      return @agent_tool.respond(
        "error: subtask \{action}: \{reason}",
        is_error=true,
      )
  }
  let (entries, _) = @subtask.load_entries(geometry.common_git_dir)
  guard entries.filter(e => e.name == name && !e.state.is_terminal()).last()
    is Some(entry) else {
    return @agent_tool.respond(
      "error: no active subtask named \{name}",
      is_error=true,
      brief="subtask \{action} \{name}",
    )
  }
  match action {
    "discard" =>
      match @subtask.discard(geometry, entry) {
        Ok(_) =>
          @agent_tool.respond(
            "subtask \{name} discarded: worktree and branch removed, paths freed.",
            brief="subtask discarded \{name}",
          )
        Err(reason) =>
          @agent_tool.respond(
            "error: subtask discard: \{reason}",
            is_error=true,
            brief="subtask discard \{name}",
          )
      }
    _ => {
      let outcome = match action {
        "integrate" => @subtask.integrate(geometry, entry)
        "integrate_continue" => @subtask.integrate_continue(geometry, entry)
        _ => @subtask.integrate_abort(geometry, entry)
      }
      let content = "subtask \{name} \{action}: \{outcome.result}\n\{outcome.detail.join("\n")}"
      @agent_tool.respond(
        content,
        is_error=outcome.result == "refused",
        brief="subtask \{action} \{name} (\{outcome.result})",
      )
    }
  }
}

///|
/// One decoded launch request.
priv struct LaunchSpec {
  name : String
  task : String
  context : String?
  allowed_paths : Array[String]
}

///|
/// Decode one launch object (the tool's own arguments, or one element of
/// `slices`). `Err` carries the model-facing message.
fn decode_launch(spec : Json) -> Result[LaunchSpec, String] {
  guard spec is { "name": String(name), .. } && !name.is_blank() else {
    return Err(
      "subtask requires `name` (launch), `slices` (parallel launch), or one of integrate/integrate_continue/integrate_abort/discard",
    )
  }
  guard spec is { "task": String(task), .. } && !task.is_blank() else {
    return Err("subtask launch requires a non-empty `task` for \{name}")
  }
  guard task.length() <= max_task_chars else {
    return Err("subtask task for \{name} exceeds \{max_task_chars} chars")
  }
  let context : String? = match spec {
    { "context": String(context), .. } if !context.is_blank() => Some(context)
    _ => None
  }
  guard !(context is Some(c) && c.length() > max_context_chars) else {
    return Err("subtask context for \{name} exceeds \{max_context_chars} chars")
  }
  let allowed_paths : Array[String] = []
  guard spec is { "allowed_paths": Array(prefixes), .. } && !prefixes.is_empty() else {
    return Err(
      "subtask launch \{name} requires a non-empty `allowed_paths` array — the repo-relative prefixes this slice may change",
    )
  }
  for prefix in prefixes {
    guard prefix is String(prefix) && !prefix.is_blank() else {
      return Err("allowed_paths entries must be non-empty strings (\{name})")
    }
    allowed_paths.push(prefix)
  }
  Ok({ name, task, context, allowed_paths, })
}

///|
/// Launch every slice CONCURRENTLY and render one combined result. This is
/// the structural answer to a real dogfood finding: batching several
/// `subtask` calls into one assistant message parallelizes them, but that
/// is advisory — in a production sweep the model serialized 2 of 3 fan-outs
/// and paid ~2.7x the wall-clock. One call carrying N slices cannot be
/// serialized by accident.
async fn subtask_launch_many(
  env : SubtaskEnv,
  specs : Array[LaunchSpec],
) -> @agent_tool.ToolAction {
  let results : Map[Int, SliceOutcome] = Map([])
  @async.with_task_group(scope => {
    for index, spec in specs {
      scope.spawn_bg(() => results.set(index, subtask_launch_one(env, spec)))
    }
  })
  // A compact status line PER SLICE comes first: four full reports can
  // exceed the loop's per-tool-result clamp, and a truncated tail would
  // otherwise erase later slices' state and next steps entirely.
  let summary = StringBuilder()
  let detail = StringBuilder()
  let mut any_error = false
  let briefs : Array[String] = []
  for index, spec in specs {
    let (status, errored, body) = match results.get(index) {
      Some({ action: Respond(output), status, }) =>
        (status, output.is_error, "\{output.content}\n\n")
      Some({ status, .. }) => (status, false, "(no result)\n\n")
      None => ("no result", true, "(no result)\n\n")
    }
    if errored {
      any_error = true
    }
    briefs.push(spec.name)
    summary <+ "- \{spec.name}: \{status}\n"
    detail <+ "## \{spec.name}\n\{body}"
  }
  let out = StringBuilder()
  out <+
    "\{specs.length()} slice(s) launched concurrently:\n\{summary.to_string()}\n"
  out <+ "\{detail.to_string()}"
  @agent_tool.respond(
    out.to_string(),
    is_error=any_error,
    brief="subtask \{specs.length()} slices (\{briefs.join(", ")})",
  )
}

///|
/// One finished slice: its rendered result plus the AUTHORITATIVE status
/// the controller derived from git evidence — carried as data so a batch
/// summary can never re-derive it from worker-authored prose.
priv struct SliceOutcome {
  action : @agent_tool.ToolAction
  status : String
}

///|
async fn subtask_launch_one(
  env : SubtaskEnv,
  spec : LaunchSpec,
) -> SliceOutcome {
  let name = spec.name
  let task = spec.task
  let context = spec.context
  let allowed_paths = spec.allowed_paths
  // Slots and budget are reserved BEFORE any state is created, so every
  // later failure path has exactly one transaction to roll back.
  guard worker_slots.try_acquire() else {
    return {
      action: @agent_tool.respond(
        "subtask worker slots are full (max \{max_active_workers} active) — integrate or await the running slices first.",
        is_error=true,
        brief="subtask (slots full)",
      ),
      status: "not launched: worker slots full",
    }
  }
  // Sync and block-scoped: a cancellation re-raised out of run_subrun still
  // returns the permit — four interrupts must not brick launching for the
  // rest of the process. (The provisioned worktree and its Running registry
  // entry survive a cancel by design: discoverable, discard-able.)
  defer worker_slots.release()
  guard env.budget.reserve(@agent_worker.default_worker_max_steps)
    is Some(granted_steps) else {
    return {
      action: @agent_tool.respond(
        "subtask budget exhausted for this turn — do the remaining slices yourself or continue next turn.",
        is_error=true,
        brief="subtask (budget exhausted)",
      ),
      status: "not launched: per-turn subtask budget exhausted",
    }
  }
  let nonce = random_salt()
  let provisioned = match
    @subtask.provision(
      env.workspace_root,
      name~,
      allowed_paths~,
      nonce=if nonce == "" { "n0" } else { nonce },
      parent_session?=env.child_session.map(session => session.parent),
    ) {
    Ok(provisioned) => provisioned
    Err(reason) =>
      return {
        action: @agent_tool.respond(
          "error: subtask provision: \{reason}",
          is_error=true,
          brief="subtask \{name} (provision refused)",
        ),
        status: "not launched: \{@agent_tool.brief_line(reason, limit=100)}",
      }
  }
  run_worker_slice(
    env,
    provisioned.geometry,
    provisioned.entry,
    name,
    task,
    context,
    // Resolved BEFORE the worktree existed, so the worker's own root is
    // naturally absent from this deny list.
    provisioned.geometry.worker_deny_roots(),
    granted_steps,
  )
}

///|
/// Run one worker child against a provisioned or resumed slice and capture
/// the outcome from git evidence. `deny_roots` is the caller's concern:
/// launch passes the pre-worktree geometry (the worker's own root is
/// naturally absent); continue passes a fresh resolve with the slice's own
/// root filtered out.
async fn run_worker_slice(
  env : SubtaskEnv,
  geometry : @subtask.Geometry,
  entry : @subtask.SubtaskEntry,
  name : String,
  task : String,
  context : String?,
  deny_roots : Array[String],
  granted_steps : Int,
) -> SliceOutcome {
  let input : Json = match context {
    Some(context) =>
      {
        "task": task,
        "context": context,
        "worker_root": entry.worker_root,
        "worker_admin_dir": entry.worker_admin_dir,
        "deny_roots": deny_roots.to_json(),
        "allowed_paths": entry.allowed_paths.to_json(),
        "base_oid": entry.base_oid,
      }
    None =>
      {
        "task": task,
        "worker_root": entry.worker_root,
        "worker_admin_dir": entry.worker_admin_dir,
        "deny_roots": deny_roots.to_json(),
        "allowed_paths": entry.allowed_paths.to_json(),
        "base_oid": entry.base_oid,
      }
  }
  let args = subrun_args(
    "worker",
    model=env.model,
    max_steps=granted_steps,
    api_url=env.api_url,
  )
  let result = @agent_subrun.run_subrun(
    command=env.self_exe,
    args~,
    input~,
    parse_report=@agent_worker.WorkerReport::parse_validated,
    wall_deadline_ms=@agent_worker.default_worker_deadline_ms,
    kind="worker",
    label=@agent_tool.brief_line("\{name}: \{task}", limit=48),
    cwd=entry.worker_root,
    child_session?=env.child_session,
  )
  // Evidence comes from git regardless of how the child ended.
  let captured = @subtask.capture(geometry, entry)
  let out = StringBuilder()
  match result.value() {
    Some(report) =>
      out <+
        "worker report (\{report.status}): \{report.summary}\nverification: \{report.verification}\n"
    None =>
      out <+ "the worker produced no report (\{Repr(result.terminal())}).\n"
  }
  out <+ "\ngit evidence:\n"
  for line in captured.evidence {
    out <+ "- \{line}\n"
  }
  for defect in captured.defects {
    out <+ "DEFECT: \{defect}\n"
  }
  let state_line = match captured.entry.state {
    Committed =>
      "state: committed on \{entry.branch} — review the evidence, then subtask integrate=\{name}; if the task is unfinished, continue=\{name} with the remainder (worktree kept at \{entry.worker_root} until then)"
    NoChanges => "state: no changes — the slice's paths are free again"
    Captured =>
      "state: NOT mergeable (captured with defects) — inspect \{entry.worker_root}; continue=\{name} with a corrective task can repair it, or discard=\{name}"
    _ =>
      // Early capture failures leave the registry entry Running, which
      // continue refuses — only discard applies here.
      "state: NOT mergeable — inspect \{entry.worker_root}, then discard=\{name} or relaunch"
  }
  out <+ "\n\{state_line}"
  let mergeable = captured.entry.state is Committed
  let is_error = !mergeable && !(captured.entry.state is NoChanges)
  {
    action: @agent_tool.respond(
      out.to_string(),
      is_error~,
      brief="subtask \{result.subrun_id()} \{name} (\{Repr(captured.entry.state)}, \{result.steps_used()} step(s))",
    ),
    status: state_line,
  }
}

///|
/// `continue=<name>`: relaunch a fresh worker on an existing slice's kept
/// worktree — the recovery path for a worker that hit its step ceiling
/// (state Committed, task unfinished) or captured NOT-mergeable (state
/// Captured). The slice keeps its name, branch, reservation, and base; the
/// new child receives the remainder work order and capture() stacks its
/// validated changes on the same branch.
async fn subtask_continue(
  env : SubtaskEnv,
  arguments : Json,
  name : String,
) -> @agent_tool.ToolAction {
  guard arguments is { "task": String(task), .. } && !task.is_blank() else {
    return @agent_tool.respond(
      "error: subtask continue=\{name} requires a `task` — the remainder work order for the fresh worker",
      is_error=true,
      brief="subtask continue \{name}",
    )
  }
  guard task.length() <= max_task_chars else {
    return @agent_tool.respond(
      "error: subtask task for \{name} exceeds \{max_task_chars} chars",
      is_error=true,
      brief="subtask continue \{name}",
    )
  }
  let parent_context : String? = match arguments {
    { "context": String(context), .. } if !context.is_blank() => Some(context)
    _ => None
  }
  guard !(parent_context is Some(c) && c.length() > max_context_chars) else {
    return @agent_tool.respond(
      "error: subtask context for \{name} exceeds \{max_context_chars} chars",
      is_error=true,
      brief="subtask continue \{name}",
    )
  }
  let geometry = match @subtask.resolve_geometry(env.workspace_root) {
    Ok(geometry) => geometry
    Err(reason) =>
      return @agent_tool.respond(
        "error: subtask continue: \{reason}",
        is_error=true,
        brief="subtask continue \{name}",
      )
  }
  guard worker_slots.try_acquire() else {
    return @agent_tool.respond(
      "subtask worker slots are full (max \{max_active_workers} active) — integrate or await the running slices first.",
      is_error=true,
      brief="subtask continue (slots full)",
    )
  }
  defer worker_slots.release()
  guard env.budget.reserve(@agent_worker.default_worker_max_steps)
    is Some(granted_steps) else {
    return @agent_tool.respond(
      "subtask budget exhausted for this turn — do the remaining work yourself or continue next turn.",
      is_error=true,
      brief="subtask continue (budget exhausted)",
    )
  }
  let entry = match @subtask.resume_running(geometry, name) {
    Ok(entry) => entry
    Err(reason) =>
      return @agent_tool.respond(
        "error: subtask continue: \{reason}",
        is_error=true,
        brief="subtask continue \{name}",
      )
  }
  // The fresh geometry lists the slice's own worktree; the worker must not
  // be denied its own root.
  let deny_roots = geometry
    .worker_deny_roots()
    .filter(root => root != entry.worker_root)
  let preamble = "RESUMED SLICE: a previous worker already worked this slice; its validated progress is already present in your worktree files. Verify the current state first, then do only what the task still requires."
  let context = Some(
    match parent_context {
      Some(context) => "\{preamble}\n\{context}"
      None => preamble
    },
  )
  run_worker_slice(
    env, geometry, entry, name, task, context, deny_roots, granted_steps,
  ).action
}
