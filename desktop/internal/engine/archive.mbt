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
/// Every store that can own a session id. Correlation and stale-client
/// defenses must search all of them: request hints are optional and cannot be
/// trusted to identify where an existing record lives.
async fn known_session_roots() -> Array[@path.Path] {
  let roots : Array[@path.Path] = []
  if resolved_session_root() is Some(root) {
    roots.push(root)
  }
  for path in registered_workspaces() {
    roots.push(workspace_session_root(Path(path)))
  }
  roots
}

///|
async fn archived_record_root(session : String) -> @path.Path? {
  guard !session.is_empty() else { return None }
  for root in known_session_roots() {
    if @fsx.is_dir(archived_session_root(root).join("sessions").join(session)) {
      return Some(root)
    }
  }
  None
}

///|
async fn ensure_session_not_archived(session : String) -> Unit {
  if archived_record_root(session) is Some(_) {
    raise EngineError("session is archived; unarchive it first")
  }
}

///|
/// The archived conversations, one group per session store — the same reply
/// shape as `list_sessions`, listing each store's `archived` twin instead.
pub async fn archived_sessions(
  manager : EngineManager,
  on_migrated : (String) -> Unit,
) -> SessionsReply {
  migrate_legacy_archive(manager, on_migrated)
  list_archived_sessions(manager)
}

///|
/// List only. Archive/unarchive already committed and published their own
/// mutation; they must not discover unrelated legacy moves while producing a
/// potentially slow reply without the list_archived dispatcher callback.
async fn list_archived_sessions(manager : EngineManager) -> SessionsReply {
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
  on_committed : () -> Unit,
) -> SessionsReply {
  let session = session.trim().to_owned()
  guard !session.is_empty() && safe_workspace_id(session) else {
    raise EngineError("invalid session id")
  }
  archive_session_commit(manager, session, on_committed)
  // Listing is intentionally outside the record-move lease. Once the
  // irreversible rename is durably published, a slow/cancelled list reply
  // must not hold the conversation unavailable or suppress session.changed.
  list_archived_sessions(manager)
}

///|
async fn archive_session_commit(
  manager : EngineManager,
  session : String,
  on_committed : () -> Unit,
) -> Unit {
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  defer (if placement_locked { manager.workspace_lifecycle_lock.release() })
  let record_guard = manager.claim_record_move(session)
  defer manager.release_record_move(session, record_guard)
  // Archive mutation requires a live pump generation. A durable record may
  // exist while Stopped, but without a current slot there is no writer/phase
  // barrier and moving it would race the next host generation.
  let sessions = manager.serving()
  let slot = slot_for(sessions, session)
  let claim = slot.claim(sessions, session, ArchivePending)
  defer claim.release(manager)
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  record_guard.wait_until_idle()
  // A start or compact between validation and its command hitting the wire
  // is about to write into the very record this op moves; claiming the slot
  // makes that window visible here — and holds it through the move, so
  // neither op can slip in under it. Always create and claim the slot while
  // the pump is serving: after a host restart a durable conversation has no
  // pre-existing in-memory slot, but must still exclude a concurrent start.
  if slot.engine is Some(live) {
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
      // drains and exits. Wait for the bounded close/cancel/reap barrier;
      // only the EOF consumer clears the handle, so no late append can land
      // after the final follower scan.
      Idle => live.close_and_wait()
    }
  }
  // Join the EOF consumer's follower retirement before touching the record:
  // the ack means no `sessions show` is in flight and none will start, so a
  // late scan can never read (and broadcast from) the directory mid-move.
  // The consumer owns an independent attempt, so cancellation before this
  // join cannot strand a follower; the slot claim blocks any successor until
  // this op releases it.
  let follower = manager.followers.get(session)
  if follower is Some(follower) {
    stop_follower_instance(manager, follower, writer_exited=true)
  }
  claim.require_current(manager)
  guard session_store_root(session) is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  // The rename and notification are the commit. Cancellation is delayed only
  // across this finite section; after it returns normally or raises Cancelled,
  // every client has already learned the canonical session id that moved.
  @async.protect_from_cancel(() => {
    claim.require_current(manager)
    move_session_record(
      root.join("sessions").join(session),
      archived_session_root(root).join("sessions"),
      session,
    )
    on_committed()
  })
}

///|
/// Restore one archived conversation into its live store and return the
/// updated archived groups. The record is looked up across every store's
/// `archived` twin — the global root first, then each registered workspace.
pub async fn unarchive_session(
  manager : EngineManager,
  session : String,
  on_committed : () -> Unit,
) -> SessionsReply {
  let session = session.trim().to_owned()
  guard !session.is_empty() && safe_workspace_id(session) else {
    raise EngineError("invalid session id")
  }
  unarchive_session_commit(manager, session, on_committed)
  list_archived_sessions(manager)
}

