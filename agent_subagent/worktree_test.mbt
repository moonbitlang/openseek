///|
/// Worker tests against a REAL git repository: the launcher forks a worktree
/// for a scripted child, which edits it; what it changed is captured from
/// git when it ends, and handed over to the launching session.

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
/// Run git in `cwd`, failing the test on its diagnostics.
async fn must_git(cwd : String, args : Array[String]) -> String {
  match @subtask.git_require(args, cwd~) {
    Ok(output) => output
    Err(reason) => fail(reason)
  }
}

///|
#cfg(not(platform="windows"))
async test "a worker's change is handed over as a commit on its branch" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      worker("printf 'ALPHA\\n' > lib/a.txt"),
      root~,
      cwd=repo,
    )
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Captured))
    guard info.workspace
      is Worktree(
        { name: "fix-lib", state: Committed(commit~), path, branch, base, .. }
      ) else {
      fail("expected a committed worktree")
    }
    // The checkout is gone; the branch holds the commit, on the base.
    assert_false(@fs.exists(path))
    assert_eq(must_git(repo, ["rev-parse", branch]).trim(), commit)
    assert_eq(must_git(repo, ["rev-parse", "\{commit}^"]).trim(), base)
    // The launching checkout is untouched until it takes the commit.
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "alpha\n")
    ignore(must_git(repo, ["cherry-pick", commit]))
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
    // Its paths and name are free again at once.
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, ..) else {
      fail("the handed-over paths are still reserved")
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}

///|
#cfg(not(platform="windows"))
async test "a worker that strays from its paths keeps its files, and a reuse of its name leaves them" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      worker("printf 'BETA\\n' > other/b.txt"),
      root~,
      cwd=repo,
    )
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    guard h.settled(job_id).workspace
      is Worktree({ state: Unmergeable(defects=[_, ..]), path, .. }) else {
      fail("expected an unmergeable worktree")
    }
    assert_eq(@fs.read_file("\{path}/other/b.txt").text(), "BETA\n")
    assert_eq(@fs.read_file("\{repo}/other/b.txt").text(), "beta\n")
    // A new slice of the same name gets a directory of its own.
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, ..) else {
      fail("the name is still reserved")
    }
    guard h.settled(job_id).workspace is Worktree({ path: second, .. }) else {
      fail("expected a worktree")
    }
    assert_true(second != path)
    assert_eq(@fs.read_file("\{path}/other/b.txt").text(), "BETA\n")
  })
}

///|
#cfg(not(platform="windows"))
async test "a running worker holds its paths; one that changed nothing leaves nothing" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      "touch \"$RESULT.reading\"; cat > /dev/null",
      root~,
      cwd=repo,
    )
    guard h.start_worker("one", ["lib"]) is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    h.reading()
    guard h.start_worker("two", ["lib/deep"]) is Unavailable(reason) else {
      fail("an overlapping slice started")
    }
    assert_true(reason.contains("overlap"))
    ignore(h.runtime.stop(job_id))
    guard h.settled(job_id).workspace
      is Worktree({ state: NoChanges, path, branch, .. }) else {
      fail("expected a worktree with no changes")
    }
    assert_false(@fs.exists(path))
    assert_true(
      @subtask.git_require(["rev-parse", "--verify", branch], cwd=repo)
      is Err(_),
    )
    guard h.start_worker("two", ["lib/deep"]) is Started(job_id~, ..) else {
      fail("the freed paths were refused")
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}

///|
#cfg(not(platform="windows"))
async test "a worktree git cannot capture is retried, then handed over with its files" {
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
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    guard h.settled(job_id).workspace
      is Worktree({ state: CaptureFailed(reasons=[_, ..]), path, .. }) else {
      fail("expected a failed capture")
    }
    assert_eq(@fs.read_file("\{path}/lib/a.txt").text(), "ALPHA\n")
    // Handed over all the same: its paths are free.
    guard h.start_worker("other-lib", ["lib"]) is Started(job_id~, ..) else {
      fail("a failed capture still holds its paths")
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}

///|
#cfg(not(platform="windows"))
async test "a worktree an earlier engine left is handed over, once, with its session" {
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
      is Ok(theirs) else {
      fail("provision failed")
    }
    let h = harness(group, "", root~, cwd=repo)
    guard h.launcher.recover()
      is [("p-sr-7", { state: Committed(commit~), name: "fix-lib", .. })] else {
      fail("expected the orphan to be handed over")
    }
    ignore(must_git(repo, ["cherry-pick", commit]))
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
    assert_true(h.launcher.recover() is [])
    assert_true(@fs.exists(theirs.entry.worker_root))
  })
}

