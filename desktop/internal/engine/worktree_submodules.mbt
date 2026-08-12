///|
/// Exact gitlink paths from `git ls-tree -z` or `git ls-files --stage -z`.
/// Reading Git metadata keeps paths with spaces unambiguous and still sees
/// submodules whose working directories are absent.
fn gitlink_paths(metadata : String) -> Array[String] {
  let paths : Array[String] = []
  for record in metadata.split("\u{0}") {
    guard record.has_prefix("160000 ") && record.find("\t") is Some(tab) else {
      continue
    }
    let path = record.view(start_offset=tab + 1).to_owned()
    // A conflicted index can carry several stages for one gitlink.
    if !paths.contains(path) {
      paths.push(path)
    }
  }
  paths
}

///|
/// Populate the new checkout with the same top-level submodules that are
/// initialized in the attached main checkout. Optional, uninitialized
/// submodules stay opt-in. `--checkout` deliberately overrides any configured
/// `!command` update procedure; recursive children use the ordinary checkout
/// strategy too.
async fn provision_initialized_submodules(
  origin : @pathx.Absolute,
  checkout : @pathx.Absolute,
) -> Unit {
  // Worktrees branch from HEAD, not the main checkout's staged index.
  let tree = git_output_text(origin, ["ls-tree", "-r", "-z", "HEAD"])
  let initialized : Array[String] = []
  for path in gitlink_paths(tree) {
    guard git_probe(origin, ["submodule", "status", "--", path]) is Some(status) &&
      !status.is_empty() &&
      !status.has_prefix("-") else {
      continue
    }
    initialized.push(path)
  }
  guard !initialized.is_empty() else { return }
  let args : Array[String] = []
  // `git submodule` does not forward repository-local protocol policy to the
  // clone helper. Preserve an explicit user opt-in for local submodule URLs;
  // never relax the default on the app's own authority.
  if git_probe(origin, ["config", "--get", "protocol.file.allow"])
    is Some("always") {
    args.push("-c")
    args.push("protocol.file.allow=always")
  }
  args.push("submodule")
  args.push("update")
  args.push("--init")
  args.push("--checkout")
  args.push("--recursive")
  args.push("--")
  for path in initialized {
    args.push(path)
  }
  ignore(git_in(checkout, args))
}

///|
test "gitlink paths preserve exact names and deduplicate conflict stages" {
  let index = "100644 dead 0\tplain\u{0}160000 aaa 0\tdeps/one\u{0}160000 bbb 1\twith space\u{0}160000 ccc 2\twith space\u{0}"
  assert_eq(gitlink_paths(index), ["deps/one", "with space"])
}

