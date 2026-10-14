///|
#cfg(not(platform="windows"))
async test "edit cleanup requires its durable receipt and an unchanged source" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-edit-cleanup-"))
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir)
  @sys.set_env_var("HOME", root.join("global").to_string())
  let workspace = attach_run_workspace(root)
  let selected = @session_store.ArchivedStore::for_workspace(workspace)
  let store = @store.SessionStore(selected.root.to_string())
  let source = @agent_session.Session(SessionId("source"), system_prompt="test")
    .append(User(UserMessage(Content([Text("original")]))))
    .append(Terminal(Finished("answer")))
  store.create(source)
  let child = @agent_session.Session(
    SessionId("source-sr-1"),
    system_prompt="child",
  ).append(User(UserMessage(Content([Text("child prompt")]))))
  store.create(child)
  let replacement = @agent_session.Session(
    SessionId("replacement"),
    system_prompt="test",
  ).append(User(UserMessage(Content([Text("edited")]), submission_id="edit-1")))
  store.create(replacement)
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  let payload : @protocol.SessionEditCommitPayload = {
    session: "source",
    workspace,
    replacement: "replacement",
    submission_id: "edit-1",
    source_sequence: 2,
  }
  let notifications : Array[String] = []
  for
    invalid in [
      { ..payload, submission_id: "wrong", },
      { ..payload, source_sequence: 1, },
    ] {
    let result : Result[SessionDeleteReply, String] = Ok(
      commit_session_edit(manager, invalid, (id, _) => notifications.push(id), on_worktree_changed=(
        _,
        _,
      ) => ()),
    ) catch {
      error => Err("\{error}")
    }
    assert_true(result is Err(_))
    assert_true(store.exists(SessionId("source")))
    assert_true(notifications.is_empty())
  }
  @async.with_task_group(group => {
    // Pause deletion after validation but before its irreversible rename.
    manager.archive_cleanup_lock.acquire()
    let mut held = true
    defer (if held { manager.archive_cleanup_lock.release() })
    let cleanup = group.spawn(() => {
      commit_session_edit(manager, payload, (id, _) => notifications.push(id), on_worktree_changed=(
        _,
        _,
      ) => ())
    })
    let writer = @fs.open(
      selected.root
      .join("sessions")
      .join("source")
      .join("session.lock")
      .to_string(),
      mode=ReadWrite,
    )
    defer writer.close()
    // Brief snapshot reads may also hold the lock. Wait for the sustained
    // hold at the paused rename; without it this loop times out.
    @async.with_timeout(3000, () => {
      while @async.with_timeout_opt(100, () => {
              writer.lock(Exclusive)
              writer.unlock()
            })
            is Some(_) {
        @async.sleep(1)
      }
    })
    assert_true(
      @async.with_timeout_opt(100, () => {
        store.append(
          source,
          User(UserMessage(Content([Text("another host's message")]))),
        )
      })
      is None,
    )
    assert_true(
      @async.with_timeout_opt(100, () => {
        store.append(
          child,
          User(UserMessage(Content([Text("another host's child event")]))),
        )
      })
      is None,
    )
    manager.archive_cleanup_lock.release()
    held = false
    assert_true(@async.with_timeout(3000, () => cleanup.wait()) is Deleted)
  })
  assert_false(store.exists(SessionId("source")))
  assert_true(store.exists(SessionId("replacement")))
  assert_eq(notifications, ["source-sr-1", "source"])
  assert_true(
    commit_session_edit(manager, payload, (id, _) => notifications.push(id), on_worktree_changed=(
      _,
      _,
    ) => ())
    is Deleted,
  )
  assert_eq(notifications, ["source-sr-1", "source", "source"])
  assert_true(manager.record_guards.is_empty())
}

///|
#cfg(not(platform="windows"))
async test "first-message replacement keeps its source's dirty checkout" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let root = worktree_test_root("openseek-first-edit-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), _ => ()))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  let created = @worktree.create(
    manager.worktree_host(),
    repo.to_string(),
    @worktree.WorktreeOwner::openseek("original"),
    _ => (),
  )
  let store = @store.SessionStore(@workspaces.store_root(repo).to_string())
  store.create(
    @agent_session.Session(SessionId("original"), system_prompt="test").append(
      User(UserMessage(Content([Text("original")]))),
    ),
  )
  let dirty = repo.join(".worktrees").join(created.name).join("unsaved.txt")
  @fs.write_file(dirty.to_string(), b"keep me", create_mode=CreateOrTruncate)
  let prepared = prepare_session_edit(
    manager,
    {
      session: "original",
      workspace: repo.resource_path(),
      through: None,
      model: "deepseek-flash",
      source_title: "Original",
    },
    on_created=_ => (),
    on_worktree_changed=(_, _) => (),
  )
  assert_true(store.exists(SessionId(prepared.session)))
  assert_false(@fs.exists(store.session_file(SessionId(prepared.session))))
  // A lost prepare reply is recoverable through the durable listing and can
  // be deleted without stranding an invisible worktree registry member.
  let listings = store.listings()
  guard listings.search_by(row => row.id().value() == prepared.session)
    is Some(index) else {
    fail("reservation was not discoverable")
  }
  assert_eq(listings[index].title(), Some("Original"))
  let empty = load_session(manager, {
    session: prepared.session,
    workspace: Some(repo.resource_path()),
  })
  assert_true(empty.session.events.unwrap_or([]).is_empty())
  let lost = prepare_session_edit(
    manager,
    {
      session: "original",
      workspace: repo.resource_path(),
      through: None,
      model: "deepseek-flash",
      source_title: "Lost reply",
    },
    on_created=_ => (),
    on_worktree_changed=(_, _) => (),
  )
  assert_true(
    delete_session(manager, lost.session, repo.resource_path(), (_, _) => ())
    is Deleted,
  )
  assert_false(store.exists(SessionId(lost.session)))
  guard @worktree.list(repo.to_string()).worktrees is [before_send] else {
    fail("checkout")
  }
  assert_false(before_send.sessions.contains(lost.session))
  // The ordinary first prompt creates the record inside the inherited tree.
  store.create(
    @agent_session.Session(SessionId(prepared.session), system_prompt="test").append(
      User(UserMessage(Content([Text("edited")]), submission_id="first-edit")),
    ),
  )
  assert_true(
    commit_session_edit(
      manager,
      {
        session: "original",
        workspace: repo.resource_path(),
        replacement: prepared.session,
        submission_id: "first-edit",
        source_sequence: 1,
      },
      (_, _) => (),
      on_worktree_changed=(_, _) => (),
    )
    is Deleted,
  )
  assert_true(@fsx.exists(dirty.to_path()))
  guard @worktree.list(repo.to_string()).worktrees is [kept] else {
    fail("checkout")
  }
  assert_true(kept.present)
  assert_false(store.exists(SessionId("original")))
  assert_true(store.exists(SessionId(prepared.session)))
}

