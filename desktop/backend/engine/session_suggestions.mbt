///|
/// A reservation is saved before a checkout or engine is created. Retrying
/// after a lost response therefore uses the same target and first prompt.
/// The target's durable User submission, not this sidecar, confirms success.
priv struct StoredSessionSuggestion {
  request : @protocol.SessionCreateFromMessagePayload
  target : String
  system_prompt : String?
  started : Bool
}

///|
impl FromJson for StoredSessionSuggestion with fn from_json(json, path) {
  guard json
    is {
      "request": request,
      "target": String(target),
      "system_prompt": system_prompt,
      "started": started,
      ..
    } else {
    raise JsonDecodeError((path, "expected a stored session suggestion"))
  }
  {
    request: @json.from_json(request, path=path.add_key("request")),
    target,
    system_prompt: @json.from_json(
      system_prompt,
      path=path.add_key("system_prompt"),
    ),
    started: @json.from_json(started, path=path.add_key("started")),
  }
}

///|
impl ToJson for StoredSessionSuggestion with fn to_json(self) {
  {
    "request": self.request,
    "target": self.target,
    "system_prompt": self.system_prompt,
    "started": self.started,
  }
}

///|
/// Orders creation attempts in this process; the operation file lock also
/// orders hosts attached to the same workspace. Held only through admission
/// and the first durable prompt, never through the new task's completion.
let session_suggestions_lock : @async.Mutex = Mutex()

