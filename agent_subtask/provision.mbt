///|
/// Provisioning: one MUTEX-HELD transaction from registry reconciliation to
/// a live worktree with a visible reservation. The mutex is keyed per
/// canonical common git dir (process-local — the single-engine-per-repo
/// assumption is a documented residual), so two concurrent subtask calls
/// cannot both observe "no overlap" and launch overlapping workers.
let repo_mutexes : Map[String, @async.Mutex] = Map([])

///|
fn repo_mutex(common_git_dir : String) -> @async.Mutex {
  match repo_mutexes.get(common_git_dir) {
    Some(mutex) => mutex
    None => {
      let mutex = @async.Mutex()
      repo_mutexes[common_git_dir] = mutex
      mutex
    }
  }
}

///|
/// Everything a launched worker (and its later capture/integrate) needs.
pub struct Provisioned {
  entry : SubtaskEntry
  geometry : Geometry
}

///|
/// Provision a worktree for `name` with `allowed_paths`, or explain why
/// not. On any failure after partial creation, the transaction rolls back
/// what it made (worktree, branch, registry entry) before returning.
pub async fn provision(
  workspace_root : String,
  name~ : String,
  allowed_paths~ : Array[String],
  nonce~ : String,
  parent_session? : String,
) -> Result[Provisioned, String] {
  guard is_valid_name(name) else {
    return Err(
      "subtask name must be a short lowercase slug ([a-z0-9][a-z0-9-]{0,39}): \{name}",
    )
  }
  let allowed_paths = match normalize_allowed_paths(allowed_paths) {
    Ok(normalized) => normalized
    Err(reason) => return Err(reason)
  }
  let geometry = match resolve_geometry(workspace_root) {
    Ok(geometry) => geometry
    Err(reason) => return Err(reason)
  }
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  // Block-scoped and sync, so a raise (cancellation included) still
  // releases; a cached locked mutex would wedge the repository for the
  // rest of the process.
  defer mutex.release()
  provision_locked(geometry, name~, allowed_paths~, nonce~, parent_session?)
}