///|
async fn unarchive_session_commit(
  manager : EngineManager,
  session : String,
  on_committed : () -> Unit,
) -> Unit {
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  defer (if placement_locked { manager.workspace_lifecycle_lock.release() })
  let record_guard = manager.claim_record_move(session)
  defer manager.release_record_move(session, record_guard)
  let sessions = manager.serving()
  let slot = slot_for(sessions, session)
  let claim = slot.claim(sessions, session, ArchivePending)
  defer claim.release(manager)
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  record_guard.wait_until_idle()
  for root in known_session_roots() {
    let record = archived_session_root(root).join("sessions").join(session)
    if @fsx.is_dir(record) {
      @async.protect_from_cancel(() => {
        claim.require_current(manager)
        move_session_record(record, root.join("sessions"), session)
        on_committed()
      })
      return
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
async fn migrate_legacy_archive(
  manager : EngineManager,
  on_migrated : (String) -> Unit,
) -> Unit {
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
    if !migrate_legacy_session(manager, root, session, on_migrated) {
      remaining.push(session)
    }
  }
  if remaining.length() == 0 {
    @fsx.remove_if_exists(list) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  } else {
    @fsx.write_text(list, "\{remaining.join("\n")}\n") catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
}

///|
/// Legacy migration is a record move too: use the same cross-generation
/// guard and current slot claim rather than letting list_archived rename a
/// record underneath a live writer or reader. A busy/stopped session remains
/// in the legacy file for a later retry.
async fn migrate_legacy_session(
  manager : EngineManager,
  root : @path.Path,
  session : String,
  on_migrated : (String) -> Unit,
) -> Bool {
  let record = root.join("sessions").join(session)
  let is_live = @fsx.is_dir(record) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if !is_live {
    return true
  }
  let record_guard = manager.claim_record_move(session) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  defer manager.release_record_move(session, record_guard)
  record_guard.wait_until_idle()
  let sessions = manager.serving() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  let slot = slot_for(sessions, session)
  let claim = slot.claim(sessions, session, ArchivePending) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  defer claim.release(manager)
  if slot.engine is Some(_) {
    return false
  }
  if manager.followers.get(session) is Some(follower) {
    stop_follower_instance(manager, follower, writer_exited=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return false
    }
  }
  try {
    @async.protect_from_cancel(() => {
      claim.require_current(manager)
      move_session_record(
        record,
        archived_session_root(root).join("sessions"),
        session,
      )
      on_migrated(session)
    })
    true
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
}

///|
let archive_env_test_lock : @async.Mutex = Mutex()

///|
#cfg(not(platform="windows"))
fn restore_session_root_env(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_SESSION_ROOT", value)
  } else {
    @sys.unset_env_var("OPENSEEK_SESSION_ROOT")
  }
}

///|
#cfg(not(platform="windows"))
async test "archive refuses a durable record while the pump is stopped" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-stopped-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  @fsx.ensure_dir(Path(dir + "/sessions/s-stopped"))
  let manager = new_engine_manager("unused")
  let committed = Ref(false)
  let detail = try {
    archive_session_commit(manager, "s-stopped", () => committed.val = true)
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("not connected"))
  assert_false(committed.val)
  assert_true(@fsx.is_dir(Path(dir + "/sessions/s-stopped")))
  assert_false(@fsx.is_dir(Path(dir + "/archived/sessions/s-stopped")))
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive publishes its move before a cancelled listing reply" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-commit-")
  let marker = dir + "/listing-started"
  let engine = dir + "/engine.sh"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  @fsx.ensure_dir(Path(dir + "/sessions/s-commit"))
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '' > '\{marker}'\nsleep 30\nprintf '%s' '{\"sessions\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  manager.pump = Serving(sessions=Map([]))
  let committed = Ref(false)
  @async.with_task_group(group => {
    let request = group.spawn(() => {
      ignore(
        archive_session(manager, "  s-commit  ", () => committed.val = true),
      )
    })
    while !@fsx.exists(Path(marker)) {
      @async.sleep(1)
    }
    request.cancel()
    let cancelled = try {
      request.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
  })
  assert_true(committed.val)
  assert_false(@fsx.is_dir(Path(dir + "/sessions/s-commit")))
  assert_true(@fsx.is_dir(Path(dir + "/archived/sessions/s-commit")))
  assert_true(manager.record_guards.get("s-commit") is None)
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archived lookup covers registered workspace stores" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-workspace-")
  let workspace = dir + "/workspace"
  let global_root = dir + "/global"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root)
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/archived/sessions/s-workspace"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let detail = try {
    ensure_session_not_archived("s-workspace")
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("is archived"))
  @fs.rmdir(dir, recursive=true)
}
