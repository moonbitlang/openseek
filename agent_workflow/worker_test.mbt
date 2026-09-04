///|
/// Worker-slice lifecycle tests against a REAL temporary git repository:
/// provisioning, confinement, git-evidence capture, integration, replay,
/// and reservation disjointness — all hermetic, with scripted `sh`
/// children standing in for the model-driven worker.
async fn init_repo() -> String {
  let dir = @fs.tmpdir(prefix="workflow-worker-repo-")
  for
    args in [
      ["init", "-q", "-b", "main"],
      ["config", "user.email", "workflow-test@example.com"],
      ["config", "user.name", "workflow test"],
    ] {
    guard @agent_subtask.git_require(args, cwd=dir) is Ok(_) else {
      fail("git \{args.join(" ")} failed in \{dir}")
    }
  }
  @fs.mkdir("\{dir}/src", recursive=true)
  @fs.write_file("\{dir}/src/a.txt", "one\n")
  for args in [["add", "-A"], ["commit", "-q", "-m", "init"]] {
    guard @agent_subtask.git_require(args, cwd=dir) is Ok(_) else {
      fail("git \{args.join(" ")} failed in \{dir}")
    }
  }
  dir
}

///|
/// The child runs with cwd already inside its confined worktree, so the
/// script edits relative paths and reports over the contract.
fn worker_workflow(
  repo : String,
  script : String,
  journal? : @workflow.Journal,
) -> @workflow.Workflow raise {
  @workflow.Workflow(
    runner=@agent_workflow.openseek_runner(
      exe="unused",
      workspace_root=repo,
      deadline_ms=10_000,
      map_launch=(spec, _) => { ..spec, command: "sh", args: ["-c", script], },
    ),
    journal?,
  )
}

///|
let edit_script : String =
  #|read line
  #|printf 'two\n' > src/a.txt
  #|printf '{"subrun_report": {"schema_version": 1, "status": "done", "summary": "edited a", "verification": "diff inspected"}}\n'

///|
async test "a worker slice commits, integrates, and lands in the repo" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let wf = worker_workflow(repo, edit_script)
  let outcome = @agent_workflow.worker(
    wf,
    name="edit-a",
    task="set src/a.txt to two",
    allowed_paths=["src/"],
  )
  guard outcome
    is {
      "state": state,
      "branch": String(branch),
      "commit_oid": String(_),
      "defects": [],
      ..
    } else {
    fail("expected a committed slice, got \{outcome.stringify()}")
  }
  assert_eq(state, Json("Committed"))
  // The branch is real git state in the origin repository.
  guard @agent_subtask.git_require(["rev-parse", "--verify", branch], cwd=repo)
    is Ok(_) else {
    fail("the slice branch must exist in the origin repo")
  }
  // Integration lands the edit in the workspace.
  guard @agent_workflow.integrate_slice(workspace_root=repo, name="edit-a")
    is Ok(_) else {
    fail("expected the committed slice to integrate")
  }
  assert_eq(@fs.read_file("\{repo}/src/a.txt").text(), "two\n")
}

///|
async test "an out-of-bounds edit is not mergeable and can be discarded" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let rogue =
    #|read line
    #|printf 'rogue\n' > outside.txt
    #|printf '{"subrun_report": {"schema_version": 1, "status": "done", "summary": "sneaky", "verification": "none"}}\n'
  let wf = worker_workflow(repo, rogue)
  guard @agent_workflow.try_worker(
      wf,
      name="rogue",
      task="edit outside the slice",
      allowed_paths=["src/"],
    )
    is Err(@workflow.AgentFailed(failure=Failed(reason), ..)) else {
    fail("expected the out-of-bounds slice to fail typed")
  }
  assert_true(reason.contains("not mergeable"))
  // The origin workspace is untouched and the slice can be abandoned.
  assert_false(@fs.exists("\{repo}/outside.txt"))
  guard @agent_workflow.discard_slice(workspace_root=repo, name="rogue")
    is Ok(_) else {
    fail("expected the failed slice to be discardable")
  }
}

///|
async test "overlapping slices are refused before any child spawns" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let wf = worker_workflow(repo, edit_script)
  let _ = @agent_workflow.worker(wf, name="first", task="edit src", allowed_paths=[
    "src/",
  ])
  // `first` is committed but not integrated: its reservation still holds.
  guard @agent_workflow.try_worker(wf, name="second", task="also edit src", allowed_paths=[
      "src/",
    ])
    is Err(@workflow.AgentFailed(failure=Failed(reason), ..)) else {
    fail("expected the overlapping slice to be refused")
  }
  assert_true(reason.contains("provision"))
  // A refused launch spent nothing beyond the first slice's child.
  assert_eq(wf.calls_made(), 2)
}

