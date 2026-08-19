///|
#cfg(not(platform="windows"))
async test "archive refuses a durable record while the pump is stopped" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-stopped-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  @fsx.ensure_dir(Path(store + "/sessions/s-stopped"))
  let manager = new_engine_manager("unused")
  let committed = Ref(false)
  let detail = try {
    ignore(
      archive_session_commit(manager, "s-stopped", (_, _) => {
        committed.val = true
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("not connected"))
  assert_false(committed.val)
  assert_true(@fsx.is_dir(Path(store + "/sessions/s-stopped")))
  assert_false(@fsx.is_dir(Path(store + "/archived/sessions/s-stopped")))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive publishes its move before a cancelled listing reply" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-commit-")
  let root : @pathx.Path = Path(dir)
  let marker = dir + "/listing-started"
  let engine = dir + "/engine.sh"
  // The listing this test cancels is per registered workspace, so the
  // conversation needs a real attached one; the env root now only locates the
  // registry that `attach_run_workspace` writes.
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  ignore(attach_run_workspace(root))
  let store = root.join("ws/.openseek")
  @fsx.ensure_dir(store.join("sessions/s-commit"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '' > '\{marker}'\nsleep 30\nprintf '%s' '{\"sessions\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  manager.pump = Serving(sessions=Map([]))
  let committed = Ref(false)
  @async.with_task_group(group => {
    let request = group.spawn(() => {
      ignore(
        archive_session(manager, "  s-commit  ", (_, _) => committed.val = true),
      )
    })
    while !@fsx.exists(Path(marker)) {
      @async.sleep(1)
    }
    request.cancel()
    let cancelled = try {
      request.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
  })
  assert_true(committed.val)
  assert_false(@fsx.is_dir(store.join("sessions/s-commit")))
  assert_true(@fsx.is_dir(store.join("archived/sessions/s-commit")))
  assert_true(manager.record_guards.get("s-commit") is None)
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive and restore move a subagent session family together" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-family-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  let live = store + "/sessions/"
  let archived = store + "/archived/sessions/"
  let family = ["chat", "chat-sr-1", "chat-sr-1-sr-3", "chat-sr-2"]
  for session_id in family {
    @fsx.ensure_dir(Path(live + session_id))
  }
  // Text that resembles the marker and an unrelated conversation must not be
  // swept into the family.
  @fsx.ensure_dir(Path(live + "chat-sr-x"))
  @fsx.ensure_dir(Path(live + "other"))
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let archived_events : Array[String] = []
  assert_true(
    archive_session_commit(manager, "chat", (id, _) => archived_events.push(id))
    is None,
  )
  assert_eq(archived_events.length(), family.length())
  assert_eq(archived_events[archived_events.length() - 1], "chat")
  for session_id in family {
    assert_true(archived_events.contains(session_id))
  }
  for session_id in family {
    assert_false(@fsx.is_dir(Path(live + session_id)))
    assert_true(@fsx.is_dir(Path(archived + session_id)))
  }
  assert_true(@fsx.is_dir(Path(live + "chat-sr-x")))
  assert_true(@fsx.is_dir(Path(live + "other")))
  let restored_events : Array[String] = []
  unarchive_session_commit(manager, "chat", (id, _) => restored_events.push(id))
  assert_eq(restored_events.length(), family.length())
  assert_eq(restored_events[0], "chat")
  for session_id in family {
    assert_true(restored_events.contains(session_id))
  }
  for session_id in family {
    assert_true(@fsx.is_dir(Path(live + session_id)))
    assert_false(@fsx.is_dir(Path(archived + session_id)))
  }
  assert_true(manager.record_guards.is_empty())
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "permanent deletion removes one archived session family only" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-delete-family-")
  let workspace = dir + "/workspace"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  @fsx.ensure_dir(Path(dir + "/global"))
  @fs.write_file(
    dir + "/global/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let store = workspace + "/.openseek"
  let archived = store + "/archived/sessions/"
  let family = ["chat", "chat-sr-1", "chat-sr-1-sr-2", "chat-sr-4"]
  for session_id in family {
    @fsx.ensure_dir(Path(archived + session_id))
  }
  @fsx.ensure_dir(Path(archived + "other"))
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let registered = @workspaces.registered()
  assert_eq(registered.length(), 1)
  let deleted : Array[String] = []
  delete_archived_session_commit(
    manager,
    "chat",
    registered[0].resource_path(),
    (session_id, _) => deleted.push(session_id),
  )
  assert_eq(deleted.length(), family.length())
  assert_eq(deleted[deleted.length() - 1], "chat")
  for session_id in family {
    assert_true(deleted.contains(session_id))
    assert_false(@fsx.exists(Path(archived + session_id)))
  }
  assert_true(@fsx.is_dir(Path(archived + "other")))
  for session_id in family {
    assert_false(@fsx.exists(Path(store + "/archived/deleting/" + session_id)))
  }
  assert_true(manager.record_guards.is_empty())
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "permanent deletion uses the selected archived store" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-delete-selected-store-")
  let global_root = dir + "/global"
  let workspace = dir + "/workspace"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root)
  @fsx.ensure_dir(Path(global_root + "/sessions/chat"))
  @fsx.ensure_dir(Path(global_root + "/archived/sessions/chat"))
  @fsx.ensure_dir(Path(workspace + "/.openseek/archived/sessions/chat"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let registered = @workspaces.registered()
  assert_eq(registered.length(), 1)
  let workspace_token = registered[0].resource_path()
  let deleted_workspaces : Array[String] = []
  delete_archived_session_commit(manager, "chat", workspace_token, (_, owner) => {
    deleted_workspaces.push(owner)
  })
  assert_true(@fsx.is_dir(Path(global_root + "/sessions/chat")))
  assert_true(@fsx.is_dir(Path(global_root + "/archived/sessions/chat")))
  assert_false(
    @fsx.exists(Path(workspace + "/.openseek/archived/sessions/chat")),
  )
  assert_eq(deleted_workspaces, [workspace_token])
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "permanent deletion refuses a live twin in the selected store" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-delete-live-twin-")
  let global_root = dir + "/global"
  let workspace = dir + "/workspace"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/chat"))
  @fsx.ensure_dir(Path(workspace + "/.openseek/archived/sessions/chat"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let detail = try {
    delete_archived_session_commit(
      manager,
      "chat",
      @pathx.Path(workspace).resolve().resource_path(),
      (_, _) => (),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("live record"))
  assert_true(@fsx.is_dir(Path(workspace + "/.openseek/sessions/chat")))
  assert_true(
    @fsx.is_dir(Path(workspace + "/.openseek/archived/sessions/chat")),
  )
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "startup sweep erases condemned records" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-delete-sweep-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  // A leading dot is a valid session id; the sweep must include hidden
  // entries instead of silently stranding this leftover.
  @fsx.ensure_dir(Path(store + "/archived/deleting/.chat/events"))
  @fsx.ensure_dir(Path(store + "/archived/deleting/chat-sr-1"))
  @fsx.ensure_dir(Path(store + "/archived/sessions/other"))
  let manager = new_engine_manager("unused")
  manager.sweep_archived_deletions()
  assert_false(@fsx.exists(Path(store + "/archived/deleting/.chat")))
  assert_false(@fsx.exists(Path(store + "/archived/deleting/chat-sr-1")))
  assert_true(@fsx.is_dir(Path(store + "/archived/sessions/other")))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "selected archived store is revalidated after detachment" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-delete-detached-selection-")
  let global_root = dir + "/global"
  let workspace = @pathx.Path(dir + "/workspace").resolve()
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(workspace.join(".openseek/archived/sessions/chat").to_path())
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace.to_string()] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let workspace_token = workspace.resource_path()
  let selected = @session_store.ArchivedStore::for_workspace(workspace_token)
  ignore(detach_workspace(manager, workspace_token, fn(_) { () }))
  let detail = try {
    let family = manager.claim_session_family_move(
      "chat",
      archived=true,
      selected~,
    )
    family.release()
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("not a registered workspace"))
  assert_true(
    @fsx.is_dir(workspace.join(".openseek/archived/sessions/chat").to_path()),
  )
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "a claimed child prevents a partial family archive" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-family-busy-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir + "/global")
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  @fsx.ensure_dir(Path(store + "/sessions/chat"))
  @fsx.ensure_dir(Path(store + "/sessions/chat-sr-1"))
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let child_claim = slot_for(sessions, "chat-sr-1").claim(
    sessions,
    "chat-sr-1",
    StartPending,
  )
  defer child_claim.release(manager)
  let detail = try {
    ignore(archive_session_commit(manager, "chat", (_, _) => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("already starting"))
  assert_true(@fsx.is_dir(Path(store + "/sessions/chat")))
  assert_true(@fsx.is_dir(Path(store + "/sessions/chat-sr-1")))
  assert_false(@fsx.exists(Path(store + "/archived/sessions")))
  assert_true(manager.record_guards.is_empty())
  @fs.rmdir(dir, recursive=true)
}
