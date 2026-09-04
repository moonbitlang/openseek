///|
/// Full-lifecycle tests against REAL git repositories: provision a worktree,
/// play the worker's part with plain filesystem edits, capture, integrate —
/// and every refusal edge the state machine promises. These are the
/// controller's ground-truth tests; the parent tool wires what they prove.
async fn seed_repo(dir : String) -> String {
  let repo = "\{dir}/repo"
  @fs.mkdir(repo)
  for
    args in [
      ["init", "-q"],
      ["config", "user.email", "e2e@test"],
      ["config", "user.name", "e2e"],
    ] {
    match @agent_subtask.git_require(args, cwd=repo) {
      Ok(_) => ()
      Err(reason) => fail(reason)
    }
  }
  @fs.mkdir("\{repo}/lib")
  @fs.mkdir("\{repo}/other")
  @vfs.write_text("\{repo}/lib", "a.txt", "alpha\n")
  @vfs.write_text("\{repo}/other", "b.txt", "beta\n")
  for args in [["add", "-A"], ["commit", "-q", "-m", "base"]] {
    match @agent_subtask.git_require(args, cwd=repo) {
      Ok(_) => ()
      Err(reason) => fail(reason)
    }
  }
  repo
}

///|
async fn must_provision(
  repo : String,
  name~ : String,
  allowed_paths~ : Array[String],
  nonce~ : String,
) -> @agent_subtask.Provisioned {
  match @agent_subtask.provision(repo, name~, allowed_paths~, nonce~) {
    Ok(provisioned) => provisioned
    Err(reason) => fail("provision failed: \{reason}")
  }
}

///|
#cfg(not(platform="windows"))
async test "provision, worker edit, capture, integrate — the happy path" {
  @vfs.with_tmpdir(prefix="openseek-subtask-happy-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let entry = provisioned.entry
    assert_true(entry.state is Running)
    assert_true(@fs.exists("\{entry.worker_root}/lib/a.txt"))
    // The worker's part: an in-scope edit.
    @vfs.write_text("\{entry.worker_root}/lib", "a.txt", "ALPHA\n")
    let captured = @agent_subtask.capture(provisioned.geometry, entry)
    assert_eq(captured.defects, ([] : Array[String]))
    assert_true(captured.entry.state is Committed)
    guard captured.entry.commit_oid is Some(_) else {
      fail("expected a commit oid")
    }
    let integrated = @agent_subtask.integrate(
      provisioned.geometry,
      captured.entry,
    )
    assert_eq(integrated.result, "integrated")
    // The change landed in origin history and the worktree is gone.
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
    assert_false(@fs.exists(entry.worker_root))
    // The registry records the terminal state.
    let (entries, skipped) = @agent_subtask.load_entries(
      provisioned.geometry.common_git_dir,
    )
    assert_eq(skipped, ([] : Array[String]))
    assert_eq(entries.length(), 1)
    assert_true(entries[0].state is Integrated)
  })
}

///|
async test "out-of-scope worker changes are captured as defects, not merged" {
  @vfs.with_tmpdir(prefix="openseek-subtask-scope-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let entry = provisioned.entry
    @vfs.write_text("\{entry.worker_root}/lib", "a.txt", "ALPHA\n")
    @vfs.write_text("\{entry.worker_root}/other", "b.txt", "INTRUDED\n")
    let captured = @agent_subtask.capture(provisioned.geometry, entry)
    assert_true(captured.defects.length() > 0)
    assert_true(captured.defects[0].contains("other/b.txt"))
    assert_true(captured.entry.state is Captured)
    // Nothing was committed; integration refuses.
    let refused = @agent_subtask.integrate(provisioned.geometry, captured.entry)
    assert_eq(refused.result, "refused")
    // Origin untouched either way.
    assert_eq(@fs.read_file("\{repo}/other/b.txt").text(), "beta\n")
  })
}

///|
async test "overlapping reservations and duplicate names refuse at provision" {
  @vfs.with_tmpdir(prefix="openseek-subtask-overlap-", dir => {
    let repo = seed_repo(dir)
    let _ = must_provision(
      repo,
      name="first",
      allowed_paths=["lib"],
      nonce="n1",
    )
    guard @agent_subtask.provision(
        repo,
        name="second",
        allowed_paths=["lib/deep"],
        nonce="n2",
      )
      is Err(overlap) else {
      fail("expected an overlap refusal")
    }
    assert_true(overlap.contains("overlap"))
    guard @agent_subtask.provision(
        repo,
        name="first",
        allowed_paths=["other"],
        nonce="n3",
      )
      is Err(duplicate) else {
      fail("expected a duplicate-name refusal")
    }
    assert_true(duplicate.contains("already active"))
    // A DISJOINT slice provisions fine alongside.
    let _ = must_provision(
      repo,
      name="third",
      allowed_paths=["other"],
      nonce="n4",
    )
  })
}

