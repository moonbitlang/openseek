///|
/// The full openseek runner: read-only kinds fan out through the plain
/// subrun adapter, and `kind="worker"` becomes a write-capable SLICE —
/// provision a confined git worktree, run the child inside it, then
/// CAPTURE the outcome from git evidence (never from the child's claims)
/// on a branch the caller integrates.
///
/// A worker call's `input` is the LOGICAL slice — {name, task,
/// allowed_paths, context?} — which is therefore also its journal replay
/// identity. The physical worktree paths are provisioned fresh on every
/// launch and never leak into the identity. A resumed workflow serves a
/// journalled slice only after VALIDATING it against the live registry
/// (same name, branch, commit, still `Committed`): an outcome whose
/// branch was since integrated, discarded, or rebuilt runs live instead
/// of lying.
///
/// At most `max_workers` slices run at once (the engine's own cap is 4);
/// this gate is per-runner and nests inside the workflow's
/// `max_concurrent`.
pub fn openseek_runner(
  exe~ : String,
  workspace_root~ : String,
  model? : String,
  api_url? : String,
  deadline_ms? : Int,
  max_workers? : Int = 4,
  extra_env? : Map[String, String],
  map_launch? : (@spawn.LaunchSpec, @workflow.AgentCall) -> @spawn.LaunchSpec,
) -> @workflow.Runner raise {
  guard max_workers >= 1 else {
    fail("openseek_runner: max_workers must be at least 1")
  }
  let scouts = subrun_runner(
    exe~,
    model?,
    api_url?,
    workspace_root~,
    deadline_ms?,
    extra_env?,
    map_launch?,
  )
  let worker_slots : @async.Semaphore = Semaphore(max_workers)
  @workflow.Runner(
    call => {
      if call.kind == "worker" {
        worker_slots.acquire()
        defer worker_slots.release()
        run_worker_slice(
          call, exe, model, api_url, workspace_root, deadline_ms, extra_env, map_launch,
        )
      } else {
        scouts.invoke(call)
      }
    },
    validate_replay=(call, outcome) => {
      validate_worker_replay(workspace_root, call, outcome)
    },
  )
}

///|
/// Launch ONE write-capable slice through the workflow: a confined worker
/// in its own git worktree, limited to `allowed_paths` (repo-relative
/// prefixes, DISJOINT across live slices — provisioning refuses
/// overlaps). Returns the slice outcome: its state, branch, commit, git
/// evidence, and the child's validated report. Success means the child
/// COMPLETED (a `Captured` terminal with a validated report) AND git
/// evidence shows `Committed`, or a clean `NoChanges` no-op the report
/// did not disclaim. Anything else raises `AgentFailed`; a salvaged
/// commit from a truncated child stays in the registry (see `slices`) but
/// never masquerades as completion. Integrate one committed slice at a
/// time via `integrate_slice`.
pub async fn worker(
  wf : @workflow.Workflow,
  name~ : String,
  task~ : String,
  allowed_paths~ : Array[String],
  context? : String,
  max_steps? : Int,
) -> Json {
  let input : Json = match context {
    Some(context) =>
      {
        "name": name,
        "task": task,
        "allowed_paths": Json(allowed_paths),
        "context": context,
      }
    None => { "name": name, "task": task, "allowed_paths": Json(allowed_paths) }
  }
  wf.agent_call(kind="worker", input~, label=name, max_steps?)
}

///|
/// `worker` with workflow-level failures folded into the return value —
/// the fan-out shape, mirroring `try_agent`.
pub async fn try_worker(
  wf : @workflow.Workflow,
  name~ : String,
  task~ : String,
  allowed_paths~ : Array[String],
  context? : String,
  max_steps? : Int,
) -> Result[Json, @workflow.WorkflowError] {
  Ok(worker(wf, name~, task~, allowed_paths~, context?, max_steps?)) catch {
    @workflow.AgentFailed(..) as err => Err(err)
    @workflow.CallBudgetExhausted(..) as err => Err(err)
    @workflow.QuorumNotReached(..) as err => Err(err)
    error => raise error
  }
}

