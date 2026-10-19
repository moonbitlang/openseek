///|
/// Fork a committed turn through the engine's prompt-building path. The
/// placement lock and reader lease keep the store attached and unarchived
/// until the copy is durable; an active source may continue appending.
///
/// A fork of a workspace-root conversation works in the workspace root too.
/// A fork of a worktree conversation gets a worktree of its own, detached at
/// the source checkout's HEAD; the engine's fork notice names the paths the
/// source had uncommitted, which the new checkout does not have. The engine
/// writes the fork's prompt in the fork's directory, so a worktree whose
/// checkout is gone is refused the way a turn there would be.
/// `on_worktree_changed` reports the new worktree.
///
/// The engine writes the session file last, so that file is what says the
/// fork exists, whichever way this request then ends. A fork that exists
/// keeps its worktree, gets its title, and is reported through `on_created`
/// — also when the engine failed after writing it, and when the request was
/// cancelled and has no reply to carry the news.
///
/// A side-chat fork is the same copy under the id `side_chat_id` gives it —
/// the source's first free side-chat ordinal — which makes it part of the
/// source's family. It is an aside about the source's work, so it shares the
/// source's checkout rather than getting one of its own. A side chat has no
/// side chats of its own.
pub async fn fork_session(
  manager : EngineManager,
  payload : @protocol.SessionForkPayload,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
) -> @protocol.SessionForkReply {
  fork_session_in(
    manager,
    payload,
    if payload.side_chat is Some(true) {
      SharedWorktree
    } else {
      OwnWorktree
    },
    on_created~,
    on_worktree_changed~,
  )
}

///|
/// Where a fork of a worktree conversation works. A fork the user asked for
/// is a second line of work and gets its own checkout; a message edit
/// replaces its source, which is deleted once the edit is saved, and takes
/// over the source's checkout by sharing it first.
priv enum ForkPlacement {
  OwnWorktree
  SharedWorktree
}