///|
async test "an empty worker tree resolves to no_changes and releases the slice" {
  @vfs.with_tmpdir(prefix="openseek-subtask-empty-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="noop",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let captured = @agent_subtask.capture(
      provisioned.geometry,
      provisioned.entry,
    )
    assert_true(captured.entry.state is NoChanges)
    assert_eq(captured.defects, ([] : Array[String]))
    // Cleanup is immediate (terminal entries are undiscoverable), so the
    // SAME name and slice provision again — with a natural trailing-slash
    // spelling, which normalization must accept.
    let again = must_provision(
      repo,
      name="noop",
      allowed_paths=["lib/"],
      nonce="n2",
    )
    assert_eq(again.entry.allowed_paths, ["lib"])
  })
}

///|
#cfg(not(platform="windows"))
async test "a conflicting merge hands off, continues after resolution" {
  @vfs.with_tmpdir(prefix="openseek-subtask-conflict-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let entry = provisioned.entry
    // Worker changes the file...
    @vfs.write_text("\{entry.worker_root}/lib", "a.txt", "WORKER\n")
    let captured = @agent_subtask.capture(provisioned.geometry, entry)
    assert_true(captured.entry.state is Committed)
    // ...and the origin advances the SAME line before integration.
    @vfs.write_text("\{repo}/lib", "a.txt", "ORIGIN\n")
    for args in [["add", "-A"], ["commit", "-q", "-m", "origin moved"]] {
      match @agent_subtask.git_require(args, cwd=repo) {
        Ok(_) => ()
        Err(reason) => fail(reason)
      }
    }
    let conflicted = @agent_subtask.integrate(
      provisioned.geometry,
      captured.entry,
    )
    assert_eq(conflicted.result, "conflicted")
    assert_true(conflicted.entry.state is Conflicted)
    assert_true(conflicted.detail[0].contains("lib/a.txt"))
    // Resolve the markers (the parent model's job, via file tools) and
    // stage the resolution — then the controller commits. A stray staged
    // file outside the slice + conflict set refuses the continue first.
    @vfs.write_text("\{repo}/lib", "a.txt", "MERGED\n")
    @vfs.write_text("\{repo}/other", "stray.txt", "stray\n")
    for args in [["add", "lib/a.txt"], ["add", "other/stray.txt"]] {
      match @agent_subtask.git_require(args, cwd=repo) {
        Ok(_) => ()
        Err(reason) => fail(reason)
      }
    }
    let strayed = @agent_subtask.integrate_continue(
      provisioned.geometry,
      conflicted.entry,
    )
    assert_eq(strayed.result, "refused")
    assert_true(strayed.detail[0].contains("other/stray.txt"))
    match
      @agent_subtask.git_require(
        ["restore", "--staged", "--worktree", "other/stray.txt"],
        cwd=repo,
      ) {
      Ok(_) => ()
      Err(reason) => fail(reason)
    }
    let continued = @agent_subtask.integrate_continue(
      provisioned.geometry,
      conflicted.entry,
    )
    assert_eq(continued.result, "integrated")
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "MERGED\n")
    assert_false(@fs.exists(entry.worker_root))
  })
}

///|
#cfg(not(platform="windows"))
async test "integrate refuses a dirty tracked origin; abort restores state" {
  @vfs.with_tmpdir(prefix="openseek-subtask-dirty-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    @vfs.write_text("\{provisioned.entry.worker_root}/lib", "a.txt", "WORKER\n")
    let captured = @agent_subtask.capture(
      provisioned.geometry,
      provisioned.entry,
    )
    // Dirty the origin's tracked file.
    @vfs.write_text("\{repo}/other", "b.txt", "dirty\n")
    let refused = @agent_subtask.integrate(provisioned.geometry, captured.entry)
    assert_eq(refused.result, "refused")
    assert_true(refused.detail[0].contains("uncommitted tracked changes"))
    // Clean it; force a conflict; then abort restores the pre-merge state.
    @vfs.write_text("\{repo}/other", "b.txt", "beta\n")
    @vfs.write_text("\{repo}/lib", "a.txt", "ORIGIN\n")
    for args in [["add", "-A"], ["commit", "-q", "-m", "origin moved"]] {
      match @agent_subtask.git_require(args, cwd=repo) {
        Ok(_) => ()
        Err(reason) => fail(reason)
      }
    }
    let conflicted = @agent_subtask.integrate(
      provisioned.geometry,
      captured.entry,
    )
    assert_eq(conflicted.result, "conflicted")
    let aborted = @agent_subtask.integrate_abort(
      provisioned.geometry,
      conflicted.entry,
    )
    assert_eq(aborted.result, "aborted")
    assert_true(aborted.entry.state is Committed)
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ORIGIN\n")
    // The branch and worktree survive an abort for a later retry.
    assert_true(@fs.exists(provisioned.entry.worker_root))
    // Discard releases everything.
    match @agent_subtask.discard(provisioned.geometry, aborted.entry) {
      Ok(_) => ()
      Err(reason) => fail(reason)
    }
    assert_false(@fs.exists(provisioned.entry.worker_root))
    let retry = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n9",
    )
    assert_true(retry.entry.state is Running)
  })
}

