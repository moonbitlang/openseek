// Codex app-server state for the dedicated Codex page. Codex keeps its own
// durable thread/turn/item model because `thread/read(includeTurns=true)` is
// the authoritative reconnect snapshot. At the view boundary those items are
// adapted to `frontend/transcript.TranscriptItem`, so Codex and OpenSeek use
// one transcript renderer without pretending their persistence models match.

///|
priv enum CodexConnection {
  CodexStarting
  CodexReady
  CodexUnavailable(String)
} derive(Eq)

///|
priv enum CodexAccount {
  CodexAccountUnknown
  CodexSignedOut(Bool)
  CodexSignedIn(kind~ : String, plan~ : String?)
} derive(Eq)

///|
/// Reading persisted history does not require a writer. A selected task only
/// asks app-server for its writer when the user first tries to send.
priv enum CodexWriteAccess {
  CodexNeedsResume
  CodexWritable
  CodexActiveElsewhere
} derive(Eq)

///|
priv struct CodexModelOption {
  id : String
  label : String
  is_default : Bool
} derive(Eq)

///|
priv struct CodexThreadRow {
  id : String
  title : String
  cwd : String?
  project_root : String?
  worktree : CodexWorktree?
} derive(Eq)

///|
/// A worktree explicitly owned by this Codex thread in SeekMoon's registry.
/// The annotation comes from the native host; cwd shape alone never claims an
/// external Codex App or manually-created Git worktree.
priv struct CodexWorktree {
  name : String
  path : String
  present : Bool
} derive(Eq)

///|
/// A dirty Codex-owned checkout waits here while the shared composer dialog
/// asks whether archiving may discard its local-only changes.
priv struct CodexArchiveConfirm {
  thread_id : String
  refusal : @protocol.ArchiveNeedsForceReply
} derive(Eq)

///|
priv struct CodexItem {
  id : String
  kind : String
  value : Json
  // Deltas are presentation-only. `item/completed` replaces `value` and
  // clears this field because the completed item is authoritative.
  streamed : String
} derive(Eq)

///|
priv struct CodexTurn {
  id : String
  status : String
  // Legacy interrupted turns can retain `startedAt` without ever receiving a
  // `completedAt`. Only app-server's explicit `inProgress` status proves that
  // this process has a live turn; writer conflicts are tracked separately.
  started_at : Int?
  completed_at : Int?
  items : Array[CodexItem]
  error : String?
} derive(Eq)

///|
priv struct CodexThread {
  id : String
  title : String
  cwd : String?
  project_root : String?
  worktree : CodexWorktree?
  // App-server captures this branch when the thread is created. It gives the
  // composer an immediate label while the host verifies the current checkout
  // and asks GitHub for its pull request.
  branch : String?
  turns : Array[CodexTurn]
} derive(Eq)

///|
/// A Codex task before its first prompt. The id is client-local: it isolates
/// Files and Terminal exactly like OpenSeek's fresh session id, but it is never
/// sent to app-server as a thread id. `cwd` is the project chosen by the add
/// button; the host confirms `project_root` before filesystem panels use it.
priv struct CodexDraftTask {
  id : String
  cwd : String
  project_root : String?
} derive(Eq)

///|
/// The Codex page selects either a local draft or an app-server thread, never
/// both. Keeping that distinction in one enum prevents an empty draft from
/// accidentally entering resume, archive, polling, or turn APIs.
priv enum CodexSelection {
  CodexNoTask
  CodexDraftTask(CodexDraftTask)
  CodexStoredTask(CodexThread)
} derive(Eq)

///|
/// The current checkout and pull request shown beside Codex's model selector.
/// `thread_id` fences a slow GitHub reply after the user selects another task.
priv struct CodexGitStatus {
  thread_id : String
  branch : String?
  pull_request : @protocol.GitPullRequest?
  compare_url : String?
} derive(Eq)

///|
priv struct CodexQuestion {
  id : String
  header : String
  question : String
  options : Array[(String, String)]
}

///|
priv struct CodexPendingRequest {
  request_id : Json
  // Every supported app-server reverse request names its owning thread.
  // Keeping that identity here prevents one task from rendering or answering
  // another task's approval after the sidebar selection changes.
  thread_id : String
  method_ : String
  params : Json
  // `item/tool/requestUserInput` keeps one answer per question. MCP form
  // elicitation uses the reserved `__content` entry as its JSON editor.
  answers : Map[String, String]
} derive(Eq)

///|
/// The exact task/input frontier captured before a start or steer request.
/// If the transport loses the reply after sending, a fresh thread snapshot
/// can distinguish a newly stored user item from everything already visible
/// before the request. Until that read completes, Send remains disabled.
priv struct CodexPendingTurnDelivery {
  thread_id : String
  input_signature : String
  known_user_items : Array[String]
} derive(Eq)

///|
priv enum CodexReplyKind {
  CodexStatusReply
  CodexRequestsReply
  CodexAccountReply
  CodexModelsReply
  CodexThreadsReply(Bool, Int)
  CodexThreadReply(String)
  CodexWriterReply(String)
  CodexDraftOpenReply(String)
  CodexDraftThreadReply(String)
  CodexTurnReply(String)
  CodexTurnReconcileReply(String)
  CodexWorktreeTurnReply(String, CodexWorktree)
  CodexWorktreeRepairReply(String, CodexWorktree)
  CodexLoginReply
  CodexArchiveReply(String)
  CodexUnarchiveReply(String)
  CodexCompactReply(String)
  CodexReviewReply(String)
  CodexInterruptReply
  CodexCancelLoginReply(String)
  CodexLogoutReply
  CodexApprovalReply
}

///|
/// The foreground operation that currently owns the shared composer lock.
/// Reply kinds with different payload shapes normalize to the same owner, so
/// worktree creation and turn reconciliation still settle the turn that
/// launched them without allowing unrelated replies to release the lock.
priv enum CodexForeground {
  CodexDraftOpenForeground(String)
  CodexThreadForeground(String)
  CodexWriterForeground(String)
  CodexDraftStartForeground(String)
  CodexTurnForeground(String)
  CodexWorktreeRepairForeground(String)
  CodexLoginForeground
  CodexCancelLoginForeground(String)
  CodexLogoutForeground
  CodexArchiveForeground(String)
  CodexUnarchiveForeground(String)
  CodexCompactForeground(String)
  CodexReviewForeground(String)
} derive(Eq)

///|
/// All Codex-local state transitions. The root frontend wraps this message as
/// one variant of its own Msg, but it never inspects app-server replies or
/// mutates Codex's account, thread, turn, item, or approval state directly.
enum Msg {
  Refresh
  // All editable input events cross the shared composer controller. Codex
  // interprets only the resulting completion choice or submission through
  // app-server after the common transition has settled.
  Composer(@composer.ControllerMsg)
  SymbolSearchDue(owner~ : CodexSearchOwner, generation~ : Int)
  FilesIndexed(
    owner~ : CodexFileOwner,
    files~ : Array[@pathx.Relative],
    truncated~ : Bool
  )
  FilesFailed(owner~ : CodexFileOwner)
  SkillsLoaded(cwd~ : String, skills~ : Array[CodexSkill])
  SkillsFailed(cwd~ : String)
  SymbolsLoaded(
    owner~ : CodexSearchOwner,
    generation~ : Int,
    items~ : Array[@symbols.Symbol]
  )
  SymbolsFailed(owner~ : CodexSearchOwner, generation~ : Int)
  ModelChanged(String)
  GitLoaded(thread_id~ : String, reply~ : @protocol.GitPullRequestReply)
  ToggleGitDetails
  CloseGitDetails
  ToggleWorktreeMode
  StartDraft(id~ : String, cwd~ : String)
  OpenThread(String)
  ArchiveThread(String)
  UnarchiveThread(String)
  RepairWorktree
  ConfirmArchiveDiscard
  CancelArchiveDiscard
  WriterAcquired(String)
  WriterConflict(String)
  TurnDeliveryUnknown(
    thread_id~ : String,
    message~ : String,
    worktree~ : CodexWorktree?
  )
  Stop
  Login
  CancelLogin
  Logout
  RequestAnswer(request_key~ : String, question_id~ : String, answer~ : String)
  Respond(request_key~ : String, decision~ : String)
  Reply(kind~ : CodexReplyKind, value~ : Json)
  Failed(kind~ : CodexReplyKind, message~ : String)
  StatusChanged(Json)
  Notification(method_~ : String, params~ : Json, generation~ : Int)
  ServerRequest(
    request_id~ : Json,
    method_~ : String,
    params~ : Json,
    generation~ : Int
  )
}

///|
/// Shell entrypoint for refreshing the focused Codex catalog.
pub fn Msg::refresh() -> Msg {
  Refresh
}

