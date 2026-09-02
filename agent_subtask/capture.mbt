///|
/// Capture: after the worker child exits, decide from GIT EVIDENCE — never
/// the child's own report — whether its changes are mergeable, and if so
/// commit them on the subtask branch. The sequence pins an immutable
/// snapshot FIRST: stage, `write-tree`, validate THAT tree object (a
/// straggling worker process racing the index can no longer smuggle
/// unvalidated paths), then commit exactly the validated tree via plumbing
/// (`commit-tree` + `update-ref` — no hooks, no index re-read).
pub struct CaptureOutcome {
  entry : SubtaskEntry
  /// Human-facing evidence lines (bounded by the caller when displayed).
  evidence : Array[String]
  /// Non-empty when the result must not merge; names each reason.
  defects : Array[String]
}

///|
/// Validate and (when clean) commit a finished worker's changes on its
/// subtask branch; see the file comment for the full sequence.
pub async fn capture(
  geometry : Geometry,
  entry : SubtaskEntry,
) -> CaptureOutcome {
  let worker = entry.worker_root
  let evidence : Array[String] = []
  let defects : Array[String] = []
  // The pin this capture measures HEAD against and stacks its commit on. A
  // first capture pins the recorded base; a RESUMED slice's worktree
  // legitimately sits at the previous capture's commit (update-ref moved
  // the checked-out branch), so later captures pin that commit instead.
  let pin = match entry.commit_oid {
    Some(prior) => prior
    None => entry.base_oid
  }
  // The worker cannot commit (the sandbox denies the shared object store);
  // a moved HEAD means something abnormal happened — refuse to reason on it.
  match git_require(["rev-parse", "HEAD"], cwd=worker) {
    Ok(head) =>
      if head.trim() != pin {
        defects.push(
          "worktree HEAD moved from the pinned base (\{head.trim()} != \{pin})",
        )
      }
    Err(reason) => defects.push(reason)
  }
  let status = git_run(
    [
      "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none",
    ],
    cwd=worker,
  )
  guard status.exit_code == 0 else {
    defects.push("git status failed: \{status.output.trim()}")
    return { entry, evidence, defects, }
  }
  let changes = parse_status_z(status.output)
  if changes.is_empty() && !defects.is_empty() {
    // A clean tree with a FAILED validation (e.g. HEAD moved off the base)
    // is abnormal, not a no-op: the worktree may hold the only reference
    // to whatever happened — keep it and report.
    let entry = { ..entry, state: Captured, }
    let _ = save_entry(geometry.common_git_dir, entry)
    return { entry, evidence, defects, }
  }
  if changes.is_empty() && entry.commit_oid is Some(prior) {
    // A resumed worker that added nothing new: the prior capture still
    // stands. The terminal cleanup below would delete the branch holding
    // already-validated work — keep everything and report instead. "Still
    // stands" is verified, not assumed: an externally moved branch must
    // surface now, not as a later integrate refusal.
    match git_require(["rev-parse", "refs/heads/\{entry.branch}"], cwd=worker) {
      Ok(tip) if tip.trim() == prior => {
        let entry = { ..entry, state: Committed, }
        let _ = save_entry(geometry.common_git_dir, entry)
        evidence.push("no additional changes since the prior capture \{prior}")
        return { entry, evidence, defects, }
      }
      Ok(tip) =>
        defects.push(
          "branch \{entry.branch} moved externally (\{tip.trim()} != prior capture \{prior})",
        )
      Err(reason) => defects.push(reason)
    }
    let entry = { ..entry, state: Captured, }
    let _ = save_entry(geometry.common_git_dir, entry)
    return { entry, evidence, defects, }
  }
  if changes.is_empty() {
    // Terminal means undiscoverable by lifecycle actions, so the worktree
    // and branch must go NOW or they leak (and block reusing the name).
    @fs.rmdir(entry.worker_root, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
    let _ = git_run(["worktree", "prune"], cwd=geometry.origin_root)
    let _ = git_run(["branch", "-D", entry.branch], cwd=geometry.origin_root)
    let entry = { ..entry, state: NoChanges, }
    let _ = save_entry(geometry.common_git_dir, entry)
    evidence.push("no changes in the worker tree; worktree and branch removed")
    return { entry, evidence, defects, }
  }
  evidence.push("\{changes.length()} changed path(s)")
  let violations = scope_violations(changes, entry.allowed_paths)
  if !violations.is_empty() {
    defects.push(
      "out-of-scope changes (allowed: \{entry.allowed_paths.join(", ")}): \{violations.join(", ")}",
    )
  }
  if !defects.is_empty() {
    let entry = { ..entry, state: Captured, }
    let _ = save_entry(geometry.common_git_dir, entry)
    return { entry, evidence, defects, }
  }
  // Stage, pin the immutable tree, and validate the TREE OBJECT itself.
  match git_require(["add", "-A"], cwd=worker) {
    Ok(_) => ()
    Err(reason) => {
      defects.push(reason)
      return { entry, evidence, defects, }
    }
  }
  let tree_oid = match git_require(["write-tree"], cwd=worker) {
    Ok(output) => output.trim().to_owned()
    Err(reason) => {
      defects.push(reason)
      return { entry, evidence, defects, }
    }
  }
  let staged = git_run(
    ["diff", "--name-status", "-z", entry.base_oid, tree_oid],
    cwd=worker,
  )
  guard staged.exit_code == 0 else {
    defects.push("git diff (tree) failed: \{staged.output.trim()}")
    return { entry, evidence, defects, }
  }
  let staged_changes = parse_diff_name_status_z(staged.output)
  let staged_violations = scope_violations(staged_changes, entry.allowed_paths)
  if !staged_violations.is_empty() {
    defects.push(
      "staged changes escaped scope between validation and staging: \{staged_violations.join(", ")}",
    )
  }
  match git_run(["diff", "--raw", "-z", entry.base_oid, tree_oid], cwd=worker) {
    raw if raw.exit_code == 0 => {
      let links = gitlink_introductions_in_raw_z(raw.output)
      if !links.is_empty() {
        defects.push(
          "the worker staged embedded repositories as gitlinks: \{links.join(", ")}",
        )
      }
    }
    raw => defects.push("git diff --raw failed: \{raw.output.trim()}")
  }
  if !defects.is_empty() {
    let entry = { ..entry, state: Captured, }
    let _ = save_entry(geometry.common_git_dir, entry)
    return { entry, evidence, defects, }
  }
  // Commit EXACTLY the validated tree; then move the branch ref to it,
  // guarded by the expected old value (the pin).
  let commit_oid = match
    git_require(
      [
        "commit-tree",
        tree_oid,
        "-p",
        pin,
        "-m",
        "subtask \{entry.name}: worker changes",
      ],
      cwd=worker,
    ) {
    Ok(output) => output.trim().to_owned()
    Err(reason) => {
      defects.push(reason)
      return { entry, evidence, defects, }
    }
  }
  match
    git_require(
      ["update-ref", "refs/heads/\{entry.branch}", commit_oid, pin],
      cwd=worker,
    ) {
    Ok(_) => ()
    Err(reason) => {
      defects.push(reason)
      return { entry, evidence, defects, }
    }
  }
  let diffstat = git_run(
    ["diff", "--stat", entry.base_oid, commit_oid],
    cwd=worker,
  )
  if diffstat.exit_code == 0 {
    evidence.push(diffstat.output.trim().to_owned())
  }
  let entry = { ..entry, state: Committed, commit_oid: Some(commit_oid), }
  let _ = save_entry(geometry.common_git_dir, entry)
  evidence.push("committed \{commit_oid} on \{entry.branch}")
  { entry, evidence, defects, }
}
