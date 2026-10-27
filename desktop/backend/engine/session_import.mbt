///|
pub async fn import_session(
  manager : EngineManager,
  payload : @protocol.SessionImportPayload,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
) -> String {
  let records = @session_import.prepare(payload.source)
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  guard @pathx.Absolute::from_uri_path(payload.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("workspace is not a registered workspace")
  }
  let root = @workspaces.store_root(workspace)
  let store = @store.SessionStore(root.to_string())
  let session_id = records[0].session.id().value()
  // Fresh ids belong to this import alone. Validate the whole family before
  // writing, then publish the parent last so a failed import can be removed.
  for record in records {
    guard !store.exists(record.session.id()) else {
      raise EngineError("import session id already exists")
    }
  }
  errdefer @async.protect_from_cancel(() => {
    if !@fs.exists(store.session_file(SessionId(session_id))) {
      for record in records {
        @fsx.remove_if_exists(
          root.join("sessions").join(record.session.id().value()).to_path(),
        )
      }
    } else {
      on_created(session_id)
    }
  })
  let token = workspace.resource_path()
  @worktree.add_session_to_worktree(
    workspace,
    session=session_id,
    worktree_of=payload.worktree_of.unwrap_or(""),
    _ => {
      for record in records.rev_iter() {
        store.create(record.session)
        store.set_title(record.session.id(), record.title) catch {
          error =>
            @xlog.warn() <?
              {
                "event": "desktop_import_title_save_failed",
                "session": record.session.id().value(),
                "error": error.to_string(),
              }
        }
      }
    },
    record_exists=() => @fs.exists(store.session_file(SessionId(session_id))),
    rows => on_worktree_changed(token, rows),
  )
  on_created(session_id)
  session_id
}
