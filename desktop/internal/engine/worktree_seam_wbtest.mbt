// Where the engine meets a worktree placement: the run configuration, the
// path resolution the FS bridge asks for, and archiving a bound conversation.
// The checkout mechanics themselves live in `internal/worktree`; what is
// covered here is the engine's reading of a placement it did not create.

///|
/// A fixture root in the tmpdir's physical spelling. The workspace registry
/// canonicalizes what it stores, so a fixture built from the symlinked
/// spelling (`/tmp` on macOS) would compare unequal to every path the
/// registry hands back.
#cfg(not(platform="windows"))
async fn worktree_test_root(prefix : String) -> @pathx.Absolute {
  @pathx.Path(@fs.realpath(@fs.tmpdir(prefix~))).resolve()
}

///|
#cfg(not(platform="windows"))
async fn prepare_git_repo(dir : @pathx.Absolute) -> Unit {
  @fsx.ensure_dir(dir.to_path())
  ignore(@gitx.run(dir, ["init", "-q"]))
  ignore(
    @gitx.run(dir, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "--allow-empty", "-q", "-m", "init",
    ]),
  )
}

///|
/// Stage placement rows the way the worktree registry writes them: one
/// `(name, branch, owning session, owning Codex thread)` per row. The file is
/// a desktop-owned on-disk contract
/// (`<workspace>/.openseek/worktrees.json`), so writing it directly keeps
/// these engine-side tests free of a real git checkout — what they exercise
/// is how the engine READS a placement.
#cfg(not(platform="windows"))
async fn stage_worktree_placements(
  workspace : @pathx.Absolute,
  rows : Array[(String, String, String?, String?)],
  base? : String = "abc",
) -> Unit {
  let store = @workspaces.store_root(workspace)
  @fsx.ensure_dir(store.to_path())
  let entries : Array[Json] = []
  for row in rows {
    let (name, branch, session, codex_thread) = row
    let entry : Map[String, Json] = {
      "name": name.to_json(),
      "branch": branch.to_json(),
      "base": base.to_json(),
    }
    if session is Some(session) {
      entry["session"] = session.to_json()
    }
    if codex_thread is Some(thread) {
      entry["codex_thread"] = thread.to_json()
    }
    entries.push(entry.to_json())
  }
  @fsx.write_text(
    store.join("worktrees.json").to_path(),
    ({ "worktrees": entries.to_json() } : Json).stringify(indent=2),
  )
}