///|
/// One worker slice, provisioned → run → captured. Refusals before the
/// child existed (bad input, provisioning) carry `attempt=None`; once the
/// child ran, its terminal AND git evidence TOGETHER decide success — a
/// child that died cannot become a success just because the tree is
/// clean, and a clean no-op the child itself reported as `failed` is a
/// failure too.
async fn run_worker_slice(
  call : @workflow.AgentCall,
  exe : String,
  model : String?,
  api_url : String?,
  workspace_root : String,
  deadline_ms : Int?,
  extra_env : Map[String, String]?,
  map_launch : ((@spawn.LaunchSpec, @workflow.AgentCall) -> @spawn.LaunchSpec)?,
) -> @workflow.AgentOutcome {
  guard call.input
    is {
      "name": String(name),
      "task": String(task),
      "allowed_paths": Array(path_values),
      ..
    } else {
    return DidNotFinish(
      failure=Failed(
        "worker input requires name, task, and allowed_paths — use @agent_workflow.worker",
      ),
      attempt=None,
    )
  }
  // Reject up front what the child would reject after spawning: the
  // refusal must carry attempt=None, not a clean-tree pseudo-success.
  guard !task.is_blank() else {
    return DidNotFinish(
      failure=Failed("worker task must not be blank"),
      attempt=None,
    )
  }
  let allowed_paths : Array[String] = []
  for value in path_values {
    guard value is String(path) else {
      return DidNotFinish(
        failure=Failed("worker allowed_paths must be strings"),
        attempt=None,
      )
    }
    allowed_paths.push(path)
  }
  guard allowed_paths.length() > 0 else {
    return DidNotFinish(
      failure=Failed("worker allowed_paths must not be empty"),
      attempt=None,
    )
  }
  let context : String? = match call.input {
    { "context": String(context), .. } => Some(context)
    _ => None
  }
  // Provision the confined worktree; a refusal here never spawned a child.
  let provisioned = match
    @agent_subtask.provision(
      workspace_root,
      name~,
      allowed_paths~,
      nonce=worker_nonce(),
    ) {
    Ok(provisioned) => provisioned
    Err(reason) =>
      return DidNotFinish(
        failure=Failed("provision \{name}: \{reason}"),
        attempt=None,
      )
  }
  let entry = provisioned.entry
  let geometry = provisioned.geometry
  // The child input mirrors the engine's own worker launcher: the
  // pre-worktree geometry supplies the deny roots (the worker's own root
  // is naturally absent from a list resolved before it existed).
  let child_input : Json = match context {
    Some(context) =>
      {
        "task": task,
        "context": context,
        "worker_root": entry.worker_root,
        "worker_admin_dir": entry.worker_admin_dir,
        "deny_roots": Json(geometry.worker_deny_roots()),
        "allowed_paths": Json(entry.allowed_paths),
        "base_oid": entry.base_oid,
      }
    None =>
      {
        "task": task,
        "worker_root": entry.worker_root,
        "worker_admin_dir": entry.worker_admin_dir,
        "deny_roots": Json(geometry.worker_deny_roots()),
        "allowed_paths": Json(entry.allowed_paths),
        "base_oid": entry.base_oid,
      }
  }
  let canonical : @spawn.LaunchSpec = {
    command: exe,
    args: subrun_args(call, model, api_url),
    cwd: Some(entry.worker_root),
    extra_env,
    deadline_ms: Some(deadline_ms.unwrap_or(default_deadline_ms("worker"))),
  }
  let spec = match map_launch {
    Some(map_launch) => map_launch(canonical, call)
    None => canonical
  }
  let result = @agent_subrun.run_subrun(
    command=spec.command,
    args=spec.args,
    input=child_input,
    // The same trust-boundary re-check the engine's launcher applies: a
    // garbled report is a Failed terminal, never presented as a report.
    parse_report=@agent_worker.WorkerReport::parse_validated,
    wall_deadline_ms=spec.deadline_ms.unwrap_or(default_deadline_ms("worker")),
    kind="worker",
    label=call.label,
    cwd?=spec.cwd,
    extra_env?=spec.extra_env,
  )
  let attempt : @workflow.AgentAttempt = {
    attempt_id: result.subrun_id(),
    steps_used: result.steps_used(),
    prompt_tokens: result.prompt_tokens(),
    completion_tokens: result.completion_tokens(),
    cost_usd: result.cost_usd(),
  }
  // Evidence comes from git regardless of how the child ended: a
  // truncated child's mergeable edits still commit — as SALVAGE in the
  // registry, not as workflow success.
  let captured = @agent_subtask.capture(geometry, entry)
  let value : Json = {
    "name": name,
    "state": Json(captured.entry.state),
    "branch": captured.entry.branch,
    // Bare string-or-null, not Option's array encoding: this value is
    // read by workflow scripts pattern-matching plain JSON.
    "commit_oid": match captured.entry.commit_oid {
      Some(oid) => Json::string(oid)
      None => Json::null()
    },
    "worker_root": entry.worker_root,
    "report": match result.value() {
      Some(report) => Json(report)
      None => Json::null()
    },
    "evidence": Json(captured.evidence),
    "defects": Json(captured.defects),
  }
  guard result.terminal() is Captured && result.value() is Some(report) else {
    // The child did not complete. When git salvaged a mergeable commit,
    // the failure SAYS so — worth trading the typed terminal for it: the
    // salvage is the actionable fact, and hiding it behind `TimedOut`
    // would leave a committed branch invisible to the workflow. With no
    // salvage, the typed terminal survives untouched.
    let failure : @workflow.AgentFailure = if captured.entry.state is Committed {
      let commit = match captured.entry.commit_oid {
        Some(oid) => " \{oid}"
        None => ""
      }
      Failed(
        "worker \{terminal_word(result.terminal())}, but a salvaged commit\{commit} remains on \{captured.entry.branch} — continue or discard via slices()",
      )
    } else {
      match result.terminal() {
        NoReport => NoReport
        MaxSteps => MaxSteps
        ContextYield => ContextYield
        TimedOut => TimedOut
        Failed(reason) => Failed(reason)
        Captured => Failed("captured terminal without a validated report")
      }
    }
    return DidNotFinish(failure~, attempt=Some(attempt))
  }
  match captured.entry.state {
    Committed => Finished(value~, attempt~)
    // A clean no-op counts only if the child itself did not disclaim it.
    NoChanges =>
      if report.status == "failed" {
        DidNotFinish(
          failure=Failed(
            "worker reported failure with no mergeable changes: \{report.summary}",
          ),
          attempt=Some(attempt),
        )
      } else {
        Finished(value~, attempt~)
      }
    state => {
      let defects = captured.defects.join("; ")
      DidNotFinish(
        failure=Failed(
          "slice \{name} not mergeable (\{Json(state).stringify()}): \{defects}",
        ),
        attempt=Some(attempt),
      )
    }
  }
}

