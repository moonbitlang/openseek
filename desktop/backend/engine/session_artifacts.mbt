///|
/// Apply an attach or UI removal to the latest stored artifact list.
/// Local lifecycle guards and the shared archive lock fence record moves;
/// the sidecar lock serializes read/modify/write across host processes.
pub async fn session_artifacts_update(
  manager : EngineManager,
  session : String,
  update~ : (@protocol.SessionArtifacts) -> @protocol.SessionArtifacts,
  on_committed~ : (@protocol.SessionArtifacts) -> Unit,
) -> @protocol.SessionArtifacts {
  guard @session_store.safe_session_id(session) else {
    raise EngineError("invalid session id")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_op(session)
  defer manager.end_record_op(session, lease)
  guard @session_store.root_of(session) is Some(root) else {
    raise EngineError("the current session has no durable record")
  }
  let shared = @fsx.FileLock::acquire(
    @session_store.archived_root(root).to_path(),
  )
  defer shared.release()
  // Another host may have archived the record while we waited. Revalidate
  // before the sidecar lock has a chance to recreate its parent directory.
  guard @session_store.root_of(session) == Some(root) else {
    raise EngineError("the current session has no durable record")
  }
  let directory = root.join("sessions").join(session)
  let lock = @fsx.FileLock::acquire(directory.join("artifacts.json").to_path())
  defer lock.release()
  let next = update(@session_store.read_artifacts(directory))
  @async.protect_from_cancel(() => {
    @openseek/atomic_file.write_text_atomic(
      directory.join("artifacts.json").to_string(),
      next.to_json().stringify(),
    )
    on_committed(next)
  })
  next
}
