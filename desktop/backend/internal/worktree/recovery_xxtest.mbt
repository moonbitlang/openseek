// Lifecycle regressions share the package's ambient HOME lock and registry
// fixtures. Private access is needed to inspect recovery refs and exercise
// rollback ownership without publishing those implementation details.

///|
#cfg(not(platform="windows"))
async fn with_recovery_fixture(
  body : async (@pathx.Absolute, WorktreeHost) -> Unit,
) -> Unit {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-recovery-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo with 空间")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  body(repo, test_host())
}

///|
#cfg(not(platform="windows"))
async fn commit_recovery_fixture(
  checkout : @pathx.Absolute,
  message : String,
) -> String {
  ignore(
    @gitx.run(checkout, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "--allow-empty", "-q", "-m", message,
    ]),
  )
  @gitx.run(checkout, ["rev-parse", "HEAD"])
}

///|
#cfg(not(platform="windows"))
async fn collect_recovery_fixture(repo : @pathx.Absolute) -> Unit {
  ignore(@gitx.run(repo, ["reflog", "expire", "--expire=now", "--all"]))
  ignore(@gitx.run(repo, ["gc", "--prune=now"]))
}

///|
#cfg(not(platform="windows"))
async test "detached archive survives GC and later user-created branches" {
  with_recovery_fixture((repo, host) => {
    let owner = WorktreeOwner::codex("archive")
    let created = create(host, resource_path(repo), owner, _ => ())
    guard created.worktrees is [info] else { fail("missing worktree") }
    let checkout = worktree_dir(repo, info.name)
    let head = commit_recovery_fixture(checkout, "detached work")
    assert_eq(owner.archive_checkout(false), None)
    assert_false(@fsx.exists(checkout.to_path()))
    collect_recovery_fixture(repo)
    let restored = create(host, resource_path(repo), owner, _ => ())
    assert_eq(restored.name, created.name)
    assert_eq(@gitx.run(checkout, ["rev-parse", "HEAD"]), head)
    assert_eq(
      @gitx.run(checkout, ["rev-parse", "--abbrev-ref", "HEAD"]),
      "HEAD",
    )
    assert_eq(tree_base(repo, "archive"), Some(info.base))
    // Publishing later is an ordinary branch creation from the task's HEAD.
    ignore(@gitx.run(checkout, ["switch", "-c", "feature/publish"]))
    let published = commit_recovery_fixture(checkout, "published work")
    assert_eq(owner.archive_checkout(false), None)
    assert_false(@fsx.exists(checkout.to_path()))
    collect_recovery_fixture(repo)
    ignore(create(host, resource_path(repo), owner, _ => ()))
    assert_eq(@gitx.run(checkout, ["rev-parse", "HEAD"]), published)
    assert_eq(
      @gitx.run(repo, ["rev-parse", "refs/heads/feature/publish"]),
      published,
    )
    assert_eq(
      @gitx.run(checkout, ["rev-parse", "--abbrev-ref", "HEAD"]),
      "HEAD",
    )
    assert_eq(tree_base(repo, "archive"), Some(info.base))
  })
}

