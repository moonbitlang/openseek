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
          ..
        },
        ..
      } else {
      fail("the worker was not given its directory: \{request.stringify()}")
    }
    assert_eq(worker_root, mine)
    assert_eq(denied, @fs.realpath(work))
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
    // A directory that is not below the checkout, or none, is refused.
    for
      (path, because) in [
        (".", "below the session's checkout"),
        (root, "below the session's checkout"),
        ("missing", "does not exist"),
        ("a/lib/a.txt", "not a directory"),
      ] {
      guard h.start_in(path) is Unavailable(reason) else {
        fail("\{path} was given")
      }
      assert_true(reason.contains(because))
    }
    // Another repository is independent of it.
    guard h.start_in("b") is Started(job_id=other, ..) else {
      fail("a separate repository was refused")
    }
    for id in [job_id, other] {
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