///|
/// Shell entrypoint for opening a local draft in an exact project directory.
/// No app-server thread exists until the draft sends its first prompt.
pub fn Msg::start_draft(id : String, cwd : String) -> Msg {
  StartDraft(id~, cwd~)
}

///|
/// Shell entrypoint for selecting a Codex sidebar row.
pub fn Msg::open_thread(thread_id : String) -> Msg {
  OpenThread(thread_id)
}

///|
/// Shell entrypoint for archiving a Codex sidebar row.
pub fn Msg::archive_thread(thread_id : String) -> Msg {
  ArchiveThread(thread_id)
}

///|
/// Shell entrypoint for restoring a Codex sidebar row from archived history.
pub fn Msg::unarchive_thread(thread_id : String) -> Msg {
  UnarchiveThread(thread_id)
}

///|
/// Decode-free boundary for the host's Codex readiness notification.
pub fn Msg::status_changed(value : Json) -> Msg {
  StatusChanged(value)
}

///|
/// Decode-free boundary for an app-server notification forwarded by the host.
pub fn Msg::notification(
  method_ : String,
  params : Json,
  generation : Int,
) -> Msg {
  Notification(method_~, params~, generation~)
}

///|
/// Decode-free boundary for an app-server request forwarded by the host.
pub fn Msg::server_request(
  request_id : Json,
  method_ : String,
  params : Json,
  generation : Int,
) -> Msg {
  ServerRequest(request_id~, method_~, params~, generation~)
}

///|
struct State {
  connection : CodexConnection
  account : CodexAccount
  login_id : String?
  auth_url : String?
  models : Array[CodexModelOption]
  selected_model : String
  threads : Array[CodexThreadRow]
  archived_threads : Array[CodexThreadRow]
  // Live and archived pagination are independent requests. Each refresh
  // advances both generations so a slower older walk cannot overwrite a
  // newer catalog after reconnect, archive, or device focus changes.
  live_catalog_generation : Int
  archived_catalog_generation : Int
  selection : CodexSelection
  // The last sidebar selection awaiting a history snapshot. A reply carries
  // the same id, so an older request can never replace a newer selection.
  requested_thread : String?
  git_status : CodexGitStatus?
  git_details_open : Bool
  write_access : CodexWriteAccess
  draft : String
  // File chips remain native app-server `UserInput::Mention` items. Symbols
  // and editor annotations use the shared mention envelope inside text inputs
  // because app-server has no structured symbol/annotation input of its own.
  mentions : Array[CodexMention]
  // OpenSeek and Codex keep separate values but use one completion state type
  // for menu selection, dismissal, and asynchronous request generations.
  completion : @composer.CompletionState[
    CodexCompletionKind,
    CodexCompletionItem,
  ]
  // `@` and `$` are cwd-scoped catalogs loaded when a thread becomes active.
  // Files use the same host index and fuzzy ranking implementation as Ctrl+P;
  // skills remain the Codex app-server catalog, not OpenSeek's registry.
  file_index : CodexFileIndex
  skills : CodexSkillCatalog
  symbol_search : CodexSymbolSearchCache
  placement : @composer.WorktreeChoice
  archive_confirm : CodexArchiveConfirm?
  pending_requests : Array[CodexPendingRequest]
  // Actor-owned request generations order the attach snapshot and live
  // reverse-request events. Older snapshots/events are ignored instead of
  // erasing a request that arrived while the snapshot was in flight.
  request_generation : Int
  // Present only after a turn request went out but its reply was lost. The
  // preserved composer input is not retryable until thread/read compares it
  // with the request-time user-item frontier.
  pending_turn_delivery : CodexPendingTurnDelivery?
  loading : Bool
  foreground : CodexForeground?
  notice : String
} derive(Eq)

///|
pub fn State::State(loading? : Bool = false) -> State {
  {
    connection: CodexStarting,
    account: CodexAccountUnknown,
    login_id: None,
    auth_url: None,
    models: [],
    selected_model: "",
    threads: [],
    archived_threads: [],
    live_catalog_generation: 0,
    archived_catalog_generation: 0,
    selection: CodexNoTask,
    requested_thread: None,
    git_status: None,
    git_details_open: false,
    write_access: CodexNeedsResume,
    draft: "",
    mentions: [],
    completion: @composer.CompletionState(),
    file_index: CodexFilesEmpty,
    skills: CodexSkillsEmpty,
    symbol_search: CodexSymbolSearchCache::empty(),
    placement: @composer.LocalCheckout,
    archive_confirm: None,
    pending_requests: [],
    request_generation: 0,
    pending_turn_delivery: None,
    loading,
    foreground: None,
    notice: "",
  }
}

///|
/// Build state from the authoritative `thread/read(includeTurns=true)` reply.
/// The shell's black-box workspace tests use the same boundary as production
/// instead of constructing Codex's private thread representation.
pub fn State::from_thread_snapshot(value : Json) -> State {
  State().with_thread_reply(value)
}

///|
/// Whether the shared sidebar's Codex add action may start a task now. The
/// root shell owns the common section heading, but readiness and in-flight
/// request state remain Codex-owned policy.
pub fn State::can_start_thread(self : State) -> Bool {
  self.connection is CodexReady && !self.loading
}

///|
/// The selected app-server task, excluding a local draft that has not sent its
/// first prompt. Mutation APIs use this method so a draft id cannot be mistaken
/// for an app-server thread id.
fn State::active_thread(self : State) -> CodexThread? {
  match self.selection {
    CodexStoredTask(thread) => Some(thread)
    CodexNoTask | CodexDraftTask(_) => None
  }
}

///|
/// A sidebar selection owns its matching history reply. Reconnect refreshes
/// have no pending selection, so they may refresh only the thread already on
/// screen; once a newer row is clicked, that newer id is the sole owner.
fn State::accepts_thread_reply(self : State, requested_thread : String) -> Bool {
  if self.requested_thread is Some(latest) {
    latest == requested_thread
  } else if self.active_thread() is Some(active) {
    active.id == requested_thread
  } else {
    false
  }
}

///|
/// Every request that can mutate the selected task carries the selection that
/// launched it. This single gate runs before update settles loading or input,
/// so an overtaken draft/turn reply is inert rather than partly applied.
fn State::accepts_reply(self : State, kind : CodexReplyKind) -> Bool {
  match kind {
    CodexThreadsReply(false, generation) =>
      generation == self.live_catalog_generation
    CodexThreadsReply(true, generation) =>
      generation == self.archived_catalog_generation
    CodexThreadReply(thread_id) => self.accepts_thread_reply(thread_id)
    CodexWriterReply(thread_id) =>
      self
      .active_thread()
      .map(thread => thread.id == thread_id)
      .unwrap_or(false)
    CodexDraftThreadReply(draft_id) =>
      self.active_draft().map(draft => draft.id == draft_id).unwrap_or(false)
    CodexTurnReply(thread_id)
    | CodexTurnReconcileReply(thread_id)
    | CodexWorktreeTurnReply(thread_id, _) =>
      self
      .active_thread()
      .map(thread => thread.id == thread_id)
      .unwrap_or(false)
    CodexWorktreeRepairReply(thread_id, _) =>
      self
      .active_thread()
      .map(thread => thread.id == thread_id)
      .unwrap_or(false)
    _ => true
  }
}

///|
/// Map a concrete reply to the foreground operation it can settle. Approval,
/// interrupt, catalog, account, and model replies intentionally own no
/// foreground lock.
fn CodexReplyKind::foreground(self : CodexReplyKind) -> CodexForeground? {
  match self {
    CodexDraftOpenReply(id) => Some(CodexDraftOpenForeground(id))
    CodexThreadReply(id) => Some(CodexThreadForeground(id))
    CodexWriterReply(id) => Some(CodexWriterForeground(id))
    CodexDraftThreadReply(id) => Some(CodexDraftStartForeground(id))
    CodexTurnReply(id)
    | CodexTurnReconcileReply(id)
    | CodexWorktreeTurnReply(id, _) => Some(CodexTurnForeground(id))
    CodexWorktreeRepairReply(id, _) => Some(CodexWorktreeRepairForeground(id))
    CodexLoginReply => Some(CodexLoginForeground)
    CodexCancelLoginReply(id) => Some(CodexCancelLoginForeground(id))
    CodexLogoutReply => Some(CodexLogoutForeground)
    CodexArchiveReply(id) => Some(CodexArchiveForeground(id))
    CodexUnarchiveReply(id) => Some(CodexUnarchiveForeground(id))
    CodexCompactReply(original) => Some(CodexCompactForeground(original))
    CodexReviewReply(original) => Some(CodexReviewForeground(original))
    CodexStatusReply
    | CodexRequestsReply
    | CodexAccountReply
    | CodexModelsReply
    | CodexThreadsReply(_, _)
    | CodexInterruptReply
    | CodexApprovalReply => None
  }
}