///|
#cfg(not(platform="windows"))
async test "repair pins all externally deleted worktree HEADs before pruning" {
  with_recovery_fixture((repo, host) => {
    let first = WorktreeOwner::openseek("first")
    let second = WorktreeOwner::codex("second")
    let a = create(host, resource_path(repo), first, _ => ())
    let b = create(host, resource_path(repo), second, _ => ())
    let a_dir = worktree_dir(repo, a.name)
    let b_dir = worktree_dir(repo, b.name)
    let a_head = commit_recovery_fixture(a_dir, "first detached commit")
    let b_head = commit_recovery_fixture(b_dir, "second detached commit")
    @fs.rmdir(a_dir.to_string(), recursive=true)
    @fs.rmdir(b_dir.to_string(), recursive=true)
    ignore(create(host, resource_path(repo), first, _ => ()))
    // Repair pruned both absent admin entries. The second HEAD must already
    // be reachable without its worktree metadata or any branch/reflog.
    collect_recovery_fixture(repo)
    ignore(create(host, resource_path(repo), second, _ => ()))
    assert_eq(@gitx.run(a_dir, ["rev-parse", "HEAD"]), a_head)
    assert_eq(@gitx.run(b_dir, ["rev-parse", "HEAD"]), b_head)
    assert_eq(
      @gitx.run(repo, [
        "for-each-ref", "--format=%(refname)", "refs/heads/openseek/",
      ]),
      "",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "legacy branch registry still archives and restores its branch" {
  with_recovery_fixture((repo, host) => {
    let base = @gitx.run(repo, ["rev-parse", "HEAD"])
    let checkout = worktree_dir(repo, "legacy")
    ignore(
      @gitx.run(repo, [
        "worktree",
        "add",
        "-b",
        "openseek/legacy",
        checkout.to_string(),
      ]),
    )
    let head = commit_recovery_fixture(checkout, "legacy work")
    let row : WorktreeEntry = {
      name: "legacy",
      checkout: Branch("openseek/legacy"),
      base,
      session: None,
      codex_thread: Some("legacy"),
    }
    write_worktrees(repo, [row])
    let owner = WorktreeOwner::codex("legacy")
    assert_eq(owner.archive_checkout(false), None)
    assert_false(@fsx.exists(checkout.to_path()))
    collect_recovery_fixture(repo)
    let restored = create(host, resource_path(repo), owner, _ => ())
    guard restored.worktrees is [info] else { fail("missing legacy row") }
    assert_eq(info.branch, Some("openseek/legacy"))
    assert_eq(
      @gitx.run(checkout, ["rev-parse", "--abbrev-ref", "HEAD"]),
      "openseek/legacy",
    )
    assert_eq(@gitx.run(checkout, ["rev-parse", "HEAD"]), head)
    assert_eq(tree_base(repo, "legacy"), Some(base))
  })
}

///|
#cfg(not(platform="windows"))
async test "failed registry publication rolls back only its own locked checkout" {
  with_recovery_fixture((repo, host) => {
    // A competing tool's worktree can have the same detached base commit.
    let other = worktree_dir(repo, "other")
    ignore(
      @gitx.run(repo, [
        "worktree",
        "add",
        "--detach",
        "--lock",
        "--reason",
        "other tool",
        other.to_string(),
        "HEAD",
      ]),
    )
    rollback_worktree_checkout(repo, "other", "our invocation")
    assert_true(@fsx.is_dir(other.to_path()))
    assert_eq(worktree_lock_reason(repo, "other"), Some("other tool"))
    @fsx.ensure_dir(@workspaces.store_root(repo).to_path())
    @fs.mkdir(
      @workspaces.store_root(repo).join(WorktreesFile + ".tmp").to_string(),
    )
    let refused = create_refusal(host, resource_path(repo), "failed", "failed")
    assert_true(refused.contains("could not stage the worktree list"))
    assert_false(@fsx.exists(worktree_dir(repo, "failed").to_path()))
    assert_eq(
      @gitx.run(repo, [
        "for-each-ref",
        "--format=%(refname)",
        WorktreeRecoveryPrefix,
      ]),
      "",
    )
    assert_eq(read_worktrees_unlocked(repo).length(), 0)
    assert_true(@fsx.is_dir(other.to_path()))
  })
}

///|
#cfg(not(platform="windows"))
async test "archive refuses to delete checkout when saving HEAD fails" {
  with_recovery_fixture((repo, host) => {
    let owner = WorktreeOwner::codex("save-failure")
    let created = create(host, resource_path(repo), owner, _ => ())
    guard read_worktrees_unlocked(repo) is [entry] else { fail("missing row") }
    let checkout = worktree_dir(repo, created.name)
    let head = commit_recovery_fixture(checkout, "must survive failed save")
    let lock_path = repo.join(".git").join(entry.checkout.revision() + ".lock")
    @fsx.write_text(lock_path.to_path(), "held by another writer")
    let refused = try {
      ignore(owner.archive_checkout(false))
      false
    } catch {
      error if @async.is_being_cancelled() => raise error
      _ => true
    }
    assert_true(refused)
    assert_true(@fsx.is_dir(checkout.to_path()))
    assert_eq(@gitx.run(checkout, ["rev-parse", "HEAD"]), head)
  })
}