///|
async fn provision_locked(
  geometry : Geometry,
  name~ : String,
  allowed_paths~ : Array[String],
  nonce~ : String,
  parent_session? : String,
) -> Result[Provisioned, String] {
  let origin = geometry.origin_root
  // 1. Reservation check against every non-terminal registry entry.
  let (entries, _) = load_entries(geometry.common_git_dir)
  for existing in entries {
    if existing.state.is_terminal() {
      continue
    }
    if existing.name == name {
      return Err(
        "a subtask named \{name} is already active (state \{Repr(existing.state)}); pick another name or integrate/discard it first",
      )
    }
    if paths_overlap(existing.allowed_paths, allowed_paths) {
      return Err(
        "allowed_paths overlap active subtask \{existing.name} (\{existing.allowed_paths.join(", ")}); partitions must be disjoint — integrate or discard it first",
      )
    }
  }
  // 2. Base is pinned BEFORE the worktree exists and passed to git
  //    explicitly, so a HEAD move between steps cannot skew evidence.
  let base_oid = match git_require(["rev-parse", "HEAD"], cwd=origin) {
    Ok(output) => output.trim().to_owned()
    Err(reason) => return Err(reason)
  }
  // 3. Submodule slices are rejected from the PINNED tree, not the checkout.
  match git_require(["ls-tree", "-r", "-z", base_oid], cwd=origin) {
    Ok(listing) =>
      for record in listing.split("\u{0}") {
        let record = record.to_owned()
        guard record.contains(" 160000 ") || record.has_prefix("160000 ") else {
          continue
        }
        guard record.split("\t").last() is Some(path) else { continue }
        let gitlink = path.to_owned()
        if scope_violations(
            [{ path: gitlink, kind: "gitlink", }],
            allowed_paths,
          ).is_empty() {
          return Err(
            "allowed_paths cover the submodule \{gitlink}; submodule slices are not supported (v1)",
          )
        }
      }
    Err(reason) => return Err(reason)
  }
  // 4. Keep .worktrees/ out of status noise, idempotently.
  let exclude = "\{geometry.common_git_dir}/info/exclude"
  let existing_exclude = @fs.read_file(exclude).text() catch {
    error if @async.is_being_cancelled() => raise error
    _ => ""
  }
  if !existing_exclude.split("\n").any(line => line == ".worktrees/") {
    @fs.write_file(
      exclude,
      "\{existing_exclude}\{if existing_exclude == "" || existing_exclude.has_suffix("\n") { "" } else { "\n" }}.worktrees/\n",
      create_mode=CreateOrTruncate,
    ) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
  // 5. Reservation becomes visible BEFORE the worktree exists: a crash
  //    between the two leaves a Provisioning entry naming what to clean.
  let branch = "openseek/\{name}--\{nonce}"
  let worker_root_spelled = "\{origin}/.worktrees/\{name}"
  let mut entry : SubtaskEntry = {
    schema_version: 1,
    name,
    nonce,
    branch,
    state: Provisioning,
    base_oid,
    worker_root: worker_root_spelled,
    worker_admin_dir: "",
    allowed_paths,
    parent_session,
    commit_oid: None,
    origin_head_before: None,
    conflict_paths: [],
  }
  match save_entry(geometry.common_git_dir, entry) {
    Ok(_) => ()
    Err(reason) => return Err(reason)
  }
  // 6. The worktree itself, pinned to the recorded base.
  match
    git_require(
      ["worktree", "add", ".worktrees/\{name}", "-b", branch, base_oid],
      cwd=origin,
      timeout_ms=60_000,
    ) {
    Ok(_) => ()
    Err(reason) => {
      let _ = rollback_provision(geometry, entry)
      return Err(reason)
    }
  }
  // 7. Canonicalize what git actually made; resolve the PRIVATE admin dir
  //    from inside the worktree (numeric suffixes exist — never construct).
  let worker_root = canonical(worker_root_spelled)
  let admin = match
    git_require(["rev-parse", "--absolute-git-dir"], cwd=worker_root) {
    Ok(output) => canonical(output.trim().to_owned())
    Err(reason) => {
      let _ = rollback_provision(geometry, entry)
      return Err(reason)
    }
  }
  entry = { ..entry, worker_root, worker_admin_dir: admin, state: Running, }
  match save_entry(geometry.common_git_dir, entry) {
    Ok(_) => ()
    Err(reason) => {
      let _ = rollback_provision(geometry, entry)
      return Err(reason)
    }
  }
  // 8. Prewarm the dependency cache when the origin has one: registry
  //    snapshots are immutable, and a worker without them pays a full
  //    re-download before its first moon command.
  copy_mooncakes(origin, worker_root)
  Ok({ entry, geometry, })
}

///|
/// Undo a partial provision: worktree directory, bookkeeping, branch, and
/// registry entry, in that order, each best-effort.
async fn rollback_provision(geometry : Geometry, entry : SubtaskEntry) -> Unit {
  @fs.rmdir(entry.worker_root, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  let _ = git_run(["worktree", "prune"], cwd=geometry.origin_root)
  let _ = git_run(["branch", "-D", entry.branch], cwd=geometry.origin_root)
  let dir = registry_dir(geometry.common_git_dir)
  @fs.remove("\{dir}/\{entry.name}--\{entry.nonce}.json") catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
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
fn is_valid_name(name : String) -> Bool {
  guard name.length() >= 1 && name.length() <= 40 else { return false }
  for index, ch in name {
    let ok = ch is ('a'..='z' | '0'..='9') || (ch == '-' && index > 0)
    if !ok {
      return false
    }
  }
  true
}

///|
/// Best-effort recursive copy of `.mooncakes` (immutable registry
/// snapshots). Failure is fine — the worker just pays the download.
async fn copy_mooncakes(origin : String, worker_root : String) -> Unit {
  let source = "\{origin}/.mooncakes"
  guard (@fs.exists(source) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }) else {
    return
  }
  let _ = @process.run(
    "cp",
    ["-R", source, "\{worker_root}/.mooncakes"],
    inherit_env=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => 1
  }
}

///|
test "subtask names are strict slugs" {
  assert_true(is_valid_name("fix-warnings"))
  assert_true(is_valid_name("a1"))
  assert_false(is_valid_name("-leading"))
  assert_false(is_valid_name("Upper"))
  assert_false(is_valid_name("has space"))
  assert_false(is_valid_name(""))
  let long = StringBuilder()
  for _ in 0..<41 {
    long.write_char('a')
  }
  assert_false(is_valid_name(long.to_string()))
}

///|
/// Normalize model-supplied prefixes into the one spelling BOTH enforcement
/// layers use: trailing slashes stripped (a natural `lib/` must not become
/// `lib` + an empty component that rejects everything), no absolute, empty,
/// `.`/`..`, or backslash components.
fn normalize_allowed_paths(
  allowed_paths : Array[String],
) -> Result[Array[String], String] {
  let normalized : Array[String] = []
  for prefix in allowed_paths {
    let mut cleaned = prefix.trim().to_owned()
    while cleaned.has_suffix("/") {
      cleaned = cleaned.view(end_offset=cleaned.length() - 1).to_owned()
    }
    guard cleaned != "" && !cleaned.has_prefix("/") else {
      return Err(
        "allowed_paths entries must be non-empty relative prefixes: \{prefix}",
      )
    }
    guard !cleaned.contains("\\") else {
      return Err("allowed_paths entries must use forward slashes: \{prefix}")
    }
    for part in cleaned.split("/") {
      guard !(part.to_owned() is ("" | "." | "..")) else {
        return Err(
          "allowed_paths entries must not contain empty, `.`, or `..` components: \{prefix}",
        )
      }
    }
    if !normalized.contains(cleaned) {
      normalized.push(cleaned)
    }
  }
  Ok(normalized)
}