///|
fn State::begin_foreground(self : State, kind : CodexReplyKind) -> State {
  guard kind.foreground() is Some(foreground) else { return self }
  { ..self, loading: true, foreground: Some(foreground), notice: "" }
}

///|
fn State::owns_foreground(self : State, kind : CodexReplyKind) -> Bool {
  kind.foreground() is Some(foreground) && self.foreground == Some(foreground)
}

///|
fn State::settle_foreground(self : State, kind : CodexReplyKind) -> State {
  if self.owns_foreground(kind) {
    { ..self, loading: false, foreground: None }
  } else {
    self
  }
}

///|
fn State::active_draft(self : State) -> CodexDraftTask? {
  match self.selection {
    CodexDraftTask(draft) => Some(draft)
    CodexNoTask | CodexStoredTask(_) => None
  }
}

///|
/// Whether a selected Codex task can own the terminal and file panels. A local
/// draft has a host-authorized id/cwd pair even though app-server knows nothing
/// about it yet.
pub fn State::has_active(self : State) -> Bool {
  !(self.selection is CodexNoTask)
}

///|
/// The selected host-panel owner: an app-server thread id after first send, or
/// the client-local draft id before it.
pub fn State::active_id(self : State) -> String? {
  match self.selection {
    CodexNoTask => None
    CodexDraftTask(draft) => Some(draft.id)
    CodexStoredTask(thread) => Some(thread.id)
  }
}

///|
/// The selected task's complete host-authorized placement. Stored tasks get
/// their cwd from app-server and their managed-worktree annotation from the
/// native host; local drafts get their project from `codex.draft.open`.
/// Malformed or incomplete data stays unresolved so files, terminals, and LSP
/// never guess an OpenSeek directory.
pub fn State::active_placement(
  self : State,
  channel : @interop.ChannelId,
) -> @interop.CheckoutPlacement? {
  match self.selection {
    CodexNoTask => None
    CodexDraftTask(draft) =>
      draft.project_root
      .bind(root => @resource.of_path(channel, root))
      .map(root => @interop.WorkspaceRoot(root~))
    CodexStoredTask(thread) => thread.placement(channel)
  }
}

///|
/// A retained registry row with no checkout is deliberately not a usable
/// cwd. Files, terminal, LSP, and sending remain blocked until the explicit
/// rebuild recreates that exact path and branch.
fn State::has_missing_worktree(self : State) -> Bool {
  self.active_thread() is Some(active) &&
  active.worktree is Some(worktree) &&
  !worktree.present
}

///|
/// The best workspace for the Codex section's global add button. Prefer the
/// owning main project so a task opened from a managed worktree does not make
/// every later task inherit that one checkout; fall back to the exact cwd for
/// standalone directories.
pub fn State::new_thread_cwd(self : State) -> String {
  match self.selection {
    CodexDraftTask(draft) => draft.project_root.unwrap_or(draft.cwd)
    CodexStoredTask(thread) =>
      match thread.project_root {
        Some(project) => project
        None => thread.cwd.unwrap_or("")
      }
    CodexNoTask => ""
  }
}

///|
/// The project in which the selected local draft may create a worktree. A
/// draft receives `project_root` only from `codex.draft.open`; the browser's
/// original cwd is not enough to offer a filesystem-mutating launch mode.
pub fn State::worktree_launch_workspace(
  self : State,
  channel : @interop.ChannelId,
) -> @common.Uri? {
  guard self.active_draft() is Some(draft) &&
    draft.project_root is Some(root) &&
    @resource.of_path(channel, root) is Some(workspace) else {
    return None
  }
  Some(workspace)
}

///|
fn State::can_choose_worktree(self : State) -> Bool {
  self.active_draft() is Some(_) && !self.loading
}

///|
/// A project draft must wait for the host to confirm its exact root. A draft
/// created without any selected project can still start an ordinary cwd-less
/// Codex thread, matching app-server's native Local behavior.
fn State::can_prompt(self : State) -> Bool {
  if self.pending_turn_delivery is Some(_) {
    return false
  }
  match self.selection {
    CodexNoTask => false
    CodexDraftTask(draft) =>
      draft.cwd.is_empty() || draft.project_root is Some(_)
    CodexStoredTask(_) => !self.has_missing_worktree()
  }
}

///|
/// Install the host-confirmed project on the same local draft that requested
/// it. A stale reply from an abandoned draft cannot re-root the current page.
fn State::with_open_draft(
  self : State,
  draft_id : String,
  value : Json,
) -> State {
  guard self.active_draft() is Some(draft) &&
    draft.id == draft_id &&
    value is Object(fields) &&
    @jsonx.json_text(fields, "draftId") == Some(draft_id) &&
    @jsonx.json_text(fields, "projectRoot") is Some(project_root) else {
    return { ..self, notice: "Malformed Codex draft workspace reply" }
  }
  {
    ..self,
    selection: CodexDraftTask({ ..draft, project_root: Some(project_root) }),
    notice: "",
  }
}

///|
fn State::select_draft(self : State, id : String, cwd : String) -> State {
  let id = id.trim().to_owned()
  let cwd = cwd.trim().to_owned()
  {
    ..self,
    selection: CodexDraftTask({ id, cwd, project_root: None }),
    requested_thread: None,
    git_status: None,
    git_details_open: false,
    write_access: CodexWritable,
    draft: "",
    mentions: [],
    completion: @composer.CompletionState(),
    file_index: CodexFilesEmpty,
    skills: CodexSkillsEmpty,
    symbol_search: CodexSymbolSearchCache::empty(),
    placement: @composer.LocalCheckout,
    archive_confirm: None,
    pending_turn_delivery: None,
    loading: false,
    foreground: None,
    notice: "",
  }
}

///|
/// Expose the draft as read-only text for shell-level integration tests.
pub fn State::draft_text(self : State) -> String {
  self.draft
}

///|
/// Add an editor comment as the same annotation chip OpenSeek renders. The
/// textarea remains the user's typed draft; selected source and comment travel
/// as structured context and are deduplicated like ordinary file mentions.
pub fn State::with_editor_comment(
  self : State,
  file : String,
  range : @common.Range,
  comment : String,
  quote : String,
) -> State {
  let mentions = self.mentions.copy()
  let annotation = CodexEditorAnnotation(file~, range~, quote~, comment~)
  if !mentions.contains(annotation) {
    mentions.push(annotation)
  }
  { ..self, mentions, }
}

///|
fn CodexItem::decode(value : Json) -> CodexItem? {
  guard value is Object(fields) &&
    @jsonx.json_text(fields, "id") is Some(id) &&
    @jsonx.json_text(fields, "type") is Some(kind) else {
    return None
  }
  Some({ id, kind, value, streamed: "" })
}

///|
/// Canonical app-server input carried by one stored user item. The frontend
/// compares this only within one thread and only after excluding every item
/// id visible before the request, so an older identical prompt is not mistaken
/// for proof that an unanswered start/steer request landed.
fn CodexItem::user_input_signature(self : CodexItem) -> String? {
  guard self.kind == "userMessage" &&
    self.value is Object(fields) &&
    fields.get("content") is Some(Array(content)) else {
    return None
  }
  Some(Json::array(content).stringify())
}

///|
fn CodexThread::user_item_ids(self : CodexThread) -> Array[String] {
  let ids : Array[String] = []
  for turn in self.turns {
    for item in turn.items {
      if item.kind == "userMessage" {
        ids.push(item.id)
      }
    }
  }
  ids
}

///|
/// A user item beyond the request-time frontier with the exact submitted
/// input proves that the unanswered request was accepted. Absence after a
/// fresh thread/read means the preserved composer may be retried deliberately.
fn CodexThread::received(
  self : CodexThread,
  pending : CodexPendingTurnDelivery,
) -> Bool {
  for turn in self.turns {
    for item in turn.items {
      if !pending.known_user_items.contains(item.id) &&
        item.user_input_signature() == Some(pending.input_signature) {
        return true
      }
    }
  }
  false
}

///|
fn CodexTurn::decode(value : Json) -> CodexTurn? {
  guard value is Object(fields) && @jsonx.json_text(fields, "id") is Some(id) else {
    return None
  }
  let items : Array[CodexItem] = []
  if fields.get("items") is Some(Array(values)) {
    for value in values {
      if CodexItem::decode(value) is Some(item) {
        items.push(item)
      }
    }
  }
  let error = match fields.get("error") {
    Some(Object(error)) => @jsonx.json_text(error, "message")
    _ => None
  }
  Some({
    id,
    status: @jsonx.json_text(fields, "status").unwrap_or("completed"),
    started_at: @jsonx.json_int(fields, "startedAt"),
    completed_at: @jsonx.json_int(fields, "completedAt"),
    items,
    error,
  })
}

