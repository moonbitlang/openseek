///|
priv struct EditSource {
  session : String
  workspace : String
  through : Int32?
  model : String
  source_title : String
}

///|
struct EditReplacement {
  session : String
  workspace : String
  replacement : String
  submission_id : String
  source_sequence : Int32
}

///|
/// A single client operation. Errors propagate normally; there is no
/// automatic resubmission or cleanup retry.
pub async fn edit_session(
  manager : EngineManager,
  payload : @protocol.SessionEditPayload,
  start~ : async (@protocol.StartPayload) -> Unit,
  on_created~ : (String) -> Unit,
  on_deleted~ : (String, String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
) -> @protocol.SessionForkReply {
  guard payload.source_sequence > 0 &&
    (!payload.task.is_blank() || !payload.images.is_empty()) else {
    raise EngineError("invalid edited message")
  }
  let reply = prepare_session_edit(
    manager,
    {
      session: payload.session,
      workspace: payload.workspace,
      through: payload.through,
      model: payload.model,
      source_title: payload.source_title,
    },
    on_created~,
    on_worktree_changed~,
  )
  let submission_id = @uuid.mint()
  start({
    moonbit_guide: None,
    session: reply.session,
    workspace: Some(payload.workspace),
    task: payload.task,
    images: payload.images,
    model: Some(payload.model),
    thinking: payload.thinking,
    approval: payload.approval,
    max_steps: payload.max_steps,
    submission_id: Some(submission_id),
  })
  let replacement : EditReplacement = {
    session: payload.session,
    workspace: payload.workspace,
    replacement: reply.session,
    submission_id,
    source_sequence: payload.source_sequence,
  }
  let selected = @session_store.ArchivedStore::for_workspace(payload.workspace)
  // agent.start acknowledges queueing, not persistence. Wait only for this
  // prompt's durable receipt before invoking the existing delete lifecycle.
  @async.with_timeout(10000, () => {
    while !edited_message_saved(selected.root, replacement) {
      @async.sleep(20)
    }
  })
  match
    commit_session_edit(manager, replacement, on_deleted, on_worktree_changed~) {
    Deleted => reply
    Unconfirmed(_) =>
      raise EngineError(
        "the original chat was kept because deleting it would remove a worktree",
      )
  }
}

///|
async fn edited_message_saved(
  root : @pathx.Absolute,
  payload : EditReplacement,
) -> Bool {
  let document = @session_record.read_document(root, payload.replacement) catch {
    @session_record.Absent(_) => return false
    error => raise error
  }
  document.events
  .unwrap_or([])
  .any(event => {
    event.item is User(message) &&
    message.submission_id == Some(payload.submission_id)
  })
}

///|
/// Later-message edits fork into the source's checkout, which the edit takes
/// over once the source is deleted. A first-message edit creates
/// an empty conversation in the same checkout; its first prompt creates the
/// record. The source is never removed by preparation.
async fn prepare_session_edit(
  manager : EngineManager,
  payload : EditSource,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[WorktreeInfo]) -> Unit,
) -> @protocol.SessionForkReply {
  if payload.through is Some(through) {
    return fork_session_in(
      manager,
      {
        session: payload.session,
        workspace: payload.workspace,
        through,
        model: payload.model,
        source_title: payload.source_title,
        side_chat: None,
      },
      SharedWorktree,
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
      _ => {
        // Keep an unsent edit discoverable using the existing directory/title
        // layout. The first prompt creates its JSONL through the normal path.
        let directory = selected.root.join("sessions").join(session)
        @fsx.ensure_dir(directory.to_path())
        @fsx.write_text_atomic(
          directory.join("session-title").to_path(),
          payload.source_title.trim().to_owned(),
        )
      },
      record_exists=() => store.exists(id),
      worktrees => on_worktree_changed(payload.workspace, worktrees),
    )
  }
  on_created(session)
  { session, title: payload.source_title, }
}

///|
/// Reuse the existing move/delete lifecycle, including its writer admission
/// and follower drain, after verifying the submitted message.
async fn commit_session_edit(
  manager : EngineManager,
  payload : EditReplacement,
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
  payload : EditReplacement,
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