///|
#cfg(not(platform="windows"))
async test "session workspace dir follows the worktree mapping while it exists" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-seam-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.join(".openseek/sessions/s-wt").to_path())
  @fsx.ensure_dir(ws.join(".openseek/sessions/s-plain").to_path())
  ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
  guard ws.to_uri_path() is Some(ws_resource) else {
    fail("workspace fixture could not be represented as a frontend resource")
  }
  stage_worktree_placements(ws, [
    ("wt", "openseek/wt", Some("s-wt"), None),
    ("codex", "openseek/codex", None, Some("codex-thread-1")),
  ])
  @fsx.ensure_dir(ws.join(".worktrees/wt").to_path())
  @fsx.ensure_dir(ws.join(".worktrees/codex").to_path())
  assert_eq(
    @work_dir.of_session("s-wt").map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  assert_eq(
    @work_dir.of_session("s-plain").map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  // The workspace hint refines to the worktree too — the FS bridge sends the
  // hint on every op.
  assert_eq(
    @work_dir.resolve_in_workspace("s-wt", "src", workspace=ws_resource).map(dir => {
      dir.to_string()
    }),
    Some(ws.join(".worktrees/wt/src").to_string()),
  )
  // Before its first prompt, a workspace-root conversation has no durable
  // session record. Its registered resource root is enough to establish the
  // directory ownership used by Files, Terminal, and language operations.
  assert_eq(
    @work_dir.resolve_in_workspace("desktop-fresh", "", workspace=ws_resource).map(dir => {
        dir.to_string()
      },
    ),
    Some(ws.to_string()),
  )
  // Terminal and file operations use the same conversation id field for
  // both products; Codex ownership must route to its registered checkout.
  assert_eq(
    @work_dir.resolve_in_workspace("codex-thread-1", "", workspace=ws_resource).map(dir => {
        dir.to_string()
      },
    ),
    Some(ws.join(".worktrees/codex").to_string()),
  )
  // Deleting the checkout retains the binding but removes the usable root:
  // every session-scoped operation refuses until Repair recreates it.
  @fs.rmdir(ws.join(".worktrees/wt").to_string(), recursive=true)
  assert_true(@work_dir.of_session("s-wt") is None)
  assert_true(
    @work_dir.resolve_in_workspace("s-wt", "", workspace=ws_resource) is None,
  )
}

///|
#cfg(not(platform="windows"))
async test "attached workspace dir resolves registered worktree paths" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-attached-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.to_path())
  ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
  stage_worktree_placements(ws, [("wt", "openseek/wt", None, None)])
  @fsx.ensure_dir(ws.join(".worktrees/wt/src").to_path())
  @fsx.ensure_dir(ws.join(".worktrees/stray").to_path())
  @fsx.ensure_dir(ws.join("src").to_path())
  @fs.write_file(
    ws.join("src/main.mbt").to_string(),
    b"main",
    create_mode=CreateOrTruncate,
  )
  let worktree_file = ws.join(".worktrees/wt/src/main.mbt")
  let stray_file = ws.join(".worktrees/stray/x.mbt")
  let workspace_file = ws.join("src/lib.mbt")
  guard @pathx.Path("\{ws}/.worktrees/wt/../../src/main.mbt").to_absolute()
    is Some(dot_segment_file) else {
    fail("expected absolute worktree fixtures")
  }
  // A registered worktree path answers from the worktree root.
  assert_eq(
    @work_dir.attached_workspace_dir(worktree_file).map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  // An unregistered `.worktrees` path (a subtask slice) and a main-tree path
  // keep resolving to the workspace root.
  assert_eq(
    @work_dir.attached_workspace_dir(stray_file).map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  assert_eq(
    @work_dir.attached_workspace_dir(workspace_file).map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  // Dot segments are cleaned before choosing the deepest owning tree. Although
  // its spelling enters a registered worktree, this file physically belongs to
  // the main workspace after `../..` is resolved.
  assert_eq(
    @work_dir.attached_workspace_dir(dot_segment_file).map(dir => {
      dir.to_string()
    }),
    Some(ws.to_string()),
  )
}

///|
#cfg(not(platform="windows"))
async test "a bound session routes every start through its checkout" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-route-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  // BYOK: the default provider needs a key. Set one here so worktree
  // routing — not endpoint resolution — is what this test can fail for.
  let previous_key = @sys.get_env_var("DEEPSEEK")
  @sys.set_env_var("DEEPSEEK", "sk-route-test")
  defer (if previous_key is Some(value) {
    @sys.set_env_var("DEEPSEEK", value)
  } else {
    @sys.unset_env_var("DEEPSEEK")
  })
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.join(".worktrees/wt").to_path())
  ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
  // Creation is the binding; the start path only READS the registry.
  stage_worktree_placements(ws, [("wt", "openseek/wt", Some("s-bind"), None)])
  let manager = new_engine_manager("openseek")
  let first = run_config(manager, {
    task: "go",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-bind",
    workspace: Some(ws.to_string()),
  })
  assert_eq(
    first.cwd.map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  // The durable record stays in the MAIN repository's store.
  assert_eq(
    first.session_root.map(dir => dir.to_string()),
    Some(ws.join(".openseek").to_string()),
  )
  // A hint-less resume goes through the durable record and the mapping.
  @fsx.ensure_dir(ws.join(".openseek/sessions/s-bind").to_path())
  let resumed = run_config(manager, {
    task: "resume",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-bind",
    workspace: None,
  })
  assert_eq(
    resumed.cwd.map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  assert_eq(
    resumed.session_root.map(dir => dir.to_string()),
    Some(ws.join(".openseek").to_string()),
  )
}

///|
#cfg(not(platform="windows"))
async test "worktree remove refuses a running conversation without unmapping it" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-busy-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.join(".worktrees/wt").to_path())
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64").to_path(),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64").to_path(),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do sleep 30; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(
    engine.to_string(),
    runtime_dir=runtime.to_path(),
  )
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      glm_api_key: None,
      custom_api_key: None,
    }),
  )
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(@workspaces.add(ws.to_string(), fn(_) {  }))
    stage_worktree_placements(ws, [
      ("wt", "openseek/wt", Some("s-wt-run"), None),
    ])
    let reply = start_run(sink, manager, {
      task: "keep running",
      submission_id: None,
      model: None,
      thinking: None,
      max_steps: None,
      session: "s-wt-run",
      workspace: Some(ws.to_string()),
    })
    assert_eq(reply.status, "accepted")
    let committed : Ref[Bool] = Ref(false)
    let detail = try {
      ignore(
        @worktree.remove(manager.worktree_host(), ws.to_string(), "wt", false, fn(
          _,
        ) {
          committed.val = true
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("still running"))
    assert_false(committed.val)
    assert_true(@fsx.is_dir(ws.join(".worktrees/wt").to_path()))
    guard @worktree.list(ws.to_string()).worktrees is [info] else {
      fail("expected the worktree to stay registered")
    }
    assert_eq(info.session, Some("s-wt-run"))
    group.return_immediately(())
  })
}

