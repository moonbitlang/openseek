///|
/// Sidecar data lives inside the session directory, so archive, restore and
/// deletion move it together with the transcript. No engine journal rewrite.
pub async fn session_artifacts_list(
  manager : EngineManager,
  session : String,
) -> @protocol.SessionArtifacts {
  guard @session_store.safe_session_id(session) else {
    raise EngineError("invalid session id")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_read(session)
  defer manager.end_record_read(session, lease)
  guard @session_store.root_of(session) is Some(root) else {
    // A new draft has no durable session directory yet.
    return @protocol.SessionArtifacts::empty()
  }
  read_session_artifacts(root, session)
}

///|
async fn read_session_artifacts(
  root : @pathx.Absolute,
  session : String,
) -> @protocol.SessionArtifacts {
  match
    @fsx.read_text_if_exists(
      root.join("sessions").join(session).join("artifacts.json").to_path(),
    ) {
    Some(text) => @json.from_json(@json.parse(text))
    None => @protocol.SessionArtifacts::empty()
  }
}

///|
/// Apply an attach or UI removal to the latest stored artifact list.
/// Local lifecycle guards and the shared archive lock fence record moves;
/// the sidecar lock serializes read/modify/write across host processes.
pub async fn session_artifacts_update(
  manager : EngineManager,
  session : String,
  update : (@protocol.SessionArtifacts) -> @protocol.SessionArtifacts,
  on_committed : () -> Unit,
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
  let next = update(read_session_artifacts(root, session))
  @async.protect_from_cancel(() => {
    @fsx.write_text_atomic(
      directory.join("artifacts.json").to_path(),
      next.to_json().stringify(),
    )
    on_committed()
  })
  next
}
