///|
/// Later-message edits use the ordinary fork. A first-message edit reserves
/// an empty conversation in the same checkout; its first prompt creates the
/// record. The source is never removed by preparation.
pub async fn prepare_session_edit(
  manager : EngineManager,
  payload : @protocol.SessionEditPreparePayload,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
) -> @protocol.SessionForkReply {
  if payload.through is Some(through) {
    return fork_session(
      manager,
      {
        session: payload.session,
        workspace: payload.workspace,
        through,
        model: payload.model,
        source_title: payload.source_title,
      },
      require_idle=true,
      on_created~,
      on_worktree_changed~,
    )
  }
  guard @session_store.safe_session_id(payload.session) &&
    @wire.split_child_session_id(payload.session) is None else {
    raise EngineError("invalid source conversation")
  }
  guard !payload.source_title.is_blank() else {
    raise EngineError("session edit source title is required")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  manager.require_idle_edit_source(payload.session)
  let lease = manager.begin_record_read(payload.session)
  defer manager.end_record_read(payload.session, lease)
  let selected = @session_store.ArchivedStore::for_workspace(payload.workspace)
  ignore(@session_record.read_document(selected.root, payload.session))
  let session = "desktop-" + @uuid.mint()
  let store = @store.SessionStore(selected.root.to_string())
  let id : @agent_session.SessionId = SessionId(session)
  {
    errdefer @async.protect_from_cancel(() => {
      if store.exists(id) {
        on_created(session)
      }
    })
    @worktree.add_session_to_worktree(
      selected.workspace,
      session~,
      worktree_of=payload.session,
      _ => store.reserve(id, payload.source_title),
      record_exists=() => store.exists(id),
      worktrees => on_worktree_changed(payload.workspace, worktrees),
    )
  }
  on_created(session)
  { session, title: payload.source_title, }
}

///|
/// The destination read lease prevents a concurrent delete from invalidating
/// the receipt within this host. delete_session rechecks both records under
/// the shared deletion lock after fencing source writers and its follower.
pub async fn commit_session_edit(
  manager : EngineManager,
  payload : @protocol.SessionEditCommitPayload,
  on_committed : (String, String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
) -> SessionDeleteReply {
  guard @session_store.safe_session_id(payload.session) &&
    @session_store.safe_session_id(payload.replacement) &&
    payload.session != payload.replacement &&
    !payload.submission_id.is_blank() &&
    payload.source_sequence > 0 &&
    @wire.split_child_session_id(payload.session) is None &&
    @wire.split_child_session_id(payload.replacement) is None else {
    raise EngineError("invalid edited conversation replacement")
  }
  let lease = manager.begin_record_read(payload.replacement)
  defer manager.end_record_read(payload.replacement, lease)
  let selected = @session_store.ArchivedStore::for_workspace(payload.workspace)
  require_edited_receipt(selected.root, payload)
  // Lost delete replies can be retried without creating another fork.
  ignore(@session_record.read_document(selected.root, payload.session)) catch {
    @session_record.Absent(_) => {
      guard !@fsx.is_dir(
          selected.root.join("sessions").join(payload.session).to_path(),
        ) &&
        !@fsx.is_dir(
          @session_store.archived_root(selected.root)
          .join("sessions")
          .join(payload.session)
          .to_path(),
        ) else {
        raise EngineError(
          "the original record moved or is unreadable; it was kept",
        )
      }
      on_committed(payload.session, payload.workspace)
      return Deleted
    }
    error => raise error
  }
  delete_session(
    manager,
    payload.session,
    payload.workspace,
    on_committed,
    edit_replacement=payload,
    on_worktree_changed~,
  )
}

///|
async fn require_edited_receipt(
  root : @pathx.Absolute,
  payload : @protocol.SessionEditCommitPayload,
) -> Unit {
  let destination = @session_record.read_document(root, payload.replacement)
  guard destination.events
    .unwrap_or([])
    .any(event => {
      event.item is User(message) &&
      message.submission_id == Some(payload.submission_id)
    }) else {
    raise EngineError(
      "the edited message has not been saved; the original conversation was kept",
    )
  }
}

///|
/// Called while holding the workspace lifecycle lock, which excludes new
/// start/compact claims until preparation has finished. Include child slots
/// even before their first record is written, without stopping any engine.
fn EngineManager::require_idle_edit_source(
  self : EngineManager,
  source : String,
) -> Unit raise EngineError {
  fn belongs(session : String) -> Bool {
    let mut current = session
    while current != source {
      guard @wire.split_child_session_id(current) is Some((parent, _)) else {
        return false
      }
      current = parent
    }
    true
  }
  for session, slot in self.serving() {
    guard belongs(session) else { continue }
    guard slot.pending is None &&
      (
        slot.engine is None ||
        (
          slot.engine is Some(engine) &&
          engine.phase is Idle(..) &&
          engine.queued_runs.is_empty()
        )
      ) else {
      raise EngineError(
        "this conversation or one of its subagents is busy; wait before editing",
      )
    }
  }
  for session, state in self.record_guards {
    if belongs(session) && (state.active_ops > 0 || state.moving) {
      raise EngineError(
        "another operation is preparing this conversation; wait before editing",
      )
    }
  }
}
