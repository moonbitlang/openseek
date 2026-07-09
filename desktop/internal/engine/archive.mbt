// Archiving a conversation: move its durable record out of the live store
// (`<root>/sessions/<id>` → `<root>/archived/sessions/<id>`), so `sessions
// list` no longer sees it; unarchiving moves it back. The archived store
// keeps the engine's own layout, so listing archived conversations — titles
// included — is one more `sessions list` against `<root>/archived`. Files in
// the conversation's workspace are never touched: archiving hides the
// conversation, not the user's work.

///|
const ArchivedDirName = "archived"

///|
/// The pre-move-archive design's record: session ids whose workspace folder
/// was zipped away, one per line in the host's runtime dir. Read once for
/// migration; never written again.
const LegacyArchivedListFile = "archived_sessions.txt"

///|
fn archived_session_root(root : @path.Path) -> @path.Path {
  root.join(ArchivedDirName).normalize()
}

///|
/// The archived conversations, one group per session store — the same reply
/// shape as `list_sessions`, listing each store's `archived` twin instead.
pub async fn archived_sessions(manager : EngineManager) -> SessionsReply {
  migrate_legacy_archive(manager)
  guard resolved_session_root() is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  let groups : Array[SessionGroup] = [
    session_group(manager, "", archived_session_root(root)),
  ]
  for path in registered_workspaces() {
    let workspace : @path.Path = Path(path)
    groups.push(
      session_group(
        manager,
        path,
        archived_session_root(workspace_session_root(workspace)),
      ),
    )
  }
  { groups, }
}

///|
/// Archive one conversation and return the updated archived groups. Refused
/// while the conversation has an open turn — the engine would keep writing
/// into a store that just moved. An idle serve process for the session is
/// forgotten so a later unarchive-and-prompt respawns against the restored
/// record.
pub async fn archive_session(
  manager : EngineManager,
  session : String,
) -> SessionsReply {
  let session = session.trim().to_owned()
  guard !session.is_empty() && safe_workspace_id(session) else {
    raise EngineError("invalid session id")
  }
  // A start or compact between validation and its command hitting the wire
  // is about to write into the very record this op moves; claiming the slot
  // makes that window visible here — and holds it through the move, so
  // neither op can slip in under it. No slot (a conversation the host never
  // touched this lifetime) means nothing to claim.
  let slot = if manager.pump is Serving(sessions~) {
    sessions.get(session)
  } else {
    None
  }
  if slot is Some(slot) {
    slot.claim(ArchivePending)
  }
  defer (if slot is Some(slot) {
    slot.pending = None
    manager.prune_slot(session)
  })
  if slot is Some(slot) && slot.engine is Some(live) {
    match live.phase {
      Running(..) =>
        raise EngineError("this conversation is still running; stop it first")
      // No open run, but the engine is still appending the summary to the
      // very record this op moves.
      Compacting =>
        raise EngineError(
          "this conversation is compacting; wait for it to finish",
        )
      // Closing stdin is the serve protocol's EOF signal: the idle engine
      // drains and exits, and its reader task cleans up. Merely dropping
      // the handle would leak the process until the app shuts down (the
      // respawn path closes the same way).
      Idle => {
        live.writer.close()
        slot.engine = None
      }
    }
  }
  guard session_store_root(session) is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  move_session_record(
    root.join("sessions").join(session),
    archived_session_root(root).join("sessions"),
    session,
  )
  archived_sessions(manager)
}

///|
/// Restore one archived conversation into its live store and return the
/// updated archived groups. The record is looked up across every store's
/// `archived` twin — the global root first, then each registered workspace.
pub async fn unarchive_session(
  manager : EngineManager,
  session : String,
) -> SessionsReply {
  let session = session.trim().to_owned()
  guard !session.is_empty() && safe_workspace_id(session) else {
    raise EngineError("invalid session id")
  }
  let roots : Array[@path.Path] = []
  if resolved_session_root() is Some(root) {
    roots.push(root)
  }
  for path in registered_workspaces() {
    roots.push(workspace_session_root(Path(path)))
  }
  for root in roots {
    let record = archived_session_root(root).join("sessions").join(session)
    if @fsx.is_dir(record) {
      move_session_record(record, root.join("sessions"), session)
      return archived_sessions(manager)
    }
  }
  raise EngineError("no archived record for this conversation")
}

///|
/// Move a session record directory into `destination_dir/<session>`,
/// creating the destination store level on demand. Same-store moves are a
/// single rename, so a conversation is never half-archived.
async fn move_session_record(
  record : @path.Path,
  destination_dir : @path.Path,
  session : String,
) -> Unit {
  guard @fsx.is_dir(record) else {
    raise EngineError("no durable record for this conversation")
  }
  let destination = destination_dir.join(session)
  guard !@fsx.exists(destination) else {
    raise EngineError("a record for this conversation already exists there")
  }
  @fsx.ensure_dir(destination_dir) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not create \{destination_dir}: \{error}")
  }
  @fs.rename(record.to_string(), destination.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise EngineError("could not move the conversation record: \{error}")
  }
}

///|
/// One-time migration from the zip-era archive record: every session id in
/// the runtime dir's `archived_sessions.txt` gets its (still-live) durable
/// record moved into the global store's `archived` twin, and the list file
/// goes away once nothing is left in it. Ids whose record is already gone
/// simply drop; a failed move keeps its id in the file for the next attempt.
/// The workspace zips the old design produced stay where they are.
async fn migrate_legacy_archive(manager : EngineManager) -> Unit {
  guard manager.runtime_dir is Some(dir) else { return }
  let list = dir.join(LegacyArchivedListFile)
  let text = (@fsx.try_read_text(list) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }).unwrap_or("")
  guard !text.is_empty() else { return }
  guard resolved_session_root() is Some(root) else { return }
  let remaining : Array[String] = []
  for line in text.split("\n") {
    let session = line.trim().to_owned()
    if session.is_empty() || !safe_workspace_id(session) {
      continue
    }
    let record = root.join("sessions").join(session)
    let is_live = @fsx.is_dir(record) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    if !is_live {
      continue
    }
    move_session_record(
      record,
      archived_session_root(root).join("sessions"),
      session,
    ) catch {
      error if @async.is_being_cancelled() => raise error
      _ => remaining.push(session)
    }
  }
  if remaining.length() == 0 {
    @fsx.remove_if_exists(list) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  } else {
    @fsx.write_text(list, remaining.join("\n") + "\n") catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
}
