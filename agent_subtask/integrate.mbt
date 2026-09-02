///|
/// Integration: merge a committed subtask branch into the origin, classify
/// the outcome by POSTCONDITIONS (MERGE_HEAD, unmerged index entries, HEAD)
/// rather than exit codes, and clean up only what a clean merge proves
/// redundant. Conflict continuation and abort are controller-owned and
/// verify the merge in progress belongs to THIS subtask attempt.
pub struct IntegrateOutcome {
  entry : SubtaskEntry
  /// "integrated" | "conflicted" | "refused"
  result : String
  detail : Array[String]
}

///|
/// The merge flag set: hooks and signing neutralized, no rerere recording
/// or autostash, ignored files protected, merge by EXACT commit OID.
fn merge_args(entry : SubtaskEntry, commit_oid : String) -> Array[String] {
  [
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "rerere.enabled=false",
    "merge",
    "--no-ff",
    "--no-edit",
    "--no-gpg-sign",
    "--no-autostash",
    "--no-overwrite-ignore",
    "-m",
    "subtask \{entry.name}: integrate worker changes",
    commit_oid,
  ]
}

///|
/// Re-read the caller's entry from the registry: the tool layer loaded its
/// snapshot BEFORE any mutex was taken, and a concurrent continue may have
/// advanced the state since (e.g. Committed → Running with a live child).
/// Operating on the stale snapshot would merge or delete under that child.
/// A missing record falls back to the snapshot — the state guards at each
/// call site then decide.
async fn reload_entry(
  common_git_dir : String,
  entry : SubtaskEntry,
) -> SubtaskEntry {
  let (entries, _) = load_entries(common_git_dir)
  match
    entries.filter(e => e.name == entry.name && e.nonce == entry.nonce).last() {
    Some(fresh) => fresh
    None => entry
  }
}

///|
/// Merge a committed subtask into the origin; outcome classified by git
/// postconditions (integrated | conflicted | refused).
pub async fn integrate(
  geometry : Geometry,
  entry : SubtaskEntry,
) -> IntegrateOutcome {
  let origin = geometry.origin_root
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  defer mutex.release()
  integrate_locked(geometry, origin, entry)
}