///|
/// The replay veto for stateful worker outcomes: a journalled `Committed`
/// slice is served only while the live registry still shows that SAME
/// slice — name, branch, and commit, still in `Committed` — in THIS
/// workspace. Anything else (integrated, discarded, rebuilt, or a
/// different repository) runs live. Pure-value outcomes (scout reports,
/// `NoChanges`) always replay.
async fn validate_worker_replay(
  workspace_root : String,
  call : @workflow.AgentCall,
  outcome : @workflow.AgentOutcome,
) -> @workflow.ReplayDecision {
  guard call.kind == "worker" else { return Serve(outcome) }
  // Journalled failures never replay anyway; only successes need a veto.
  guard outcome is Finished(value~, ..) else { return Serve(outcome) }
  guard value
    is {
      "state": String(state),
      "name": String(name),
      "branch": String(branch),
      ..
    } else {
    return Rerun
  }
  if state == "NoChanges" {
    return Serve(outcome)
  }
  guard state == "Committed" else { return Rerun }
  let commit : String? = match value {
    { "commit_oid": String(oid), .. } => Some(oid)
    _ => None
  }
  guard @agent_subtask.resolve_geometry(workspace_root) is Ok(geometry) else {
    return Rerun
  }
  let (entries, _) = @agent_subtask.load_entries(geometry.common_git_dir)
  for entry in entries {
    if entry.name == name &&
      entry.branch == branch &&
      entry.state is Committed &&
      entry.commit_oid == commit &&
      // Worktree siblings share the registry: bind the replay to THIS
      // checkout with the same exact-path predicate integration uses —
      // a lexical prefix would accept /repo-copy for /repo.
      geometry.is_integration_target_for(entry) {
      return Serve(outcome)
    }
  }
  Rerun
}

