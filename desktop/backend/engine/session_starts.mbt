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
    ..self.current,
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
priv struct SessionStartsLocation {
  root : @pathx.Absolute
  workspace : String
}

///|
async fn session_starts_location(
  session : String,
  workspace? : String,
  archived~ : Bool = false,
  manager? : EngineManager,
) -> SessionStartsLocation? {
  if workspace is Some(hint) {
    let selected = @session_store.ArchivedStore::for_workspace(hint)
    return Some({ root: selected.root, workspace: selected.workspace_token, })
  }
  let root = if archived {
    @session_store.archived_root_of(session)
  } else if manager is Some(manager) &&
    manager.followers.get(session) is Some(follower) {
    // MCP grants carry the source id. Its active follower identifies the
    // actual store even when another attached project contains the same id.
    Some(follower.root)
  } else {
    @session_store.root_of(session)
  }
  guard root is Some(root) else { return None }
  for project in @workspaces.registered() {
    if @workspaces.store_root(project) == root {
      return Some({ root, workspace: project.resource_path(), })
    }
  }
  raise EngineError("the source session's workspace is no longer registered")
}

///|
async fn read_session_starts(
  file : @pathx.Path,
  session : String,
  workspace : String?,
  archived : Bool,
) -> @protocol.SessionStartsSnapshot {
  if @fsx.read_text_if_exists(file) is Some(text) {
    let snapshot : @protocol.SessionStartsSnapshot = @json.from_json(
      @json.parse(text),
    )
    guard snapshot.session == session else {
      raise EngineError("session suggestion sidecar belongs to another session")
    }
    // Legacy sidecars lack this scope; the selected record, rather than the
    // file's old metadata, is the authority for both replies and notifications.
    { ..snapshot, workspace, archived: Some(archived), }
  } else {
    {
      session,
      workspace,
      archived: Some(archived),
      generation: 0,
      proposals: [],
    }
  }
}

///|
pub async fn session_starts_list(
  manager : EngineManager,
  session : String,
  workspace? : String,
  archived~ : Bool = false,
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
  guard session_starts_location(session, workspace?, archived~, manager~)
    is Some(location) else {
    return {
      session,
      workspace: None,
      archived: Some(archived),
      generation: 0,
      proposals: [],
    }
  }
  let root = if archived {
    @session_store.archived_root(location.root)
  } else {
    location.root
  }
  read_session_starts(
    root.join("sessions").join(session).join("session-starts.json").to_path(),
    session,
    Some(location.workspace),
    archived,
  )
}

///|
/// Only a previously admitted operation's result may follow its source into
/// the archived twin. New proposals and decisions retain the live-only default.
/// The shared archive lock keeps record moves outside this short mutation.
pub async fn[T] with_session_starts(
  manager : EngineManager,
  session : String,
  on_committed : (@protocol.SessionStartsSnapshot) -> Unit,
  action : async (SessionStartsStore) -> T,
  workspace? : String,
  allow_archived~ : Bool = false,
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
  let selected = session_starts_location(session, workspace?, manager~)
  let location = if selected is Some(location) {
    location
  } else if allow_archived {
    guard session_starts_location(session, archived=true) is Some(location) else {
      raise EngineError("the current session has no durable record")
    }
    location
  } else {
    raise EngineError("the current session has no durable record")
  }
  let shared = @fsx.FileLock::acquire(
    @session_store.archived_root(location.root).to_path(),
  )
  defer shared.release()
  let live = @fsx.is_dir(location.root.join("sessions").join(session).to_path())
  let archived = !live &&
    allow_archived &&
    @fsx.is_dir(
      @session_store.archived_root(location.root)
      .join("sessions")
      .join(session)
      .to_path(),
    )
  guard live || archived else {
    raise EngineError("the current session has no durable record")
  }
  let root = if archived {
    @session_store.archived_root(location.root)
  } else {
    location.root
  }
  let file = root
    .join("sessions")
    .join(session)
    .join("session-starts.json")
    .to_path()
  let lock = @fsx.FileLock::acquire(file)
  defer lock.release()
  let current = read_session_starts(
    file,
    session,
    Some(location.workspace),
    archived,
  )
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
  action({ file, current, requests, on_committed, })
}

///|
/// The execution lock lives outside the record, so source archive/restore does
/// not replace its identity. Only one user choice for this proposal can run.
pub async fn[T] with_session_start_decision(
  source : String,
  id : String,
  action : async () -> T,
  workspace? : String,
) -> T {
  let lock = @fsx.FileLock::acquire(
    session_start_decision_file(source, id, workspace?),
  )
  defer lock.release()
  action()
}

///|
pub async fn[T] try_with_session_start_decision(
  source : String,
  id : String,
  action : async () -> T,
  workspace? : String,
) -> T? {
  guard @fsx.FileLock::try_acquire(
      session_start_decision_file(source, id, workspace?),
    )
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
  workspace? : String,
) -> @pathx.Path {
  guard @session_store.safe_session_id(source) &&
    @session_store.safe_session_id(id) else {
    raise EngineError("invalid session suggestion identity")
  }
  guard session_starts_location(source, workspace?) is Some(location) else {
    raise EngineError("the current session has no durable record")
  }
  location.root.join("session-start-decisions").join(id).to_path()
}

///|
/// Read a receipt from the selected project's exact live/archived pair.
/// Missing live data may be a not-yet-written task; read errors stay errors.
pub async fn session_start_target_archived(
  session : String,
  workspace : String,
) -> Bool {
  guard @session_store.safe_session_id(session) else {
    raise EngineError("invalid session id")
  }
  let selected = @session_store.ArchivedStore::for_workspace(workspace)
  if @fsx.is_dir(selected.root.join("sessions").join(session).to_path()) {
    return false
  }
  @fsx.is_dir(
    @session_store.archived_root(selected.root)
    .join("sessions")
    .join(session)
    .to_path(),
  )
}