///|
fn CodexWorktree::decode(value : Json) -> CodexWorktree? {
  guard value is Object(fields) &&
    @jsonx.json_text(fields, "name") is Some(name) &&
    @jsonx.json_text(fields, "path") is Some(path) else {
    return None
  }
  Some({ name, path, present: fields.get("present") is Some(True) })
}

///|
/// Select the exact registry row created or rebuilt for this Codex owner.
/// The host reply is authoritative; name alone is insufficient because the
/// same workspace can contain worktrees owned by OpenSeek conversations.
fn CodexWorktree::from_create_reply(
  reply : @protocol.WorktreeCreateReply,
  thread_id : String,
) -> CodexWorktree? {
  for info in reply.worktrees {
    if info.name == reply.name &&
      info.codex_thread == Some(thread_id) &&
      info.present &&
      !info.path.trim().is_empty() {
      return Some({ name: info.name, path: info.path, present: true })
    }
  }
  None
}

///|
fn CodexThread::decode(value : Json) -> CodexThread? {
  guard value is Object(fields) && @jsonx.json_text(fields, "id") is Some(id) else {
    return None
  }
  let turns : Array[CodexTurn] = []
  if fields.get("turns") is Some(Array(values)) {
    for value in values {
      if CodexTurn::decode(value) is Some(turn) {
        turns.push(turn)
      }
    }
  }
  Some({
    id,
    title: CodexThreadRow::title(fields),
    cwd: @jsonx.json_text(fields, "cwd"),
    project_root: @jsonx.json_text(fields, "projectRoot"),
    worktree: fields.get("openseekWorktree").bind(CodexWorktree::decode),
    branch: CodexThreadRow::branch(fields),
    turns,
  })
}

///|
/// Combine app-server's cwd with the native host's managed-worktree metadata.
/// An unannotated cwd remains an ordinary root even when app-server reports a
/// different `projectRoot`: SeekMoon must not claim ownership of an external
/// Codex App or manually-created Git worktree from path shape alone.
fn CodexThread::placement(
  self : CodexThread,
  channel : @interop.ChannelId,
) -> @interop.CheckoutPlacement? {
  match self.worktree {
    Some(worktree) => {
      guard self.project_root is Some(project_path) &&
        @resource.of_path(channel, project_path) is Some(project) else {
        return None
      }
      if !worktree.present {
        return Some(@interop.MissingWorktree(project~, name=worktree.name))
      }
      guard self.cwd is Some(cwd) &&
        !cwd.trim().is_empty() &&
        @resource.of_path(channel, cwd) is Some(root) else {
        return None
      }
      Some(@interop.Worktree(project~, name=worktree.name, root~))
    }
    None =>
      match self.cwd {
        Some(cwd) if !cwd.trim().is_empty() =>
          @resource.of_path(channel, cwd).map(root => {
            @interop.WorkspaceRoot(root~)
          })
        // app-server tasks created without cwd still own a host-lazy scratch
        // terminal. The host does not disclose its path, so keep `root=None`:
        // Terminal can use the task id while Files and language services stay
        // unavailable instead of receiving an invented directory.
        _ => Some(@interop.Scratch(root=None))
      }
  }
}

///|
fn CodexThreadRow::title(fields : Map[String, Json]) -> String {
  let title = @jsonx.json_text(fields, "name").unwrap_or("").trim().to_owned()
  if !title.is_empty() {
    return title
  }
  let preview = @jsonx.json_text(fields, "preview")
    .unwrap_or("")
    .trim()
    .to_owned()
  if preview.is_empty() {
    "New Codex thread"
  } else {
    preview
  }
}

///|
/// Decode app-server's creation-time Git metadata without treating it as the
/// final answer. The host's later `git.pull_request` request re-reads HEAD and
/// replaces this label if the checkout moved since the thread was created.
fn CodexThreadRow::branch(fields : Map[String, Json]) -> String? {
  match fields.get("gitInfo") {
    Some(Object(git)) =>
      @jsonx.json_text(git, "branch").bind(branch => {
        let branch = branch.trim().to_owned()
        if branch.is_empty() {
          None
        } else {
          Some(branch)
        }
      })
    _ => None
  }
}

///|
fn State::with_status(self : State, value : Json) -> State {
  guard value is Object(fields) &&
    @jsonx.json_text(fields, "status") is Some(status) else {
    return { ..self, connection: CodexUnavailable("Malformed status reply") }
  }
  {
    ..self
    // A fresh device mirror starts in a bootstrap loading state without a
    // foreground owner. The first status proves that bootstrap completed;
    // status refreshes during a real foreground operation leave its lock.
    ,
    loading: if self.foreground is None {
      false
    } else {
      self.loading
    },
    connection: match status {
      "ready" => CodexReady
      "starting" => CodexStarting
      _ =>
        CodexUnavailable(
          @jsonx.json_text(fields, "message").unwrap_or("Codex is unavailable"),
        )
    },
  }
}

///|
fn State::with_account(self : State, value : Json) -> State {
  guard value is Object(fields) else {
    return { ..self, notice: "Malformed Codex account reply" }
  }
  let requires_auth = fields.get("requiresOpenaiAuth") is Some(True)
  let account = match fields.get("account") {
    Some(Object(account)) =>
      CodexSignedIn(
        kind=@jsonx.json_text(account, "type").unwrap_or("Codex"),
        plan=@jsonx.json_text(account, "planType"),
      )
    _ => CodexSignedOut(requires_auth)
  }
  // A fresh account snapshot settles both successful and cancelled login
  // attempts. Do not leave an obsolete browser URL actionable afterward.
  { ..self, account, login_id: None, auth_url: None, notice: "" }
}

///|
fn State::with_models(self : State, value : Json) -> State {
  guard value is Object(fields) && fields.get("data") is Some(Array(values)) else {
    return { ..self, notice: "Malformed Codex model list" }
  }
  let models : Array[CodexModelOption] = []
  let mut default_model = ""
  for value in values {
    guard value is Object(model) && @jsonx.json_text(model, "id") is Some(id) else {
      continue
    }
    let is_default = model.get("isDefault") is Some(True)
    if is_default {
      default_model = id
    }
    models.push({
      id,
      label: @jsonx.json_text(model, "displayName").unwrap_or(id),
      is_default,
    })
  }
  let selected_model = if self.selected_model.is_empty() ||
    !models.iter().any(model => model.id == self.selected_model) {
    if !default_model.is_empty() {
      default_model
    } else {
      models.get(0).map(model => model.id).unwrap_or("")
    }
  } else {
    self.selected_model
  }
  { ..self, models, selected_model, notice: "" }
}

///|
fn State::with_threads(self : State, value : Json, archived : Bool) -> State {
  guard value is Object(fields) && fields.get("data") is Some(Array(values)) else {
    return { ..self, notice: "Malformed Codex thread list" }
  }
  let threads : Array[CodexThreadRow] = []
  for value in values {
    if CodexThreadRow::decode(value) is Some(thread) {
      threads.push(thread)
    }
  }
  if archived {
    return { ..self, archived_threads: threads, notice: "" }
  }
  // A just-started thread may not be present in the first state-DB page yet,
  // especially when the 100-row catalog is full. Its `thread/start` reply is
  // newer and authoritative, so do not let an older list snapshot erase the
  // active row from the navigation rail.
  let visible = if self.active_thread() is Some(active) &&
    !threads.iter().any(thread => thread.id == active.id) {
    let visible : Array[CodexThreadRow] = [
      {
        id: active.id,
        title: active.title,
        cwd: active.cwd,
        project_root: active.project_root,
        worktree: active.worktree,
      },
    ]
    for thread in threads {
      visible.push(thread)
    }
    visible
  } else {
    threads
  }
  { ..self, threads: visible, notice: "" }
}

///|
fn CodexThreadRow::decode(value : Json) -> CodexThreadRow? {
  guard value is Object(thread) && @jsonx.json_text(thread, "id") is Some(id) else {
    return None
  }
  Some({
    id,
    title: CodexThreadRow::title(thread),
    cwd: @jsonx.json_text(thread, "cwd"),
    project_root: @jsonx.json_text(thread, "projectRoot"),
    worktree: thread.get("openseekWorktree").bind(CodexWorktree::decode),
  })
}

///|
fn State::with_requests(self : State, value : Json) -> State {
  guard value is Object(fields) &&
    @jsonx.json_int(fields, "generation") is Some(generation) &&
    fields.get("data") is Some(Array(values)) else {
    return { ..self, notice: "Malformed Codex request list" }
  }
  if generation < self.request_generation {
    return self
  }
  let pending_requests : Array[CodexPendingRequest] = []
  for value in values {
    guard value is Object(request) &&
      request.get("request_id") is Some(request_id) &&
      @jsonx.json_text(request, "method") is Some(method_) &&
      request.get("params") is Some(params) &&
      CodexPendingRequest::decode(request_id, method_, params) is Some(decoded) else {
      continue
    }
    // Preserve edits for a request already shown while replacing the list
    // with the actor's exact live ownership snapshot.
    let key = request_id.stringify()
    let mut answers : Map[String, String] = Map([])
    for existing in self.pending_requests {
      if existing.request_id.stringify() == key {
        answers = existing.answers
        break
      }
    }
    pending_requests.push({ ..decoded, answers, })
  }
  { ..self, pending_requests, request_generation: generation }
}

