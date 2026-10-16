///|
/// Sidecar data lives inside the session directory, so archive, restore and
/// deletion move it together with the transcript. No engine journal rewrite.
pub async fn session_pr_list(
  manager : EngineManager,
  session : String,
) -> @protocol.SessionPrBindings {
  guard @session_store.safe_session_id(session) else {
    raise EngineError("invalid session id")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_read(session)
  defer manager.end_record_read(session, lease)
  guard @session_store.root_of(session) is Some(root) else {
    // A new draft has no durable session directory yet.
    return @protocol.SessionPrBindings::empty()
  }
  read_session_pr(root, session)
}

///|
async fn read_session_pr(
  root : @pathx.Absolute,
  session : String,
) -> @protocol.SessionPrBindings {
  match
    @fsx.read_text_if_exists(
      root.join("sessions").join(session).join("pr-bindings.json").to_path(),
    ) {
    Some(text) => @json.from_json(@json.parse(text))
    None => @protocol.SessionPrBindings::empty()
  }
}

///|
/// Replace the entire list, or remove one URL from the latest stored list.
/// Local lifecycle guards and the shared archive lock fence record moves;
/// the sidecar lock serializes read/modify/write across host processes.
pub async fn session_pr_update(
  manager : EngineManager,
  session : String,
  update : (@protocol.SessionPrBindings) -> @protocol.SessionPrBindings,
  on_committed : () -> Unit,
) -> @protocol.SessionPrBindings {
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
  let lock = @fsx.FileLock::acquire(
    directory.join("pr-bindings.json").to_path(),
  )
  defer lock.release()
  let next = update(read_session_pr(root, session))
  @async.protect_from_cancel(() => {
    @fsx.write_text_atomic(
      directory.join("pr-bindings.json").to_path(),
      next.to_json().stringify(),
    )
    on_committed()
  })
  next
}