///|
async test "a journalled worker slice replays without provisioning" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let dir = @fs.tmpdir(prefix="workflow-worker-journal-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let path = "\{dir}/journal.jsonl"
  let wf1 = worker_workflow(
    repo,
    edit_script,
    journal=@workflow.Journal::load(path),
  )
  let first = @agent_workflow.worker(
    wf1,
    name="edit-a",
    task="set src/a.txt to two",
    allowed_paths=["src/"],
  )
  // Generation 2: the poisoned child would report differently AND
  // provisioning would be refused (the slice still holds its paths) —
  // replay must serve generation 1's outcome without either happening.
  let poisoned =
    #|read line
    #|printf '{"subrun_report": {"schema_version": 1, "status": "done", "summary": "wrong", "verification": "checked"}}\n'
  let wf2 = worker_workflow(
    repo,
    poisoned,
    journal=@workflow.Journal::load(path),
  )
  let second = @agent_workflow.worker(
    wf2,
    name="edit-a",
    task="set src/a.txt to two",
    allowed_paths=["src/"],
  )
  assert_eq(second, first)
  assert_eq(wf2.calls_made(), 0)
  assert_eq(wf2.calls_replayed(), 1)
}

///|
async test "a discarded slice does not replay: the veto reruns it live" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let dir = @fs.tmpdir(prefix="workflow-worker-veto-")
  defer (@fs.rmdir(dir, recursive=true) catch { _ => () })
  let path = "\{dir}/journal.jsonl"
  let wf1 = worker_workflow(
    repo,
    edit_script,
    journal=@workflow.Journal::load(path),
  )
  let _ = @agent_workflow.worker(
    wf1,
    name="edit-a",
    task="set src/a.txt to two",
    allowed_paths=["src/"],
  )
  guard @agent_workflow.discard_slice(workspace_root=repo, name="edit-a")
    is Ok(_) else {
    fail("expected the committed slice to be discardable")
  }
  // The journalled Committed outcome now points at destroyed state: the
  // validator must veto it and the call must run LIVE (a clean no-op).
  let noop =
    #|read line
    #|printf '{"subrun_report": {"schema_version": 1, "status": "done", "summary": "nothing left to do", "verification": "tree clean"}}\n'
  let wf2 = worker_workflow(repo, noop, journal=@workflow.Journal::load(path))
  let second = @agent_workflow.worker(
    wf2,
    name="edit-a",
    task="set src/a.txt to two",
    allowed_paths=["src/"],
  )
  guard second is { "state": "NoChanges", .. } else {
    fail("expected the live rerun's no-op outcome, got \{second.stringify()}")
  }
  assert_eq(wf2.calls_made(), 1)
  assert_eq(wf2.calls_replayed(), 0)
}

///|
async test "a dead child cannot become a clean-tree success" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  // No argv seam: the missing binary is really spawned and really dies.
  let wf = @workflow.Workflow(
    runner=@agent_workflow.openseek_runner(
      exe="/nonexistent/openseek-not-here",
      workspace_root=repo,
      deadline_ms=2_000,
    ),
  )
  guard @agent_workflow.try_worker(wf, name="doomed", task="edit src", allowed_paths=[
      "src/",
    ])
    is Err(@workflow.AgentFailed(..)) else {
    fail("a spawn failure must never look like a completed slice")
  }
}

///|
async test "blank tasks and empty allowed_paths are refused pre-provision" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let wf = worker_workflow(repo, edit_script)
  guard @agent_workflow.try_worker(wf, name="blank", task="  ", allowed_paths=[
      "src/",
    ])
    is Err(@workflow.AgentFailed(failure=Failed(task_reason), ..)) else {
    fail("expected the blank task to be refused")
  }
  assert_true(task_reason.contains("task"))
  guard @agent_workflow.try_worker(wf, name="pathless", task="edit", allowed_paths=[])
    is Err(@workflow.AgentFailed(failure=Failed(path_reason), ..)) else {
    fail("expected the empty allowed_paths to be refused")
  }
  assert_true(path_reason.contains("allowed_paths"))
  // Neither refusal provisioned anything.
  guard @agent_workflow.slices(workspace_root=repo) is Ok(entries) else {
    fail("expected a readable registry")
  }
  assert_eq(entries.length(), 0)
}

