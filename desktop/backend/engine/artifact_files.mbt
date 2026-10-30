///|
/// Read a generated file only from the message's exact owning workspace and
/// conversation. The lifecycle lease keeps archive/delete from moving the
/// scratch directory while its file is being read.
pub async fn session_artifact_file(
  manager : EngineManager,
  payload : @protocol.ArtifactFilePayload,
) -> @protocol.ArtifactFileReply {
  guard @session_store.safe_session_id(payload.session) else {
    raise EngineError("invalid session id")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_read(payload.session)
  defer manager.end_record_read(payload.session, lease)
  guard @pathx.Absolute::from_uri_path(payload.workspace) is Some(requested) &&
    @workspaces.registered_dir(requested) is Some(workspace) else {
    raise EngineError("workspace is not registered")
  }
  let live = @workspaces.store_root(workspace)
  let root = if payload.archived {
    @session_store.archived_root(live)
  } else {
    live
  }
  let store = @store.SessionStore(root.to_string())
  let id : @agent_session.SessionId = SessionId(payload.session)
  guard @fs.exists(store.session_file(id)) else {
    raise EngineError("conversation record is unavailable")
  }
  let path = store.artifact_file(id, payload.reference)
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let lower = path.to_lower()
  let content = if lower.has_suffix(".html") ||
    lower.has_suffix(".htm") ||
    lower.has_suffix(".svg") {
    // Self-contained compiled interactive pages include their JS and CSS.
    // Bound before allocation and refuse rather than display truncated code.
    guard file.size() <= 8L * 1024 * 1024 else {
      raise EngineError("artifact preview exceeds 8 MiB")
    }
    Some(file.read_all().text())
  } else {
    None
  }
  { path, content, }
}