///|
#cfg(not(platform="windows"))
async test "a checkout deleted outside the app refuses runs and is repairable" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-vanished-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  // BYOK: the default provider needs a key. Set one here so the vanished
  // checkout's refusal — not endpoint resolution — is what this test can
  // fail for.
  let previous_key = @sys.get_env_var("DEEPSEEK")
  @sys.set_env_var("DEEPSEEK", "sk-vanish-test")
  defer (if previous_key is Some(value) {
    @sys.set_env_var("DEEPSEEK", value)
  } else {
    @sys.unset_env_var("DEEPSEEK")
  })
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  let created = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("s-vanish"),
    fn(_) {  },
    name="wt",
  )
  let checkout = repo.join(".worktrees/wt")
  // A commit on the worktree's branch stands in for the conversation's
  // work: the repair must bring it back, not just an empty directory.
  @fsx.write_text(checkout.join("kept.txt").to_path(), "committed work")
  ignore(@gitx.run(checkout, ["add", "kept.txt"]))
  ignore(
    @gitx.run(checkout, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-m", "work",
    ]),
  )
  // Someone deletes the checkout outside the app; the registry row survives,
  // which is what distinguishes this from our own removal.
  @fs.rmdir(checkout.to_string(), recursive=true)
  // The durable record is how a hint-less resume recovers its registered
  // workspace after an app restart.
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-vanish").to_path(),
  )
  guard @worktree.list(repo.to_string()).worktrees is [gone] else {
    fail("the registry row must survive an external deletion")
  }
  assert_false(gone.present)
  assert_eq(gone.session, Some("s-vanish"))
  // Every session-scoped surface refuses rather than silently moving into the
  // main checkout: file/terminal resolution returns no root, and a run names
  // the missing worktree.
  assert_true(@worktree.tree_dir(repo, "s-vanish") is None)
  assert_true(@work_dir.of_session("s-vanish") is None)
  assert_true(@work_dir.session_cwd("s-vanish") is None)
  assert_true(
    @work_dir.resolve_in_workspace("s-vanish", "", workspace=repo.to_string())
    is None,
  )
  let refusal = try {
    ignore(@worktree.run_dir(repo, "s-vanish"))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(refusal.contains("wt") && refusal.contains("gone"))
  let hinted_refusal = try {
    ignore(
      run_config(manager, {
        task: "continue",
        submission_id: None,
        model: None,
        thinking: None,
        max_steps: None,
        session: "s-vanish",
        workspace: Some(repo.to_string()),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(hinted_refusal.contains("wt") && hinted_refusal.contains("gone"))
  let resumed_refusal = try {
    ignore(
      run_config(manager, {
        task: "resume",
        submission_id: None,
        model: None,
        thinking: None,
        max_steps: None,
        session: "s-vanish",
        workspace: None,
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(
    resumed_refusal.contains("wt") && resumed_refusal.contains("gone"),
  )
  // Recreating repairs the SAME environment: same name, same branch, and the
  // branch's commit is back in the working tree.
  let repaired = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("s-vanish"),
    fn(_) {  },
  )
  assert_eq(repaired.name, created.name)
  assert_true(@fsx.is_dir(checkout.to_path()))
  assert_eq(
    @fsx.read_text(checkout.join("kept.txt").to_path()),
    "committed work",
  )
  guard created.worktrees is [created_info] else {
    fail("create must publish the one worktree it made")
  }
  // The repair restores the very branch create minted (`openseek/wt-<salt>`),
  // never a lookalike.
  assert_true(created_info.branch.has_prefix("openseek/wt-"))
  assert_eq(
    @gitx.run(checkout, ["rev-parse", "--abbrev-ref", "HEAD"]),
    created_info.branch,
  )
  assert_eq(
    @worktree.run_dir(repo, "s-vanish").to_string(),
    checkout.to_string(),
  )
  // If the first repair's request was cancelled after restoring the checkout
  // but before broadcasting, its idempotent retry must publish the complete
  // host-derived list so clients leave MissingWorktree.
  let replayed : Array[WorktreeInfo] = []
  let replay = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("s-vanish"),
    infos => {
      for info in infos {
        replayed.push(info)
      }
    },
  )
  assert_eq(replay.name, repaired.name)
  guard replayed is [replayed_info] else {
    fail("repair replay did not publish its worktree list")
  }
  assert_eq(replayed_info.name, repaired.name)
  assert_eq(replayed_info.session, Some("s-vanish"))
  assert_true(replayed_info.present)
}

///|
#cfg(not(platform="windows"))
async test "archive keeps worktree placement for explicit repair after unarchive" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-archive-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  ignore(
    @worktree.create(
      manager.worktree_host(),
      repo.to_string(),
      @worktree.WorktreeOwner::openseek("s-arc"),
      fn(_) {  },
    ),
  )
  // The first turn has landed: the durable record now exists in the
  // workspace store (create's has-history refusal applies only before the
  // binding, so this is the normal begun-conversation shape).
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-arc").to_path(),
  )
  @fs.write_file(
    repo.join(".worktrees/wt-1/junk.txt").to_string(),
    b"x",
    create_mode=CreateOrTruncate,
  )
  // A dirty checkout returns a structured confirmation state before anything
  // irreversible: the record stays live and the checkout stays on disk.
  guard archive_session(manager, "s-arc", (_, _) => ()) is NeedsForce(refusal) else {
    fail("dirty archive returned no force confirmation")
  }
  assert_eq(refusal.worktree, "wt-1")
  assert_eq(refusal.dirty_paths, ["junk.txt"])
  assert_eq(refusal.dirty_path_count, 1)
  assert_true(
    @fsx.is_dir(
      @workspaces.store_root(repo).join("sessions").join("s-arc").to_path(),
    ),
  )
  assert_true(@fsx.is_dir(repo.join(".worktrees/wt-1").to_path()))
  // The confirmed dialog retries with force: the checkout goes away, while
  // the branch, archived history, and placement row all survive. The retained
  // row broadcasts as missing before the conversation is archived.
  let changes : Array[(String, Array[WorktreeInfo])] = []
  guard archive_session(manager, "s-arc", (_, _) => (), force=true, on_worktree_changed=(
      workspace,
      rows,
    ) => changes.push((workspace, rows)))
    is Archived(_) else {
    fail("forced archive did not commit")
  }
  assert_eq(changes.length(), 1)
  let (workspace, rows) = changes[0]
  assert_eq(workspace, repo.to_string())
  guard rows is [archived_worktree] else {
    fail("archive must retain one missing worktree placement")
  }
  assert_eq(archived_worktree.session, Some("s-arc"))
  assert_false(archived_worktree.present)
  assert_false(@fsx.exists(repo.join(".worktrees/wt-1").to_path()))
  assert_true(
    @gitx.probe(repo, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{archived_worktree.branch}",
    ])
    is Some(_),
  )
  assert_true(
    @fsx.is_dir(
      @session_store.archived_root(@workspaces.store_root(repo))
      .join("sessions")
      .join("s-arc")
      .to_path(),
    ),
  )
  guard @worktree.list(repo.to_string()).worktrees is [retained] else {
    fail("archived worktree placement was not retained")
  }
  assert_eq(retained.session, Some("s-arc"))
  assert_false(retained.present)
  // Unarchive restores only the durable conversation. The retained placement
  // keeps every workspace surface blocked until the user explicitly repairs.
  ignore(unarchive_session(manager, "s-arc", (_, _) => ()))
  assert_true(
    @fsx.is_dir(
      @workspaces.store_root(repo).join("sessions").join("s-arc").to_path(),
    ),
  )
  assert_true(@worktree.tree_dir(repo, "s-arc") is None)
  assert_true(
    @work_dir.resolve_in_workspace("s-arc", "", workspace=repo.to_string())
    is None,
  )
  let repaired = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("s-arc"),
    fn(_) {  },
  )
  assert_eq(repaired.name, "wt-1")
  assert_true(@fsx.is_dir(repo.join(".worktrees/wt-1").to_path()))
  // A clean bound worktree archives in one go, no force needed.
  ignore(
    @worktree.create(
      manager.worktree_host(),
      repo.to_string(),
      @worktree.WorktreeOwner::openseek("s-arc2"),
      fn(_) {  },
    ),
  )
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-arc2").to_path(),
  )
  assert_true(archive_session(manager, "s-arc2", (_, _) => ()) is Archived(_))
  assert_false(@fsx.exists(repo.join(".worktrees/wt-2").to_path()))
  guard @worktree.list(repo.to_string()).worktrees is [first, second] else {
    fail("both worktree placements must survive archive")
  }
  assert_true(first.present)
  assert_false(second.present)
  assert_eq(second.session, Some("s-arc2"))
  // Codex archive uses the same dirty-check and retained-placement methods;
  // app-server fencing happens in the API immediately before this call.
  let codex_owner = @worktree.WorktreeOwner::codex("thread-archive")
  let codex = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    codex_owner,
    fn(_) {  },
  )
  @fs.write_file(
    repo.join(".worktrees/\{codex.name}/local.txt").to_string(),
    b"dirty",
    create_mode=CreateOrTruncate,
  )
  guard codex_owner.archive_check() is Some(codex_refusal) else {
    fail("Codex archive should require confirmation for a dirty checkout")
  }
  assert_eq(codex_refusal.worktree, codex.name)
  ignore(codex_owner.archive_checkout(true))
  guard @worktree.list(repo.to_string()).worktrees
    .iter()
    .find_first(info => info.codex_thread == Some("thread-archive"))
    is Some(codex_archived) else {
    fail("Codex archive must retain its registry placement")
  }
  assert_false(codex_archived.present)
}