///|
async test "names are reusable and lifecycle binds to the active generation" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let wf = worker_workflow(repo, edit_script)
  let _ = @agent_workflow.worker(
    wf,
    name="edit-a",
    task="set src/a.txt to two",
    allowed_paths=["src/"],
  )
  guard @agent_workflow.integrate_slice(workspace_root=repo, name="edit-a")
    is Ok(_) else {
    fail("expected the first generation to integrate")
  }
  // The name is free again: a NEW generation may claim it (with a fresh
  // edit — repeating the integrated one would be a clean no-op).
  let three =
    #|read line
    #|printf 'three\n' > src/a.txt
    #|printf '{"subrun_report": {"schema_version": 1, "status": "done", "summary": "edited a again", "verification": "diff inspected"}}\n'
  let wf2 = worker_workflow(repo, three)
  let second = @agent_workflow.worker(
    wf2,
    name="edit-a",
    task="set src/a.txt to three",
    allowed_paths=["src/"],
  )
  guard second is { "state": "Committed", .. } else {
    fail("expected the second generation to commit")
  }
  // ...and lifecycle-by-name binds to the ACTIVE generation, never the
  // integrated one.
  guard @agent_workflow.discard_slice(workspace_root=repo, name="edit-a")
    is Ok(_) else {
    fail("expected the active generation to be discardable")
  }
  guard @agent_workflow.slices(workspace_root=repo) is Ok(entries) else {
    fail("expected a readable registry")
  }
  let states = entries
    .filter(entry => entry.name == "edit-a")
    .map(entry => Json(entry.state))
  assert_true(states.contains(Json("Integrated")))
  assert_true(states.contains(Json("Discarded")))
}

///|
async test "an invalid report shape fails the slice at the trust boundary" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  // Edits land, but the report violates the contract (no schema_version,
  // unknown status): git salvage stays in the registry, the slice fails.
  let garbled =
    #|read line
    #|printf 'two\n' > src/a.txt
    #|printf '{"subrun_report": {"status": "completed", "summary": "edited"}}\n'
  let wf = worker_workflow(repo, garbled)
  guard @agent_workflow.try_worker(wf, name="garbled", task="edit src", allowed_paths=[
      "src/",
    ])
    is Err(@workflow.AgentFailed(failure=Failed(reason), ..)) else {
    fail("expected the garbled report to fail the slice")
  }
  assert_true(reason.contains("salvaged commit"))
}

///|
async test "a clean no-op the child disclaims is a failure" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  let gave_up =
    #|read line
    #|printf '{"subrun_report": {"schema_version": 1, "status": "failed", "summary": "could not do it", "verification": "nothing ran"}}\n'
  let wf = worker_workflow(repo, gave_up)
  guard @agent_workflow.try_worker(wf, name="gave-up", task="edit src", allowed_paths=[
      "src/",
    ])
    is Err(@workflow.AgentFailed(failure=Failed(reason), ..)) else {
    fail("expected the disclaimed no-op to be a failure")
  }
  assert_true(reason.contains("reported failure"))
}

///|
async test "a typed terminal with salvage names the salvaged commit" {
  guard can_spawn_sh_here() else {
    println("skipped: cannot spawn sh")
    return
  }
  let repo = init_repo()
  defer (@fs.rmdir(repo, recursive=true) catch { _ => () })
  // The child makes a mergeable edit, then dies at its step ceiling
  // without a report: the failure must SAY a salvaged commit exists
  // rather than hiding it behind the bare terminal.
  let truncated =
    #|read line
    #|printf 'two\n' > src/a.txt
    #|printf '{"timestamp":"t","level":"INFO","source":"s","event":"max_steps_exhausted"}\n'
  let wf = worker_workflow(repo, truncated)
  guard @agent_workflow.try_worker(wf, name="truncated", task="edit src", allowed_paths=[
      "src/",
    ])
    is Err(@workflow.AgentFailed(failure=Failed(reason), ..)) else {
    fail("expected the truncated slice to fail with salvage visibility")
  }
  assert_true(reason.contains("salvaged commit"))
  assert_true(reason.contains("exhausted its steps"))
  // The message names the real branch, not a placeholder.
  assert_true(reason.contains("openseek/truncated"))
}

///|
async test "an invalid max_workers is refused recoverably" {
  let mut refused = false
  fn probe() -> Unit raise {
    let _ = @agent_workflow.openseek_runner(
      exe="unused",
      workspace_root=".",
      max_workers=0,
    )
  }
  probe() catch {
    _ => refused = true
  }
  assert_true(refused)
}