///|
async fn fork_session_in(
  manager : EngineManager,
  payload : @protocol.SessionForkPayload,
  placement : ForkPlacement,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
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
  let side_chat = payload.side_chat is Some(true)
  guard !side_chat || @protocol.split_side_chat_id(payload.session) is None else {
    raise EngineError("a side chat cannot open a side chat of its own")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_read(payload.session)
  defer manager.end_record_read(payload.session, lease)
  guard @pathx.Absolute::from_uri_path(payload.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("workspace is not a registered workspace")
  }
  let root = @workspaces.store_root(workspace)
  let store = @store.SessionStore(root.to_string())
  // Under the placement lock no other fork names a side chat of this source
  // meanwhile; the engine's claim on the directory refuses a collision anyway.
  let session = if side_chat {
    let mut ordinal = 1
    while store.exists(
            SessionId(@protocol.side_chat_id(payload.session, ordinal)),
          ) {
      ordinal += 1
    }
    @protocol.side_chat_id(payload.session, ordinal)
  } else {
    "desktop-" + @uuid.mint()
  }
  let id : @agent_session.SessionId = SessionId(session)
  let workspace_token = workspace.resource_path()
  // The renderer uses the same label as the sidebar, including titles derived
  // from the first prompt before any explicit rename has been saved.
  let title = payload.source_title
  // What a fork that exists is owed. The title is best effort: failing to
  // save it must not turn a fork that was made into a retry that makes
  // another.
  async fn announce() -> Unit {
    store.set_title(id, title) catch {
      error =>
        @xlog.warn() <?
          {
            "event": "desktop_fork_title_save_failed",
            "session": session,
            "error": error.to_string(),
          }
    }
    on_created(session)
  }

  {
    errdefer @async.protect_from_cancel(() => {
      if @fs.exists(store.session_file(id)) {
        announce()
      }
    })
    // `notice` is the host's part of the fork's notice: what it knows of
    // `dir` that the engine does not.
    async fn engine_fork(dir : @pathx.Absolute, notice : String?) -> Unit {
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
      // The `=` spelling keeps text that starts with `-` a value.
      if notice is Some(text) {
        args.push("--notice=\{text}")
      }
      if resolved_global_skills_dir() is Some(skills) {
        args.append(["--global-skills-dir", skills.to_string()])
      }
      let failure : Error? = try {
        ignore(engine_stdout(manager, args))
        None
      } catch {
        error => Some(error)
      }
      // The record says whether the fork was made — not how the engine
      // exited, nor what it printed. Reporting a failure for a fork that
      // exists would invite a retry that makes a second one.
      if !@fs.exists(store.session_file(id)) {
        if failure is Some(error) {
          raise error
        }
        raise EngineError("engine reported a fork it did not write")
      }
      if failure is Some(error) {
        @xlog.warn() <?
          {
            "event": "desktop_fork_engine_failed_after_commit",
            "session": session,
            "error": error.to_string(),
          }
      }
    }

    match placement {
      OwnWorktree =>
        @worktree.add_session_to_new_worktree(
          workspace,
          session~,
          worktree_of=payload.session,
          checkout => {
            match checkout {
              WorkspaceRoot(dir) => engine_fork(dir, None)
              NewWorktree(dir~, uncommitted~, omitted~) =>
                engine_fork(
                  dir,
                  Some(new_worktree_notice(uncommitted~, omitted~)),
                )
            }
          },
          record_exists=() => @fs.exists(store.session_file(id)),
          worktrees => on_worktree_changed(workspace_token, worktrees),
        )
      SharedWorktree =>
        @worktree.add_session_to_worktree(
          workspace,
          session~,
          worktree_of=payload.session,
          dir => engine_fork(dir, None),
          record_exists=() => @fs.exists(store.session_file(id)),
          worktrees => on_worktree_changed(workspace_token, worktrees),
        )
    }
  }
  @async.protect_from_cancel(() => announce())
  { session, title, }
}

///|
/// The host's part of the notice of a fork made in a worktree of its own:
/// how its checkout came to be, which the engine — handed only a directory —
/// cannot know. `uncommitted` lists paths the source's checkout had changed
/// and the new one lacks; `omitted` counts the ones left unlisted.
fn new_worktree_notice(
  uncommitted~ : Array[String],
  omitted~ : Int32,
) -> String {
  let lines = [
    "The working directory is a new git worktree, checked out at the commit the original conversation's worktree had at HEAD. Uncommitted changes in that worktree were not carried over.",
  ]
  if !uncommitted.is_empty() || omitted > 0 {
    lines.push("That worktree had uncommitted changes to:")
    for path in uncommitted {
      lines.push("- \{path}")
    }
    if omitted > 0 {
      lines.push("- and \{omitted} more")
    }
  }
  lines.join("\n")
}

///|
test "a new worktree's notice lists what was left behind" {
  inspect(
    new_worktree_notice(uncommitted=[], omitted=0).contains("\n"),
    content="false",
  )
  assert_true(
    new_worktree_notice(uncommitted=["-dash.txt", "src/a.mbt"], omitted=3).has_suffix(
      "\nThat worktree had uncommitted changes to:\n- -dash.txt\n- src/a.mbt\n- and 3 more",
    ),
  )
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
    side_chat: None,
  }
  let ordinary = try {
    ignore(
      fork_session(manager, payload, on_created=_ => (), on_worktree_changed=(
        _,
        _,
      ) => ()),
    )
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(ordinary, Some("engine reported a fork it did not write"))
  assert_true(manager.record_guards.get("source") is None)
  // A worktree conversation's fork starts from its checkout's HEAD, so one
  // whose checkout is gone is refused before anything is spawned or made.
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
    ignore(
      fork_session(manager, payload, on_created=_ => (), on_worktree_changed=(
        _,
        _,
      ) => ()),
    )
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
      ignore(
        fork_session(manager, { ..payload, session, }, on_created=_ => (), on_worktree_changed=(
          _,
          _,
        ) => ()),
      )
      None
    } catch {
      EngineError(detail) => Some(detail)
      error => raise error
    }
    assert_eq(child, Some("forking a subrun conversation is not supported"))
    assert_true(manager.record_guards.get(session) is None)
  }
  let invalid = try {
    ignore(
      fork_session(manager, { ..payload, through: 0, }, on_created=_ => (), on_worktree_changed=(
        _,
        _,
      ) => ()),
    )
    None
  } catch {
    EngineError(detail) => Some(detail)
    error => raise error
  }
  assert_eq(invalid, Some("invalid session fork boundary"))
}