///|
#cfg(not(platform="windows"))
async test "linked worktree provisions and integrates into itself" {
  @vfs.with_tmpdir(prefix="openseek-subtask-precond-", dir => {
    let repo = seed_repo(dir)
    let linked = "\{dir}/linked"
    match
      @agent_subtask.git_require(
        ["worktree", "add", "-q", "../linked", "-b", "linked"],
        cwd=repo,
      ) {
      Ok(_) => ()
      Err(reason) => fail(reason)
    }
    let provisioned = must_provision(
      linked,
      name="x",
      allowed_paths=["lib"],
      nonce="n1",
    )
    guard @agent_subtask.resolve_geometry(repo) is Ok(main_geometry) else {
      fail("expected main worktree geometry")
    }
    let linked_root = provisioned.geometry.origin_root
    assert_eq(provisioned.entry.worker_root, "\{linked_root}/.worktrees/x")
    let deny_roots = provisioned.geometry.worker_deny_roots()
    assert_true(deny_roots.contains(provisioned.geometry.common_git_dir))
    assert_true(deny_roots.contains(main_geometry.origin_root))
    assert_true(deny_roots.contains(linked_root))
    @vfs.write_text("\{provisioned.entry.worker_root}/lib", "a.txt", "LINKED\n")
    let captured = @agent_subtask.capture(
      provisioned.geometry,
      provisioned.entry,
    )
    assert_true(captured.entry.state is Committed)

    // The repository-wide registry is visible from the main worktree, but a
    // lifecycle action there must not redirect this slice's merge target.
    guard @agent_subtask.resume_running(main_geometry, "x")
      is Err(wrong_continue) else {
      fail("expected sibling-worktree continue to be refused")
    }
    assert_true(wrong_continue.contains("different worktree"))
    guard @agent_subtask.discard(main_geometry, captured.entry)
      is Err(wrong_discard) else {
      fail("expected sibling-worktree discard to be refused")
    }
    assert_true(wrong_discard.contains("different worktree"))
    let wrong_target = @agent_subtask.integrate(main_geometry, captured.entry)
    assert_eq(wrong_target.result, "refused")
    assert_true(wrong_target.detail[0].contains("different worktree"))
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "alpha\n")
    assert_true(@fs.exists(provisioned.entry.worker_root))

    let integrated = @agent_subtask.integrate(
      provisioned.geometry,
      captured.entry,
    )
    assert_eq(integrated.result, "integrated")
    assert_eq(@fs.read_file("\{linked_root}/lib/a.txt").text(), "LINKED\n")
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "alpha\n")
    assert_false(@fs.exists(provisioned.entry.worker_root))
  })
}

