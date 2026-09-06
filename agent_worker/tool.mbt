// `worker_system_prompt()` — the confined write-capable worker's system
// prompt — is generated from `worker_system_prompt.mbt.md` by the
// `md_to_mbt_string` dev_build rule (see moon.pkg). Edit the markdown, not
// the generated `.mbt`.

///|
/// Step ceiling requested for one worker child. Sized from real sweep
/// workloads, not the scout's Q&A profile: an edit+verify worker spends
/// 2-3 steps per fix cluster, and package-sized slices complete at ~80-100
/// steps — the old ceiling of 100 truncated the overflow tail in two
/// consecutive production sweeps. 300 is ~3x the observed completion
/// envelope; the wall deadline below is the hang guard, and the prompt's
/// answer-early rule is what bounds real cost.
pub let default_worker_max_steps : Int = 300

///|
/// Wall deadline for one worker child. Observed sweep pace is ~6-8s/step,
/// so the step ceiling above spends at most ~30-40 minutes of steady
/// progress; 45 minutes keeps the deadline from truncating a worker the
/// step ceiling would allow, while still cutting off a hung child.
pub let default_worker_deadline_ms : Int = 2_700_000

///|
/// The geometry and work order a worker child receives from the worker
/// controller (`agent_workflow`), decoded from the `subrun worker` input line. Every path is
/// canonical (the controller realpaths at provision time) — the child does
/// not re-derive geometry, it enforces with what it was handed.
pub struct WorkerInput {
  priv task : String
  priv context : String?
  priv worker_root : String
  priv worker_admin_dir : String
  priv deny_roots : Array[String]
  allowed_paths : Array[String]
  priv base_oid : String
} derive(Debug, Eq)

///|
/// Decode and validate the input line. `Err` names the defect — the child
/// dispatch surfaces it as a command error rather than running unconfined.
pub fn WorkerInput::parse(input : Json) -> Result[WorkerInput, String] {
  guard input is { "task": String(task), .. } && !task.is_blank() else {
    return Err("worker input requires a non-empty `task`")
  }
  let context : String? = match input {
    { "context": String(context), .. } if !context.is_blank() => Some(context)
    _ => None
  }
  guard input is { "worker_root": String(worker_root), .. } &&
    @path.Path(worker_root).is_absolute() else {
    return Err("worker input requires an absolute `worker_root`")
  }
  guard input is { "worker_admin_dir": String(worker_admin_dir), .. } &&
    @path.Path(worker_admin_dir).is_absolute() else {
    return Err("worker input requires an absolute `worker_admin_dir`")
  }
  guard input is { "base_oid": String(base_oid), .. } && !base_oid.is_blank() else {
    return Err("worker input requires a non-empty `base_oid`")
  }
  let deny_roots : Array[String] = []
  guard input is { "deny_roots": Array(roots), .. } && !roots.is_empty() else {
    return Err("worker input requires a non-empty `deny_roots` array")
  }
  for root in roots {
    guard root is String(root) && @path.Path(root).is_absolute() else {
      return Err("worker input deny_roots must be absolute paths")
    }
    deny_roots.push(root)
  }
  let allowed_paths : Array[String] = []
  guard input is { "allowed_paths": Array(prefixes), .. } &&
    !prefixes.is_empty() else {
    return Err("worker input requires a non-empty `allowed_paths` array")
  }
  for prefix in prefixes {
    guard prefix is String(prefix) && !prefix.is_blank() else {
      return Err("worker input allowed_paths must be non-empty strings")
    }
    allowed_paths.push(prefix)
  }
  Ok({
    task,
    context,
    worker_root,
    worker_admin_dir,
    deny_roots,
    allowed_paths,
    base_oid,
  })
}

///|
/// The child's task text: the work order, its boundaries, and the base it
/// forked from — everything the worker needs to stay honest about scope.
fn worker_task(input : WorkerInput) -> String {
  let out = StringBuilder()
  out <+ "Your assigned slice of work:\n\n\{input.task}\n"
  if input.context is Some(context) {
    out <+ "\nContext from the delegating agent:\n\{context}\n"
  }
  out <+ "\nYour worktree (your whole writable world): \{input.worker_root}\n"
  out <+
    "Allowed paths (relative to the worktree; the file tools enforce these):\n"
  for prefix in input.allowed_paths {
    out <+ "- \{prefix}\n"
  }
  out <+
    "\nYou forked from commit \{input.base_oid}. Do not commit — the harness commits and merges validated changes after you submit_result.\n"
  out.to_string()
}

///|
/// The CHILD-side entry for `openseek subrun worker`: decode the input
/// line, assemble the confined toolset, run the worker's turn in this
/// process, and return the report (the dispatch prints it as the final
/// `subrun_report` line). `Err` for malformed input — the child must never
/// run unconfined; `Ok(None)` when the child finished without a valid
/// submission.
pub async fn run_child(
  input : Json,
  api_key~ : String,
  model~ : @deepseek.Model,
  max_steps~ : Int,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  session_id? : String = "worker",
  append_item? : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
) -> Result[WorkerReport?, String] {
  let input = match WorkerInput::parse(input) {
    Ok(input) => input
    Err(reason) => return Err(reason)
  }
  let write_scope = match
    @write_scope.WriteScope::create(
      root=input.worker_root,
      allowed_paths=input.allowed_paths,
    ) {
    Ok(scope) => scope
    Err(reason) => return Err(reason)
  }
  let worker_sandbox : @mbtx.WorkerSandbox = {
    deny_roots: input.deny_roots,
    worker_root: input.worker_root,
    worker_admin_dir: input.worker_admin_dir,
  }
  // One provenance map across every file tool, as the main registry wires
  // it: remove's created-only gate and edit's rebind detection only work
  // when all four tools share the record.
  let file_state = @agent_tool.FileStateMap()
  let report = @agent_kind.execute_kind(
    session_id~,
    append_item?,
    system_prompt=worker_system_prompt(),
    task=worker_task(input),
    tools=captured => {
      Tools([
        @read.definition(workspace_root=input.worker_root),
        @mbtx.definition(workspace_root=input.worker_root, worker_sandbox~),
        @edit.definition(
          workspace_root=input.worker_root,
          file_state~,
          write_scope~,
        ),
        @multi_edit.definition(
          workspace_root=input.worker_root,
          file_state~,
          write_scope~,
        ),
        @write.definition(
          workspace_root=input.worker_root,
          file_state~,
          write_scope~,
        ),
        @remove.definition(
          workspace_root=input.worker_root,
          file_state~,
          write_scope~,
        ),
        submit_result_tool(captured),
      ])
    },
    max_steps~,
    api_key~,
    model~,
    thinking~,
    api_url?,
    workspace_root=input.worker_root,
  )
  Ok(report)
}

///|
pub extend WorkerInput with Debug::{to_repr}

///|
pub extend WorkerInput with Eq::{equal, not_equal}