///|
/// The nonce prefix the launcher gives the worktrees of session `parent`.
fn nonce_prefix(parent : String) -> String {
  let digest = @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(parent)))
  "\{digest.view(end_offset=8)}-"
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

///|
/// Workers started at once are admitted against the cap at once: claiming
/// their sessions suspends, and the cap must hold across it.
#cfg(not(platform="windows"))
async test "workers started in parallel stay within the cap" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    let h = harness(
      group,
      "touch \"$RESULT.reading\"; cat > /dev/null",
      root~,
      cwd=repo,
      max_workers=1,
    )
    let results : Array[@agent_subagent.StartResult] = []
    @async.with_task_group(starts => {
      starts.spawn_bg(() => results.push(h.start_worker("one", ["lib"])))
      starts.spawn_bg(() => results.push(h.start_worker("two", ["other"])))
    })
    let started = results.filter_map(result => {
      match result {
        Started(job_id~, ..) => Some(job_id)
        _ => None
      }
    })
    assert_eq(started.length(), 1)
    for job_id in started {
      ignore(h.runtime.stop(job_id))
      ignore(h.settled(job_id))
    }
  })
}

///|
/// A change an earlier engine captured and handed over as it shut down
/// reached no notice: the next engine reports it, once, while its branch is
/// still there to take.
#cfg(not(platform="windows"))
async test "a change handed over at shutdown is reported until it is taken" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    guard @subtask.provision(
        repo,
        name="fix-lib",
        allowed_paths=["lib"],
        nonce="\{nonce_prefix("p")}sr-3",
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
    // What the earlier engine did as it ended: capture, then release.
    let captured = @subtask.capture(provisioned.geometry, provisioned.entry)
    guard @subtask.hand_off(provisioned.geometry, captured.entry)
      is Ok(released) else {
      fail("hand-off failed")
    }
    let h = harness(group, "", root~, cwd=repo)
    guard h.launcher.recover()
      is [("p-sr-3", { state: Committed(commit~), .. })] else {
      fail("expected the unreported change")
    }
    assert_eq(Some(commit), released.commit_oid)
    assert_true(h.launcher.recover() is [])
    // Once it is taken and its branch deleted, nothing is left to report.
    ignore(must_git(repo, ["cherry-pick", commit]))
    ignore(must_git(repo, ["branch", "-D", released.branch]))
    let fresh = harness(group, "", root~, cwd=repo)
    assert_true(fresh.launcher.recover() is [])
  })
}

///|
/// A start cut short after its reservation is saved (here while the
/// dependency cache is being copied in) leaves no worker behind: recovery
/// takes what it forked, and the same slice can start again.
#cfg(not(platform="windows"))
async test "a cancelled worker start leaves nothing that blocks a retry" {
  @async.with_task_group(group => {
    let (root, repo) = seeded(group)
    // A dependency cache big enough that copying it is a window to cancel in.
    for i in 0..<400 {
      let dir = "\{repo}/.mooncakes/pkg\{i}"
      @fs.mkdir(dir, recursive=true)
      @fs.write_file("\{dir}/f.txt", "x", create_mode=CreateOrTruncate)
    }
    let h = harness(
      group,
      "touch \"$RESULT.reading\"; cat > /dev/null",
      root~,
      cwd=repo,
    )
    let registry = "\{repo}/.git/openseek/subtasks"
    let start = group.spawn(() => h.start_worker("fix-lib", ["lib"]))
    let mut saw_running = false
    for _ in 0..<2000 {
      for name in (@fs.readdir(registry) catch { _ => [] }) {
        let text = @fs.read_file("\{registry}/\{name}").text() catch { _ => "" }
        if name.has_suffix(".json") && text.contains("\"Running\"") {
          saw_running = true
        }
      }
      if saw_running {
        break
      }
      @async.sleep(1)
    }
    start.cancel()
    ignore(start.wait()) catch {
      _ => ()
    }
    // Whether or not the cancel landed before the job registered, what is
    // left blocks nothing: recovery takes an orphan, and a retry starts.
    ignore(h.launcher.recover())
    guard h.start_worker("fix-lib", ["lib"]) is Started(job_id~, ..) else {
      fail(
        "the cancelled start still blocks its slice (saw running: \{saw_running})",
      )
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}