///|
/// Two disjoint slices provisioned back-to-back both go live — the shape a
/// one-call `slices` fan-out relies on (the tool layer runs these
/// concurrently; here the controller-level invariant is what matters).
async test "disjoint slices coexist as active reservations" {
  @vfs.with_tmpdir(prefix="openseek-subtask-fanout-", dir => {
    let repo = seed_repo(dir)
    let a = must_provision(
      repo,
      name="slice-a",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let b = must_provision(
      repo,
      name="slice-b",
      allowed_paths=["other"],
      nonce="n2",
    )
    assert_true(a.entry.state is Running)
    assert_true(b.entry.state is Running)
    assert_true(@fs.exists("\{a.entry.worker_root}/lib/a.txt"))
    assert_true(@fs.exists("\{b.entry.worker_root}/other/b.txt"))
    // Both reservations are visible; a third overlapping slice is refused.
    guard @agent_subtask.provision(
        repo,
        name="slice-c",
        allowed_paths=["lib/deep"],
        nonce="n3",
      )
      is Err(_) else {
      fail("expected the overlapping third slice to be refused")
    }
  })
}

///|
/// The resume path's controller half: capture is re-entrant. A second
/// capture after further edits stacks a child commit on the same branch; a
/// second capture with nothing new leaves the prior commit standing instead
/// of tripping the no-changes cleanup (which would delete validated work).
#cfg(not(platform="windows"))
async test "capture is re-entrant: resumed work stacks on the same branch" {
  @vfs.with_tmpdir(prefix="openseek-subtask-resume-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let entry = provisioned.entry
    @vfs.write_text("\{entry.worker_root}/lib", "a.txt", "ALPHA\n")
    let first = @agent_subtask.capture(provisioned.geometry, entry)
    assert_eq(first.defects, ([] : Array[String]))
    assert_true(first.entry.state is Committed)
    guard first.entry.commit_oid is Some(commit1) else {
      fail("expected a first commit")
    }
    // Resume finds the entry continuable and flips it back to Running.
    let resumed = match
      @agent_subtask.resume_running(provisioned.geometry, "fix-lib") {
      Ok(resumed) => resumed
      Err(reason) => fail("resume_running failed: \{reason}")
    }
    assert_true(resumed.state is Running)
    assert_eq(resumed.commit_oid, Some(commit1))
    // A resumed worker that adds nothing: the prior capture must stand and
    // the worktree and branch must survive.
    let idle = @agent_subtask.capture(provisioned.geometry, resumed)
    assert_eq(idle.defects, ([] : Array[String]))
    assert_true(idle.entry.state is Committed)
    assert_eq(idle.entry.commit_oid, Some(commit1))
    assert_true(@fs.exists(entry.worker_root))
    // A resumed worker that adds more work: the second capture stacks a
    // commit whose parent is the first capture's commit.
    @vfs.write_text("\{entry.worker_root}/lib", "c.txt", "GAMMA\n")
    let second = @agent_subtask.capture(provisioned.geometry, idle.entry)
    assert_eq(second.defects, ([] : Array[String]))
    assert_true(second.entry.state is Committed)
    guard second.entry.commit_oid is Some(commit2) else {
      fail("expected a second commit")
    }
    assert_true(commit1 != commit2)
    match @agent_subtask.git_require(["rev-parse", "\{commit2}^"], cwd=repo) {
      Ok(parent) => assert_eq(parent.trim().to_owned(), commit1)
      Err(reason) => fail(reason)
    }
    // Integration lands BOTH captures' work.
    let integrated = @agent_subtask.integrate(
      provisioned.geometry,
      second.entry,
    )
    assert_eq(integrated.result, "integrated")
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
    assert_eq(@fs.read_file("\{repo}/lib/c.txt").text(), "GAMMA\n")
  })
}

///|
/// resume_running refuses what it must: unknown names, and states without a
/// kept worktree (a Running slice may still have a live child).
#cfg(not(platform="windows"))
async test "resume_running refuses unknown names and running slices" {
  @vfs.with_tmpdir(prefix="openseek-subtask-resume-refuse-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    guard @agent_subtask.resume_running(provisioned.geometry, "nope")
      is Err(unknown) else {
      fail("expected an unknown-name refusal")
    }
    assert_true(unknown.contains("no active subtask"))
    // Freshly provisioned means Running — a child may still be live.
    guard @agent_subtask.resume_running(provisioned.geometry, "fix-lib")
      is Err(running) else {
      fail("expected a running-state refusal")
    }
    assert_true(running.contains("Running"))
  })
}