///|
fn State::with_thread_reply(
  self : State,
  value : Json,
  requested_thread? : String,
) -> State {
  guard value is Object(fields) &&
    fields.get("thread") is Some(thread) &&
    CodexThread::decode(thread) is Some(active) else {
    return { ..self, notice: "Malformed Codex thread reply" }
  }
  if requested_thread is Some(requested) && active.id != requested {
    return {
      ..self,
      notice: "Codex returned thread \{active.id} for requested thread \{requested}",
    }
  }
  // Selecting a stored thread must not promote it to the top of the sidebar.
  // Replace its row in place; only `thread/start`, whose id is genuinely new,
  // is prepended until the authoritative catalog refresh arrives.
  let row : CodexThreadRow = {
    id: active.id,
    title: active.title,
    cwd: active.cwd,
    project_root: active.project_root,
    worktree: active.worktree,
  }
  let threads : Array[CodexThreadRow] = []
  let mut replaced = false
  for thread in self.threads {
    if thread.id == active.id {
      threads.push(row)
      replaced = true
    } else {
      threads.push(thread)
    }
  }
  let visible = if replaced {
    threads
  } else {
    let visible : Array[CodexThreadRow] = [row]
    for thread in threads {
      visible.push(thread)
    }
    visible
  }
  {
    ..self,
    threads: visible,
    selection: CodexStoredTask(active),
    requested_thread: None,
    git_status: Some({
      thread_id: active.id,
      branch: active.branch,
      pull_request: None,
      compare_url: None,
    }),
    git_details_open: false,
    placement: match active.worktree {
      Some(worktree) => @composer.BoundWorktree(worktree.name)
      None if self.placement is @composer.FreshWorktree &&
        (
          self.active_draft() is Some(_) ||
          (self.active_thread() is Some(previous) && previous.id == active.id)
        ) => @composer.FreshWorktree
      None => @composer.LocalCheckout
    },
    notice: "",
  }
}

///|
/// Reconcile a turn request whose transport reply was lost. This read is the
/// boundary that permits another Send: accepted input is cleared, while input
/// absent from the authoritative snapshot stays in the composer for an
/// explicit retry.
fn State::with_reconciled_turn_reply(
  self : State,
  value : Json,
  thread_id : String,
) -> State {
  guard self.pending_turn_delivery is Some(pending) &&
    pending.thread_id == thread_id &&
    value is Object(fields) &&
    fields.get("thread") is Some(thread) &&
    CodexThread::decode(thread) is Some(authoritative) &&
    authoritative.id == thread_id else {
    return {
      ..self,
      notice: "Codex turn delivery is still unconfirmed; reopen the task to refresh it before retrying.",
    }
  }
  let received = authoritative.received(pending)
  let next = self.with_thread_reply(value, requested_thread=thread_id)
  if received {
    {
      ..next,
      draft: "",
      mentions: [],
      completion: next.completion.dismissed(),
      pending_turn_delivery: None,
      notice: "Codex accepted the prompt; its reply was recovered from refreshed history.",
    }
  } else {
    {
      ..next,
      pending_turn_delivery: None,
      notice: "The prompt is not present in refreshed Codex history; it is available to send again.",
    }
  }
}

///|
/// Bind the just-created checkout before rendering the first turn. The host
/// has already persisted this owner/path pair and authorized it for files,
/// terminals, and language operations.
fn State::with_created_worktree(
  self : State,
  worktree : CodexWorktree,
) -> State {
  guard self.active_thread() is Some(active) else { return self }
  let active = { ..active, cwd: Some(worktree.path), worktree: Some(worktree) }
  {
    ..self,
    selection: CodexStoredTask(active),
    placement: @composer.BoundWorktree(worktree.name),
    threads: self.threads.map(thread => {
      if thread.id == active.id {
        { ..thread, cwd: Some(worktree.path), worktree: Some(worktree) }
      } else {
        thread
      }
    }),
  }
}

///|
/// Apply a GitHub answer only to the task that requested it. The host has
/// already validated a recovered branch against HEAD; only a completely empty
/// answer falls back to app-server's creation-time label.
fn State::with_git_reply(
  self : State,
  thread_id : String,
  reply : @protocol.GitPullRequestReply,
) -> State {
  guard self.active_thread() is Some(active) && active.id == thread_id else {
    return self
  }
  {
    ..self,
    git_status: Some({
      thread_id,
      branch: match reply.branch {
        Some(branch) => Some(branch)
        None => active.branch
      },
      pull_request: reply.pull_request,
      compare_url: reply.compare_url,
    }),
  }
}

///|
/// The shell uses this to install the same click-away dismissal as OpenSeek's
/// Git details popover without reaching into Codex's private fields.
pub fn State::git_details_open(self : State) -> Bool {
  self.git_details_open
}

///|
/// Close the Codex Git details when the shell leaves the Codex screen.
pub fn State::with_git_details_closed(self : State) -> State {
  { ..self, git_details_open: false }
}

///|
/// Shell entrypoint for the document-wide click-away subscription.
pub fn Msg::close_git_details() -> Msg {
  CloseGitDetails
}

///|
fn State::without_thread(self : State, thread_id : String) -> State {
  let removing_active = self.active_thread() is Some(active) &&
    active.id == thread_id
  {
    ..self,
    threads: self.threads.filter(thread => thread.id != thread_id),
    selection: if removing_active {
      CodexNoTask
    } else {
      self.selection
    },
    requested_thread: if self.requested_thread == Some(thread_id) {
      None
    } else {
      self.requested_thread
    },
    git_status: match self.git_status {
      Some(status) if status.thread_id == thread_id => None
      other => other
    },
    write_access: if removing_active {
      CodexNeedsResume
    } else {
      self.write_access
    },
    placement: if removing_active {
      @composer.LocalCheckout
    } else {
      self.placement
    },
    archive_confirm: match self.archive_confirm {
      Some(confirm) if confirm.thread_id == thread_id => None
      other => other
    },
  }
}

///|
fn State::without_archived_thread(self : State, thread_id : String) -> State {
  {
    ..self,
    archived_threads: self.archived_threads.filter(thread => {
      thread.id != thread_id
    }),
  }
}

///|
fn State::with_login(self : State, value : Json) -> State {
  guard value is Object(fields) &&
    @jsonx.json_text(fields, "loginId") is Some(login_id) &&
    @jsonx.json_text(fields, "authUrl") is Some(auth_url) else {
    return { ..self, notice: "Malformed Codex login reply" }
  }
  { ..self, login_id: Some(login_id), auth_url: Some(auth_url) }
}

///|
fn State::is_running(self : State) -> Bool {
  guard self.active_thread() is Some(active) else { return false }
  active.turns.iter().any(turn => turn.is_running())
}

///|
fn CodexTurn::is_running(self : CodexTurn) -> Bool {
  self.status == "inProgress"
}

///|
fn State::is_active_elsewhere(self : State) -> Bool {
  self.write_access is CodexActiveElsewhere
}

///|
fn State::active_turn_id(self : State) -> String? {
  guard self.active_thread() is Some(active) else { return None }
  for index = active.turns.length() - 1; index >= 0; index = index - 1 {
    if active.turns[index].status == "inProgress" {
      return Some(active.turns[index].id)
    }
  }
  None
}

///|
/// A running turn is mutable only after this Desktop actor acquired the
/// app-server writer. Persisted history may contain a running turn, but that
/// alone never grants interrupt authority.
fn State::writable_turn_id(self : State) -> String? {
  if self.write_access is CodexWritable {
    self.active_turn_id()
  } else {
    None
  }
}

///|
/// A running turn discovered before writer acquisition is display-only. Idle
/// tasks remain resumable on the next send; only a live turn is locked here.
fn State::active_turn_is_read_only(self : State) -> Bool {
  self.active_turn_id() is Some(_) && !(self.write_access is CodexWritable)
}

///|
fn CodexTurn::with_item(
  self : CodexTurn,
  item : CodexItem,
  completed~ : Bool,
) -> CodexTurn {
  let mut found = false
  let items = self.items.map(existing => {
    if existing.id == item.id {
      found = true
      if completed {
        item
      } else {
        { ..item, streamed: existing.streamed }
      }
    } else {
      existing
    }
  })
  if !found {
    items.push(item)
  }
  { ..self, items, }
}

