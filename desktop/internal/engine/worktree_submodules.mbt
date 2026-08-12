///|
/// Exact gitlink `(path, target commit)` pairs from `git ls-tree -z` or
/// `git ls-files --stage -z`. Reading Git metadata keeps paths with spaces
/// unambiguous and still sees submodules whose working directories are
/// absent. The two commands lay their records out differently —
/// `160000 <sha> <stage>` for the index, `160000 commit <sha>` for a tree —
/// and a conflicted index can carry several stages (and so several targets)
/// for one gitlink.
fn gitlink_entries(metadata : String) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  for record in metadata.split("\u{0}") {
    guard record.has_prefix("160000 ") && record.find("\t") is Some(tab) else {
      continue
    }
    let path = record.view(start_offset=tab + 1).to_owned()
    let fields = record
      .view(end_offset=tab)
      .split(" ")
      .map(field => field.to_owned())
      .collect()
    let sha = match fields {
      [_, "commit", sha] => sha
      [_, sha, _] => sha
      _ => continue
    }
    if !entries.contains((path, sha)) {
      entries.push((path, sha))
    }
  }
  entries
}

///|
fn gitlink_paths(metadata : String) -> Array[String] {
  let paths : Array[String] = []
  for entry in gitlink_entries(metadata) {
    if !paths.contains(entry.0) {
      paths.push(entry.0)
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
/// Every gitlink path of `checkout`: the index's, plus HEAD's — a staged
/// removal can hide a committed gitlink from the index while Git still
/// treats the worktree as containing submodules.
async fn checkout_gitlink_paths(checkout : @pathx.Absolute) -> Array[String] {
  let index = git_output_text(checkout, ["ls-files", "--stage", "-z", "--"])
  let paths = gitlink_paths(index)
  // An unborn HEAD (a repository with no commits yet) has no committed tree
  // to inspect; only the index can carry gitlinks then.
  guard git_probe(checkout, ["ls-tree", "-r", "-z", "HEAD"]) is Some(tree) else {
    return paths
  }
  for path in gitlink_paths(tree) {
    if !paths.contains(path) {
      paths.push(path)
    }
  }
  paths
}

///|
/// Preserve submodule commits that exist only inside `checkout` before it is
/// deleted. A linked worktree's submodule clones live under the worktree's
/// private gitdir (`.git/worktrees/<id>/modules/...`), which the deletion's
/// `worktree prune` destroys — while the surviving branch keeps gitlinks
/// pointing at whatever those clones held. What must stay resolvable are
/// the gitlink TARGETS the retained history references — HEAD's and the
/// index's, not merely wherever the submodule happens to be checked out —
/// plus the submodule's current HEAD; each is ensured present in the
/// workspace's own clone of the same submodule (fetched by exact commit
/// when missing — the target may be unreachable from the source's refs
/// after a submodule reset, hence `allowAnySHA1InWant`) and anchored under
/// `refs/openseek/preserved/<sha>`, so a later gc cannot reap it even when
/// it arrived dangling. A target absent from the source clone too is
/// skipped: deletion destroys nothing there. A submodule initialized only
/// inside the checkout has no durable clone to preserve into and is
/// skipped — its `.gitmodules` URL on the retained branch keeps an
/// explicit re-init possible. A failed transfer refuses the deletion
/// rather than proceeding to destroy the only copy.
async fn preserve_submodule_commits(
  workspace : @pathx.Absolute,
  name : String,
  checkout : @pathx.Absolute,
) -> Unit {
  let wanted : Map[String, Array[String]] = Map([])
  let index = git_output_text(checkout, ["ls-files", "--stage", "-z", "--"])
  let tree = git_probe(checkout, ["ls-tree", "-r", "-z", "HEAD"]).unwrap_or("")
  for metadata in [index, tree] {
    for entry in gitlink_entries(metadata) {
      let (path, sha) = entry
      let shas = if wanted.get(path) is Some(existing) {
        existing
      } else {
        let fresh : Array[String] = []
        wanted[path] = fresh
        fresh
      }
      if !shas.contains(sha) {
        shas.push(sha)
      }
    }
  }
  for path, shas in wanted {
    let source = checkout.join(path)
    let initialized = @fsx.exists(source.join(".git").to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    guard initialized else { continue }
    if git_probe(source, ["rev-parse", "HEAD"]) is Some(head) &&
      !head.is_empty() &&
      !shas.contains(head) {
      shas.push(head)
    }
    let destination = workspace.join(path)
    let has_destination = @fsx.exists(destination.join(".git").to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    guard has_destination else { continue }
    for sha in shas {
      let present = git_probe(destination, ["cat-file", "-e", "\{sha}^{commit}"])
        is Some(_)
      if !present &&
        !(git_probe(source, ["cat-file", "-e", "\{sha}^{commit}"]) is Some(_)) {
        continue
      }
      try {
        if !present {
          ignore(
            git_in(destination, [
              "-c",
              "uploadpack.allowAnySHA1InWant=true",
              "fetch",
              "--quiet",
              source.to_string(),
              sha,
            ]),
          )
        }
        ignore(
          git_in(destination, [
            "update-ref",
            "refs/openseek/preserved/\{sha}",
            sha,
          ]),
        )
      } catch {
        error if @async.is_being_cancelled() => raise error
        EngineError(detail) =>
          raise EngineError(
            "could not preserve \{path} commits of worktree \{name}: \{detail}",
          )
        error =>
          raise EngineError(
            "could not preserve \{path} commits of worktree \{name}: \{error}",
          )
      }
    }
  }
}

///|
test "gitlink paths preserve exact names and deduplicate conflict stages" {
  let index = "100644 dead 0\tplain\u{0}160000 aaa 0\tdeps/one\u{0}160000 bbb 1\twith space\u{0}160000 ccc 2\twith space\u{0}"
  assert_eq(gitlink_paths(index), ["deps/one", "with space"])
  // Conflict stages keep one path but every distinct target commit.
  assert_eq(gitlink_entries(index), [
    ("deps/one", "aaa"),
    ("with space", "bbb"),
    ("with space", "ccc"),
  ])
  // `ls-tree` lays the record out as `160000 commit <sha>`.
  let tree = "100644 blob dead\tplain\u{0}160000 commit abc\tdeps/one\u{0}"
  assert_eq(gitlink_entries(tree), [("deps/one", "abc")])
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
  // Git's own `worktree remove` refuses a tree containing gitlinks; the app's
  // fallback must honor an external lock before deleting a clean checkout.
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
  assert_true(locked_detail.contains("is locked"))
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
  // must delete the checkout even though `git worktree remove --force`
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
  // A committed gitlink target must survive even when the submodule was
  // since reset elsewhere: the commit is dangling in the checkout's clone
  // (reachable from no ref), so preservation has to fetch it by exact sha.
  let base = git_in(dirty_checkout.join("deps/one"), ["rev-parse", "HEAD"])
  ignore(
    git_in(dirty_checkout.join("deps/one"), [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "--allow-empty", "-m", "committed-then-reset",
    ]),
  )
  let divergent = git_in(dirty_checkout.join("deps/one"), ["rev-parse", "HEAD"])
  ignore(git_in(dirty_checkout, ["add", "deps/one"]))
  ignore(
    git_in(dirty_checkout, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-m", "bump gitlink",
    ]),
  )
  ignore(
    git_in(dirty_checkout.join("deps/one"), ["reset", "-q", "--hard", base]),
  )
  guard archive_session(manager, "s-sub-dirty", _ => (), force=true)
    is Archived(_) else {
    fail("forced archive must delete the submodule checkout")
  }
  assert_false(@fsx.exists(dirty_checkout.to_path()))
  assert_true(
    git_probe(repo.join("deps/one"), ["cat-file", "-e", "\{divergent}^{commit}"])
    is Some(_),
  )
  assert_eq(
    git_probe(repo.join("deps/one"), [
      "rev-parse",
      "refs/openseek/preserved/\{divergent}",
    ]),
    Some(divergent),
  )
  // A clean submodule checkout archives in one go, exactly like a clean
  // plain worktree — and commits that exist only inside its private
  // submodule clone are preserved into the workspace's clone first, so the
  // retained branch's gitlink stays resolvable after the clone is pruned.
  ignore(create_worktree(manager, repo.to_string(), "s-sub-clean", fn(_) {  }))
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-sub-clean").to_path(),
  )
  let clean_checkout = repo.join(".worktrees/wt-2")
  assert_true(@fsx.exists(clean_checkout.join("deps/one/.git").to_path()))
  ignore(
    git_in(clean_checkout.join("deps/one"), [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "--allow-empty", "-m", "worktree-only",
    ]),
  )
  let preserved_sha = git_in(clean_checkout.join("deps/one"), [
    "rev-parse", "HEAD",
  ])
  ignore(git_in(clean_checkout, ["add", "deps/one"]))
  ignore(
    git_in(clean_checkout, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-m", "bump gitlink",
    ]),
  )
  assert_true(
    git_probe(repo.join("deps/one"), ["cat-file", "-e", preserved_sha]) is None,
  )
  guard archive_session(manager, "s-sub-clean", _ => ()) is Archived(_) else {
    fail("clean submodule checkout must archive without confirmation")
  }
  assert_false(@fsx.exists(clean_checkout.to_path()))
  assert_true(
    git_probe(repo.join("deps/one"), [
      "cat-file",
      "-e",
      "\{preserved_sha}^{commit}",
    ])
    is Some(_),
  )
  assert_eq(
    git_probe(repo.join("deps/one"), [
      "rev-parse",
      "refs/openseek/preserved/\{preserved_sha}",
    ]),
    Some(preserved_sha),
  )
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
async test "gitlink deletion fallback refuses a replaced checkout" {
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
  // staged gitlink at the same path. Its gitlinks route deletion into the
  // recursive fallback, which must then refuse: the target is a standalone
  // repository, not this workspace's linked worktree.
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
    remove_refusal(manager, repo.to_string(), "wt-1", true).contains(
      "another tool may own it",
    ),
  )
  let archive_detail = try {
    ignore(archive_session(manager, "s-replaced", _ => (), force=true))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(archive_detail.contains("another tool may own it"))
  // The unrelated repository survives untouched, registry entry and all.
  assert_true(@fsx.is_dir(target.join(".git").to_path()))
  assert_eq(list_worktrees(repo.to_string()).worktrees.length(), 1)
  @fs.rmdir(root.to_string(), recursive=true)
}
