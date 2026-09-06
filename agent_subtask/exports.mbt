// Deliberate exports with no in-repo production consumer (see
// shrink_package.md). Each entry documents its reason.
//
// `integrate_continue`, `integrate_abort`, `resume_running`: the
// conflict-resolution and continue halves of the slice lifecycle. Their
// production caller, the `subtask` tool, was removed in #1320; the worker
// controller that hosted workflows will reach (a self-provisioning
// `subrun worker` plus an `integrate` child mode) needs exactly these, and
// `lifecycle_test.mbt` exercises them end to end.
//
// `git_require`: test seam — agent_workflow's worker tests drive real git
// through it to set up and inspect repositories.

///|
/// Continue a conflicted integration after the caller resolved the markers:
/// verify the in-progress merge is THIS attempt, nothing is left unmerged,
/// and the staged resolution stays inside scope ∪ the conflicted set, then
/// commit through the controller.
pub async fn integrate_continue(
  geometry : Geometry,
  entry : SubtaskEntry,
) -> IntegrateOutcome {
  let origin = geometry.origin_root
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  defer mutex.release()
  integrate_continue_locked(geometry, origin, entry)
}

///|
async fn integrate_continue_locked(
  geometry : Geometry,
  origin : String,
  entry : SubtaskEntry,
) -> IntegrateOutcome {
  let entry = reload_entry(geometry.common_git_dir, entry)
  guard geometry.is_integration_target_for(entry) else {
    return {
      entry,
      result: "refused",
      detail: [
        "subtask \{entry.name} belongs to a different worktree; continue the integration from the worktree that launched it",
      ],
    }
  }
  guard entry.state is Conflicted && entry.commit_oid is Some(commit_oid) else {
    return {
      entry,
      result: "refused",
      detail: ["subtask \{entry.name} has no conflicted integration"],
    }
  }
  let merge_head = git_run(
    ["rev-parse", "-q", "--verify", "MERGE_HEAD"],
    cwd=origin,
  )
  guard merge_head.exit_code == 0 && merge_head.output.trim() == commit_oid else {
    return {
      entry,
      result: "refused",
      detail: [
        "no merge of \{commit_oid} is in progress — the conflicted state is stale",
      ],
    }
  }
  match entry.origin_head_before {
    Some(before) =>
      match git_require(["rev-parse", "HEAD"], cwd=origin) {
        Ok(head) =>
          if head.trim() != before {
            return {
              entry,
              result: "refused",
              detail: ["origin HEAD moved during the conflicted window"],
            }
          }
        Err(reason) => return { entry, result: "refused", detail: [reason], }
      }
    None => ()
  }
  let unmerged = git_run(["ls-files", "-u", "-z"], cwd=origin)
  if unmerged.exit_code == 0 && unmerged.output != "" {
    return {
      entry,
      result: "refused",
      detail: ["unresolved conflict entries remain; resolve them all first"],
    }
  }
  // The staged resolution may only touch the slice's scope plus the
  // recorded conflict set — a stray `git add -A` must not smuggle
  // unrelated changes into the merge commit.
  let staged = git_run(
    ["diff", "--cached", "--name-status", "-z", "HEAD"],
    cwd=origin,
  )
  guard staged.exit_code == 0 else {
    return {
      entry,
      result: "refused",
      detail: ["git diff --cached failed: \{staged.output.trim()}"],
    }
  }
  let permitted = entry.allowed_paths + entry.conflict_paths
  let strays = scope_violations(
    parse_diff_name_status_z(staged.output),
    permitted,
  )
  if !strays.is_empty() {
    return {
      entry,
      result: "refused",
      detail: [
        "the staged resolution touches paths outside the slice and its conflict set: \{strays.join(", ")}; unstage them first",
      ],
    }
  }
  match
    git_require(
      [
        "-c", "core.hooksPath=/dev/null", "commit", "--no-verify", "--no-gpg-sign",
        "--no-edit",
      ],
      cwd=origin,
    ) {
    Ok(_) => ()
    Err(reason) => return { entry, result: "refused", detail: [reason], }
  }
  let entry = { ..entry, state: Integrated, }
  let _ = save_entry(geometry.common_git_dir, entry)
  remove_worktree_and_branch(origin, entry, force=false)
  { entry, result: "integrated", detail: ["conflict resolution committed"], }
}

