///|
/// Unsandboxed setup helper: run git and require success.
async fn git_setup(args : Array[String], cwd : String) -> String {
  let (code, data) = @process.collect_stdout(
    "git",
    args,
    inherit_env=true,
    cwd=cwd.view(),
  )
  guard code == 0 else { fail("git failed in \{cwd}: \{data.text()}") }
  data.text()
}

///|
/// The worker profile, end to end on a real repository with real linked
/// worktrees: the worker tree is writable, `git status`/`add`-class reads of
/// its private admin dir work, and every shared surface — origin files, a
/// sibling worktree, the shared object store (via commit), the gitfile
/// pointer — is kernel-denied. Guarded on real sandbox availability.
async test "the worker profile confines writes to the worker tree" {
  @vfs.with_tmpdir(prefix="openseek-worker-profile-", dir => {
    // Fixture: a repo with one commit and two linked worktrees.
    let repo = "\{dir}/repo"
    @fs.mkdir(repo)
    let _ = git_setup(["init", "-q"], repo)
    let _ = git_setup(["config", "user.email", "e2e@test"], repo)
    let _ = git_setup(["config", "user.name", "e2e"], repo)
    @vfs.write_text(repo, "seed.txt", "seed\n")
    let _ = git_setup(["add", "-A"], repo)
    let _ = git_setup(["commit", "-q", "-m", "base"], repo)
    let _ = git_setup(
      ["worktree", "add", "-q", ".worktrees/w1", "-b", "w1"],
      repo,
    )
    let _ = git_setup(
      ["worktree", "add", "-q", ".worktrees/w2", "-b", "w2"],
      repo,
    )
    let origin = @fs.realpath(repo)
    let worker_root = @fs.realpath("\{repo}/.worktrees/w1")
    let sibling = @fs.realpath("\{repo}/.worktrees/w2")
    let admin_raw = git_setup(["rev-parse", "--absolute-git-dir"], worker_root)
    let worker_admin_dir = @fs.realpath(admin_raw.trim().to_owned())
    let common = @fs.realpath("\{origin}/.git")
    let deny_roots = [common, origin, sibling]
    async fn probe(cmd : String) -> @sandbox.SandboxedCommand? {
      @sandbox.SandboxedCommand::create_worker_if_available(
        Shell(cmd),
        deny_roots~,
        worker_root~,
        worker_admin_dir~,
      )
    }

    guard probe(":") is Some(_) else {
      println("sandbox-exec unavailable; skipping")
      return
    }
    // 1. The worker's own tree is writable.
    guard probe("printf x > \{worker_root}/scratch.txt") is Some(own) else {
      fail("probe build failed")
    }
    let (own_exit, _) = merged_output_text(own)
    assert_eq(own_exit, 0)
    assert_true(@fs.exists("\{worker_root}/scratch.txt"))
    // 2. Reads of git state through the private admin dir keep working.
    guard probe("cd \{worker_root} && git status --porcelain") is Some(status) else {
      fail("probe build failed")
    }
    let (status_exit, _) = merged_output_text(status)
    assert_eq(status_exit, 0)
    // 3. Origin files survive (the denial is the assertion that matters).
    guard probe("printf x > \{origin}/seed.txt") is Some(against_origin) else {
      fail("probe build failed")
    }
    let (origin_exit, origin_text) = merged_output_text(against_origin)
    assert_true(origin_exit != 0)
    assert_eq(@fs.read_file("\{origin}/seed.txt").text(), "seed\n")
    assert_true(against_origin.output_reports_denial(origin_text))
    // The guidance follows the profile. A worker that hit its boundary must not
    // get the source-write text: it would be told to make source changes with
    // `edit`, which is neither what failed nor something it needs — its own tree
    // is writable.
    let guidance = against_origin.denial_feedback()
    assert_true(guidance.contains("OUTSIDE your worktree"))
    assert_false(guidance.contains("line-anchored `edit`"))
    // 4. A sibling worktree is not writable.
    guard probe("printf x > \{sibling}/intrude.txt") is Some(against_sibling) else {
      fail("probe build failed")
    }
    let (sibling_exit, _) = merged_output_text(against_sibling)
    assert_true(sibling_exit != 0)
    assert_false(@fs.exists("\{sibling}/intrude.txt"))
    // 5. The gitfile pointer is pinned even though it lives in the allowed
    // worker root.
    guard probe("printf y > \{worker_root}/.git") is Some(against_gitfile) else {
      fail("probe build failed")
    }
    let (gitfile_exit, _) = merged_output_text(against_gitfile)
    assert_true(gitfile_exit != 0)
    assert_true(
      @fs.read_file("\{worker_root}/.git").text().has_prefix("gitdir:"),
    )
    // 6. Commits cannot land: blob/object writes hit the shared store. The
    // add/commit chain fails and the branch still holds only the base commit.
    guard probe("cd \{worker_root} && git add -A && git commit -q -m steal")
      is Some(against_store) else {
      fail("probe build failed")
    }
    let (commit_exit, _) = merged_output_text(against_store)
    assert_true(commit_exit != 0)
    let log = git_setup(["log", "--oneline"], worker_root)
    assert_eq(log.trim().to_owned().split("\n").count(), 1)
  })
}

///|
/// Caller-bug validation raises instead of failing open.
async test "worker profile validation rejects impossible geometries" {
  @vfs.with_tmpdir(prefix="openseek-worker-profile-validate-", dir => {
    let root = @fs.realpath(dir)
    // Worker root not nested below any denied root.
    let outside = @sandbox.SandboxedCommand::create_worker_if_available(
      Shell(":"),
      deny_roots=["\{root}/repo"],
      worker_root="\{root}/elsewhere",
      worker_admin_dir="\{root}/repo/.git/worktrees/x",
    ) catch {
      _ => None
    }
    assert_true(outside is None)
    // A denied root below the worker root would be re-opened wholesale.
    let reopened = @sandbox.SandboxedCommand::create_worker_if_available(
      Shell(":"),
      deny_roots=["\{root}/repo", "\{root}/repo/.worktrees/w1/nested"],
      worker_root="\{root}/repo/.worktrees/w1",
      worker_admin_dir="\{root}/repo/.git/worktrees/w1",
    ) catch {
      _ => None
    }
    assert_true(reopened is None)
    // A miscomputed admin dir that IS a denied root would re-open it.
    let admin_reopens = @sandbox.SandboxedCommand::create_worker_if_available(
      Shell(":"),
      deny_roots=["\{root}/repo", "\{root}/repo/.git"],
      worker_root="\{root}/repo/.worktrees/w1",
      worker_admin_dir="\{root}/repo/.git",
    ) catch {
      _ => None
    }
    assert_true(admin_reopens is None)
  })
}
