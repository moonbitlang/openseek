///|
/// Provisioning: one MUTEX-HELD transaction from registry reconciliation to
/// a live worktree with a visible reservation. The mutex is keyed per
/// canonical common git dir (process-local — the single-engine-per-repo
/// assumption is a documented residual), so two concurrent subtask calls
/// cannot both observe "no overlap" and launch overlapping workers.
let repo_mutexes : Map[String, @async.Mutex] = Map([])

///|
fn repo_mutex(common_git_dir : String) -> @async.Mutex {
  repo_mutexes.get_or_init(common_git_dir, () => Mutex())
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
/// Tear down a slice's worktree: remove the directory, prune git's now-stale
/// worktree bookkeeping, then drop the branch — in that order, each
/// best-effort, because a teardown that stops at the first failure leaks the
/// rest. (`git worktree remove` refuses ANY worktree in a repo with tracked
/// submodules, so removal is rm + prune by design.) `force` picks `branch -D`
/// for a branch being abandoned over `-d` for one a merge proved redundant.
async fn remove_worktree_and_branch(
  origin : String,
  entry : SubtaskEntry,
  force~ : Bool,
) -> Unit {
  @fs.rmdir(entry.worker_root, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  let _ = git_run(["worktree", "prune"], cwd=origin)
  let _ = git_run(
    ["branch", if force { "-D" } else { "-d" }, entry.branch],
    cwd=origin,
  )
}

///|
/// Undo a partial provision: worktree directory, bookkeeping, branch, and
/// registry entry, in that order, each best-effort.
async fn rollback_provision(geometry : Geometry, entry : SubtaskEntry) -> Unit {
  remove_worktree_and_branch(geometry.origin_root, entry, force=true)
  let dir = registry_dir(geometry.common_git_dir)
  @fs.remove("\{dir}/\{entry.name}--\{entry.nonce}.json") catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
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
  assert_false(is_valid_name("a".repeat(41)))
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
    let cleaned = prefix.trim().trim_end(chars="/").to_owned()
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