///|
#cfg(not(platform="windows"))
async test "worktree lifecycle mirrors initialized submodules" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-submodules-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let required = root.join("required")
  let optional = root.join("optional")
  prepare_git_repo(required)
  prepare_git_repo(optional)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  // Local fixture repositories keep the lifecycle test deterministic and
  // offline; production submodules retain Git's normal transport policy.
  ignore(git_in(repo, ["config", "protocol.file.allow", "always"]))
  ignore(
    git_in(repo, [
      "-c",
      "protocol.file.allow=always",
      "submodule",
      "add",
      "-q",
      required.to_string(),
      "deps/required",
    ]),
  )
  ignore(
    git_in(repo, [
      "-c",
      "protocol.file.allow=always",
      "submodule",
      "add",
      "-q",
      optional.to_string(),
      "deps/optional",
    ]),
  )
  ignore(
    git_in(repo, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-am", "add submodules",
    ]),
  )
  ignore(
    git_in(repo, ["submodule", "deinit", "--force", "--", "deps/optional"]),
  )
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  let created = create_worktree(
    manager,
    repo.to_string(),
    "s-submodules",
    fn(_) {  },
    name="with-submodules",
  )
  assert_eq(created.name, "with-submodules")
  let checkout = repo.join(".worktrees/with-submodules")
  assert_eq(
    git_in(checkout.join("deps/required"), ["rev-parse", "HEAD"]),
    git_in(required, ["rev-parse", "HEAD"]),
  )
  assert_false(@fsx.exists(checkout.join("deps/optional/.git").to_path()))
  // Repair follows the same provisioning rule after an external deletion.
  @fs.rmdir(checkout.to_string(), recursive=true)
  ignore(
    create_worktree(
      manager,
      repo.to_string(),
      "s-submodules",
      fn(_) {  },
      name="with-submodules",
    ),
  )
  assert_eq(
    git_in(checkout.join("deps/required"), ["rev-parse", "HEAD"]),
    git_in(required, ["rev-parse", "HEAD"]),
  )
  assert_false(@fsx.exists(checkout.join("deps/optional/.git").to_path()))
  // Removal always passes a single `--force` (plain `worktree remove`
  // refuses any gitlink checkout, clean or not); an external lock takes a
  // second `--force`, so Git itself keeps refusing a locked checkout.
  ignore(
    git_in(repo, [
      "worktree", "lock", "--reason", "held by test", ".worktrees/with-submodules",
    ]),
  )
  let locked_detail = try {
    ignore(
      remove_worktree(manager, repo.to_string(), "with-submodules", false, fn(
        _,
      ) {

      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(locked_detail.contains("locked"))
  assert_true(@fsx.is_dir(checkout.to_path()))
  ignore(git_in(repo, ["worktree", "unlock", ".worktrees/with-submodules"]))
  // Once unlocked, clean removal unregisters and deletes the checkout.
  let removed = remove_worktree(
    manager,
    repo.to_string(),
    "with-submodules",
    false,
    fn(_) {  },
  )
  assert_eq(removed.worktrees.length(), 0)
  assert_false(@fsx.exists(checkout.to_path()))
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive deletes a submodule checkout that git worktree remove refuses" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-sub-archive-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let dep = root.join("dep")
  prepare_git_repo(dep)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(git_in(repo, ["config", "protocol.file.allow", "always"]))
  ignore(
    git_in(repo, [
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
    git_in(repo, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-am", "add submodule",
    ]),
  )
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  // A dirty checkout still confirms first, and the confirmed force retry
  // must delete the checkout even though plain `git worktree remove`
  // refuses over the gitlink.
  ignore(create_worktree(manager, repo.to_string(), "s-sub-dirty", fn(_) {  }))
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-sub-dirty").to_path(),
  )
  let dirty_checkout = repo.join(".worktrees/wt-1")
  assert_true(@fsx.exists(dirty_checkout.join("deps/one/.git").to_path()))
  @fs.write_file(
    dirty_checkout.join("junk.txt").to_string(),
    b"x",
    create_mode=CreateOrTruncate,
  )
  guard archive_session(manager, "s-sub-dirty", _ => ()) is NeedsForce(refusal) else {
    fail("dirty submodule checkout must ask for confirmation")
  }
  assert_eq(refusal.worktree, "wt-1")
  assert_eq(refusal.dirty_paths, ["junk.txt"])
  guard archive_session(manager, "s-sub-dirty", _ => (), force=true)
    is Archived(_) else {
    fail("forced archive must delete the submodule checkout")
  }
  assert_false(@fsx.exists(dirty_checkout.to_path()))
  // A clean submodule checkout archives in one go, exactly like a clean
  // plain worktree.
  ignore(create_worktree(manager, repo.to_string(), "s-sub-clean", fn(_) {  }))
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-sub-clean").to_path(),
  )
  let clean_checkout = repo.join(".worktrees/wt-2")
  assert_true(@fsx.exists(clean_checkout.join("deps/one/.git").to_path()))
  guard archive_session(manager, "s-sub-clean", _ => ()) is Archived(_) else {
    fail("clean submodule checkout must archive without confirmation")
  }
  assert_false(@fsx.exists(clean_checkout.to_path()))
  // Branches and placements survive, and git's worktree bookkeeping is
  // pruned rather than left stale.
  assert_true(
    git_probe(repo, [
      "show-ref", "--verify", "--quiet", "refs/heads/openseek/wt-1",
    ])
    is Some(_),
  )
  assert_false(
    git_in(repo, ["worktree", "list", "--porcelain"]).contains(".worktrees/"),
  )
  guard list_worktrees(repo.to_string()).worktrees is [first, second] else {
    fail("both worktree placements must survive archive")
  }
  assert_false(first.present)
  assert_false(second.present)
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "worktree deletion refuses a replaced checkout" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-replaced-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  ignore(create_worktree(manager, repo.to_string(), "s-replaced", fn(_) {  }))
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-replaced").to_path(),
  )
  // Externally delete the checkout and drop an unrelated repository with a
  // staged gitlink at the same path. `git worktree remove --force` validates
  // that the path is this repository's own linked worktree — a standalone
  // repository fails that validation, so both deletion surfaces refuse and
  // leave it untouched.
  let target = repo.join(".worktrees/wt-1")
  @fs.rmdir(target.to_string(), recursive=true)
  @fsx.ensure_dir(target.to_path())
  ignore(git_in(target, ["init", "-q"]))
  let sha = git_in(repo, ["rev-parse", "HEAD"])
  ignore(
    git_in(target, [
      "update-index",
      "--add",
      "--cacheinfo",
      "160000,\{sha},vendored",
    ]),
  )
  assert_true(
    remove_refusal(manager, repo.to_string(), "wt-1", true) != "no error",
  )
  let archive_detail = try {
    ignore(archive_session(manager, "s-replaced", _ => (), force=true))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(archive_detail != "no error")
  // The unrelated repository survives untouched, registry entry and all.
  assert_true(@fsx.is_dir(target.join(".git").to_path()))
  assert_eq(list_worktrees(repo.to_string()).worktrees.length(), 1)
  @fs.rmdir(root.to_string(), recursive=true)
}
