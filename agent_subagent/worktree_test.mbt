///|
/// Worker tests against a REAL git repository: the launcher forks a worktree
/// for a scripted child, which edits it, and what it changed is captured
/// from git when it ends.

///|
/// A fresh store root holding a repository `repo` with `lib/a.txt` and
/// `other/b.txt` committed; the store's own files are its siblings.
async fn[X] seeded(group : @async.TaskGroup[X]) -> (String, String) {
  let root = @fs.tmpdir(prefix="openseek-worker-")
  group.add_defer(() => @fs.rmdir(root, recursive=true))
  let repo = "\{root}/repo"
  @fs.mkdir(repo)
  @fs.mkdir("\{repo}/lib")
  @fs.mkdir("\{repo}/other")
  @fs.write_file("\{repo}/lib/a.txt", "alpha\n", create_mode=CreateOrTruncate)
  @fs.write_file("\{repo}/other/b.txt", "beta\n", create_mode=CreateOrTruncate)
  for
    args in [
      ["init", "-q"],
      ["config", "user.email", "e2e@test"],
      ["config", "user.name", "e2e"],
      ["add", "-A"],
      ["commit", "-q", "-m", "base"],
    ] {
    guard @subtask.git_require(args, cwd=repo) is Ok(_) else {
      fail("git \{args.join(" ")} failed")
    }
  }
  (root, repo)
}

///|
/// A worker child that checks it was handed its worktree, then runs `edit`
/// in it and reports.
fn worker(edit : String) -> String {
  (
    $|case "$line" in *'"worker_root"'*'"base_oid"'*) ;; *) exit 3 ;; esac
    $|\{edit}
    $|result '"status":"completed","output":{"status":"done"}'
  )
}

///|
async fn Harness::start_worker(
  self : Harness,
  name : String,
  allowed_paths : Array[String],
) -> @agent_subagent.StartResult {
  self.launcher.start(
    kind="worker",
    input={ "task": "t" },
    label=name,
    launch=Direct,
    validate=accept,
    slice={ name, allowed_paths, },
  )
}

///|
#cfg(not(platform="windows"))
async test "a worker's changes are committed on its branch and integrated on request" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      worker("printf 'ALPHA\\n' > lib/a.txt"),
      root~,
      cwd=repo,
    )
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, session~) else {
      fail("the worker did not start")
    }
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Captured))
    guard info.workspace
      is Worktree({ name: "fix-lib", state: Committed(..), path, .. }) else {
      fail("expected a committed worktree")
    }
    // The launching checkout is untouched until it integrates.
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "alpha\n")
    // What it would integrate is its commit against its base.
    guard h.launcher.changes(session) is Some(Ok(diff)) else {
      fail("expected the worker's changes")
    }
    assert_true(diff.contains("lib/a.txt") && diff.contains("+ALPHA"), msg=diff)
    assert_true(h.launcher.changes("nobody") is None)
    guard h.launcher.worktree(session, Integrate)
      is Changed({ state: Integrated, .. }, ..) else {
      fail("expected the worktree to integrate")
    }
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
    assert_false(@fs.exists(path))
    assert_true(h.launcher.changes(session) is Some(Err(_)))
    // The job ended before the integration: the change is published apart.
    assert_true(h.workers is [(s, { state: Integrated, .. })] && s == session)
    assert_true(h.launcher.worktree(session, Integrate) is Refused(_))
    // Gone is gone: a newer slice may reuse its name and directory.
    assert_true(h.launcher.worktree(session, Discard) is Refused(_))
    // The job id names the same worker as its session.
    assert_true(h.launcher.worktree(job_id, Discard) is Refused(_))
  })
}

///|
#cfg(not(platform="windows"))
async test "a worker that strays from its paths is unmergeable, and discard removes it" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      worker("printf 'BETA\\n' > other/b.txt"),
      root~,
      cwd=repo,
    )
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, session~) else {
      fail("the worker did not start")
    }
    guard h.settled(job_id).workspace
      is Worktree({ state: Unmergeable(defects=[_, ..]), path, branch, .. }) else {
      fail("expected an unmergeable worktree")
    }
    assert_true(h.launcher.worktree(session, Integrate) is Refused(_))
    guard h.launcher.worktree(session, Discard)
      is Changed({ state: Discarded, .. }, ..) else {
      fail("expected the worktree to be discarded")
    }
    assert_false(@fs.exists(path))
    assert_true(
      @subtask.git_require(["rev-parse", "--verify", branch], cwd=repo)
      is Err(_),
    )
    assert_eq(@fs.read_file("\{repo}/other/b.txt").text(), "beta\n")
  })
}