///|
async fn integrate_locked(
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
        "subtask \{entry.name} belongs to a different worktree; integrate it from the worktree that launched it",
      ],
    }
  }
  guard entry.state is Committed && entry.commit_oid is Some(commit_oid) else {
    return {
      entry,
      result: "refused",
      detail: ["subtask \{entry.name} is not in a committed state"],
    }
  }
  // The branch must still point at the validated commit, and that commit
  // must descend from the recorded base.
  match git_require(["rev-parse", entry.branch], cwd=origin) {
    Ok(tip) =>
      if tip.trim() != commit_oid {
        return {
          entry,
          result: "refused",
          detail: [
            "branch \{entry.branch} moved (\{tip.trim()} != validated \{commit_oid})",
          ],
        }
      }
    Err(reason) => return { entry, result: "refused", detail: [reason], }
  }
  if git_run(
      ["merge-base", "--is-ancestor", entry.base_oid, commit_oid],
      cwd=origin,
    ).exit_code !=
    0 {
    return {
      entry,
      result: "refused",
      detail: ["\{commit_oid} does not descend from the recorded base"],
    }
  }
  // Origin gate: no staged changes, no unstaged changes to tracked files.
  // Gitlink dirt (a chronically-drifting submodule pointer) is carved out:
  // submodule slices were rejected at provision, so it cannot collide.
  let status = git_run(
    ["status", "--porcelain=v1", "-z", "--ignore-submodules=dirty"],
    cwd=origin,
  )
  guard status.exit_code == 0 else {
    return {
      entry,
      result: "refused",
      detail: ["git status failed: \{status.output.trim()}"],
    }
  }
  for change in parse_status_z(status.output) {
    if change.kind != "??" {
      return {
        entry,
        result: "refused",
        detail: [
          "the origin has uncommitted tracked changes (\{change.path}); commit or stash them before integrating",
        ],
      }
    }
  }
  let head_before = match git_require(["rev-parse", "HEAD"], cwd=origin) {
    Ok(output) => output.trim().to_owned()
    Err(reason) => return { entry, result: "refused", detail: [reason], }
  }
  let entry = { ..entry, origin_head_before: Some(head_before), }
  let _ = save_entry(geometry.common_git_dir, entry)
  let merge = git_run(
    merge_args(entry, commit_oid),
    cwd=origin,
    timeout_ms=120_000,
  )
  // Classify by postconditions, not the exit code.
  let merge_head = git_run(
    ["rev-parse", "-q", "--verify", "MERGE_HEAD"],
    cwd=origin,
  )
  let unmerged = git_run(["ls-files", "-u", "-z"], cwd=origin)
  if merge_head.exit_code == 0 {
    // A merge is in progress: a real conflict handoff only when it is OUR
    // commit being merged.
    if merge_head.output.trim() == commit_oid &&
      unmerged.exit_code == 0 &&
      unmerged.output != "" {
      let files : Array[String] = []
      for
        change in parse_status_z(
          git_run(["status", "--porcelain=v1", "-z"], cwd=origin).output,
        ) {
        if change.kind.contains("U") && !files.contains(change.path) {
          files.push(change.path)
        }
      }
      let entry = { ..entry, state: Conflicted, conflict_paths: files.copy(), }
      let _ = save_entry(geometry.common_git_dir, entry)
      return {
        entry,
        result: "conflicted",
        detail: [
          "merge conflict in: \{files.join(", ")}",
          "resolve the markers with the file tools, then integrate_continue (or integrate_abort)",
        ],
      }
    }
    // A foreign or degenerate in-progress merge: abort OUR attempt only if
    // it is ours; otherwise leave the user's state alone.
    if merge_head.output.trim() == commit_oid {
      let _ = git_run(["merge", "--abort"], cwd=origin)
    }
    return {
      entry,
      result: "refused",
      detail: ["merge did not complete cleanly: \{merge.output.trim()}"],
    }
  }
  // No merge in progress: either it completed or it never started.
  let head_after = git_run(["rev-parse", "HEAD"], cwd=origin)
  if head_after.exit_code == 0 && head_after.output.trim() != head_before {
    let entry = { ..entry, state: Integrated, }
    let _ = save_entry(geometry.common_git_dir, entry)
    // The branch's content now lives in origin history: the worktree and
    // branch are provably redundant — the one auto-clean that is safe.
    // (`git worktree remove` refuses ANY worktree in repos with tracked
    // submodules, so removal is rm + prune by design.)
    @fs.rmdir(entry.worker_root, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
    let _ = git_run(["worktree", "prune"], cwd=origin)
    let _ = git_run(["branch", "-d", entry.branch], cwd=origin)
    return {
      entry,
      result: "integrated",
      detail: ["merged \{commit_oid} into \{head_after.output.trim()}"],
    }
  }
  {
    entry,
    result: "refused",
    detail: ["merge did not land: \{merge.output.trim()}"],
  }
}

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
  @fs.rmdir(entry.worker_root, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  let _ = git_run(["worktree", "prune"], cwd=origin)
  let _ = git_run(["branch", "-d", entry.branch], cwd=origin)
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
/// Discard a subtask that will not be integrated: remove its worktree and
/// branch, release the reservation. Refused while a merge of this subtask
/// is in progress.
pub async fn discard(
  geometry : Geometry,
  entry : SubtaskEntry,
) -> Result[Unit, String] {
  let origin = geometry.origin_root
  // Discard stays the destructive escape hatch for ANY non-terminal state
  // (it is the documented recovery for a crashed or cancelled child), but
  // it serializes with the other lifecycle actions and acts on the fresh
  // record, never a stale snapshot.
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  defer mutex.release()
  let entry = reload_entry(geometry.common_git_dir, entry)
  guard geometry.is_integration_target_for(entry) else {
    return Err(
      "subtask \{entry.name} belongs to a different worktree; discard it from the worktree that launched it",
    )
  }
  if entry.commit_oid is Some(commit_oid) {
    let merge_head = git_run(
      ["rev-parse", "-q", "--verify", "MERGE_HEAD"],
      cwd=origin,
    )
    if merge_head.exit_code == 0 && merge_head.output.trim() == commit_oid {
      return Err("a merge of this subtask is in progress; abort it first")
    }
  }
  @fs.rmdir(entry.worker_root, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  let _ = git_run(["worktree", "prune"], cwd=origin)
  let _ = git_run(["branch", "-D", entry.branch], cwd=origin)
  let entry = { ..entry, state: Discarded, }
  let _ = save_entry(geometry.common_git_dir, entry)
  Ok(())
}
