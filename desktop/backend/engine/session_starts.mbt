// Session start suggestions share the transcript's lifecycle without rewriting it.

///|
struct SessionStartsStore {
  file : @pathx.Path
  mut current : @protocol.SessionStartsSnapshot
  requests : Map[String, @protocol.SessionStartRequest]
  on_committed : (@protocol.SessionStartsSnapshot) -> Unit
}

///|
pub fn SessionStartsStore::snapshot(
  self : SessionStartsStore,
) -> @protocol.SessionStartsSnapshot {
  self.current
}

///|
pub fn SessionStartsStore::request(
  self : SessionStartsStore,
  request_id : String,
) -> @protocol.SessionStartRequest? {
  self.requests.get(request_id)
}

///|
pub async fn SessionStartsStore::save(
  self : SessionStartsStore,
  proposals : Array[@protocol.SessionStartProposal],
) -> @protocol.SessionStartsSnapshot {
  let next : @protocol.SessionStartsSnapshot = {
    session: self.current.session,
    generation: self.current.generation + 1,
    proposals,
  }
  let requests = self.requests.copy()
  for proposal in proposals {
    if !requests.contains(proposal.request_id) {
      requests[proposal.request_id] = proposal.request()
    }
  }
  @async.protect_from_cancel(() => {
    let encoded = match next.to_json() {
      Object(fields) => fields
      _ => Map([])
    }
    encoded["requests"] = Json(requests)
    @fsx.write_text_atomic(self.file, Json(encoded).stringify())
    for key, request in requests {
      self.requests[key] = request
    }
    self.current = next
    (self.on_committed)(next)
  })
  next
}

///|
async fn read_session_starts(
  file : @pathx.Path,
  session : String,
) -> @protocol.SessionStartsSnapshot {
  if @fsx.read_text_if_exists(file) is Some(text) {
    let snapshot : @protocol.SessionStartsSnapshot = @json.from_json(
      @json.parse(text),
    )
    guard snapshot.session == session else {
      raise EngineError("session suggestion sidecar belongs to another session")
    }
    snapshot
  } else {
    { session, generation: 0, proposals: [], }
  }
}

///|
pub async fn session_starts_list(
  manager : EngineManager,
  session : String,
) -> @protocol.SessionStartsSnapshot {
  guard @session_store.safe_session_id(session) else {
    raise EngineError("invalid session id")
  }
  manager.workspace_lifecycle_lock.acquire()
  let lease = {
    errdefer manager.workspace_lifecycle_lock.release()
    manager.begin_record_read(session)
  }
  manager.workspace_lifecycle_lock.release()
  defer manager.end_record_read(session, lease)
  guard @session_store.root_of(session) is Some(root) else {
    return { session, generation: 0, proposals: [], }
  }
  read_session_starts(
    root.join("sessions").join(session).join("session-starts.json").to_path(),
    session,
  )
}

///|
/// Apply a short source-sidecar mutation against the newest snapshot. Long
/// engine/worktree operations use `with_session_start_decision` outside this
/// callback, so an agent can keep proposing while Work here awaits steering.
pub async fn[T] with_session_starts(
  manager : EngineManager,
  session : String,
  on_committed : (@protocol.SessionStartsSnapshot) -> Unit,
  action : async (SessionStartsStore) -> T,
) -> T {
  guard @session_store.safe_session_id(session) else {
    raise EngineError("invalid session id")
  }
  manager.workspace_lifecycle_lock.acquire()
  let lease = {
    errdefer manager.workspace_lifecycle_lock.release()
    manager.begin_record_read(session)
  }
  manager.workspace_lifecycle_lock.release()
  defer manager.end_record_read(session, lease)
  guard @session_store.root_of(session) is Some(root) else {
    raise EngineError("the current session has no durable record")
  }
  let shared = @fsx.FileLock::acquire(
    @session_store.archived_root(root).to_path(),
  )
  defer shared.release()
  guard @session_store.root_of(session) == Some(root) else {
    raise EngineError("the current session has no durable record")
  }
  let file = root
    .join("sessions")
    .join(session)
    .join("session-starts.json")
    .to_path()
  let lock = @fsx.FileLock::acquire(file)
  defer lock.release()
  let current = read_session_starts(file, session)
  let requests : Map[String, @protocol.SessionStartRequest] = if @fsx.read_text_if_exists(
      file,
    )
    is Some(text) &&
    @json.parse(text) is Object(fields) &&
    fields.get("requests") is Some(value) {
    @json.from_json(value)
  } else {
    Map([])
  }
  for proposal in current.proposals {
    if !requests.contains(proposal.request_id) {
      requests[proposal.request_id] = proposal.request()
    }
  }
  let store : SessionStartsStore = { file, current, requests, on_committed, }
  action(store)
}

///|
/// A proposal's execution lock is outside the source record, so its identity
/// survives source archive/restore. It fences an entire user choice without
/// holding a workspace-wide archive lock or blocking other proposals' saves.
pub async fn[T] with_session_start_decision(
  source : String,
  id : String,
  action : async () -> T,
) -> T {
  let lock = @fsx.FileLock::acquire(session_start_decision_file(source, id))
  defer lock.release()
  action()
}

///|
/// Skip an actively owned proposal during snapshot recovery. Its owner will
/// publish the result; only an abandoned decision needs reconciliation here.
pub async fn[T] try_with_session_start_decision(
  source : String,
  id : String,
  action : async () -> T,
) -> T? {
  guard @fsx.FileLock::try_acquire(session_start_decision_file(source, id))
    is Some(lock) else {
    return None
  }
  defer lock.release()
  Some(action())
}

///|
async fn session_start_decision_file(
  source : String,
  id : String,
) -> @pathx.Path {
  guard @session_store.safe_session_id(source) &&
    @session_store.safe_session_id(id) else {
    raise EngineError("invalid session suggestion identity")
  }
  guard @session_store.root_of(source) is Some(root) else {
    raise EngineError("the current session has no durable record")
  }
  root.join("session-start-decisions").join(id).to_path()
}