///|
fn CodexTurn::with_delta(
  self : CodexTurn,
  item_id : String,
  delta : String,
) -> CodexTurn {
  {
    ..self,
    items: self.items.map(item => {
      if item.id == item_id {
        { ..item, streamed: item.streamed + delta }
      } else {
        item
      }
    }),
  }
}

///|
fn CodexThread::with_turn(self : CodexThread, turn : CodexTurn) -> CodexThread {
  let mut found = false
  let turns = self.turns.map(existing => {
    if existing.id == turn.id {
      found = true
      turn
    } else {
      existing
    }
  })
  if !found {
    turns.push(turn)
  }
  { ..self, turns, }
}

///|
fn CodexThread::with_item(
  self : CodexThread,
  turn_id : String,
  item : CodexItem,
  completed~ : Bool,
) -> CodexThread {
  let mut found = false
  let turns = self.turns.map(turn => {
    if turn.id == turn_id {
      found = true
      turn.with_item(item, completed~)
    } else {
      turn
    }
  })
  if !found {
    turns.push({
      id: turn_id,
      status: "inProgress",
      started_at: None,
      completed_at: None,
      items: [item],
      error: None,
    })
  }
  { ..self, turns, }
}

///|
fn CodexThread::with_delta(
  self : CodexThread,
  turn_id : String,
  item_id : String,
  delta : String,
) -> CodexThread {
  {
    ..self,
    turns: self.turns.map(turn => {
      if turn.id == turn_id {
        turn.with_delta(item_id, delta)
      } else {
        turn
      }
    }),
  }
}

///|
fn State::with_notification(
  self : State,
  method_ : String,
  params : Json,
  generation : Int,
) -> State {
  guard params is Object(fields) else { return self }
  if method_ == "serverRequest/resolved" &&
    fields.get("requestId") is Some(request_id) {
    if generation <= self.request_generation {
      return self
    }
    let key = request_id.stringify()
    return {
      ..self,
      pending_requests: self.pending_requests.filter(request => {
        request.request_id.stringify() != key
      }),
      request_generation: generation,
    }
  }
  if method_ == "thread/archived" &&
    @jsonx.json_text(fields, "threadId") is Some(thread_id) {
    return self.without_thread(thread_id)
  }
  if method_ == "thread/unarchived" &&
    @jsonx.json_text(fields, "threadId") is Some(thread_id) {
    return self.without_archived_thread(thread_id)
  }
  guard self.active_thread() is Some(active) &&
    @jsonx.json_text(fields, "threadId").unwrap_or(active.id) == active.id else {
    return self
  }
  match method_ {
    "thread/name/updated" =>
      if @jsonx.json_text(fields, "name") is Some(title) {
        { ..self, selection: CodexStoredTask({ ..active, title, }) }
      } else {
        self
      }
    // The notification's cwd has not crossed the Desktop host's path
    // authority check. Update reruns `thread/read` before adopting it.
    "thread/settings/updated" => self
    "turn/started" | "turn/completed" =>
      if fields.get("turn") is Some(value) &&
        CodexTurn::decode(value) is Some(turn) {
        { ..self, selection: CodexStoredTask(active.with_turn(turn)) }
      } else {
        self
      }
    "item/started" | "item/completed" =>
      if @jsonx.json_text(fields, "turnId") is Some(turn_id) &&
        fields.get("item") is Some(value) &&
        CodexItem::decode(value) is Some(item) {
        {
          ..self,
          selection: CodexStoredTask(
            active.with_item(
              turn_id,
              item,
              completed=method_ == "item/completed",
            ),
          ),
        }
      } else {
        self
      }
    "item/agentMessage/delta"
    | "item/plan/delta"
    | "item/reasoning/summaryTextDelta"
    | "item/reasoning/textDelta"
    | "item/commandExecution/outputDelta" =>
      if @jsonx.json_text(fields, "turnId") is Some(turn_id) &&
        @jsonx.json_text(fields, "itemId") is Some(item_id) &&
        @jsonx.json_text(fields, "delta") is Some(delta) {
        {
          ..self,
          selection: CodexStoredTask(active.with_delta(turn_id, item_id, delta)),
        }
      } else {
        self
      }
    "error" =>
      if fields.get("error") is Some(Object(error)) &&
        @jsonx.json_text(error, "message") is Some(message) {
        { ..self, notice: message }
      } else {
        self
      }
    "warning" =>
      if @jsonx.json_text(fields, "message") is Some(message) {
        { ..self, notice: message }
      } else {
        self
      }
    _ => self
  }
}

///|
fn State::with_pending_request(
  self : State,
  request_id : Json,
  method_ : String,
  params : Json,
  generation : Int,
) -> State {
  if generation <= self.request_generation {
    return self
  }
  guard CodexPendingRequest::decode(request_id, method_, params)
    is Some(request) else {
    return { ..self, request_generation: generation }
  }
  let key = request_id.stringify()
  if self.pending_requests
    .iter()
    .any(request => request.request_id.stringify() == key) {
    return { ..self, request_generation: generation }
  }
  let pending_requests = self.pending_requests.copy()
  pending_requests.push(request)
  { ..self, pending_requests, request_generation: generation }
}

///|
fn CodexPendingRequest::decode(
  request_id : Json,
  method_ : String,
  params : Json,
) -> CodexPendingRequest? {
  guard params is Object(fields) &&
    @jsonx.json_text(fields, "threadId") is Some(thread_id) else {
    return None
  }
  Some({ request_id, thread_id, method_, params, answers: Map([]) })
}

///|
fn State::with_request_answer(
  self : State,
  request_key : String,
  question_id : String,
  answer : String,
) -> State {
  {
    ..self,
    pending_requests: self.pending_requests.map(request => {
      if request.request_id.stringify() == request_key &&
        self.active_thread() is Some(active) &&
        request.thread_id == active.id {
        let answers = request.answers.copy()
        answers[question_id] = answer
        { ..request, answers, }
      } else {
        request
      }
    }),
  }
}

///|
fn CodexPendingRequest::questions(
  self : CodexPendingRequest,
) -> Array[CodexQuestion] {
  guard self.params is Object(fields) &&
    fields.get("questions") is Some(Array(values)) else {
    return []
  }
  let questions : Array[CodexQuestion] = []
  for value in values {
    guard value is Object(question) &&
      @jsonx.json_text(question, "id") is Some(id) else {
      continue
    }
    let options : Array[(String, String)] = []
    if question.get("options") is Some(Array(values)) {
      for value in values {
        if value is Object(option) &&
          @jsonx.json_text(option, "label") is Some(label) {
          options.push(
            (label, @jsonx.json_text(option, "description").unwrap_or("")),
          )
        }
      }
    }
    questions.push({
      id,
      header: @jsonx.json_text(question, "header").unwrap_or("Question"),
      question: @jsonx.json_text(question, "question").unwrap_or(""),
      options,
    })
  }
  questions
}

///|
fn CodexPendingRequest::response(
  self : CodexPendingRequest,
  decision : String,
) -> Json? {
  match self.method_ {
    "item/commandExecution/requestApproval"
    | "item/fileChange/requestApproval" =>
      Some({ "decision": Json::string(decision) })
    "item/permissions/requestApproval" =>
      if decision == "decline" {
        Some({ "permissions": {}, "scope": "turn" })
      } else if self.params is Object(fields) &&
        fields.get("permissions") is Some(permissions) {
        Some({
          "permissions": permissions,
          "scope": if decision == "acceptForSession" {
            "session"
          } else {
            "turn"
          },
        })
      } else {
        None
      }
    "item/tool/requestUserInput" => {
      let answers : Map[String, Json] = Map([])
      for question in self.questions() {
        let text = self.answers.get(question.id).unwrap_or("").trim().to_owned()
        if text.is_empty() {
          return None
        }
        answers[question.id] = { "answers": [Json::string(text)] }
      }
      Some({ "answers": Json::object(answers) })
    }
    "mcpServer/elicitation/request" =>
      if decision == "decline" || decision == "cancel" {
        Some({ "action": Json::string(decision), "content": Json::null() })
      } else {
        let text = self.answers
          .get("__content")
          .unwrap_or("{}")
          .trim()
          .to_owned()
        let content = @json.parse(text) catch { _ => return None }
        Some({ "action": "accept", "content": content })
      }
    _ => None
  }
}

