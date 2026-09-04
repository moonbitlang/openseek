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
/// strategy too. The timeout is the caller's validated workspace-settings
/// snapshot; expiry raises into the existing create-or-repair rollback path.
async fn provision_initialized_submodules(
  origin : @pathx.Absolute,
  checkout : @pathx.Absolute,
  timeout_seconds : Int,
) -> Unit {
  // Worktrees branch from HEAD, not the main checkout's staged index.
  let tree = @gitx.output(origin, ["ls-tree", "-r", "-z", "HEAD"])
  let initialized : Array[String] = []
  for path in gitlink_paths(tree) {
    guard @gitx.probe(origin, ["submodule", "status", "--", path])
      is Some(status) &&
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
  if @gitx.probe(origin, ["config", "--get", "protocol.file.allow"])
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
  guard @async.with_timeout_opt(timeout_seconds * 1_000, () => {
      @gitx.run(checkout, args)
    })
    is Some(_) else {
    raise WorktreeError(
      "Submodules did not finish initializing within \{timeout_seconds} seconds. Increase the checkout timeout in Workspace Settings or leave submodules uninitialized.",
    )
  }
}

///|
test "gitlink paths preserve exact names and deduplicate conflict stages" {
  let index = "100644 dead 0\tplain\u{0}160000 aaa 0\tdeps/one\u{0}160000 bbb 1\twith space\u{0}160000 ccc 2\twith space\u{0}"
  assert_eq(gitlink_paths(index), ["deps/one", "with space"])
}

///|
#cfg(not(platform="windows"))
async test "submodule checkout stops at its hard timeout" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let root = worktree_test_root("openseek-worktree-sub-timeout-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let dependency = root.join("dependency")
  prepare_git_repo(dependency)
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
      dependency.to_string(),
      "deps/one",
    ]),
  )
  ignore(
    @gitx.run(repo, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-am", "add submodule",
    ]),
  )
  let checkout = root.join("checkout")
  ignore(@gitx.run(repo, ["worktree", "add", "-q", checkout.to_string()]))
  let detail = try {
    provision_initialized_submodules(repo, checkout, 0)
    "no error"
  } catch {
    WorktreeError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_eq(
    detail, "Submodules did not finish initializing within 0 seconds. Increase the checkout timeout in Workspace Settings or leave submodules uninitialized.",
  )
}

///|
#cfg(not(platform="windows"))
async test "worktree lifecycle mirrors initialized submodules" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-submodules-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let required = root.join("required")
  let optional = root.join("optional")
  prepare_git_repo(required)
  prepare_git_repo(optional)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  // Local fixture repositories keep the lifecycle test deterministic and
  // offline; production submodules retain Git's normal transport policy.
  ignore(@gitx.run(repo, ["config", "protocol.file.allow", "always"]))
  ignore(
    @gitx.run(repo, [
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
    @gitx.run(repo, [
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
    @gitx.run(repo, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-am", "add submodules",
    ]),
  )
  ignore(
    @gitx.run(repo, ["submodule", "deinit", "--force", "--", "deps/optional"]),
  )
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  let created = create(
    host,
    repo.to_string(),
    WorktreeOwner::openseek("s-submodules"),
    fn(_) {  },
    name="with-submodules",
  )
  assert_eq(created.name, "with-submodules")
  let checkout = repo.join(".worktrees/with-submodules")
  assert_eq(
    @gitx.run(checkout.join("deps/required"), ["rev-parse", "HEAD"]),
    @gitx.run(required, ["rev-parse", "HEAD"]),
  )
  assert_false(@fsx.exists(checkout.join("deps/optional/.git").to_path()))
  // Repair follows the same provisioning rule after an external deletion.
  @fs.rmdir(checkout.to_string(), recursive=true)
  ignore(
    create(
      host,
      repo.to_string(),
      WorktreeOwner::openseek("s-submodules"),
      fn(_) {  },
      name="with-submodules",
    ),
  )
  assert_eq(
    @gitx.run(checkout.join("deps/required"), ["rev-parse", "HEAD"]),
    @gitx.run(required, ["rev-parse", "HEAD"]),
  )
  assert_false(@fsx.exists(checkout.join("deps/optional/.git").to_path()))
  // Removal always passes a single `--force` (plain `worktree remove`
  // refuses any gitlink checkout, clean or not); an external lock takes a
  // second `--force`, so Git itself keeps refusing a locked checkout.
  ignore(
    @gitx.run(repo, [
      "worktree", "lock", "--reason", "held by test", ".worktrees/with-submodules",
    ]),
  )
  let locked_detail = try {
    ignore(remove(host, repo.to_string(), "with-submodules", false, fn(_) {  }))
    "no error"
  } catch {
    WorktreeError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(locked_detail.contains("locked"))
  assert_true(@fsx.is_dir(checkout.to_path()))
  ignore(@gitx.run(repo, ["worktree", "unlock", ".worktrees/with-submodules"]))
  // Once unlocked, clean removal unregisters and deletes the checkout.
  let removed = remove(host, repo.to_string(), "with-submodules", false, fn(_) {

  })
  assert_eq(removed.worktrees.length(), 0)
  assert_false(@fsx.exists(checkout.to_path()))
  // This workspace setting leaves even an initialized main-checkout
  // submodule untouched in subsequent worktrees.
  ignore(
    @workspaces.update_settings(
      repo.to_string(),
      fn(_) {  },
      checkout_submodules=false,
    ),
  )
  let skipped = create(
    host,
    repo.to_string(),
    WorktreeOwner::openseek("s-without-submodules"),
    fn(_) {  },
    name="without-submodules",
  )
  assert_eq(skipped.name, "without-submodules")
  let skipped_checkout = repo.join(".worktrees/without-submodules")
  assert_false(
    @fsx.exists(skipped_checkout.join("deps/required/.git").to_path()),
  )
}