///|
#cfg(not(platform="windows"))
async test "edit cleanup rechecks a replacement deleted by another host" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-edit-cross-host-"))
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir)
  @sys.set_env_var("HOME", root.join("global").to_string())
  let workspace = attach_run_workspace(root)
  let selected = @session_store.ArchivedStore::for_workspace(workspace)
  let store = @store.SessionStore(selected.root.to_string())
  store.create(
    @agent_session.Session(SessionId("source"), system_prompt="test")
    .append(User(UserMessage(Content([Text("original")]))))
    .append(Terminal(Finished("answer"))),
  )
  store.create(
    @agent_session.Session(SessionId("replacement"), system_prompt="test").append(
      User(UserMessage(Content([Text("edited")]), submission_id="edit-1")),
    ),
  )
  let first = new_engine_manager("openseek")
  first.pump = Serving(sessions=Map([]))
  let second = new_engine_manager("openseek")
  second.pump = Serving(sessions=Map([]))
  let removed : Array[String] = []
  @async.with_task_group(group => {
    first.archive_commit_lock.acquire()
    let mut locked = true
    defer (if locked { first.archive_commit_lock.release() })
    let cleanup = group.spawn(() => {
      let result : Result[SessionDeleteReply, String] = Ok(
        commit_session_edit(
          first,
          {
            session: "source",
            workspace,
            replacement: "replacement",
            submission_id: "edit-1",
            source_sequence: 2,
          },
          (session, _) => removed.push(session),
          on_worktree_changed=(_, _) => (),
        ),
      ) catch {
        error => Err("\{error}")
      }
      result
    })
    // A has read the receipt and claimed the source, but cannot acquire its
    // commit lock yet. B has independent record guards, like another host.
    @async.with_timeout(3000, () => {
      while !(first.record_guards.get("source") is Some({ moving: true, .. }) &&
            first.record_guards.get("replacement") is Some({ readers: 1, .. })) {
        @async.sleep(1)
      }
    })
    assert_true(
      delete_session(second, "replacement", workspace, (_, _) => ()) is Deleted,
    )
    assert_false(store.exists(SessionId("replacement")))
    first.archive_commit_lock.release()
    locked = false
    assert_true(@async.with_timeout(3000, () => cleanup.wait()) is Err(_))
  })
  assert_true(store.exists(SessionId("source")))
  assert_true(removed.is_empty())
  assert_true(first.record_guards.is_empty())
  assert_true(second.record_guards.is_empty())
}

///|
#cfg(not(platform="windows"))
async test "editing refuses busy source and child slots before preparing either kind of copy" {
  let manager = new_engine_manager("/bin/sh")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let notifications : Array[String] = []
  @async.with_task_group(group => {
    let engine = start_fake_idle_engine(group, manager, sessions, "source")
    for
      phase in [
        Running(run_id="active", compact_queued=false),
        Compacting(last_run=None),
      ] {
      engine.phase = phase
      for through in [None, Some(3)] {
        let result : Result[@protocol.SessionForkReply, String] = Ok(
          prepare_session_edit(
            manager,
            {
              session: "source",
              workspace: "/unused",
              through,
              model: "deepseek-flash",
              source_title: "Original",
            },
            on_created=id => notifications.push(id),
            on_worktree_changed=(_, _) => notifications.push("placement"),
          ),
        ) catch {
          error => Err("\{error}")
        }
        guard result is Err(message) else { fail("accepted busy edit") }
        assert_true(message.contains("busy"))
      }
      assert_false(engine.condemned)
      assert_false(engine.phase is Idle(..))
      assert_true(notifications.is_empty())
    }
    engine.phase = Idle(last_run=None)
    manager.require_idle_edit_source("source")
    let claim = slot_for(sessions, "source-sr-1-sr-2").claim(
      sessions,
      "source-sr-1-sr-2",
      StartPending,
    )
    let refused = try {
      manager.require_idle_edit_source("source")
      false
    } catch {
      _ => true
    }
    assert_true(refused)
    claim.release(manager)
    manager.require_idle_edit_source("source")
    engine.close_and_wait()
  })
  assert_true(manager.record_guards.is_empty())
}
