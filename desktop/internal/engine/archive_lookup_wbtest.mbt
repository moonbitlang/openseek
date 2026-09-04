// Archive's record lookup against stores a stale client can still name: a
// conversation row can outlive its workspace's registration (detach) or its
// directory (external deletion), and a second archive click can race the
// first one's commit. Each state must answer with its own actionable
// refusal, and a failed attempt must leave no wedged host state behind.

///|
#cfg(not(platform="windows"))
async test "archive names the missing store after a workspace detach" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-detach-")
  defer @fs.rmdir(dir, recursive=true)
  let workspace = dir + "/ws"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-ws"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  // The sidebar's remove button: detach commits and the registry forgets
  // the workspace, while the record stays on disk in the project store.
  let detached = detach_workspace(manager, workspace, fn(_) {  })
  assert_true(detached is Workspaces([]))
  // A stale sidebar can still offer the conversation; archiving it now
  // reports the record as unreachable instead of pretending it never
  // existed.
  let detail = try {
    ignore(archive_session(manager, "s-ws", (_, _) => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    detail,
    content=(
      #|"no durable record for this conversation in the global store or any attached workspace"
    ),
  )
  assert_true(@fsx.is_dir(Path(workspace + "/.openseek/sessions/s-ws")))
  // The failed attempt must leave no wedged host state behind: no record
  // move claim, no pending slot, and the next attempt reports the same
  // refusal instead of "already moving".
  assert_true(manager.record_guards.get("s-ws") is None)
  guard manager.pump is Serving(sessions~) else { fail("pump stopped") }
  assert_true(sessions.get("s-ws") is None)
  let second = try {
    ignore(archive_session(manager, "s-ws", (_, _) => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    second,
    content=(
      #|"no durable record for this conversation in the global store or any attached workspace"
    ),
  )
}

///|
#cfg(not(platform="windows"))
async test "archive reports a workspace record whose directory vanished" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-gone-")
  defer @fs.rmdir(dir, recursive=true)
  let workspace = dir + "/ws"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-ws"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  // The workspace directory vanishes outside the app; the registry keeps
  // its dead entry addressable, so the sidebar still shows the workspace.
  @fs.rmdir(workspace, recursive=true)
  let detail = try {
    ignore(archive_session(manager, "s-ws", (_, _) => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    detail,
    content=(
      #|"no durable record for this conversation in the global store or any attached workspace"
    ),
  )
}

///|
#cfg(not(platform="windows"))
async test "loading a conversation from a detached workspace names that state" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-load-detached-")
  defer @fs.rmdir(dir, recursive=true)
  let workspace = dir + "/ws"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-ws"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let detached = detach_workspace(manager, workspace, fn(_) {  })
  assert_true(detached is Workspaces([]))
  // A stale client's transcript reload names the conversation without a
  // workspace hint; the reply must say the record is unreachable rather
  // than surface the engine's raw file error.
  let detail = try {
    ignore(load_session(manager, { session: "s-ws", workspace: None, }))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    detail,
    content=(
      #|"no attached workspace holds this conversation; attach its project first"
    ),
  )
}

///|
#cfg(not(platform="windows"))
async test "archiving an already-archived conversation names that state" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-again-")
  defer @fs.rmdir(dir, recursive=true)
  @sys.set_env_var("HOME", dir + "/global")
  ignore(attach_run_workspace(Path(dir)))
  let store = dir + "/ws/.openseek"
  @fsx.ensure_dir(Path(store + "/archived/sessions/s-done"))
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let detail = try {
    ignore(archive_session(manager, "s-done", (_, _) => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    detail,
    content=(
      #|"this conversation is already archived"
    ),
  )
  assert_true(@fsx.is_dir(Path(store + "/archived/sessions/s-done")))
}
