///|
/// Fork a committed turn through the engine's prompt-building path. The
/// placement lock and reader lease keep the store attached and unarchived
/// until the copy is durable; an active source may continue appending.
///
/// The fork works where its original works: in the workspace root, or bound
/// to the same worktree, whose checkout the two then share. The engine writes
/// the fork's prompt in that directory, so a worktree whose checkout is gone
/// is refused the way a turn there would be. `on_worktree_changed` reports
/// the worktree's new member.
pub async fn fork_session(
  manager : EngineManager,
  payload : @protocol.SessionForkPayload,
  on_worktree_changed : (String, Array[WorktreeInfo]) -> Unit,
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
  let dir = @worktree.run_dir(workspace, payload.session)
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
    dir.to_string(),
    "--model",
    payload.model,
  ]
  if resolved_global_skills_dir() is Some(dir) {
    args.append(["--global-skills-dir", dir.to_string()])
  }
  let store = @store.SessionStore(root.to_string())
  let id : @agent_session.SessionId = SessionId(session)
  let workspace_token = workspace.resource_path()
  // The engine writes the session file last, so it is what says the fork
  // exists: its worktree binding stays exactly when that file does.
  @worktree.add_session_to_worktree(
    workspace,
    session~,
    worktree_of=payload.session,
    () => {
      let output = engine_stdout(manager, args)
      guard output.trim() == session else {
        raise EngineError("engine returned an unexpected fork identity")
      }
    },
    record_exists=() => @fs.exists(store.session_file(id)),
    worktrees => on_worktree_changed(workspace_token, worktrees),
  )
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
async test "fork validates its request before spawning and releases its reader lease" {
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
    ignore(fork_session(manager, payload, (_, _) => ()))
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(ordinary, Some("engine returned an unexpected fork identity"))
  assert_true(manager.record_guards.get("source") is None)
  // A worktree conversation forks in its checkout, so one whose checkout is
  // gone is refused before anything is spawned or bound.
  let registry = workspace + "/.openseek/worktrees.json"
  @fs.write_file(
    registry,
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
  let unbound = @fs.read_file(registry).text()
  let missing = try {
    ignore(fork_session(manager, payload, (_, _) => ()))
    None
  } catch {
    @worktree.WorktreeError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(
    missing,
    Some(
      "worktree example for this conversation is gone; rebuild it or archive the conversation",
    ),
  )
  assert_eq(@fs.read_file(registry).text(), unbound)
  assert_true(manager.record_guards.get("source") is None)
  for session in ["source-sr-1", "source-sr-1-sr-2"] {
    let child = try {
      ignore(fork_session(manager, { ..payload, session, }, (_, _) => ()))
      None
    } catch {
      EngineError(detail) => Some(detail)
      error => raise error
    }
    assert_eq(child, Some("forking a subrun conversation is not supported"))
    assert_true(manager.record_guards.get(session) is None)
  }
  let invalid = try {
    ignore(fork_session(manager, { ..payload, through: 0, }, (_, _) => ()))
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(invalid, Some("invalid session fork boundary"))
}
