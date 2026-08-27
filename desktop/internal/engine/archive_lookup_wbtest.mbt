// Archive's store selection against stores a stale client can still name: a
// conversation row can outlive its workspace's registration (detach) or its
// directory (external deletion), and a second archive click can race the
// first one's commit. Each state must answer with its own actionable
// refusal, and a failed attempt must leave no wedged host state behind.

///|
#cfg(not(platform="windows"))
async test "archive names the detached workspace the client selected" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-detach-")
  let workspace = dir + "/ws"
  let other = dir + "/other"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-ws"))
  @fsx.ensure_dir(Path(other + "/.openseek"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace, other] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  // The sidebar's remove button: detach commits and the registry forgets
  // the workspace, while the record stays on disk in the project store.
  let detached = detach_workspace(manager, workspace, fn(_) {  })
  assert_true(detached is Workspaces([_]))
  // A stale sidebar can still offer the conversation, selecting the store it
  // last saw. Naming a store the host no longer owns is refused by name
  // rather than silently redirected to whatever else holds the id.
  let selected = @pathx.Path(workspace).resolve().resource_path()
  let detail = try {
    ignore(archive_session(manager, "s-ws", selected, (_, _) => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.has_suffix("is not a registered workspace"))
  assert_true(@fsx.is_dir(Path(workspace + "/.openseek/sessions/s-ws")))
  // The failed attempt must leave no wedged host state behind: no record
  // move claim, no pending slot, and the next attempt reports the same
  // refusal instead of "already moving".
  assert_true(manager.record_guards.get("s-ws") is None)
  guard manager.pump is Serving(sessions~) else { fail("pump stopped") }
  assert_true(sessions.get("s-ws") is None)
  // The record is not reachable through another attached store either:
  // selection is exact, so the id alone opens no back door into a store that
  // does not hold it.
  let other_attempt = try {
    ignore(
      archive_session(
        manager,
        "s-ws",
        @pathx.Path(other).resolve().resource_path(),
        (_, _) => (),
      ),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    other_attempt,
    content=(
      #|"no durable record for this conversation in the selected store"
    ),
  )
  assert_true(@fsx.is_dir(Path(workspace + "/.openseek/sessions/s-ws")))
  assert_true(manager.record_guards.get("s-ws") is None)
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive reports a workspace record whose directory vanished" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-gone-")
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
    ignore(
      archive_session(
        manager,
        "s-ws",
        @pathx.Path(workspace).resolve().resource_path(),
        (_, _) => (),
      ),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    detail,
    content=(
      #|"no durable record for this conversation in the selected store"
    ),
  )
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "loading a conversation from a detached workspace names that state" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-load-detached-")
  let workspace = dir + "/ws"
  let other = dir + "/other"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-ws"))
  @fsx.ensure_dir(Path(other + "/.openseek"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace, other] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  // Another attached store never answers for an id it does not hold. The
  // record is visibly `workspace`'s, so naming `other` is a mis-addressed
  // request rather than a conversation whose first turn has not committed.
  let other_attempt = try {
    ignore(
      load_session(manager, {
        session: "s-ws",
        workspace: @pathx.Path(other).resolve().resource_path(),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  debug_inspect(
    other_attempt,
    content=(
      #|"no durable record for this conversation in the selected store"
    ),
  )
  let detached = detach_workspace(manager, workspace, fn(_) {  })
  assert_true(detached is Workspaces([_]))
  // A stale client's transcript reload still names the store it last saw;
  // the reply must say that store is gone rather than read the global one or
  // surface the engine's raw file error.
  let detail = try {
    ignore(
      load_session(manager, {
        session: "s-ws",
        workspace: @pathx.Path(workspace).resolve().resource_path(),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.has_suffix("is not a registered workspace"))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "a conversation whose first turn has not committed loads as empty" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-load-fresh-")
  let workspace = dir + "/ws"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  // `agent.started` precedes the first durable write, so a client that
  // reconnects in that window asks for a record no store holds yet. That is
  // this conversation's answer — an empty transcript it will fill — and not
  // a failure it could only retry forever.
  let reply = load_session(manager, {
    session: "s-uncommitted",
    workspace: @pathx.Path(workspace).resolve().resource_path(),
  })
  assert_eq(reply.session.id, Some("s-uncommitted"))
  assert_true(reply.session.events is Some([]))
  assert_eq(reply.watermark, Some(0))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive moves the selected store's record, not the same id elsewhere" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-same-id-")
  let workspace = dir + "/ws"
  let other = dir + "/other"
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  @sys.set_env_var("HOME", home)
  @fsx.ensure_dir(Path(global_root))
  // The same session id in two attached projects — what the sidebar renders
  // as two rows. Registration order decides which one a search would find
  // first, so archiving without a store would always move that one.
  @fsx.ensure_dir(Path(other + "/.openseek/sessions/s-both"))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-both"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [other, workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let moved : Array[(String, String)] = []
  let selected = @pathx.Path(workspace).resolve().resource_path()
  assert_true(
    archive_session(manager, "s-both", selected, (id, store) => {
      moved.push((id, store))
    })
    is Archived(_),
  )
  // Only the selected project's record moved, and the notification names its
  // store, so no client applies the disposition to the other project's row.
  assert_eq(moved.length(), 1)
  assert_eq(moved[0].0, "s-both")
  assert_true(moved[0].1.has_suffix("/ws"))
  assert_false(@fsx.exists(Path(workspace + "/.openseek/sessions/s-both")))
  assert_true(
    @fsx.is_dir(Path(workspace + "/.openseek/archived/sessions/s-both")),
  )
  assert_true(@fsx.is_dir(Path(other + "/.openseek/sessions/s-both")))
  assert_false(@fsx.exists(Path(other + "/.openseek/archived/sessions/s-both")))
  // Unarchiving restores the selected record beside the untouched one in the
  // other project instead of colliding with it.
  ignore(unarchive_session(manager, "s-both", selected, (_, _) => ()))
  assert_true(@fsx.is_dir(Path(workspace + "/.openseek/sessions/s-both")))
  assert_true(@fsx.is_dir(Path(other + "/.openseek/sessions/s-both")))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archiving an already-archived conversation names that state" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-again-")
  @sys.set_env_var("HOME", dir + "/global")
  let workspace = attach_run_workspace(Path(dir))
  let store = dir + "/ws/.openseek"
  @fsx.ensure_dir(Path(store + "/archived/sessions/s-done"))
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let detail = try {
    ignore(archive_session(manager, "s-done", workspace, (_, _) => ()))
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
  @fs.rmdir(dir, recursive=true)
}