///|
fn CodexItem::text(self : CodexItem) -> String {
  let streamed = self.streamed
  guard self.value is Object(fields) else { return self.value.stringify() }
  match self.kind {
    "userMessage" => {
      let parts : Array[String] = []
      let mentions : Array[@mention_context.MentionRef] = []
      if fields.get("content") is Some(Array(values)) {
        for value in values {
          if value is Object(input) &&
            @jsonx.json_text(input, "text") is Some(text) {
            // Editor annotations are sent as one shared mention envelope in a
            // text input. Unwrap each one before combining it with native
            // app-server file mentions for the shared transcript renderer.
            match @mention_context.parse(text) {
              Some(parsed) => {
                if !parsed.task.is_empty() {
                  parts.push(parsed.task)
                }
                for mention in parsed.mentions {
                  mentions.push(mention)
                }
              }
              None => parts.push(text)
            }
          } else if value is Object(input) &&
            @jsonx.json_text(input, "type") is Some("mention") &&
            @jsonx.json_text(input, "path") is Some(path) {
            // This envelope is presentation-only. Codex still sends and
            // stores native `UserInput::Mention` values; adapting them here
            // lets the shared transcript rebuild the same chips its composer
            // showed without changing the app-server payload.
            mentions.push(
              @mention_context.Symbol(
                name=@jsonx.json_text(input, "name").unwrap_or(path),
                file=path,
                line=0,
              ),
            )
          }
        }
      }
      @mention_context.encode(mentions, parts.join("\n"))
    }
    "agentMessage" | "plan" => {
      let text = @jsonx.json_text(fields, "text").unwrap_or("")
      if text.is_empty() {
        streamed
      } else {
        text
      }
    }
    "reasoning" =>
      if !streamed.is_empty() {
        streamed
      } else {
        match fields.get("summary") {
          Some(String(text)) => text
          Some(Array(parts)) => {
            let text : Array[String] = []
            for part in parts {
              match part {
                String(value) => text.push(value)
                Object(fields) =>
                  if @jsonx.json_text(fields, "text") is Some(value) {
                    text.push(value)
                  }
                _ => ()
              }
            }
            text.join("\n")
          }
          _ => ""
        }
      }
    "commandExecution" => {
      let command = @jsonx.json_text(fields, "command").unwrap_or("Command")
      let output = @jsonx.json_text(fields, "aggregatedOutput").unwrap_or(
        streamed,
      )
      if output.is_empty() {
        command
      } else {
        command + "\n\n" + output
      }
    }
    "fileChange" =>
      fields
      .get("changes")
      .map(value => value.stringify())
      .unwrap_or("File changes")
    "webSearch" =>
      "Web search: " + @jsonx.json_text(fields, "query").unwrap_or("")
    "imageView" =>
      "Viewed image: " + @jsonx.json_text(fields, "path").unwrap_or("")
    "enteredReviewMode" | "exitedReviewMode" =>
      @jsonx.json_text(fields, "review").unwrap_or(self.kind)
    "contextCompaction" => "Compacted conversation context"
    _ => self.value.stringify()
  }
}

///|
/// Convert one app-server semantic item into the display model consumed by
/// OpenSeek's transcript renderer. This is the only place that knows both
/// vocabularies; the shared view never switches on Codex JSON item names.
fn CodexItem::transcript_item(self : CodexItem) -> @transcript.TranscriptItem {
  let kind = match self.kind {
    "userMessage" => @transcript.User
    "agentMessage" | "plan" => @transcript.Assistant(is_danger=false)
    "reasoning" => @transcript.Reasoning
    "contextCompaction" => @transcript.Summary
    _ =>
      @transcript.Tool(
        call_id=self.id,
        name=self.tool_name(),
        arguments=self.tool_arguments(),
        has_result=self.tool_has_result(),
        is_error=self.tool_failed(),
        brief=self.tool_brief(),
      )
  }
  {
    kind,
    content: if kind is @transcript.Tool(..) {
      self.tool_output()
    } else {
      self.text()
    },
    // The current app-server item snapshot has no durable display timestamp.
    // Leaving it absent is honest; the shared turn rule simply omits its clock.
    ts: None,
    // App-server items have their own ids but no OpenSeek store sequence. The
    // transcript overview therefore derives a stable fallback turn key.
    sequence: None,
  }
}

///|
/// Normalize app-server tool-like item names to the categories already used
/// by OpenSeek's activity summary (read/edit/shell) where the meaning matches.
fn CodexItem::tool_name(self : CodexItem) -> String {
  match self.kind {
    "commandExecution" => "shell"
    "fileChange" => "edit"
    other => other
  }
}

///|
/// Keep the operation input separate from its result so the shared expanded
/// tool row can render Arguments before Output instead of one raw JSON blob.
fn CodexItem::tool_arguments(self : CodexItem) -> String? {
  guard self.value is Object(fields) else {
    return Some(self.value.stringify())
  }
  match self.kind {
    "commandExecution" => {
      let arguments : Json = {
        "command": @jsonx.json_text(fields, "command").unwrap_or(""),
      }
      Some(arguments.stringify())
    }
    "fileChange" =>
      match fields.get("changes") {
        Some(changes) => {
          let arguments : Json = { "changes": changes }
          Some(arguments.stringify())
        }
        None => None
      }
    "webSearch" => {
      let arguments : Json = {
        "query": @jsonx.json_text(fields, "query").unwrap_or(""),
      }
      Some(arguments.stringify())
    }
    "imageView" => {
      let arguments : Json = {
        "path": @jsonx.json_text(fields, "path").unwrap_or(""),
      }
      Some(arguments.stringify())
    }
    _ => Some(self.value.stringify())
  }
}

///|
/// The completed app-server object replaces live deltas. While it is still in
/// progress the shared row remains a pending call with any streamed output it
/// has already received.
fn CodexItem::tool_has_result(self : CodexItem) -> Bool {
  guard self.value is Object(fields) else { return true }
  match @jsonx.json_text(fields, "status") {
    Some("inProgress") | Some("pending") => false
    _ => true
  }
}

///|
/// App-server status and process exit code both contribute to the common red
/// failure treatment; either signal is sufficient.
fn CodexItem::tool_failed(self : CodexItem) -> Bool {
  guard self.value is Object(fields) else { return false }
  let failed_status = match @jsonx.json_text(fields, "status") {
    Some("failed") | Some("declined") | Some("cancelled") => true
    _ => false
  }
  failed_status ||
  @jsonx.json_int(fields, "exitCode").map(code => code != 0).unwrap_or(false)
}

///|
/// Only tool result text belongs in Output. Commands keep their command line
/// in Arguments; file edits keep their change list there as well.
fn CodexItem::tool_output(self : CodexItem) -> String {
  guard self.value is Object(fields) else { return self.value.stringify() }
  match self.kind {
    "commandExecution" =>
      @jsonx.json_text(fields, "aggregatedOutput").unwrap_or(self.streamed)
    "fileChange" => @jsonx.json_text(fields, "status").unwrap_or("")
    "enteredReviewMode" | "exitedReviewMode" =>
      @jsonx.json_text(fields, "review").unwrap_or("")
    _ => ""
  }
}

///|
/// The activity summary owns the count (for example "Ran 2 commands"); this
/// brief labels the individual expandable row underneath it.
fn CodexItem::tool_brief(self : CodexItem) -> String? {
  guard self.value is Object(fields) else { return Some(self.kind) }
  Some(
    match self.kind {
      "commandExecution" =>
        @jsonx.json_text(fields, "command").unwrap_or("Command")
      "fileChange" => "Changed files"
      "webSearch" => "Searched the web"
      "imageView" => "Viewed image"
      "enteredReviewMode" => "Entered review mode"
      "exitedReviewMode" => "Exited review mode"
      other => other
    },
  )
}

///|
/// The root shell consumes this display-only snapshot with the same transcript
/// view used for OpenSeek. Notices and per-turn failures become ordinary
/// danger messages, so Codex does not need a parallel banner/message layout.
pub fn State::transcript_items(
  self : State,
) -> Array[@transcript.TranscriptItem] {
  let items : Array[@transcript.TranscriptItem] = []
  if !self.notice.is_empty() {
    items.push({
      kind: @transcript.Assistant(is_danger=true),
      content: self.notice,
      ts: None,
      sequence: None,
    })
  }
  if self.active_thread() is Some(active) {
    for turn in active.turns {
      for item in turn.items {
        items.push(item.transcript_item())
      }
      if turn.error is Some(message) {
        items.push({
          kind: @transcript.Assistant(is_danger=true),
          content: message,
          ts: None,
          sequence: None,
        })
      }
    }
  }
  items
}

///|
test "Codex completed items replace streamed presentation state" {
  let started = CodexItem::decode({
    "id": "item-1",
    "type": "agentMessage",
    "text": "",
  }).unwrap()
  let turn : CodexTurn = {
    id: "turn-1",
    status: "inProgress",
    started_at: None,
    completed_at: None,
    items: [started],
    error: None,
  }
  let streamed = turn.with_delta("item-1", "partial")
  assert_eq(streamed.items[0].text(), "partial")
  let completed = CodexItem::decode({
    "id": "item-1",
    "type": "agentMessage",
    "text": "final",
  }).unwrap()
  let settled = streamed.with_item(completed, completed=true)
  assert_eq(settled.items[0].text(), "final")
  assert_eq(settled.items[0].streamed, "")
}