///|
/// Abort a conflicted integration: verify ownership first, then restore
/// the pre-merge state. The subtask returns to `committed` (its branch and
/// worktree survive) — the reservation is NOT released.
pub async fn integrate_abort(
  geometry : Geometry,
  entry : SubtaskEntry,
) -> IntegrateOutcome {
  let origin = geometry.origin_root
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  defer mutex.release()
  let entry = reload_entry(geometry.common_git_dir, entry)
  guard geometry.is_integration_target_for(entry) else {
    return {
      entry,
      result: "refused",
      detail: [
        "subtask \{entry.name} belongs to a different worktree; abort the integration from the worktree that launched it",
      ],
    }
  }
  guard entry.state is Conflicted && entry.commit_oid is Some(commit_oid) else {
    return {
      entry,
      result: "refused",
      detail: ["subtask \{entry.name} has no conflicted integration"],
    }
  }
  let merge_head = git_run(
    ["rev-parse", "-q", "--verify", "MERGE_HEAD"],
    cwd=origin,
  )
  guard merge_head.exit_code == 0 && merge_head.output.trim() == commit_oid else {
    return {
      entry,
      result: "refused",
      detail: ["no merge of \{commit_oid} is in progress"],
    }
  }
  match git_require(["merge", "--abort"], cwd=origin) {
    Ok(_) => ()
    Err(reason) => return { entry, result: "refused", detail: [reason], }
  }
  let entry = { ..entry, state: Committed, }
  let _ = save_entry(geometry.common_git_dir, entry)
  {
    entry,
    result: "aborted",
    detail: ["merge aborted; the branch and worktree remain"],
  }
}

///|
/// Flip the active slice `name` back to Running for a resume relaunch, or
/// explain why not. Only a kept-worktree state — Committed (a truncated
/// worker's validated partial) or Captured (a defective capture awaiting
/// repair) — can host a fresh worker; capture() then measures the resumed
/// run against the entry's prior commit and stacks its commit on it.
pub async fn resume_running(
  geometry : Geometry,
  name : String,
) -> Result[SubtaskEntry, String] {
  // The same mutex provision and integrate hold: a continue racing an
  // in-flight integrate must observe its OUTCOME state (Conflicted refuses
  // below; Integrated is terminal; a clean merge removed the worktree),
  // never the pre-merge Committed. A cancelled continue still leaks a
  // Running entry whose branch holds validated work (capture never ran) —
  // that residual mirrors the launch-cancel one and only discard clears it.
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  defer mutex.release()
  let (entries, _) = load_entries(geometry.common_git_dir)
  guard entries.filter(e => e.name == name && !e.state.is_terminal()).last()
    is Some(entry) else {
    return Err("no active subtask named \{name}")
  }
  guard geometry.is_integration_target_for(entry) else {
    return Err(
      "subtask \{name} belongs to a different worktree; continue it from the worktree that launched it",
    )
  }
  guard entry.state is (Committed | Captured) else {
    return Err(
      "subtask \{name} is \{Repr(entry.state)} — only a captured or committed slice with a kept worktree can be continued",
    )
  }
  guard (@fs.exists(entry.worker_root) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }) else {
    return Err(
      "subtask \{name}'s worktree is gone (\{entry.worker_root}); discard it and launch a fresh slice",
    )
  }
  let entry = { ..entry, state: Running, }
  match save_entry(geometry.common_git_dir, entry) {
    Ok(_) => Ok(entry)
    Err(reason) => Err(reason)
  }
}

///|
/// Run git and require success; `Err` carries the merged diagnostics.
pub async fn git_require(
  args : Array[String],
  cwd~ : String,
  timeout_ms? : Int = 30_000,
) -> Result[String, String] {
  let outcome = git_run(args, cwd~, timeout_ms~)
  if outcome.exit_code == 0 {
    Ok(outcome.output)
  } else {
    Err(
      "git \{args.join(" ")} failed (exit \{outcome.exit_code}): \{outcome.output}",
    )
  }
}