///|
/// Source-side metadata sections follow the lifecycle -> archive -> sidecar
/// lock order used by record moves. Their body only reads/writes metadata;
/// worktree creation and run admission happen after all three are released.
async fn[T] with_session_suggestions(
  manager : EngineManager,
  payload : @protocol.SessionSuggestionsPayload,
  body : async (
    @session_store.ArchivedStore,
    @pathx.Path,
    @protocol.SessionDocument,
  ) -> T,
  allow_archived~ : Bool = false,
) -> T {
  guard @session_store.safe_session_id(payload.session) &&
    @wire.split_child_session_id(payload.session) is None else {
    raise EngineError("invalid source conversation")
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  let lease = manager.begin_record_read(payload.session)
  defer manager.end_record_read(payload.session, lease)
  let selected = @session_store.ArchivedStore::for_workspace(payload.workspace)
  let shared = lock_archived_store(selected.root)
  defer shared.release()
  let (record_root, document) = (
    selected.root,
    @session_record.read_document(selected.root, payload.session),
  ) catch {
    @session_record.Absent(_) if allow_archived => {
      let archived = @session_store.archived_root(selected.root)
      (archived, @session_record.read_document(archived, payload.session))
    }
    error => raise error
  }
  let path = record_root
    .join("sessions")
    .join(payload.session)
    .join("suggestions.json")
    .to_path()
  let sidecar = @fsx.FileLock::acquire(path)
  defer sidecar.release()
  body(selected, path, document)
}

///|
async fn read_session_suggestions(
  path : @pathx.Path,
) -> Array[StoredSessionSuggestion] {
  if @fsx.read_text_if_exists(path) is Some(text) {
    @json.from_json(@json.parse(text))
  } else {
    []
  }
}

///|
/// Some(false) is a live created task, Some(true) an archived task. Missing
/// or not-yet-started reservations remain absent from the visible snapshot.
/// Every other read failure propagates: it cannot establish absence.
async fn session_suggestion_target(
  root : @pathx.Absolute,
  target : String,
  confirmed : Bool,
) -> Bool? {
  for archived in [false, true] {
    let store = if archived { @session_store.archived_root(root) } else { root }
    let document = @session_record.read_document(store, target) catch {
      @session_record.Absent(_) => continue
      error => raise error
    }
    if confirmed ||
      document.events.map_or(false, events => {
        events.any(event => {
          event.item is User(user) && user.submission_id == Some(target)
        })
      }) {
      return Some(archived)
    }
  }
  None
}

///|
pub async fn session_suggestions(
  manager : EngineManager,
  payload : @protocol.SessionSuggestionsPayload,
) -> @protocol.SessionSuggestionsReply {
  with_session_suggestions(manager, payload, (selected, path, _) => {
    let entries = read_session_suggestions(path)
    let suggestions : Array[@protocol.SessionSuggestion] = []
    let mut recovered = false
    for index, entry in entries {
      if session_suggestion_target(selected.root, entry.target, entry.started)
        is Some(archived) {
        suggestions.push({
          sequence: entry.request.sequence,
          block: entry.request.block,
          session: entry.target,
          archived,
        })
        // A lost create response can leave only the reservation. Persist the
        // recovered receipt before exposing it as a confirmed association.
        if !entry.started {
          entries[index] = { ..entry, started: true, }
          recovered = true
        }
      }
    }
    if recovered {
      @fsx.write_text_atomic(path, Json(entries).stringify())
    }
    { suggestions, }
  })
}

///|
/// Create only in response to the user's card click. The stored association
/// survives archive and restore with its source, while a successful target
/// is recovered from its first durable prompt after a disconnect or restart.
pub async fn create_session_from_message(
  manager : EngineManager,
  payload : @protocol.SessionCreateFromMessagePayload,
  start~ : async (@protocol.StartPayload) -> Unit,
  on_created~ : (String) -> Unit,
  on_worktree_changed~ : (String, Array[@protocol.WorktreeInfo]) -> Unit,
) -> @protocol.SessionCreateFromMessageReply {
  guard payload.sequence > 0 &&
    payload.block >= 0 &&
    !payload.prompt.is_blank() &&
    !payload.model.is_blank() else {
    raise EngineError(
      "a session suggestion needs a saved message, prompt and model",
    )
  }
  session_suggestions_lock.acquire()
  defer session_suggestions_lock.release()
  let selected = @session_store.ArchivedStore::for_workspace(payload.workspace)
  // This operation lock is outside every movable session directory. It is
  // never acquired by worktree, engine or archive operations, so it may span
  // their normal lifecycle locks without reversing their lock order.
  let operation = @fsx.FileLock::acquire(
    selected.root.join("session-suggestions").to_path(),
  )
  defer operation.release()
  let source : @protocol.SessionSuggestionsPayload = {
    session: payload.session,
    workspace: selected.workspace_token,
  }
  let (entry, ready) : (StoredSessionSuggestion, Bool?) = with_session_suggestions(
    manager,
    source,
    (selected, path, document) => {
      guard document.events.map_or(false, events => {
        events.any(event => {
          event.sequence == payload.sequence &&
          (event.item is Assistant(_) || event.item is Terminal(Finished(_)))
        })
      }) else {
        raise EngineError("the source assistant message is no longer present")
      }
      let entries = read_session_suggestions(path)
      let index = entries.search_by(entry => {
        entry.request.sequence == payload.sequence &&
        entry.request.block == payload.block
      })
      let previous = index.map(index => entries[index])
      if previous is Some(entry) {
        guard entry.request.prompt == payload.prompt else {
          raise EngineError(
            "this suggestion was already used with a different prompt",
          )
        }
        if session_suggestion_target(selected.root, entry.target, entry.started)
          is Some(archived) {
          if !entry.started && index is Some(index) {
            entries[index] = { ..entry, started: true, }
            @fsx.write_text_atomic(path, Json(entries).stringify())
          }
          return (entry, Some(archived))
        }
      }
      let entry = if previous is Some(entry) && !entry.started {
        // A definitely failed start can leave engine metadata after its new
        // checkout was removed. Worktree creation correctly refuses to bind
        // that existing record. Retry with a fresh id while keeping the
        // captured prompt/settings; no successful task exists to duplicate.
        if !suggestion_run_active(manager, entry.target) &&
          @worktree.tree_base(selected.workspace, entry.target) is None &&
          @fsx.is_dir(
            selected.root.join("sessions").join(entry.target).to_path(),
          ) {
          { ..entry, target: "desktop-" + @uuid.mint(), }
        } else {
          entry
        }
      } else {
        let store = @store.SessionStore(selected.root.to_string())
        {
          request: payload,
          target: "desktop-" + @uuid.mint(),
          system_prompt: saved_session_prompt(store, SessionId(payload.session)),
          started: false,
        }
      }
      if index is Some(index) {
        entries[index] = entry
      } else {
        entries.push(entry)
      }
      @fsx.write_text_atomic(path, Json(entries).stringify())
      (entry, None)
    },
  )
  if ready is Some(archived) {
    return { session: entry.target, archived, }
  }
  let host = manager.worktree_host()
  // A retry can adopt a checkout whose engine is already accepting its first
  // prompt. An error from this retry must never remove that prior checkout.
  let adopted = @worktree.tree_base(selected.workspace, entry.target) is Some(_)
  let created = @worktree.create(
    host,
    selected.workspace,
    @worktree.WorktreeOwner::openseek(entry.target),
    worktrees => on_worktree_changed(selected.workspace_token, worktrees),
  )
  // Cancellation leaves the reservation and checkout for recovery. Ordinary
  // failures remove only a checkout this attempt created, after confirming
  // that no first prompt was saved and no run still owns the target.
  let failure : Error? = try {
    start({
      system_prompt: entry.system_prompt,
      images: [],
      task: entry.request.prompt,
      submission_id: Some(entry.target),
      model: Some(entry.request.model),
      thinking: Some(entry.request.thinking),
      approval: Some(entry.request.approval),
      max_steps: None,
      session: entry.target,
      workspace: Some(selected.workspace_token),
    })
    None
  } catch {
    error => Some(error)
  }
  if failure is Some(error) {
    if !adopted && !suggestion_run_active(manager, entry.target) {
      let receipt = session_suggestion_target(
        selected.root,
        entry.target,
        false,
      )
      if receipt is None {
        ignore(
          @worktree.remove(host, selected.workspace, created.name, false, worktrees => {
            on_worktree_changed(selected.workspace_token, worktrees)
          }),
        ) catch {
          cleanup =>
            @xlog.warn() <?
              {
                "event": "desktop_session_suggestion_cleanup_failed",
                "session": entry.target,
                "worktree": created.name,
                "error": cleanup.to_string(),
                "start_error": error.to_string(),
              }
        }
      }
    }
    raise error
  }
  @async.protect_from_cancel(() => {
    with_session_suggestions(
      manager,
      source,
      (_, path, _) => {
        let entries = read_session_suggestions(path)
        guard entries.search_by(candidate => candidate.target == entry.target)
          is Some(index) else {
          raise EngineError(
            "the source suggestion changed while its conversation was starting",
          )
        }
        entries[index] = { ..entry, started: true, }
        @fsx.write_text_atomic(path, Json(entries).stringify())
      },
      allow_archived=true,
    ) catch {
      // The target already owns a durable prompt. A source deleted or moved
      // meanwhile cannot undo that task. A surviving reservation is recovered
      // from the receipt by the next lookup; return the created task's identity.
      error =>
        @xlog.warn() <?
          {
            "event": "desktop_session_suggestion_confirmation_save_failed",
            "source": payload.session,
            "session": entry.target,
            "error": error.to_string(),
          }
    }
    on_created(entry.target)
  })
  { session: entry.target, archived: false, }
}

///|
fn suggestion_run_active(manager : EngineManager, session : String) -> Bool {
  manager.pump is Serving(sessions~) &&
  sessions.get(session) is Some(slot) &&
  (
    slot.pending is Some(_) ||
    (slot.engine is Some(engine) && !(engine.phase is Idle(..)))
  )
}