///|
#cfg(not(platform="windows"))
async test "permanent archived deletion drops placement but keeps files and branch" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let root = worktree_test_root("openseek-archive-delete-worktree-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let global = root.join("global")
  let workspace = root.join("workspace")
  @sys.set_env_var("HOME", global.to_string())
  prepare_git_repo(workspace)
  ignore(@gitx.run(workspace, ["branch", "openseek/chat"]))
  ignore(@workspaces.add(workspace.to_string(), fn(_) {  }))
  @fs.write_file(
    workspace.join("project-note.txt").to_string(),
    b"keep me",
    create_mode=CreateOrTruncate,
  )
  @fsx.ensure_dir(workspace.join(".openseek/archived/sessions/chat").to_path())
  stage_worktree_placements(
    workspace,
    [
      ("chat-tree", "openseek/chat", Some("chat"), None),
      ("other-tree", "openseek/other", Some("other"), None),
    ],
    base=@gitx.run(workspace, ["rev-parse", "HEAD"]),
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let worktree_changed = Ref(false)
  let committed_infos : Array[WorktreeInfo] = []
  delete_archived_session_commit(
    manager,
    "chat",
    workspace.resource_path(),
    (_, _) => (),
    on_worktree_changed=(_, infos) => {
      worktree_changed.val = true
      committed_infos.clear()
      for info in infos {
        committed_infos.push(info)
      }
    },
  )
  let entries = @worktree.list(workspace.to_string()).worktrees
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].session, Some("other"))
  assert_true(worktree_changed.val)
  assert_eq(committed_infos.length(), 1)
  assert_eq(committed_infos[0].session, Some("other"))
  assert_true(@fsx.exists(workspace.join("project-note.txt").to_path()))
  assert_true(
    @gitx.run(workspace, ["branch", "--list", "openseek/chat"]).contains(
      "openseek/chat",
    ),
  )
}
