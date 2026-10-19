///|
/// Directory workers against REAL git repositories: two checkouts side by
/// side in a plain directory, as a session started over many repositories
/// sees them.

///|
/// A fresh store root holding `work/a` and `work/b`, each a repository with
/// `lib/a.txt` committed; `work` itself is a plain directory.
async fn[X] repositories(group : @async.TaskGroup[X]) -> (String, String) {
  let root = @fs.tmpdir(prefix="openseek-directory-")
  group.add_defer(() => @fs.rmdir(root, recursive=true))
  let work = "\{root}/work"
  for name in ["a", "b"] {
    let repo = "\{work}/\{name}"
    @fs.mkdir("\{repo}/lib", recursive=true)
    @fs.write_file("\{repo}/lib/a.txt", "alpha\n", create_mode=CreateOrTruncate)
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
  }
  (root, work)
}

///|
async fn Harness::start_in(
  self : Harness,
  directory : String,
) -> @agent_subagent.StartResult {
  self.launcher.start(
    kind="worker",
    input={ "task": "t" },
    label=directory,
    launch=Direct,
    validate=accept,
    workplace=Directory(directory),
  )
}

///|
#cfg(not(platform="windows"))
async test "a directory worker changes its directory in place and leaves the change there" {
  @async.with_task_group(group => {
    let (root, work) = repositories(group)
    let h = harness(
      group,
      (
        $|printf '%s' "$line" > "$RESULT.request"
        $|printf 'ALPHA\{"\\n"}' > lib/a.txt
        $|result '"status":"completed","output":{"status":"done"}'
      ),
      root~,
      cwd=work,
    )
    guard h.start_in("a") is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    let info = h.settled(job_id)
    assert_true(info.outcome is Some(Captured))
    let mine = @fs.realpath("\{work}/a")
    assert_eq(info.workspace, Directory(path=mine))
    // It ran there, with what its sandbox needs: its directory, and the
    // checkout as what is denied.
    let request : Json = @json.parse(
      @fs.read_file("\{root}/results/\{info.session}.result.json.request").text(),
    )
    guard request
      is {
        "input": {
          "mode": "directory",
          "worker_root": String(worker_root),
          "deny_roots": [String(denied), ..],
          "git_index": String(git_index),
          ..
        },
        ..
      } else {
      fail("the worker was not given its directory: \{request.stringify()}")
    }
    assert_eq(worker_root, mine)
    assert_eq(denied, @fs.realpath(work))
    // The one piece of git state it may write: its repository's index.
    assert_eq(git_index, "\{mine}/.git/index")
    // Its change is left uncommitted in its repository; the other is untouched.
    assert_eq(@fs.read_file("\{mine}/lib/a.txt").text(), "ALPHA\n")
    let status = @subtask.git_require(["status", "--porcelain"], cwd=mine)
    assert_true(status is Ok(status) && status.contains("lib/a.txt"))
    let log = @subtask.git_require(["log", "--oneline"], cwd=mine)
    assert_true(log is Ok(log) && log.trim().split("\n").count() == 1)
    assert_eq(@fs.read_file("\{work}/b/lib/a.txt").text(), "alpha\n")
    // What to do with it names the directory.
    guard @agent_subagent.describe_workspace(info.workspace) is Some(text) else {
      fail("a directory worker's change was not described")
    }
    assert_true(text.contains("git -C \{mine} diff"))
  })
}

