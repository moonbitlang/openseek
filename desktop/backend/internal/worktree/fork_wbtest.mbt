// A fork of a worktree conversation in a worktree of its own. These tests
// exercise the real git binary through the recovery fixture.

///|
#cfg(not(platform="windows"))
async test "a fork gets its own checkout at the source's HEAD, without its uncommitted work" {
  with_recovery_fixture((repo, host) => {
    let created = create(
      host,
      resource_path(repo),
      WorktreeOwner::openseek("first"),
      _ => (),
    )
    let source = worktree_dir(repo, created.name)
    let head = commit_recovery_fixture(source, "source work")
    for n in 1..<=21 {
      @fsx.write_text(source.join("draft-\{n}.txt").to_path(), "uncommitted")
    }
    guard read_worktrees_unlocked(repo) is [source_row] else {
      fail("expected the source row")
    }
    let published : Array[Array[WorktreeInfo]] = []
    let seen : Array[ForkCheckout] = []
    let members_at_creation : Array[Array[String]] = []
    add_session_to_new_worktree(
      repo,
      session="fork",
      worktree_of="first",
      checkout => {
        seen.push(checkout)
        // The fork's row is committed before its record is created.
        for row in read_worktrees_unlocked(repo) {
          members_at_creation.push(row.sessions)
        }
      },
      record_exists=() => true,
      rows => published.push(rows),
    )
    guard seen is [NewWorktree(dir~, uncommitted~, omitted~)] else {
      fail("the record is created once, in a new worktree")
    }
    assert_eq(members_at_creation, [["first"], ["fork"]])
    assert_true(dir != source)
    assert_eq(@gitx.run(dir, ["rev-parse", "HEAD"]), head)
    assert_false(@fsx.exists(dir.join("draft-1.txt").to_path()))
    // The source's uncommitted paths are reported, the list bounded.
    assert_eq(uncommitted.length(), 20)
    assert_eq(omitted, 1)
    assert_true(uncommitted.all(path => path.has_prefix("draft-")))
    // The source checkout is left as it was.
    assert_true(@fsx.exists(source.join("draft-1.txt").to_path()))
    guard read_worktrees_unlocked(repo) is [first, fork] else {
      fail("expected the source's row and the fork's")
    }
    assert_eq(first.sessions, ["first"])
    assert_eq(fork.sessions, ["fork"])
    // The review of either one spans the whole task.
    assert_eq(fork.base, source_row.base)
    assert_eq(
      tree_dir(repo, "fork").map(dir => dir.to_string()),
      Some(dir.to_string()),
    )
    // Committed and announced: the provisioning lock is gone.
    assert_true(worktree_lock_reason(repo, fork.name) is None)
    guard published is [[_, reported]] else {
      fail("the new worktree must be reported once")
    }
    assert_eq(reported.name, fork.name)
    assert_eq(reported.sessions, ["fork"])
    // A conversation in the workspace root forks there, with nothing to
    // report and no worktree made.
    let mut in_root = false
    add_session_to_new_worktree(
      repo,
      session="root-fork",
      worktree_of="root",
      checkout => in_root = checkout is WorkspaceRoot(dir) && dir == repo,
      record_exists=() => true,
      rows => published.push(rows),
    )
    assert_true(in_root)
    assert_eq(published.length(), 1)
    assert_eq(read_worktrees_unlocked(repo).length(), 2)
  })
}

///|
#cfg(not(platform="windows"))
async test "a fork whose record was not written leaves no worktree behind" {
  with_recovery_fixture((repo, host) => {
    let created = create(
      host,
      resource_path(repo),
      WorktreeOwner::openseek("first"),
      _ => (),
    )
    let published : Array[Array[WorktreeInfo]] = []
    let made : Array[@pathx.Absolute] = []
    let failed = try {
      add_session_to_new_worktree(
        repo,
        session="broken",
        worktree_of="first",
        checkout => {
          made.push(checkout.dir())
          raise WorktreeError("record failed")
        },
        record_exists=() => false,
        rows => published.push(rows),
      )
      false
    } catch {
      WorktreeError(_) => true
      error => raise error
    }
    assert_true(failed)
    guard made is [dir] else { fail("the record was attempted once") }
    assert_false(@fsx.exists(dir.to_path()))
    assert_eq(published.length(), 0)
    guard read_worktrees_unlocked(repo) is [row] else {
      fail("only the source's row may remain")
    }
    assert_eq(row.name, created.name)
    // Neither its git registration nor its recovery reference survives.
    assert_eq(checkout_states(repo).length(), 1)
    let refs = @gitx.run(repo, [
      "for-each-ref",
      "--format=%(refname)",
      WorktreeRecoveryPrefix,
    ])
    assert_true(refs.has_prefix("\{WorktreeRecoveryPrefix}\{created.name}-"))
    assert_false(refs.contains("\n"))
    // A record that was written keeps its worktree, whatever became of the
    // call that wrote it, and the worktree is reported.
    let failed_late = try {
      add_session_to_new_worktree(
        repo,
        session="late",
        worktree_of="first",
        _ => raise WorktreeError("the writer failed after the record"),
        record_exists=() => true,
        rows => published.push(rows),
      )
      false
    } catch {
      WorktreeError(_) => true
      error => raise error
    }
    assert_true(failed_late)
    guard published is [[_, late]] else {
      fail("a fork that exists must be reported with its worktree")
    }
    assert_eq(late.sessions, ["late"])
    assert_true(late.present)
    assert_true(worktree_lock_reason(repo, late.name) is None)
  })
}

///|
#cfg(not(platform="windows"))
async test "a source whose checkout is gone is refused before anything is made" {
  with_recovery_fixture((repo, host) => {
    let created = create(
      host,
      resource_path(repo),
      WorktreeOwner::openseek("first"),
      _ => (),
    )
    @fs.rmdir(worktree_dir(repo, created.name).to_string(), recursive=true)
    let mut asked = false
    let refused = try {
      add_session_to_new_worktree(
        repo,
        session="fork",
        worktree_of="first",
        _ => asked = true,
        record_exists=() => false,
        _ => (),
      )
      None
    } catch {
      WorktreeError(detail) => Some(detail)
      error => raise error
    }
    assert_eq(refused, Some(missing_checkout_refusal(created.name)))
    assert_false(asked)
    guard read_worktrees_unlocked(repo) is [row] else {
      fail("the source row must survive a refused fork")
    }
    assert_eq(row.sessions, ["first"])
  })
}

///|
#cfg(not(platform="windows"))
async test "a fork provisions the submodules of its own commit" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-fork-submodules-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let dependency = root.join("dependency")
  prepare_git_repo(dependency)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  // Local fixture repositories keep the test offline.
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
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let created = create(
    test_host(),
    repo.to_string(),
    WorktreeOwner::openseek("first"),
    _ => (),
  )
  // The source removes the submodule the main checkout still has
  // initialized; its HEAD is what the fork is made from.
  let source = worktree_dir(repo, created.name)
  ignore(@gitx.run(source, ["rm", "-q", "deps/one"]))
  let head = commit_recovery_fixture(source, "drop submodule")
  let made : Array[@pathx.Absolute] = []
  add_session_to_new_worktree(
    repo,
    session="fork",
    worktree_of="first",
    checkout => made.push(checkout.dir()),
    record_exists=() => true,
    _ => (),
  )
  guard made is [dir] else { fail("the fork's record must be created") }
  assert_eq(@gitx.run(dir, ["rev-parse", "HEAD"]), head)
  assert_false(@fsx.exists(dir.join("deps/one").to_path()))
}
