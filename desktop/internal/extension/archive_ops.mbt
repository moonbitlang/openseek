// Archiving a conversation: the host moves its durable record into the
// session store's `archived` twin (and back on unarchive) — see the engine
// package's archive.mbt. Nothing in the conversation's workspace is touched.
// All three ops reply with the archived groups, `list_sessions`-shaped.

///|
async fn archived_sessions_op(
  manager : @engine.EngineManager,
) -> @engine.SessionsReply {
  @engine.archived_sessions(manager) catch {
    @engine.EngineError(message) => raise HostError(message)
    error => raise error
  }
}

///|
async fn archive_session_op(
  manager : @engine.EngineManager,
  payload : ArchiveSessionPayload,
) -> @engine.SessionsReply {
  @engine.archive_session(manager, payload.session) catch {
    @engine.EngineError(message) => raise HostError(message)
    error => raise error
  }
}

///|
async fn unarchive_session_op(
  manager : @engine.EngineManager,
  payload : ArchiveSessionPayload,
) -> @engine.SessionsReply {
  @engine.unarchive_session(manager, payload.session) catch {
    @engine.EngineError(message) => raise HostError(message)
    error => raise error
  }
}