///|
/// The repair half of continue: a defective re-capture preserves the prior
/// commit_oid, resume admits the Captured state, and once the intrusion is
/// reverted the idle re-capture returns to Committed on the SAME commit.
#cfg(not(platform="windows"))
async test "captured defects repair through resume and re-capture" {
  @vfs.with_tmpdir(prefix="openseek-subtask-repair-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let entry = provisioned.entry
    @vfs.write_text("\{entry.worker_root}/lib", "a.txt", "ALPHA\n")
    let first = @agent_subtask.capture(provisioned.geometry, entry)
    assert_true(first.entry.state is Committed)
    guard first.entry.commit_oid is Some(commit1) else {
      fail("expected a first commit")
    }
    // A resumed worker strays out of scope: the re-capture is defective but
    // must keep the prior commit pinned.
    @vfs.write_text("\{entry.worker_root}/other", "b.txt", "INTRUDED\n")
    let defective = @agent_subtask.capture(provisioned.geometry, first.entry)
    assert_true(defective.defects.length() > 0)
    assert_true(defective.entry.state is Captured)
    assert_eq(defective.entry.commit_oid, Some(commit1))
    // Captured is continuable; the repair worker reverts the intrusion.
    // other/b.txt is TRACKED (seeded in the base commit) and commit1's
    // tree holds it at "beta" — restoring that content makes the worktree
    // status clean again, which is what routes the re-capture through the
    // idle guard below.
    let resumed = match
      @agent_subtask.resume_running(provisioned.geometry, "fix-lib") {
      Ok(resumed) => resumed
      Err(reason) => fail("resume_running refused a Captured slice: \{reason}")
    }
    @vfs.write_text("\{resumed.worker_root}/other", "b.txt", "beta\n")
    let repaired = @agent_subtask.capture(provisioned.geometry, resumed)
    assert_eq(repaired.defects, ([] : Array[String]))
    assert_true(repaired.entry.state is Committed)
    assert_eq(repaired.entry.commit_oid, Some(commit1))
    let integrated = @agent_subtask.integrate(
      provisioned.geometry,
      repaired.entry,
    )
    assert_eq(integrated.result, "integrated")
    assert_eq(@fs.read_file("\{repo}/lib/a.txt").text(), "ALPHA\n")
    assert_eq(@fs.read_file("\{repo}/other/b.txt").text(), "beta\n")
  })
}

///|
/// The integration-safety gates: a Conflicted slice and a gone worktree
/// both refuse resume — continue must never race a half-done merge or
/// relaunch into a deleted tree.
#cfg(not(platform="windows"))
async test "resume_running refuses conflicted slices and gone worktrees" {
  @vfs.with_tmpdir(prefix="openseek-subtask-resume-gates-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    let entry = provisioned.entry
    @vfs.write_text("\{entry.worker_root}/lib", "a.txt", "WORKER\n")
    let captured = @agent_subtask.capture(provisioned.geometry, entry)
    assert_true(captured.entry.state is Committed)
    // Origin advances the same line: integration conflicts.
    @vfs.write_text("\{repo}/lib", "a.txt", "ORIGIN\n")
    for args in [["add", "-A"], ["commit", "-q", "-m", "origin moved"]] {
      match @agent_subtask.git_require(args, cwd=repo) {
        Ok(_) => ()
        Err(reason) => fail(reason)
      }
    }
    let conflicted = @agent_subtask.integrate(
      provisioned.geometry,
      captured.entry,
    )
    assert_eq(conflicted.result, "conflicted")
    guard @agent_subtask.resume_running(provisioned.geometry, "fix-lib")
      is Err(midmerge) else {
      fail("expected a conflicted-state refusal")
    }
    assert_true(midmerge.contains("Conflicted"))
    // Abort the merge, then delete the worktree out from under the entry.
    let aborted = @agent_subtask.integrate_abort(
      provisioned.geometry,
      conflicted.entry,
    )
    assert_eq(aborted.result, "aborted")
    @fs.rmdir(entry.worker_root, recursive=true)
    guard @agent_subtask.resume_running(provisioned.geometry, "fix-lib")
      is Err(gone) else {
      fail("expected a gone-worktree refusal")
    }
    assert_true(gone.contains("gone"))
  })
}

///|
/// The stale-snapshot gate: lifecycle actions re-read the registry under
/// the repo mutex, so an entry object captured BEFORE a concurrent
/// continue flipped the slice to Running cannot merge or discard under the
/// live child.
#cfg(not(platform="windows"))
async test "integrate refuses a stale snapshot of a resumed slice" {
  @vfs.with_tmpdir(prefix="openseek-subtask-stale-", dir => {
    let repo = seed_repo(dir)
    let provisioned = must_provision(
      repo,
      name="fix-lib",
      allowed_paths=["lib"],
      nonce="n1",
    )
    @vfs.write_text("\{provisioned.entry.worker_root}/lib", "a.txt", "ALPHA\n")
    let captured = @agent_subtask.capture(
      provisioned.geometry,
      provisioned.entry,
    )
    assert_true(captured.entry.state is Committed)
    // A continue flips the slice to Running on disk; the caller still
    // holds the Committed snapshot.
    match @agent_subtask.resume_running(provisioned.geometry, "fix-lib") {
      Ok(_) => ()
      Err(reason) => fail("resume_running failed: \{reason}")
    }
    let refused = @agent_subtask.integrate(provisioned.geometry, captured.entry)
    assert_eq(refused.result, "refused")
    assert_true(refused.detail[0].contains("not in a committed state"))
    // The worktree survives for the (simulated) live child.
    assert_true(@fs.exists(provisioned.entry.worker_root))
  })
}
