///|
/// Import an exported local conversation, with its subruns, into a
/// registered workspace through the engine's `sessions import`. The engine
/// validates the export, refuses one exported from Cloud, and builds the new
/// conversation's system prompt for the directory it will work in, as it
/// does for a fork. It writes the conversation's record last and removes
/// what it wrote when it fails, so that record is what says the import
/// exists, whichever way this request then ends.
pub async fn import_session(
  manager : EngineManager,
  payload : @protocol.SessionImportPayload,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[@protocol.WorktreeInfo]) -> Unit,
) -> String {
  let text = @session_import.prepare(payload.source)
  // The new prompt names the MCP servers a conversation's engine is given;
  // the user's file is read before the lifecycle lock, as it always is.
  let mcp_config = resolved_mcp_config()
  let staging = @fs.tmpdir(prefix="openseek-import-")
  defer @async.protect_from_cancel(() => {
    @fs.rmdir(staging, recursive=true) catch {
      _ => ()
    }
  })
  let source = "\{staging}/export.json"
  @fs.write_file(source, text, create_mode=CreateOrTruncate)
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let requested = @pathx.Absolute::parse_resource_path(payload.workspace)
  guard @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("workspace is not a registered workspace")
  }
  let root = @workspaces.store_root(workspace)
  let store = @store.SessionStore(root.to_string())
  let session_id = "desktop-" + @uuid.mint()
  let id : @agent_session.SessionId = SessionId(session_id)
  errdefer @async.protect_from_cancel(() => {
    if @fs.exists(store.session_file(id)) {
      on_created(session_id)
    }
  })
  async fn engine_import(dir : @pathx.Absolute) -> Unit {
    let args = [
      "sessions",
      "import",
      "--as",
      session_id,
      "--origin",
      "local",
      "--source",
      source,
      "--session-root",
      root.to_string(),
      "--dir",
      dir.to_string(),
    ]
    if resolved_global_skills_dir() is Some(skills) {
      args.append(["--global-skills-dir", skills.to_string()])
    }
    args.append(
      engine_mcp_args(
        mcp_config,
        manager.runtime_dir,
        @sys.get_env_vars(),
        host_mcp=manager.mcp.server is Some(_),
      ),
    )
    ignore(engine_stdout(manager, args))
    guard @fs.exists(store.session_file(id)) else {
      raise EngineError("engine reported an import it did not write")
    }
  }

  let token = workspace.resource_path()
  @worktree.add_session_to_worktree(
    workspace,
    session=session_id,
    worktree_of=payload.worktree_of.unwrap_or(""),
    engine_import,
    record_exists=() => @fs.exists(store.session_file(id)),
    rows => on_worktree_changed(token, rows),
  )
  on_created(session_id)
  session_id
}