///|
/// The wire word for a terminal, for salvage messages.
fn terminal_word(terminal : @agent_subrun.SubrunTerminal) -> String {
  match terminal {
    Captured => "captured"
    NoReport => "exited without a report"
    MaxSteps => "exhausted its steps"
    ContextYield => "yielded at its context ceiling"
    TimedOut => "timed out"
    Failed(reason) => "failed (\{reason})"
  }
}

///|
/// Every slice the registry knows for this workspace, each with its
/// lifecycle state — including terminal generations.
pub async fn slices(
  workspace_root~ : String,
) -> Result[Array[@agent_subtask.SubtaskEntry], String] {
  match @agent_subtask.resolve_geometry(workspace_root) {
    Ok(geometry) => {
      let (entries, _) = @agent_subtask.load_entries(geometry.common_git_dir)
      Ok(entries)
    }
    Err(reason) => Err(reason)
  }
}

///|
/// Merge one committed slice's branch into the workspace. Run checks
/// after each integration; on a conflict the outcome says so and the
/// caller resolves then calls `@agent_subtask.integrate_continue`.
pub async fn integrate_slice(
  workspace_root~ : String,
  name~ : String,
) -> Result[@agent_subtask.IntegrateOutcome, String] {
  with_slice(workspace_root, name, (geometry, entry) => {
    @agent_subtask.integrate(geometry, entry)
  })
}

///|
/// Abandon one ACTIVE slice: free its paths and drop its worktree.
pub async fn discard_slice(
  workspace_root~ : String,
  name~ : String,
) -> Result[Unit, String] {
  match
    with_slice(workspace_root, name, (geometry, entry) => {
      @agent_subtask.discard(geometry, entry)
    }) {
    Ok(result) => result
    Err(reason) => Err(reason)
  }
}

///|
/// Resolve a name to its ONE active slice. Names are reusable across
/// generations (a terminal entry frees its name), so lifecycle operations
/// bind to the single non-terminal match and refuse ambiguity — acting on
/// a stale generation by name could destroy a newer worker's worktree.
async fn[T] with_slice(
  workspace_root : String,
  name : String,
  action : async (@agent_subtask.Geometry, @agent_subtask.SubtaskEntry) -> T,
) -> Result[T, String] {
  guard @agent_subtask.resolve_geometry(workspace_root) is Ok(geometry) else {
    return Err("not inside a git workspace: \{workspace_root}")
  }
  let (entries, _) = @agent_subtask.load_entries(geometry.common_git_dir)
  let active = entries.filter(entry => {
    entry.name == name && !entry.state.is_terminal()
  })
  match active {
    [entry] => Ok(action(geometry, entry))
    [] => Err("no active slice named \{name} in this workspace's registry")
    _ =>
      Err(
        "\{active.length()} active slices named \{name} — refuse to guess; inspect slices() and act on the registry directly",
      )
  }
}

///|
/// A collision-resistant nonce for worktree/branch naming, minted from
/// the OS's own unique-tempdir generator (no ambient randomness needed).
async fn worker_nonce() -> String {
  let prefix = "openseek-wf-nonce-"
  let dir = @fs.tmpdir(prefix~) catch { _ => return "n0" }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  guard dir.rev_split_once(prefix) is Some((_, suffix)) else { return "n0" }
  let salt = StringBuilder()
  for ch in suffix {
    if ch is ('0'..='9' | 'a'..='z' | 'A'..='Z') {
      salt.write_char(ch)
    }
  }
  let salt = salt.to_string()
  if salt.is_empty() {
    "n0"
  } else {
    salt
  }
}