///|
test "Codex reasoning summaries render text instead of JSON syntax" {
  let item = CodexItem::decode({
    "id": "reasoning-1",
    "type": "reasoning",
    "summary": [
      { "type": "summary_text", "text": "First" },
      { "type": "summary_text", "text": "Second" },
    ],
  }).unwrap()
  assert_eq(item.text(), "First\nSecond")
}

///|
test "Codex interrupted history is not an active writer signal" {
  // Historical review parents can be interrupted after their review child
  // completes. Older records omit `completedAt`, so timestamp absence cannot
  // prove that another app-server still owns the writer.
  let interrupted = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "status": { "type": "notLoaded" },
      "turns": [
        {
          "id": "turn-1",
          "status": "interrupted",
          "startedAt": 100,
          "completedAt": Json::null(),
          "items": [],
        },
      ],
    },
  })
  assert_false(interrupted.is_running())
  assert_false(interrupted.is_active_elsewhere())

  let running = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [
        {
          "id": "turn-1",
          "status": "inProgress",
          "startedAt": 100,
          "completedAt": Json::null(),
          "items": [],
        },
      ],
    },
  })
  assert_true(running.is_running())
  assert_false(running.is_active_elsewhere())

  // Old persisted turns can lack both timestamp fields. Do not classify an
  // ordinary historical interruption as live merely because completion time
  // was never recorded by that older schema.
  let legacy = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "interrupted", "items": [] }],
    },
  })
  assert_false(legacy.is_running())
}

///|
test "Codex interrupt authority requires the local writer" {
  let observed = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  assert_eq(observed.active_turn_id(), Some("turn-1"))
  assert_eq(observed.writable_turn_id(), None)
  assert_true(observed.active_turn_is_read_only())

  let owned = { ..observed, write_access: CodexWritable }
  assert_eq(owned.writable_turn_id(), Some("turn-1"))
  assert_false(owned.active_turn_is_read_only())

  let idle = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "completed", "items": [] }],
    },
  })
  assert_eq(idle.writable_turn_id(), None)
  assert_false(idle.active_turn_is_read_only())
}

///|
test "Codex user-input replies preserve exact question ids" {
  let request : CodexPendingRequest = {
    request_id: Json::number(7),
    thread_id: "thread-1",
    method_: "item/tool/requestUserInput",
    params: {
      "questions": [
        {
          "id": "scope",
          "header": "Scope",
          "question": "Which scope?",
          "options": [{ "label": "Small", "description": "One package" }],
        },
      ],
    },
    answers: { "scope": "Small" },
  }
  assert_eq(
    request.response("accept"),
    Some({ "answers": { "scope": { "answers": ["Small"] } } }),
  )
}

///|
test "Codex account snapshots settle browser login state" {
  let state = {
    ..State(),
    login_id: Some("login-1"),
    auth_url: Some("https://example.invalid/login"),
  }
  let settled = state.with_account({
    "account": { "type": "chatgpt", "planType": "pro" },
    "requiresOpenaiAuth": true,
  })
  assert_eq(settled.login_id, None)
  assert_eq(settled.auth_url, None)
  assert_true(settled.account is CodexSignedIn(..))
}

///|
test "Codex archive notification closes the active thread" {
  let state = State().with_thread_reply({
    "thread": { "id": "thread-1", "turns": [] },
  })
  let settled = state.with_notification(
    "thread/archived",
    { "threadId": "thread-1" },
    0,
  )
  assert_true(settled.active_thread() is None)
  assert_eq(settled.threads.length(), 0)
}

///|
test "Codex active and archived catalogs remain independent" {
  let state = State()
    .with_threads(
      { "data": [{ "id": "thread-live", "preview": "Live" }] },
      false,
    )
    .with_threads(
      { "data": [{ "id": "thread-archived", "preview": "Archived" }] },
      true,
    )
  assert_eq(state.threads.map(thread => thread.id), ["thread-live"])
  assert_eq(state.archived_threads.map(thread => thread.id), ["thread-archived"])
  let restored = state.with_notification(
    "thread/unarchived",
    { "threadId": "thread-archived" },
    0,
  )
  assert_eq(restored.threads.map(thread => thread.id), ["thread-live"])
  assert_true(restored.archived_threads.is_empty())
}

///|
test "Codex thread replies are visible before catalog refresh" {
  let state = State().with_thread_reply({
    "thread": {
      "id": "thread-1",
      "cwd": "/project",
      "projectRoot": "/project",
      "preview": "Smoke test",
      "turns": [],
    },
  })
  assert_eq(state.threads.length(), 1)
  assert_eq(state.threads[0].id, "thread-1")
  assert_eq(state.threads[0].title, "Smoke test")
  assert_eq(state.threads[0].project_root, Some("/project"))
  assert_eq(state.worktree_launch_workspace(@interop.ChannelId::Local), None)
  let external_worktree = State().with_thread_reply({
    "thread": {
      "id": "thread-external",
      "cwd": "/external/worktree",
      "projectRoot": "/project",
      "turns": [],
    },
  })
  assert_eq(
    external_worktree.worktree_launch_workspace(@interop.ChannelId::Local),
    None,
  )
  let refreshed = state.with_threads({ "data": [] }, false)
  assert_eq(refreshed.threads.length(), 1)
  assert_eq(refreshed.threads[0].id, "thread-1")
}

///|
test "opening a Codex conversation preserves its catalog position" {
  let listed = State().with_threads(
    {
      "data": [
        { "id": "thread-new", "preview": "Newest" },
        { "id": "thread-middle", "preview": "Middle" },
        { "id": "thread-old", "preview": "Oldest" },
      ],
    },
    false,
  )
  let opened = listed.with_thread_reply({
    "thread": {
      "id": "thread-middle",
      "preview": "Middle refreshed",
      "turns": [],
    },
  })
  assert_eq(opened.threads.map(thread => thread.id), [
    "thread-new", "thread-middle", "thread-old",
  ])
  assert_eq(opened.threads[1].title, "Middle refreshed")
}

///|
test "Codex Git status starts from app-server and accepts current checkout" {
  let state = State().with_thread_reply({
    "thread": {
      "id": "thread-1",
      "cwd": "/worktrees/a/project",
      "projectRoot": "/workspace/project",
      "gitInfo": { "branch": "captured-branch" },
      "turns": [],
    },
  })
  assert_eq(state.new_thread_cwd(), "/workspace/project")
  assert_eq(state.git_status.unwrap().branch, Some("captured-branch"))
  let refreshed = state.with_git_reply("thread-1", {
    pull_request: None,
    compare_url: None,
    branch: Some("current-branch"),
  })
  assert_eq(refreshed.git_status.unwrap().branch, Some("current-branch"))
  let empty = state.with_git_reply("thread-1", {
    pull_request: None,
    compare_url: None,
    branch: None,
  })
  assert_eq(empty.git_status.unwrap().branch, Some("captured-branch"))
}

///|
test "Codex worktree conversations share their main project key" {
  let state = State().with_threads(
    {
      "data": [
        {
          "id": "thread-47b9",
          "cwd": "/Users/me/.codex/worktrees/47b9/openseek",
          "projectRoot": "/Users/me/src/openseek",
          "name": "Split frontend update",
        },
        {
          "id": "thread-dd8c",
          "cwd": "/Users/me/.codex/worktrees/dd8c/openseek",
          "projectRoot": "/Users/me/src/openseek",
          "name": "Evaluate macOS package",
        },
      ],
    },
    false,
  )
  assert_eq(state.threads.length(), 2)
  assert_eq(
    state.threads[0].project_key(),
    Some(CodexProject("/Users/me/src/openseek")),
  )
  assert_eq(state.threads[1].project_key(), state.threads[0].project_key())
}

///|
test "Codex editor annotations stay in chips and preserve model context" {
  let state = State::from_thread_snapshot({
    "thread": {
      "id": "codex-thread-annotation",
      "cwd": "/work/project",
      "preview": "Review",
      "turns": [],
    },
  })
  let range = @common.Range::Range(5, 2, 6, 8)
  let once = state.with_editor_comment(
    "src/main.mbt", range, "rename this", "fn parse_hover() {",
  )
  let twice = once.with_editor_comment(
    "src/main.mbt", range, "rename this", "fn parse_hover() {",
  )
  assert_eq(twice.draft, "")
  assert_eq(twice.mentions.length(), 1)
  guard twice.mentions[0].to_input() is Object(input) &&
    @jsonx.json_text(input, "text") is Some(text) &&
    @mention_context.parse(text) is Some(parsed) else {
    fail("expected the annotation chip to use the shared mention envelope")
  }
  assert_eq(parsed.mentions, [
    @mention_context.Annotation(
      file="src/main.mbt",
      start_line=5,
      end_line=6,
      quote="fn parse_hover() {",
      comment="rename this",
      side=@mention_context.WorkingRevision,
    ),
  ])
}
