///|
/// Fork a committed turn through the engine's prompt-building path. The
/// placement lock and reader lease keep the store attached and unarchived
/// until the copy is durable; an active source may continue appending.
pub async fn fork_session(
  manager : EngineManager,
  payload : @protocol.SessionForkPayload,
) -> @protocol.SessionForkReply {
  guard @session_store.safe_session_id(payload.session) && payload.through > 0 else {
    raise EngineError("invalid session fork boundary")
  }
  guard !payload.source_title.is_blank() else {
    raise EngineError("session fork source title is required")
  }
  guard @wire.split_child_session_id(payload.session) is None else {
    raise EngineError("forking a subrun conversation is not supported")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_read(payload.session)
  defer manager.end_record_read(payload.session, lease)
  guard @pathx.Absolute::from_uri_path(payload.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("workspace is not a registered workspace")
  }
  guard @worktree.run_dir(workspace, payload.session) == workspace else {
    raise EngineError("forking a worktree conversation is not supported yet")
  }
  let root = @workspaces.store_root(workspace)
  let session = "desktop-" + @uuid.mint()
  let args = [
    "sessions",
    "fork",
    payload.session,
    "--as",
    session,
    "--through",
    payload.through.to_string(),
    "--session-root",
    root.to_string(),
    "--dir",
    workspace.to_string(),
    "--model",
    payload.model,
  ]
  if resolved_global_skills_dir() is Some(dir) {
    args.append(["--global-skills-dir", dir.to_string()])
  }
  let output = engine_stdout(manager, args)
  guard output.trim() == session else {
    raise EngineError("engine returned an unexpected fork identity")
  }
  let store = @store.SessionStore(root.to_string())
  let id : @agent_session.SessionId = SessionId(session)
  // The renderer uses the same label as the sidebar, including titles derived
  // from the first prompt before any explicit rename has been saved.
  let title = payload.source_title
  // The CLI has already committed the new session. A best-effort title write
  // must not turn that success into a retry that creates another fork.
  @async.protect_from_cancel(() => {
    store.set_title(id, title) catch {
      error =>
        @xlog.warn() <?
          {
            "event": "desktop_fork_title_save_failed",
            "session": session,
            "error": error.to_string(),
          }
    }
  })
  { session, title, }
}

///|
#cfg(not(platform="windows"))
async test "fork validates placement before spawning and releases its reader lease" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  defer restore_home_env(previous)
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-desktop-fork-"))
  defer @fs.rmdir(dir, recursive=true)
  let workspace = dir + "/workspace"
  @sys.set_env_var("HOME", dir + "/home")
  @fs.mkdir(dir + "/home/.openseek", recursive=true)
  @fs.mkdir(workspace + "/.openseek", recursive=true)
  @fs.write_file(
    dir + "/home/.openseek/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
  )
  // A successful /bin/echo spawn gets as far as the identity check. This
  // distinguishes ordinary project placement from a rejected worktree.
  let manager = new_engine_manager("/bin/echo")
  let payload : @protocol.SessionForkPayload = {
    session: "source",
    workspace: @pathx.Path(workspace).resolve().resource_path(),
    through: 3,
    model: "deepseek-flash",
    source_title: "Source conversation",
  }
  let ordinary = try {
    ignore(fork_session(manager, payload))
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(ordinary, Some("engine returned an unexpected fork identity"))
  assert_true(manager.record_guards.get("source") is None)
  @fs.mkdir(workspace + "/.worktrees/example", recursive=true)
  @fs.write_file(
    workspace + "/.openseek/worktrees.json",
    (
      {
        "worktrees": [
          {
            "name": "example",
            "branch": "example",
            "base": "base",
            "session": "source",
          },
        ],
      } : Json).stringify(),
  )
  let bound = try {
    ignore(fork_session(manager, payload))
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(bound, Some("forking a worktree conversation is not supported yet"))
  assert_true(manager.record_guards.get("source") is None)
  for session in ["source-sr-1", "source-sr-1-sr-2"] {
    let child = try {
      ignore(fork_session(manager, { ..payload, session, }))
      None
    } catch {
      EngineError(detail) => Some(detail)
      error => raise error
    }
    assert_eq(child, Some("forking a subrun conversation is not supported"))
    assert_true(manager.record_guards.get(session) is None)
  }
  let invalid = try {
    ignore(fork_session(manager, { ..payload, through: 0, }))
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(invalid, Some("invalid session fork boundary"))
}