///|
#cfg(not(platform="windows"))
async test "a running worker holds its paths and its worktree" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      "touch \"$RESULT.reading\"; cat > /dev/null",
      root~,
      cwd=repo,
    )
    guard h.start_worker("one", ["lib"]) is Started(job_id~, session~) else {
      fail("the worker did not start")
    }
    h.reading()
    guard h.start_worker("two", ["lib/deep"]) is Unavailable(reason) else {
      fail("an overlapping slice started")
    }
    assert_true(reason.contains("overlap"))
    assert_true(h.launcher.worktree(session, Discard) is Refused(_))
    ignore(h.runtime.stop(job_id))
    guard h.settled(job_id).workspace is Worktree({ state: NoChanges, .. }) else {
      fail("expected a worktree with no changes")
    }
    // Its paths are free again.
    guard h.start_worker("two", ["lib/deep"]) is Started(job_id~, ..) else {
      fail("the freed paths were refused")
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}

///|
#cfg(not(platform="windows"))
async test "the next engine captures a worktree whose worker it never ran" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    // An earlier engine of session `p` forked `sr-7` and died with it.
    guard @subtask.provision(
        repo,
        name="fix-lib",
        allowed_paths=["lib"],
        nonce="\{nonce_prefix("p")}sr-7",
        parent_session="p",
      )
      is Ok(provisioned) else {
      fail("provision failed")
    }
    @fs.write_file(
      "\{provisioned.entry.worker_root}/lib/a.txt",
      "ALPHA\n",
      create_mode=CreateOrTruncate,
    )
    // Another session's worktree is not this one's to touch.
    guard @subtask.provision(
        repo,
        name="theirs",
        allowed_paths=["other"],
        nonce="\{nonce_prefix("q")}sr-1",
        parent_session="q",
      )
      is Ok(_) else {
      fail("provision failed")
    }
    let h = harness(group, "", root~, cwd=repo)
    guard h.launcher.worktrees()
      is Ok([("p-sr-7", { state: Committed(..), name: "fix-lib", .. })]) else {
      fail("expected the orphan to be captured")
    }
    assert_true(h.workers is [("p-sr-7", { state: Committed(..), .. })])
    // Once captured, it is listed as it is, with nothing more published.
    guard h.launcher.worktrees() is Ok([(_, { state: Committed(..), .. })]) else {
      fail("expected the captured worktree")
    }
    assert_eq(h.workers.length(), 1)
    guard h.launcher.worktree("p-sr-7", Integrate)
      is Changed({ state: Integrated, .. }, ..) else {
      fail("expected the recovered worktree to integrate")
    }
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
  })
}

///|
/// The nonce prefix the launcher gives the worktrees of session `parent`.
fn nonce_prefix(parent : String) -> String {
  let digest = @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(parent)))
  "\{digest.view(end_offset=8)}-"
}

///|
#cfg(not(platform="windows"))
async test "a worktree git could not capture says why, and is captured again" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    // The worker leaves its index locked, so staging its change fails.
    let h = harness(
      group,
      worker(
        "printf 'ALPHA\\n' > lib/a.txt; touch \"$(git rev-parse --git-dir)/index.lock\"",
      ),
      root~,
      cwd=repo,
    )
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, session~) else {
      fail("the worker did not start")
    }
    guard h.settled(job_id).workspace
      is Worktree({ state: CaptureFailed(reasons=[_, ..]), path, .. }) else {
      fail("expected a failed capture")
    }
    assert_true(h.launcher.worktree(session, Integrate) is Refused(_))
    // Once the cause is gone, listing captures it.
    guard @subtask.git_require(["rev-parse", "--git-dir"], cwd=path)
      is Ok(git_dir) else {
      fail("no git dir")
    }
    @fs.remove("\{git_dir.trim()}/index.lock")
    guard h.launcher.worktrees() is Ok([(s, { state: Committed(..), .. })]) &&
      s == session else {
      fail("expected the worktree to be captured again")
    }
    assert_true(h.workers is [(_, { state: Committed(..), .. })])
  })
}

///|
/// Workers have their own cap below the session's: each builds in its own
/// worktree. A read-only child still starts when the workers are full.
#cfg(not(platform="windows"))
async test "workers are capped apart from the other subagents" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      "touch \"$RESULT.reading\"; cat > /dev/null",
      root~,
      cwd=repo,
      max_workers=1,
    )
    guard h.start_worker("one", ["lib"]) is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    guard h.start_worker("two", ["other"]) is Unavailable(reason) else {
      fail("a second worker started past the cap")
    }
    assert_true(reason.contains("1 workers are already running"), msg=reason)
    let (scout, _) = h.start()
    ignore(h.runtime.stop(job_id))
    ignore(h.runtime.stop(scout))
    ignore(h.settled(job_id))
    // Its slot is back once it has ended.
    guard h.start_worker("two", ["other"]) is Started(job_id~, ..) else {
      fail("the freed worker slot was refused")
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}
