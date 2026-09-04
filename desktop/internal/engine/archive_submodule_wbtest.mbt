// Archiving a conversation whose checkout carries submodules. The checkout
// mechanics live in `internal/worktree`; what these cover is archive's own
// deletion path meeting a directory `git worktree remove` refuses to touch.

///|
#cfg(not(platform="windows"))
async test "archive deletes a submodule checkout that git worktree remove refuses" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-sub-archive-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let dep = root.join("dep")
  prepare_git_repo(dep)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@gitx.run(repo, ["config", "protocol.file.allow", "always"]))
  ignore(
    @gitx.run(repo, [
      "-c",
      "protocol.file.allow=always",
      "submodule",
      "add",
      "-q",
      dep.to_string(),
      "deps/one",
    ]),
  )
  ignore(
    @gitx.run(repo, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-am", "add submodule",
    ]),
  )
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  // A dirty checkout still confirms first, and the confirmed force retry
  // must delete the checkout even though plain `git worktree remove`
  // refuses over the gitlink.
  ignore(
    @worktree.create(
      manager.worktree_host(),
      repo.to_string(),
      @worktree.WorktreeOwner::openseek("s-sub-dirty"),
      fn(_) {  },
    ),
  )
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-sub-dirty").to_path(),
  )
  let dirty_checkout = repo.join(".worktrees/wt-1")
  assert_true(@fsx.exists(dirty_checkout.join("deps/one/.git").to_path()))
  @fs.write_file(
    dirty_checkout.join("junk.txt").to_string(),
    b"x",
    create_mode=CreateOrTruncate,
  )
  guard archive_session(manager, "s-sub-dirty", (_, _) => ())
    is NeedsForce(refusal) else {
    fail("dirty submodule checkout must ask for confirmation")
  }
  assert_eq(refusal.worktree, "wt-1")
  assert_eq(refusal.dirty_paths, ["junk.txt"])
  guard archive_session(manager, "s-sub-dirty", (_, _) => (), force=true)
    is Archived(_) else {
    fail("forced archive must delete the submodule checkout")
  }
  assert_false(@fsx.exists(dirty_checkout.to_path()))
  // A clean submodule checkout archives in one go, exactly like a clean
  // plain worktree.
  ignore(
    @worktree.create(
      manager.worktree_host(),
      repo.to_string(),
      @worktree.WorktreeOwner::openseek("s-sub-clean"),
      fn(_) {  },
    ),
  )
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-sub-clean").to_path(),
  )
  let clean_checkout = repo.join(".worktrees/wt-2")
  assert_true(@fsx.exists(clean_checkout.join("deps/one/.git").to_path()))
  guard archive_session(manager, "s-sub-clean", (_, _) => ()) is Archived(_) else {
    fail("clean submodule checkout must archive without confirmation")
  }
  assert_false(@fsx.exists(clean_checkout.to_path()))
  // Branches and placements survive, and git's worktree bookkeeping is
  // pruned rather than left stale.
  guard @worktree.list(repo.to_string()).worktrees is [first, second] else {
    fail("both worktree placements must survive archive")
  }
  assert_true(
    @gitx.probe(repo, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{first.branch}",
    ])
    is Some(_),
  )
  assert_false(
    @gitx.run(repo, ["worktree", "list", "--porcelain"]).contains(".worktrees/"),
  )
  assert_false(first.present)
  assert_false(second.present)
}

///|
#cfg(not(platform="windows"))
async test "worktree deletion refuses a replaced checkout" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-replaced-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  ignore(
    @worktree.create(
      manager.worktree_host(),
      repo.to_string(),
      @worktree.WorktreeOwner::openseek("s-replaced"),
      fn(_) {  },
    ),
  )
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-replaced").to_path(),
  )
  // Externally delete the checkout and drop an unrelated repository with a
  // staged gitlink at the same path. `git worktree remove --force` validates
  // that the path is this repository's own linked worktree — a standalone
  // repository fails that validation, so both deletion surfaces refuse and
  // leave it untouched.
  let target = repo.join(".worktrees/wt-1")
  @fs.rmdir(target.to_string(), recursive=true)
  @fsx.ensure_dir(target.to_path())
  ignore(@gitx.run(target, ["init", "-q"]))
  let sha = @gitx.run(repo, ["rev-parse", "HEAD"])
  ignore(
    @gitx.run(target, [
      "update-index",
      "--add",
      "--cacheinfo",
      "160000,\{sha},vendored",
    ]),
  )
  let remove_detail = try {
    ignore(
      @worktree.remove(
        manager.worktree_host(),
        repo.to_string(),
        "wt-1",
        true,
        fn(_) {  },
      ),
    )
    "no error"
  } catch {
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(remove_detail != "no error")
  let archive_detail = try {
    ignore(archive_session(manager, "s-replaced", (_, _) => (), force=true))
    "no error"
  } catch {
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(archive_detail != "no error")
  // The unrelated repository survives untouched, registry entry and all.
  assert_true(@fsx.is_dir(target.join(".git").to_path()))
  assert_eq(@worktree.list(repo.to_string()).worktrees.length(), 1)
}