///|
#cfg(not(platform="windows"))
async test "a running directory worker holds its directory, and only a directory below the checkout is given" {
  @async.with_task_group(group => {
    let (root, work) = repositories(group)
    let h = harness(
      group,
      "touch \"$RESULT.reading\"; cat > /dev/null",
      root~,
      cwd=work,
    )
    guard h.start_in("a") is Started(job_id~, ..) else {
      fail("the worker did not start")
    }
    h.reading()
    // The same directory, one inside it, or one holding it is refused.
    for overlapping in ["a", "a/lib", "./a/", "\{work}/a"] {
      guard h.start_in(overlapping) is Unavailable(reason) else {
        fail("an overlapping directory \{overlapping} was given")
      }
      assert_true(reason.contains("overlaps"))
    }
    // A directory that is not below the checkout, or none, is refused; so
    // is one inside a MoonBit module (it builds at the module's root), and
    // git metadata or a worktree.
    @fs.mkdir("\{work}/m/pkg", recursive=true)
    @fs.write_file("\{work}/m/moon.mod", "name = \"m\"\n")
    @fs.mkdir("\{work}/b/.worktrees/w1", recursive=true)
    let module_root = "\{@fs.realpath(work)}/m"
    for
      (path, because) in [
        (".", "below the session's checkout"),
        (root, "below the session's checkout"),
        ("missing", "does not exist"),
        ("a/lib/a.txt", "not a directory"),
        ("m/pkg", "inside the MoonBit module or workspace at \{module_root}"),
        ("b/.worktrees/w1", "a worktree"),
        ("b/.git", "git metadata"),
      ] {
      guard h.start_in(path) is Unavailable(reason) else {
        fail("\{path} was given")
      }
      assert_true(reason.contains(because))
    }
    // Another repository, or a module's root, is independent of it.
    guard h.start_in("b") is Started(job_id=other, ..) else {
      fail("a separate repository was refused")
    }
    guard h.start_in("m") is Started(job_id=root_job, ..) else {
      fail("a module's root was refused")
    }
    for id in [job_id, other, root_job] {
      ignore(h.runtime.stop(id))
      ignore(h.settled(id))
    }
    // Ended, its directory is free.
    guard h.start_in("a/lib") is Started(job_id~, ..) else {
      fail("the freed directory was refused")
    }
    ignore(h.runtime.stop(job_id))
    ignore(h.settled(job_id))
  })
}

///|
/// An earlier engine's job record of a subagent, as it was last published.
fn earlier_job(
  id : String,
  workspace : @protocol.SubagentWorkspace,
  outcome : @protocol.SubagentOutcome?,
) -> @protocol.JobRecord {
  {
    generation: "gen-dead",
    id,
    revision: 2,
    command: "openseek run --kind worker --session p-sr-1",
    description: Some("upgrade a"),
    cwd: None,
    state: if outcome is Some(_) {
      Exited(0)
    } else {
      Running
    },
    started_at_ms: 100L,
    backgrounded_at_ms: 100L,
    finished_at_ms: None,
    last_output_at_ms: None,
    output_file: None,
    output_persistent: true,
    output_bytes: 0L,
    output_chars: 0,
    output_truncated: false,
    invalid_utf8: false,
    output_error: None,
    persistence_error: None,
    cleanup_error: None,
    data: None,
    subagent: Some({
      kind: "worker",
      label: "upgrade a",
      session: "p-sr-1",
      launch: Direct,
      outcome,
      usage: None,
      report: None,
      workspace,
    }),
  }
}

///|
/// A directory worker of an earlier engine whose end the transcript never
/// heard gets a notice: how its record says it ended, and where its change may
/// be. One the transcript already names, a worktree worker, and a read-only
/// child get none.
test "an earlier engine's unreported directory workers are noticed" {
  let records = [
    earlier_job("uuid-cut", Directory(path="/work/a"), None),
    earlier_job("uuid-done", Directory(path="/work/b"), Some(Captured)),
    earlier_job("uuid-told", Directory(path="/work/c"), Some(Captured)),
    earlier_job("uuid-explore", InPlace, None),
  ]
  let notices = @agent_subagent.unreported_directory_workers(records, notified=id => {
    id == "uuid-told"
  })
  assert_eq(notices.length(), 2)
  // Each names its job as an end notice does, so it counts as delivered once
  // it is in the transcript.
  assert_true(
    notices[0].has_prefix("subagent job uuid-cut (worker: upgrade a) "),
  )
  assert_true(
    notices[0].contains("holds no outcome, so it was most likely cut off"),
  )
  assert_true(notices[0].contains("git -C /work/a diff"))
  assert_true(notices[1].has_prefix("subagent job uuid-done "))
  assert_true(notices[1].contains("its record says it reported"))
  assert_true(notices[1].contains("Directory /work/b may hold what it changed"))
}
