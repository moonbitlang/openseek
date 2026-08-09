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
fn archived_session_root(root : @pathx.Absolute) -> @pathx.Absolute {
  root.join(ArchivedDirName).normalize()
}

///|
/// Every store that can own a session id. Correlation and stale-client
/// defenses must search all of them: request hints are optional and cannot be
/// trusted to identify where an existing record lives.
async fn known_session_roots() -> Array[@pathx.Absolute] {
  let roots : Array[@pathx.Absolute] = []
  if resolved_session_root() is Some(root) {
    roots.push(root)
  }
  for path in registered_workspaces() {
    roots.push(workspace_session_root(path))
  }
  roots
}

///|
async fn archived_record_root(session : String) -> @pathx.Absolute? {
  guard !session.is_empty() else { return None }
  for root in known_session_roots() {
    if @fsx.is_dir(
        archived_session_root(root).join("sessions").join(session).to_path(),
      ) {
      return Some(root)
    }
  }
  None
}

///|
/// The store root whose live `sessions/<id>` holds this conversation's
/// durable record, searched like `archived_record_root`. Archive must find
/// the record where it actually lives: a stale client can name a
/// conversation long after its workspace detached, and the session id alone
/// says nothing about which store owns it.
async fn live_record_root(session : String) -> @pathx.Absolute? {
  guard !session.is_empty() else { return None }
  for root in known_session_roots() {
    if @fsx.is_dir(root.join("sessions").join(session).to_path()) {
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
/// Whether `candidate` is a sub-run transcript descended from `ancestor`.
/// Walk the structural `-sr-N` suffixes instead of matching a textual prefix:
/// a user-chosen id such as `chat-sr-not-an-ordinal` must remain unrelated.
fn is_descendant_session(candidate : String, ancestor : String) -> Bool {
  let mut current = candidate
  for ;; {
    guard @wire.split_child_session_id(current) is Some((parent, _)) else {
      return false
    }
    if parent == ancestor {
      return true
    }
    current = parent
  }
}

///|
/// The parent plus every descendant record present beside it in one live or
/// archived store. Session records are flat sibling directories even though
/// the sidebar presents them as a tree.
async fn session_family_in(
  store : @pathx.Absolute,
  session : String,
) -> Array[String] {
  let sessions_dir = store.join("sessions")
  let entries = @fs.readdir(sessions_dir.to_string(), sort=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not list session records: \{error}")
  }
  let family : Array[String] = [session]
  for candidate in entries {
    if candidate != session &&
      is_descendant_session(candidate, session) &&
      @fsx.is_dir(sessions_dir.join(candidate).to_path()) {
      family.push(candidate)
    }
  }
  family
}

///|
/// The record and engine claims held while a whole conversation family moves.
/// Claims are acquired for every member before any writer is closed or record
/// is renamed, so a busy child refuses the operation without partially moving
/// its siblings.
priv struct SessionFamilyMove {
  manager : EngineManager
  root : @pathx.Absolute
  members : Array[String]
  guards : Array[(String, SessionRecordGuard)]
  claims : Array[PendingClaim]
  mut active : Bool
}

///|
fn SessionFamilyMove::release(self : SessionFamilyMove) -> Unit {
  guard self.active else { return }
  self.active = false
  for claim in self.claims.rev_iter() {
    claim.release(self.manager)
  }
  for entry in self.guards.rev_iter() {
    let (session_id, record_state) = entry
    self.manager.release_record_move(session_id, record_state)
  }
}

///|
/// Locate and exclusively claim one family in either the live or archived
/// twin. The workspace lifecycle lock covers discovery through slot claims;
/// after it is released those claims make detach/start/compact observe the
/// move until `SessionFamilyMove::release`.
async fn claim_session_family_move(
  manager : EngineManager,
  session : String,
  archived~ : Bool,
) -> SessionFamilyMove {
  manager.workspace_lifecycle_lock.acquire()
  let mut placement_locked = true
  let guards : Array[(String, SessionRecordGuard)] = []
  let claims : Array[PendingClaim] = []
  let mut handed_off = false
  defer {
    if !handed_off {
      for claim in claims.rev_iter() {
        claim.release(manager)
      }
      for entry in guards.rev_iter() {
        let (session_id, record_state) = entry
        manager.release_record_move(session_id, record_state)
      }
    }
    if placement_locked {
      manager.workspace_lifecycle_lock.release()
    }
  }
  let root = if archived {
    archived_record_root(session)
  } else {
    live_record_root(session)
  }
  guard root is Some(root) else {
    if archived {
      raise EngineError("no archived record for this conversation")
    }
    // Name the state the caller can act on. A record already sitting in an
    // archived twin is not "missing" — the stale client just resyncs; and a
    // conversation whose workspace detached needs that workspace re-attached,
    // not a hunt for a lost record.
    if archived_record_root(session) is Some(_) {
      raise EngineError("this conversation is already archived")
    }
    guard resolved_session_root() is Some(_) else {
      raise EngineError(
        "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
      )
    }
    raise EngineError(
      "no durable record for this conversation in the global store or any attached workspace",
    )
  }
  let source = if archived { archived_session_root(root) } else { root }
  let members = session_family_in(source, session)
  for session_id in members {
    let record_state = manager.claim_record_move(session_id)
    guards.push((session_id, record_state))
  }
  let sessions = manager.serving()
  let slots : Array[SessionSlot] = []
  for session_id in members {
    let slot = slot_for(sessions, session_id)
    claims.push(slot.claim(sessions, session_id, ArchivePending))
    slots.push(slot)
  }
  placement_locked = false
  manager.workspace_lifecycle_lock.release()
  for entry in guards {
    let (_, record_state) = entry
    record_state.wait_until_idle()
  }
  // Validate the complete family before closing any idle process. A running
  // child can be reached by opening its transcript and continuing it, even
  // though its ordinary nested sidebar row has no independent archive action.
  for slot in slots {
    if slot.engine is Some(live) {
      match live.phase {
        Running(..) =>
          raise EngineError(
            "this conversation or one of its subagents is still running; stop it first",
          )
        Compacting =>
          raise EngineError(
            "this conversation or one of its subagents is compacting; wait for it to finish",
          )
        Idle => ()
      }
    }
  }
  for slot in slots {
    if slot.engine is Some(live) {
      live.close_and_wait()
    }
  }
  for session_id in members {
    if manager.followers.get(session_id) is Some(follower) {
      stop_follower_instance(manager, follower, writer_exited=true)
    }
  }
  for claim in claims {
    claim.require_current(manager)
  }
  handed_off = true
  { manager, root, members, guards, claims, active: true }
}

///|
/// Move every claimed family record and publish each moved identity only
/// after all renames succeed. Archive removes descendants first and the
/// parent last, so even an external store reader never sees orphaned live
/// children. Restore uses the inverse order. A filesystem failure rolls back
/// the completed renames best-effort before surfacing the error.
async fn move_session_family(
  family : SessionFamilyMove,
  to_archive~ : Bool,
  on_committed : (String) -> Unit,
) -> Unit {
  let live = family.root.join("sessions")
  let archived = archived_session_root(family.root).join("sessions")
  let source = if to_archive { live } else { archived }
  let destination = if to_archive { archived } else { live }
  let order = if to_archive {
    let children = family.members[1:].to_owned()
    children.push(family.members[0])
    children
  } else {
    family.members.copy()
  }
  for session_id in order {
    guard @fsx.is_dir(source.join(session_id).to_path()) else {
      raise EngineError("no durable record for conversation \{session_id}")
    }
    guard !@fsx.exists(destination.join(session_id).to_path()) else {
      raise EngineError(
        "a record for conversation \{session_id} already exists there",
      )
    }
  }
  @fsx.ensure_dir(destination.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not create \{destination}: \{error}")
  }
  @async.protect_from_cancel(() => {
    let moved : Array[String] = []
    try {
      for session_id in order {
        move_session_record(source.join(session_id), destination, session_id)
        moved.push(session_id)
      }
    } catch {
      error => {
        let mut rollback_failed = false
        for session_id in moved.rev_iter() {
          move_session_record(destination.join(session_id), source, session_id) catch {
            _ => rollback_failed = true
          }
        }
        let detail = match error {
          EngineError(detail) => detail
          _ => "\{error}"
        }
        raise EngineError(
          if rollback_failed {
            "\{detail}; some session-family moves could not be rolled back"
          } else {
            detail
          },
        )
      }
    }
    for session_id in order {
      on_committed(session_id)
    }
  })
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
    session_group(manager, None, archived_session_root(root)),
  ]
  for path in registered_workspaces() {
    groups.push(
      session_group(
        manager,
        Some(path),
        archived_session_root(workspace_session_root(path)),
      ),
    )
  }
  { groups, }
}

///|
/// Archive one conversation family and return the updated archived groups.
/// The family is the requested record plus every descendant sub-run record in
/// the same store. Refused while any member has an open turn — its engine
/// would keep writing into a store that just moved. Idle serve processes are
/// forgotten so a later unarchive-and-prompt respawns against the restored
/// records. The conversation's worktree checkout, if it holds one, goes with
/// it, while its registry row stays as durable placement: unarchiving restores
/// the conversation in a blocked `MissingTree` state until the user rebuilds
/// it. Committed work survives on the branch. A dirty checkout refuses unless
/// `force`, which is how the client's discard-confirmation dialog answers;
/// `on_worktree_changed` broadcasts the checkout's disappearance.
pub async fn archive_session(
  manager : EngineManager,
  session : String,
  on_committed : (String) -> Unit,
  force? : Bool = false,
  on_worktree_changed? : (String, Array[WorktreeInfo]) -> Unit,
) -> ArchiveReply {
  let session = session.trim().to_owned()
  guard !session.is_empty() && safe_workspace_id(session) else {
    raise EngineError("invalid session id")
  }
  let refusal = archive_session_commit(
    manager,
    session,
    on_committed,
    force~,
    on_worktree_changed?,
  )
  if refusal is Some(refusal) {
    return NeedsForce(refusal)
  }
  // Listing is intentionally outside the record-move lease. Once the
  // irreversible rename is durably published, a slow/cancelled list reply
  // must not hold the conversation unavailable or suppress session.changed.
  Archived(list_archived_sessions(manager))
}

///|
async fn archive_session_commit(
  manager : EngineManager,
  session : String,
  on_committed : (String) -> Unit,
  force? : Bool = false,
  on_worktree_changed? : (String, Array[WorktreeInfo]) -> Unit,
) -> ArchiveNeedsForceReply? {
  let family = claim_session_family_move(manager, session, archived=false)
  defer family.release()
  // The checkout goes with the conversation. A dirty refusal
  // lands here — after the idle engine already closed, which is harmless
  // (the next prompt respawns) — so nothing irreversible has happened yet;
  // a removal that succeeds while the record move below then fails leaves a
  // live conversation safely blocked on its retained missing placement.
  let refusal = archive_bound_worktree_checkout(
    session,
    force,
    on_committed?=on_worktree_changed,
  )
  if refusal is Some(refusal) {
    return Some(refusal)
  }
  // The rename and notification are the commit. Cancellation is delayed only
  // across this finite section; after it returns normally or raises Cancelled,
  // every client has already learned every family identity that moved.
  move_session_family(family, to_archive=true, on_committed)
  None
}

///|
/// Restore one archived conversation family into its live store and return
/// the updated archived groups. The root record is looked up across every
/// store's `archived` twin — the global root first, then each registered
/// workspace — and descendant records beside it move in the same operation.
pub async fn unarchive_session(
  manager : EngineManager,
  session : String,
  on_committed : (String) -> Unit,
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
  on_committed : (String) -> Unit,
) -> Unit {
  let family = claim_session_family_move(manager, session, archived=true)
  defer family.release()
  move_session_family(family, to_archive=false, on_committed)
}

///|
/// Move a session record directory into `destination_dir/<session>`,
/// creating the destination store level on demand. Same-store moves are a
/// single rename, so a conversation is never half-archived.
async fn move_session_record(
  record : @pathx.Absolute,
  destination_dir : @pathx.Absolute,
  session : String,
) -> Unit {
  guard @fsx.is_dir(record.to_path()) else {
    raise EngineError("no durable record for this conversation")
  }
  let destination = destination_dir.join(session)
  guard !@fsx.exists(destination.to_path()) else {
    raise EngineError("a record for this conversation already exists there")
  }
  @fsx.ensure_dir(destination_dir.to_path()) catch {
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
  root : @pathx.Absolute,
  session : String,
  on_migrated : (String) -> Unit,
) -> Bool {
  let record = root.join("sessions").join(session)
  let is_live = @fsx.is_dir(record.to_path()) catch {
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
    ignore(
      archive_session_commit(manager, "s-stopped", _ => committed.val = true),
    )
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
        archive_session(manager, "  s-commit  ", _ => committed.val = true),
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
async test "archive and restore move a subagent session family together" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-family-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  let live = dir + "/sessions/"
  let archived = dir + "/archived/sessions/"
  let family = ["chat", "chat-sr-1", "chat-sr-1-sr-3", "chat-sr-2"]
  for session_id in family {
    @fsx.ensure_dir(Path(live + session_id))
  }
  // Text that resembles the marker and an unrelated conversation must not be
  // swept into the family.
  @fsx.ensure_dir(Path(live + "chat-sr-x"))
  @fsx.ensure_dir(Path(live + "other"))
  let manager = new_engine_manager("unused")
  manager.pump = Serving(sessions=Map([]))
  let archived_events : Array[String] = []
  assert_true(
    archive_session_commit(manager, "chat", id => archived_events.push(id))
    is None,
  )
  assert_eq(archived_events.length(), family.length())
  assert_eq(archived_events[archived_events.length() - 1], "chat")
  for session_id in family {
    assert_true(archived_events.contains(session_id))
  }
  for session_id in family {
    assert_false(@fsx.is_dir(Path(live + session_id)))
    assert_true(@fsx.is_dir(Path(archived + session_id)))
  }
  assert_true(@fsx.is_dir(Path(live + "chat-sr-x")))
  assert_true(@fsx.is_dir(Path(live + "other")))
  let restored_events : Array[String] = []
  unarchive_session_commit(manager, "chat", id => restored_events.push(id))
  assert_eq(restored_events.length(), family.length())
  assert_eq(restored_events[0], "chat")
  for session_id in family {
    assert_true(restored_events.contains(session_id))
  }
  for session_id in family {
    assert_true(@fsx.is_dir(Path(live + session_id)))
    assert_false(@fsx.is_dir(Path(archived + session_id)))
  }
  assert_true(manager.record_guards.is_empty())
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "a claimed child prevents a partial family archive" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous)
  let dir = @fs.tmpdir(prefix="openseek-archive-family-busy-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir)
  @fsx.ensure_dir(Path(dir + "/sessions/chat"))
  @fsx.ensure_dir(Path(dir + "/sessions/chat-sr-1"))
  let manager = new_engine_manager("unused")
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let child_claim = slot_for(sessions, "chat-sr-1").claim(
    sessions,
    "chat-sr-1",
    StartPending,
  )
  defer child_claim.release(manager)
  let detail = try {
    ignore(archive_session_commit(manager, "chat", _ => ()))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("already starting"))
  assert_true(@fsx.is_dir(Path(dir + "/sessions/chat")))
  assert_true(@fsx.is_dir(Path(dir + "/sessions/chat-sr-1")))
  assert_false(@fsx.exists(Path(dir + "/archived/sessions")))
  assert_true(manager.record_guards.is_empty())
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
