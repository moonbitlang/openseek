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
/// The permission picker keeps its current choice inside every transient UI
/// state. Full access cannot become active until the explicit confirmation
/// transition completes.
priv enum CodexPermissionPicker {
  CodexPermissionClosed(@protocol.CodexPermissionMode)
  CodexPermissionOpen(@protocol.CodexPermissionMode)
  CodexPermissionConfirmingFullAccess(@protocol.CodexPermissionMode)
} derive(Eq)

///|
fn CodexPermissionPicker::mode(
  self : CodexPermissionPicker,
) -> @protocol.CodexPermissionMode {
  match self {
    CodexPermissionClosed(mode)
    | CodexPermissionOpen(mode)
    | CodexPermissionConfirmingFullAccess(mode) => mode
  }
}

///|
fn CodexPermissionPicker::is_open(self : CodexPermissionPicker) -> Bool {
  self is CodexPermissionOpen(_)
}

///|
fn CodexPermissionPicker::toggle(
  self : CodexPermissionPicker,
) -> CodexPermissionPicker {
  match self {
    CodexPermissionClosed(mode) => CodexPermissionOpen(mode)
    CodexPermissionOpen(mode) => CodexPermissionClosed(mode)
    CodexPermissionConfirmingFullAccess(_) => self
  }
}

///|
fn CodexPermissionPicker::close(
  self : CodexPermissionPicker,
) -> CodexPermissionPicker {
  match self {
    CodexPermissionOpen(mode) => CodexPermissionClosed(mode)
    CodexPermissionConfirmingFullAccess(previous) =>
      CodexPermissionClosed(previous)
    CodexPermissionClosed(_) => self
  }
}

///|
fn CodexPermissionPicker::choose(
  self : CodexPermissionPicker,
  mode : @protocol.CodexPermissionMode,
) -> CodexPermissionPicker {
  if mode is @protocol.FullAccess {
    CodexPermissionConfirmingFullAccess(self.mode())
  } else {
    CodexPermissionClosed(mode)
  }
}

///|
fn CodexPermissionPicker::confirm_full_access(
  self : CodexPermissionPicker,
) -> CodexPermissionPicker {
  match self {
    CodexPermissionConfirmingFullAccess(_) =>
      CodexPermissionClosed(@protocol.FullAccess)
    _ => self
  }
}

///|
fn CodexPermissionPicker::cancel_full_access(
  self : CodexPermissionPicker,
) -> CodexPermissionPicker {
  match self {
    CodexPermissionConfirmingFullAccess(previous) =>
      CodexPermissionClosed(previous)
    _ => self
  }
}

///|
priv struct CodexModelOption {
  id : String
  label : String
  is_default : Bool
  reasoning_efforts : Array[CodexReasoningEffort]
  default_reasoning_effort : String?
} derive(Eq)

///|
/// One effort advertised by app-server for one exact model. Values remain
/// catalog-owned strings so newer Codex releases can add a level without a
/// SeekMoon protocol release.
priv struct CodexReasoningEffort {
  value : String
  description : String
} derive(Eq)

///|
priv struct CodexThreadRow {
  id : String
  title : String
  cwd : String?
  project_root : String?
  worktree : CodexWorktree?
  runtime : CodexThreadRuntime?
  // App-server last-activity stamp, converted to milliseconds so it is
  // directly comparable with OpenSeek's session mtimes when the shared
  // sidebar interleaves the two sources by recency.
  updated_at_ms : Double?
} derive(Eq)

///|
/// App-server's durable thread status, reduced to the distinction the sidebar
/// needs. Unknown future variants remain absent instead of being guessed idle.
priv enum CodexThreadRuntime {
  ThreadActive
  ThreadInactive
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
  // `completedAt`. Only app-server's explicit `inProgress` status reports a
  // live turn; it does not identify which process owns the writer.
  started_at : Int?
  completed_at : Int?
  items : Array[CodexItem]
  // App-server's own statement of how complete `items` is: "full" is the
  // whole history, while "summary" (a `turn/completed` envelope drops the
  // user message, observed live against 0.147) and "notLoaded" (start
  // reply, `turn/started`) are partial by contract. `None` is an app-server
  // that predates the field.
  items_view : String?
  error : String?
} derive(Eq)

///|
/// Whether this turn envelope's `items` may replace what the client already
/// accumulated. Only the explicit "full" view is the complete list; absent
/// means an older app-server whose envelopes carried full items.
fn CodexTurn::items_authoritative(self : CodexTurn) -> Bool {
  match self.items_view {
    Some(view) => view == "full"
    None => true
  }
}

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
  runtime : CodexThreadRuntime?
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
/// A display-only receipt for input submitted through `turn/steer`.
///
/// App-server owns the durable `userMessage` item and its id. This local value
/// is never inserted into `CodexTurn.items`, never used to retry a request, and
/// disappears only on a definite request failure or when the corresponding
/// canonical item is observed under the single-client FIFO rule documented in
/// `State::with_observed_steer_item`.
priv struct CodexSteerReceipt {
  submission_id : Int
  turn_id : String
  submitted : @composer.Draft
  known_user_item_ids : Array[String]
  delivery : CodexSteerDelivery
} derive(Eq)

///|
/// RPC acceptance and transcript durability are separate facts. A successful
/// `turn/steer` reply advances Sending to Accepted, but only the later
/// app-server item notification removes the receipt from the display.
priv enum CodexSteerDelivery {
  CodexSteerSending
  CodexSteerAccepted
} derive(Eq)

///|
/// The request-time identity and activity cut for one half of the paged
/// sidebar catalog. Keeping these fields together prevents a reply from
/// accidentally pairing one generation with another request's frontier.
priv struct CodexCatalogReplyContext {
  archived : Bool
  generation : Int
  activity_frontier : CodexActivityFrontier
}

///|
/// Why one complete thread snapshot is entering State. History reads carry
/// the request-time activity cut and expected id; thread creation and the
/// public test boundary are authoritative local transitions.
priv enum CodexThreadSnapshotOrigin {
  CodexHistoryRead(String, CodexActivityFrontier)
  CodexThreadStart
  CodexImportedSnapshot
}

///|
/// The typed operation associated with one app-server reply.
priv enum CodexReplyKind {
  CodexStatusReply
  CodexRequestsReply
  CodexAccountReply
  CodexModelsReply
  CodexThreadsReply(CodexCatalogReplyContext)
  CodexThreadReply(String, CodexActivityFrontier)
  CodexResumeReply(String)
  CodexDraftOpenReply(String)
  CodexDraftThreadReply(String)
  // Both requests own the same composer lock, but their failure receipts are
  // different: start clears the first prompt, while steer clears only Sending.
  CodexTurnStartReply(String)
  CodexTurnSteerReply(String)
  CodexWorktreeTurnReply(String, CodexWorktree)
  CodexWorktreeRepairReply(String, CodexWorktree)
  CodexLoginReply
  CodexArchiveReply(String)
  CodexUnarchiveReply(String)
  CodexCompactReply(String, String)
  CodexReviewReply(String, String)
  CodexInterruptReply
  CodexCancelLoginReply(String)
  CodexLogoutReply
  CodexApprovalReply
}

///|
/// The foreground operation that currently owns the shared composer lock.
/// Reply kinds with different payload shapes normalize to the same owner, so
/// worktree creation still settles the turn that launched it without allowing
/// unrelated replies to release the lock.
priv enum CodexForeground {
  CodexDraftOpenForeground(String)
  CodexThreadForeground(String)
  CodexResumeForeground(String)
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
  // Only deliberate operations leave the shared Rabbita component. Raw
  // keystrokes, completion navigation, and async search replies remain local
  // to @composer and never traverse Codex's transcript-sized State.
  ComposerAction(@composer.Action)
  SkillsLoaded(cwd~ : String, skills~ : Array[CodexSkill])
  SkillsFailed(cwd~ : String)
  ModelChanged(String)
  EffortChanged(String)
  TogglePermissionMenu
  DismissPermissionMenu
  ChoosePermission(@protocol.CodexPermissionMode)
  ConfirmFullAccess
  CancelFullAccess
  GitLoaded(
    thread_id~ : String,
    generation~ : Int,
    requested_cwd~ : String,
    reply~ : @protocol.GitPullRequestReply
  )
  // The native worktree registry has bound this exact task id to one checkout.
  // This is independent of app-server's settings stream: every frontend sees
  // the same host commit even though only the creator receives its RPC reply.
  WorktreeChanged(
    thread_id~ : String,
    project_root~ : String,
    name~ : String,
    path~ : String,
    present~ : Bool
  )
  ToggleGitDetails
  CloseGitDetails
  ToggleWorktreeMode
  StartDraft(id~ : String, cwd~ : String)
  AbandonDraft
  OpenThread(String)
  ArchiveThread(String)
  UnarchiveThread(String)
  RepairWorktree
  ConfirmArchiveDiscard
  CancelArchiveDiscard
  ResumeSucceeded(String)
  Stop
  Login
  CancelLogin
  Logout
  RequestAnswer(request_key~ : String, question_id~ : String, answer~ : String)
  // Command approvals can carry an execution-policy amendment object, not
  // only a string. Preserve the exact advertised decision through the UI.
  Respond(request_key~ : String, decision~ : Json)
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
/// Shell entrypoint for operations emitted by Codex's shared composer
/// instance. Identity validation and app-server interpretation remain local.
pub fn Msg::composer_action(action : @composer.Action) -> Msg {
  ComposerAction(action)
}

///|
/// Shell entrypoint for opening a local draft in an exact project directory.
/// No app-server thread exists until the draft sends its first prompt.
pub fn Msg::start_draft(id : String, cwd : String) -> Msg {
  StartDraft(id~, cwd~)
}

///|
/// Shell entrypoint for the unified model chip: adopt a Codex model id for
/// the next thread start or turn. The root persists the preference; this
/// package only carries the current pick.
pub fn Msg::model_changed(id : String) -> Msg {
  ModelChanged(id)
}

///|
/// Shell entrypoint for the Codex reasoning selector. The catalog validates
/// the value before it can become the next `turn/start` override.
pub fn Msg::effort_changed(effort : String) -> Msg {
  EffortChanged(effort)
}

///|
/// Shell entrypoint for dropping a composing draft: the unified model chip
/// switched the fresh conversation to another agent before its first send.
pub fn Msg::abandon_draft() -> Msg {
  AbandonDraft
}

///|
/// Shell entrypoints for the Settings page's Codex account group; the
/// login/logout flows themselves stay inside this package.
pub fn Msg::login() -> Msg {
  Login
}

///|
pub fn Msg::cancel_login() -> Msg {
  CancelLogin
}

///|
pub fn Msg::logout() -> Msg {
  Logout
}

///|
/// Whether a ChatGPT account is signed in on the app-server.
pub fn State::signed_in(self : State) -> Bool {
  self.account is CodexSignedIn(..)
}

///|
/// Whether the app-server is waiting for a sign-in before Codex can work.
pub fn State::sign_in_required(self : State) -> Bool {
  self.account is CodexSignedOut(true)
}

///|
/// The browser sign-in page of a login attempt still in flight.
pub fn State::pending_auth_url(self : State) -> String? {
  self.auth_url
}

///|
/// Whether an app-server request is in flight; the Settings account buttons
/// disable on it exactly like the old topbar ones did.
pub fn State::is_busy(self : State) -> Bool {
  self.loading
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
/// Apply one host-authored Codex worktree registry row. The shell has already
/// matched `thread_id` against the selected task on the event's source device;
/// this package remains responsible for its thread and placement transition.
pub fn Msg::worktree_changed(
  thread_id : String,
  project_root : String,
  name : String,
  path : String,
  present : Bool,
) -> Msg {
  WorktreeChanged(thread_id~, project_root~, name~, path~, present~)
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
  // The next ordinary turn's app-server `effort`. It is always empty when the
  // selected model has no advertised effort metadata.
  selected_effort : String
  permission_picker : CodexPermissionPicker
  threads : Array[CodexThreadRow]
  archived_threads : Array[CodexThreadRow]
  // Ordered lifecycle evidence remains available when a task's transcript is
  // not selected. Request frontiers prevent older snapshots from overwriting
  // notifications that arrived while those requests were in flight.
  activity : CodexActivityLedger
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
  // Every live Git lookup carries the number minted here. The counter belongs
  // to the Codex page rather than a thread or checkout because either can be
  // replaced while an older request is still in flight.
  git_request_generation : Int
  git_details_open : Bool
  draft : String
  mentions : Array[@composer.Mention]
  // The first submitted input remains visible while thread/worktree startup
  // has not produced its real app-server User item yet. This is display-only:
  // request construction continues to read `draft` and `mentions`, and no
  // retry or history read is derived from this field.
  submitted_first_prompt : @composer.Draft?
  // Later inputs sent into an in-progress turn get the same immediate visual
  // receipt as the first prompt. These receipts remain separate from canonical
  // turn items because app-server does not return the new user item id from
  // `turn/steer`.
  pending_steers : Array[CodexSteerReceipt]
  next_steer_submission_id : Int
  // The shared component advances only after app-server accepts a submission.
  // Failed sends therefore keep the local draft.
  submission_sequence : Int
  // `$` remains the cwd-scoped app-server catalog. `@` and `#` are owned by
  // the shared component and use the same file/symbol subscriptions as Chat.
  skills : CodexSkillCatalog
  placement : @composer.WorktreeChoice
  archive_confirm : CodexArchiveConfirm?
  pending_requests : Array[CodexPendingRequest]
  // Actor-owned request generations order the attach snapshot and live
  // reverse-request events. Older snapshots/events are ignored instead of
  // erasing a request that arrived while the snapshot was in flight.
  request_generation : Int
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
    selected_effort: "",
    // Match Codex App's assisted workflow: the workspace sandbox remains in
    // force, while eligible boundary requests go to the reviewer agent.
    permission_picker: CodexPermissionClosed(@protocol.AutoReview),
    threads: [],
    archived_threads: [],
    activity: CodexActivityLedger::empty(),
    live_catalog_generation: 0,
    archived_catalog_generation: 0,
    selection: CodexNoTask,
    requested_thread: None,
    git_status: None,
    git_request_generation: 0,
    git_details_open: false,
    draft: "",
    mentions: [],
    submitted_first_prompt: None,
    pending_steers: [],
    next_steer_submission_id: 1,
    submission_sequence: 0,
    skills: CodexSkillsEmpty,
    placement: @composer.LocalCheckout,
    archive_confirm: None,
    pending_requests: [],
    request_generation: 0,
    loading,
    foreground: None,
    notice: "",
  }
}

///|
/// The selected mode is request data, independent of whether its menu or the
/// full-access warning is currently visible.
fn State::permission_mode(self : State) -> @protocol.CodexPermissionMode {
  self.permission_picker.mode()
}

///|
/// The cwd override safe to send on an ordinary `turn/start`. Only the native
/// worktree registry populates `CodexThread::worktree`; an unannotated
/// app-server cwd must remain `None` here so the browser cannot turn an
/// arbitrary path into a Desktop-authorized checkout.
fn State::registry_turn_cwd(self : State) -> String? {
  guard self.active_thread() is Some(active) else { return None }
  match active.worktree {
    Some(worktree) if worktree.present => Some(worktree.path)
    _ => None
  }
}

///|
/// Permission changes are frozen while an operation is being accepted or a
/// turn is active, so the visible choice always describes the next request.
fn State::can_choose_permission(self : State) -> Bool {
  self.foreground is None && self.active_turn_id() is None
}

///|
/// Build state from the authoritative `thread/read(includeTurns=true)` reply.
/// The shell's black-box workspace tests use the same boundary as production
/// instead of constructing Codex's private thread representation.
pub fn State::from_thread_snapshot(value : Json) -> State {
  State().with_thread_reply(value, CodexImportedSnapshot)
}

///|
/// Whether the shared sidebar's Codex add action may start a task now. The
/// root shell owns the common section heading, but readiness and in-flight
/// request state remain Codex-owned policy.
pub fn State::can_start_thread(self : State) -> Bool {
  self.connection is CodexReady && !self.loading
}

///|
/// Whether the page is composing a local draft that has not created its
/// app-server thread yet — the only Codex surface where the unified model
/// chip may still switch the conversation to another agent.
pub fn State::composing_draft(self : State) -> Bool {
  self.selection is CodexDraftTask(_)
}

///|
/// Select a catalog model and retain the current effort only when that exact
/// model supports it. Otherwise the model's advertised default (then its first
/// supported value) becomes the next turn's setting.
fn State::with_selected_model(self : State, id : String) -> State {
  let id = id.trim().to_owned()
  if self.models.is_empty() {
    // Startup restores preferences before model/list settles.
    return { ..self, selected_model: id, }
  }
  for model in self.models {
    if model.id == id {
      return {
        ..self,
        selected_model: id,
        selected_effort: model.reasoning_effort(self.selected_effort),
      }
    }
  }
  self
}

///|
/// Adopt only a value the selected model advertised. Before model/list
/// arrives, retain the preference so catalog reconciliation can validate it.
fn State::with_selected_effort(self : State, effort : String) -> State {
  let effort = effort.trim().to_owned()
  if self.models.is_empty() {
    return { ..self, selected_effort: effort, }
  }
  guard self.selected_model_option() is Some(model) &&
    model.reasoning_efforts.iter().any(option => option.value == effort) else {
    return self
  }
  { ..self, selected_effort: effort, }
}

///|
fn State::selected_model_option(self : State) -> CodexModelOption? {
  for model in self.models {
    if model.id == self.selected_model {
      return Some(model)
    }
  }
  None
}

///|
fn CodexModelOption::reasoning_effort(
  self : CodexModelOption,
  preferred : String,
) -> String {
  let preferred = preferred.trim().to_owned()
  if self.reasoning_efforts.iter().any(option => option.value == preferred) {
    return preferred
  }
  if self.default_reasoning_effort is Some(default_) &&
    self.reasoning_efforts.iter().any(option => option.value == default_) {
    return default_
  }
  self.reasoning_efforts.get(0).map(option => option.value).unwrap_or("")
}

///|
/// What the unified model chip can offer for Codex right now. The chip is
/// root-owned; this value keeps catalog, selection, and availability policy
/// inside the package that fetched them.
pub enum CodexModelListing {
  /// The fetched catalog and the id the next thread start or turn would use.
  CodexModels(Array[@composer.ModelOption], selected~ : String)
  /// No usable catalog; the label explains why. Picking the row is a request
  /// to open the Codex page, where sign-in and connection state live.
  CodexModelsUnavailable(String)
}

///|
pub fn State::model_listing(self : State) -> CodexModelListing {
  if !self.models.is_empty() {
    let options : Array[@composer.ModelOption] = []
    for model in self.models {
      options.push({ value: model.id, label: model.label, })
    }
    // `with_models` never leaves an empty selection beside a non-empty
    // catalog, so this selected id names a real option.
    return CodexModels(options, selected=self.selected_model)
  }
  match self.connection {
    CodexStarting => CodexModelsUnavailable("Codex — connecting…")
    CodexUnavailable(_) => CodexModelsUnavailable("Codex unavailable")
    CodexReady =>
      if self.account is CodexSignedOut(_) {
        CodexModelsUnavailable("Sign in to Codex…")
      } else {
        CodexModelsUnavailable("Codex — loading models…")
      }
  }
}

///|
test "the model listing follows catalog and account state" {
  guard State().model_listing() is CodexModelsUnavailable(connecting) else {
    fail("a starting connection should have no usable catalog")
  }
  inspect(connecting, content="Codex — connecting…")
  let signed_out = {
    ..State(),
    connection: CodexReady,
    account: CodexSignedOut(true),
  }
  guard signed_out.model_listing() is CodexModelsUnavailable(sign_in) else {
    fail("a signed-out account should have no usable catalog")
  }
  inspect(sign_in, content="Sign in to Codex…")
  let listed = State().with_models({
    "data": [
      { "id": "gpt-5.4", "displayName": "GPT-5.4" },
      {
        "id": "gpt-5.4-codex",
        "displayName": "GPT-5.4 Codex",
        "isDefault": true,
      },
    ],
  })
  guard listed.model_listing() is CodexModels(options, selected~) else {
    fail("a fetched catalog should list its models")
  }
  assert_eq(options.length(), 2)
  inspect(selected, content="gpt-5.4-codex")
}

///|
test "the model catalog validates reasoning effort per model" {
  let listed = {
    ..State(),
    selected_model: "gpt-main",
    selected_effort: "xhigh",
  }.with_models({
    "data": [
      {
        "id": "gpt-main",
        "isDefault": true,
        "defaultReasoningEffort": "medium",
        "supportedReasoningEfforts": [
          { "reasoningEffort": "low", "description": "Faster" },
          { "reasoningEffort": "medium", "description": "Balanced" },
        ],
      },
      {
        "id": "gpt-fast",
        "defaultReasoningEffort": "minimal",
        "supportedReasoningEfforts": [
          { "reasoningEffort": "minimal", "description": "Fastest" },
        ],
      },
    ],
  })
  // A stale stored value falls back to this model's catalog default.
  assert_eq(listed.selected_effort, "medium")
  let low = listed.with_selected_effort("low")
  assert_eq(low.selected_effort, "low")
  // Changing model revalidates the effort instead of sending an unsupported
  // model/effort pair to app-server.
  let fast = low.with_selected_model("gpt-fast")
  assert_eq(fast.selected_effort, "minimal")
  assert_eq(fast.with_selected_effort("high").selected_effort, "minimal")
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
    CodexThreadsReply(context) =>
      if context.archived {
        context.generation == self.archived_catalog_generation
      } else {
        context.generation == self.live_catalog_generation
      }
    CodexThreadReply(thread_id, frontier) =>
      frontier.connection_epoch == self.activity.connection_epoch &&
      self.accepts_thread_reply(thread_id)
    CodexResumeReply(thread_id) =>
      self
      .active_thread()
      .map(thread => thread.id == thread_id)
      .unwrap_or(false)
    CodexDraftThreadReply(draft_id) =>
      self.active_draft().map(draft => draft.id == draft_id).unwrap_or(false)
    CodexTurnStartReply(thread_id)
    | CodexTurnSteerReply(thread_id)
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
    CodexThreadReply(id, _) => Some(CodexThreadForeground(id))
    CodexResumeReply(id) => Some(CodexResumeForeground(id))
    CodexDraftThreadReply(id) => Some(CodexDraftStartForeground(id))
    CodexTurnStartReply(id)
    | CodexTurnSteerReply(id)
    | CodexWorktreeTurnReply(id, _) => Some(CodexTurnForeground(id))
    CodexWorktreeRepairReply(id, _) => Some(CodexWorktreeRepairForeground(id))
    CodexLoginReply => Some(CodexLoginForeground)
    CodexCancelLoginReply(id) => Some(CodexCancelLoginForeground(id))
    CodexLogoutReply => Some(CodexLogoutForeground)
    CodexArchiveReply(id) => Some(CodexArchiveForeground(id))
    CodexUnarchiveReply(id) => Some(CodexUnarchiveForeground(id))
    CodexCompactReply(thread_id, _) => Some(CodexCompactForeground(thread_id))
    CodexReviewReply(thread_id, _) => Some(CodexReviewForeground(thread_id))
    CodexStatusReply
    | CodexRequestsReply
    | CodexAccountReply
    | CodexModelsReply
    | CodexThreadsReply(_)
    | CodexInterruptReply
    | CodexApprovalReply => None
  }
}

///|
/// Whether this foreground operation belongs to one stored Codex task. Global
/// account operations and draft creation deliberately return false, so an
/// external archive releases only work that can no longer produce an accepted
/// reply for the removed task.
fn CodexForeground::belongs_to_thread(
  self : CodexForeground,
  thread_id : String,
) -> Bool {
  match self {
    CodexThreadForeground(owner)
    | CodexResumeForeground(owner)
    | CodexTurnForeground(owner)
    | CodexWorktreeRepairForeground(owner)
    | CodexArchiveForeground(owner)
    | CodexUnarchiveForeground(owner)
    | CodexCompactForeground(owner)
    | CodexReviewForeground(owner) => owner == thread_id
    CodexDraftOpenForeground(_)
    | CodexDraftStartForeground(_)
    | CodexLoginForeground
    | CodexCancelLoginForeground(_)
    | CodexLogoutForeground => false
  }
}

///|
fn State::begin_foreground(self : State, kind : CodexReplyKind) -> State {
  guard kind.foreground() is Some(foreground) else { return self }
  {
    ..self,
    loading: true,
    foreground: Some(foreground),
    permission_picker: self.permission_picker.close(),
    notice: "",
  }
}

///|
fn State::owns_foreground(self : State, kind : CodexReplyKind) -> Bool {
  kind.foreground() is Some(foreground) && self.foreground == Some(foreground)
}

///|
fn State::settle_foreground(self : State, kind : CodexReplyKind) -> State {
  if self.owns_foreground(kind) {
    { ..self, loading: false, foreground: None, }
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
/// Terminal needs a durable task identity, not necessarily a filesystem root.
/// A cwd-less Codex task is a valid scratch terminal group; only an unresolved
/// selection or a retained missing worktree must keep the toggle disabled.
fn State::terminal_available(
  self : State,
  channel : @interop.ChannelId,
) -> Bool {
  self
  .active_placement(channel)
  .map(placement => placement.is_ready())
  .unwrap_or(false)
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
    return { ..self, notice: "Malformed Codex draft workspace reply", }
  }
  {
    ..self,
    selection: CodexDraftTask({ ..draft, project_root: Some(project_root), }),
    notice: "",
  }
}

///|
fn State::select_draft(self : State, id : String, cwd : String) -> State {
  let id = id.trim().to_owned()
  let cwd = cwd.trim().to_owned()
  {
    ..self,
    selection: CodexDraftTask({ id, cwd, project_root: None, }),
    requested_thread: None,
    git_status: None,
    git_details_open: false,
    draft: "",
    mentions: [],
    submitted_first_prompt: None,
    pending_steers: [],
    skills: CodexSkillsEmpty,
    placement: @composer.LocalCheckout,
    archive_confirm: None,
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
/// Original-revision comments retain their source line but deliberately have no
/// working-document navigation range.
pub fn State::with_editor_comment(
  self : State,
  file : String,
  range : @common.Range,
  comment : String,
  quote : String,
  side? : @mention_context.AnnotationSide = @mention_context.WorkingRevision,
) -> State {
  let mentions = self.mentions.copy()
  let annotation : @composer.Mention = {
    ref_: @mention_context.Annotation(
      file~,
      start_line=range.start_line_number,
      end_line=range.end_line_number,
      quote~,
      comment~,
      side~,
    ),
    range: if side is @mention_context.OriginalRevision {
      None
    } else {
      Some(range)
    },
  }
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
  Some({ id, kind, value, streamed: "", })
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
    items_view: @jsonx.json_text(fields, "itemsView"),
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
  Some({ name, path, present: fields.get("present") is Some(True), })
}

///|
fn CodexThreadRuntime::decode(value : Json?) -> CodexThreadRuntime? {
  guard value is Some(Object(fields)) &&
    @jsonx.json_text(fields, "type") is Some(type_) else {
    return None
  }
  match type_ {
    "active" => Some(ThreadActive)
    "idle" | "notLoaded" | "systemError" => Some(ThreadInactive)
    _ => None
  }
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
      return Some({ name: info.name, path: info.path, present: true, })
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
  let runtime = match CodexThreadRuntime::decode(fields.get("status")) {
    Some(runtime) => Some(runtime)
    None if turns.iter().any(turn => turn.is_running()) => Some(ThreadActive)
    None => None
  }
  Some({
    id,
    title: CodexThreadRow::title(fields),
    cwd: @jsonx.json_text(fields, "cwd"),
    project_root: @jsonx.json_text(fields, "projectRoot"),
    worktree: fields.get("openseekWorktree").bind(CodexWorktree::decode),
    branch: CodexThreadRow::branch(fields),
    runtime,
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
    "New chat"
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
  let connection = match value {
    Object(fields) =>
      match @jsonx.json_text(fields, "status") {
        Some("ready") => CodexReady
        Some("starting") => CodexStarting
        Some(_) =>
          CodexUnavailable(
            @jsonx.json_text(fields, "message").unwrap_or(
              "Codex is unavailable",
            ),
          )
        None => CodexUnavailable("Malformed status reply")
      }
    _ => CodexUnavailable("Malformed status reply")
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
    connection,
    // A disconnect ends running work owned by that process.
    // Advance the connection epoch only on the ready-to-disconnected edge so
    // repeated starting/unavailable reports do not invalidate fresh requests.
    activity: if self.connection is CodexReady && !(connection is CodexReady) {
      self.activity.disconnected()
    } else {
      self.activity
    },
  }
}

///|
fn State::with_account(self : State, value : Json) -> State {
  guard value is Object(fields) else {
    return { ..self, notice: "Malformed Codex account reply", }
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
  { ..self, account, login_id: None, auth_url: None, notice: "", }
}

///|
fn State::with_models(self : State, value : Json) -> State {
  guard value is Object(fields) && fields.get("data") is Some(Array(values)) else {
    return { ..self, notice: "Malformed Codex model list", }
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
    let reasoning_efforts : Array[CodexReasoningEffort] = []
    if model.get("supportedReasoningEfforts") is Some(Array(efforts)) {
      for effort in efforts {
        guard effort is Object(effort) &&
          @jsonx.json_text(effort, "reasoningEffort") is Some(value) else {
          continue
        }
        reasoning_efforts.push({
          value,
          description: @jsonx.json_text(effort, "description").unwrap_or(""),
        })
      }
    }
    models.push({
      id,
      label: @jsonx.json_text(model, "displayName").unwrap_or(id),
      is_default,
      reasoning_efforts,
      default_reasoning_effort: @jsonx.json_text(
        model, "defaultReasoningEffort",
      ),
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
  let selected_effort = models
    .iter()
    .find_first(model => model.id == selected_model)
    .map(model => model.reasoning_effort(self.selected_effort))
    .unwrap_or("")
  { ..self, models, selected_model, selected_effort, notice: "", }
}

///|
fn State::with_threads(
  self : State,
  value : Json,
  archived : Bool,
  activity_frontier : CodexActivityFrontier,
) -> State {
  guard value is Object(fields) && fields.get("data") is Some(Array(values)) else {
    return { ..self, notice: "Malformed Codex thread list", }
  }
  let threads : Array[CodexThreadRow] = []
  for value in values {
    if CodexThreadRow::decode(value) is Some(thread) {
      threads.push(thread)
    }
  }
  if archived {
    // The archived catalog is authoritative even when its notification was
    // missed while disconnected. Remove matching live rows in either reply
    // order, and settle a selected task through the same removal transition as
    // a live `thread/archived` notification.
    let mut activity = self.activity
    for thread in threads {
      activity = activity.retired(thread.id)
    }
    let next = {
      ..self,
      threads: self.threads.filter(live => {
        !threads.iter().any(archived => archived.id == live.id)
      }),
      archived_threads: threads,
      activity,
      notice: "",
    }
    if next.active_thread() is Some(active) &&
      next.archived_threads.iter().any(thread => thread.id == active.id) {
      return next.without_thread(active.id)
    }
    return next
  }
  // A just-started thread may not be present in the first state-DB page yet,
  // especially when the 100-row catalog is full. Its `thread/start` reply is
  // newer and authoritative, so do not let an older list snapshot erase the
  // active row from the navigation rail.
  let visible = if self.active_thread() is Some(active) &&
    !threads.iter().any(thread => thread.id == active.id) &&
    !self.archived_threads.iter().any(thread => thread.id == active.id) {
    // The list snapshot has no stamp for this thread; carry the one its
    // previous row held (the `thread/start` reply's), so the fresh thread
    // does not sink below stamped history until the next refresh.
    let mut carried_ms : Double? = None
    for existing in self.threads {
      if existing.id == active.id {
        carried_ms = existing.updated_at_ms
        break
      }
    }
    let visible : Array[CodexThreadRow] = [
      {
        id: active.id,
        title: active.title,
        cwd: active.cwd,
        project_root: active.project_root,
        worktree: active.worktree,
        runtime: active.runtime,
        updated_at_ms: carried_ms,
      },
    ]
    for thread in threads {
      visible.push(thread)
    }
    visible
  } else {
    threads
  }
  // Only rows returned by this list response carry new runtime evidence. The
  // selected row may be carried forward solely for navigation continuity, and
  // its cached runtime must not overwrite a newer lifecycle notification.
  let statuses = threads.map(thread => (thread.id, thread.runtime))
  let next = { ..self, threads: visible, notice: "", }
  {
    ..next,
    activity: next.activity.reconcile_snapshot(statuses, activity_frontier),
  }
}

///|
fn CodexThreadRow::decode(value : Json) -> CodexThreadRow? {
  guard value is Object(thread) && @jsonx.json_text(thread, "id") is Some(id) else {
    return None
  }
  let updated_at_ms = match thread.get("updatedAt") {
    // The app-server stamps threads in unix seconds.
    Some(Number(seconds, ..)) => Some(seconds * 1000.0)
    _ => None
  }
  Some({
    id,
    title: CodexThreadRow::title(thread),
    cwd: @jsonx.json_text(thread, "cwd"),
    project_root: @jsonx.json_text(thread, "projectRoot"),
    worktree: thread.get("openseekWorktree").bind(CodexWorktree::decode),
    runtime: CodexThreadRuntime::decode(thread.get("status")),
    updated_at_ms,
  })
}

///|
fn State::with_requests(self : State, value : Json) -> State {
  guard value is Object(fields) &&
    @jsonx.json_int(fields, "generation") is Some(generation) &&
    fields.get("data") is Some(Array(values)) else {
    return { ..self, notice: "Malformed Codex request list", }
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
  { ..self, pending_requests, request_generation: generation, }
}

///|
fn State::with_thread_reply(
  self : State,
  value : Json,
  origin : CodexThreadSnapshotOrigin,
) -> State {
  let (requested_thread, activity_frontier) = match origin {
    CodexHistoryRead(thread_id, frontier) => (Some(thread_id), frontier)
    CodexThreadStart | CodexImportedSnapshot => (None, self.activity.frontier())
  }
  guard value is Object(fields) &&
    fields.get("thread") is Some(thread) &&
    CodexThread::decode(thread) is Some(active) else {
    return { ..self, notice: "Malformed Codex thread reply", }
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
  let reply_stamp_ms = match thread {
    Object(thread_fields) =>
      match thread_fields.get("updatedAt") {
        Some(Number(seconds, ..)) => Some(seconds * 1000.0)
        _ => None
      }
    _ => None
  }
  let row : CodexThreadRow = {
    id: active.id,
    title: active.title,
    cwd: active.cwd,
    project_root: active.project_root,
    worktree: active.worktree,
    runtime: active.runtime,
    updated_at_ms: reply_stamp_ms,
  }
  let threads : Array[CodexThreadRow] = []
  let mut replaced = false
  for existing in self.threads {
    if existing.id == active.id {
      // A reply without a stamp must not erase the catalog's; keep the row
      // where the list already had it.
      threads.push(
        if reply_stamp_ms is Some(_) {
          row
        } else {
          { ..row, updated_at_ms: existing.updated_at_ms, }
        },
      )
      replaced = true
    } else {
      threads.push(existing)
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
  let next = {
    ..self,
    threads: visible,
    selection: CodexStoredTask(active),
    requested_thread: None,
    // A sidebar read selects an existing task and owns no local first-input
    // preview. A thread/start reply promotes the composing draft in place and
    // must carry that preview into the real task identity.
    submitted_first_prompt: if requested_thread is Some(_) {
      None
    } else {
      self.submitted_first_prompt
    },
    // A selected-history snapshot is authoritative for its visible transcript
    // and owns none of the previous task's local receipts. Thread creation has
    // no steer receipts yet and may preserve only the first-prompt preview.
    pending_steers: if requested_thread is Some(_) {
      []
    } else {
      self.pending_steers
    },
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
  {
    ..next,
    activity: next.activity.reconcile_snapshot(
      [(active.id, active.runtime)],
      activity_frontier,
    ),
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
  let active = { ..active, cwd: Some(worktree.path), worktree: Some(worktree), }
  {
    ..self,
    selection: CodexStoredTask(active),
    placement: @composer.BoundWorktree(worktree.name),
    threads: self.threads.map(thread => {
      if thread.id == active.id {
        { ..thread, cwd: Some(worktree.path), worktree: Some(worktree), }
      } else {
        thread
      }
    }),
  }
}

///|
/// Adopt the native registry's exact owner/path binding in every frontend
/// that already has this task open. `turn/start` may update app-server cwd,
/// but that live settings notification is not a synchronization read: the
/// registry commit itself supplies the authoritative Desktop placement.
fn State::with_worktree_change(
  self : State,
  thread_id : String,
  project_root : String,
  name : String,
  path : String,
  present : Bool,
) -> State {
  guard self.active_thread() is Some(active) && active.id == thread_id else {
    return self
  }
  let worktree : CodexWorktree = { name, path, present, }
  let active = {
    ..active,
    cwd: Some(path),
    project_root: Some(project_root),
    worktree: Some(worktree),
  }
  {
    ..self,
    selection: CodexStoredTask(active),
    placement: @composer.BoundWorktree(name),
    threads: self.threads.map(thread => {
      if thread.id == thread_id {
        {
          ..thread,
          cwd: Some(path),
          project_root: Some(project_root),
          worktree: Some(worktree),
        }
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
  generation : Int,
  requested_cwd : String,
  reply : @protocol.GitPullRequestReply,
) -> State {
  guard self.active_thread() is Some(active) &&
    active.id == thread_id &&
    generation == self.git_request_generation &&
    active.cwd == Some(requested_cwd) else {
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
  { ..self, git_details_open: false, }
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
  let removing_foreground = self.foreground
    .map(owner => owner.belongs_to_thread(thread_id))
    .unwrap_or(false)
  {
    ..self,
    threads: self.threads.filter(thread => thread.id != thread_id),
    activity: self.activity.retired(thread_id),
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
    placement: if removing_active {
      @composer.LocalCheckout
    } else {
      self.placement
    },
    archive_confirm: match self.archive_confirm {
      Some(confirm) if confirm.thread_id == thread_id => None
      other => other
    },
    pending_requests: self.pending_requests.filter(request => {
      request.thread_id != thread_id
    }),
    submitted_first_prompt: if removing_active {
      None
    } else {
      self.submitted_first_prompt
    },
    pending_steers: if removing_active {
      []
    } else {
      self.pending_steers
    },
    loading: if removing_foreground {
      false
    } else {
      self.loading
    },
    foreground: if removing_foreground {
      None
    } else {
      self.foreground
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
    return { ..self, notice: "Malformed Codex login reply", }
  }
  { ..self, login_id: Some(login_id), auth_url: Some(auth_url), }
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
        { ..item, streamed: existing.streamed, }
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
        { ..item, streamed: item.streamed + delta, }
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
      if turn.items_authoritative() {
        turn
      } else {
        turn.merged_onto(existing)
      }
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
/// Whether the app-server transcript has supplied the real presentation of
/// the first submitted input. Item ids stay app-server-owned; the local
/// preview needs only this semantic boundary and never tries to match text.
fn CodexThread::has_user_item(self : CodexThread) -> Bool {
  for turn in self.turns {
    if turn.items.iter().any(item => item.kind == "userMessage") {
      return true
    }
  }
  false
}

///|
/// Keep the local first-input preview only until the selected thread exposes
/// a real User item. This method changes presentation state only; it never
/// starts, retries, or reads a Codex operation.
fn State::with_observed_first_prompt(self : State) -> State {
  guard self.submitted_first_prompt is Some(_) &&
    self.active_thread() is Some(active) &&
    active.has_user_item() else {
    return self
  }
  { ..self, submitted_first_prompt: None, }
}

///|
/// The exact interval in which the transcript should show the submitted
/// first input locally and the composer should say `Starting…`.
fn State::waiting_for_first_user_item(self : State) -> Bool {
  self.submitted_first_prompt is Some(_) &&
  self.active_thread().map(thread => !thread.has_user_item()).unwrap_or(true)
}

///|
/// Adopt a partial-view turn envelope over what this client accumulated.
/// The envelope is authoritative for the turn's status, timestamps, and
/// error; its `items` are declaredly incomplete (`itemsView` "summary" or
/// "notLoaded"), so items merge by id instead of replacing: an incoming
/// item wins its slot, an accumulated one survives an envelope that lacks
/// it, and genuinely new items append in the envelope's order. Observed
/// live against app-server 0.147: `turn/completed` carries a "summary"
/// view holding only the agent message — replacing wholesale erased the
/// user's own bubble from the transcript.
fn CodexTurn::merged_onto(self : CodexTurn, existing : CodexTurn) -> CodexTurn {
  let items : Array[CodexItem] = []
  for item in existing.items {
    let mut merged = item
    for incoming in self.items {
      if incoming.id == item.id {
        merged = incoming
        break
      }
    }
    items.push(merged)
  }
  for incoming in self.items {
    if !existing.items.iter().any(item => item.id == incoming.id) {
      items.push(incoming)
    }
  }
  { ..self, items, }
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
      // Locally minted to hold an early item; the server never stated an
      // items view for it.
      items_view: None,
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
  let thread_id = @jsonx.json_text(fields, "threadId")
  let observed = match (method_, thread_id, fields.get("turn")) {
    ("turn/started", Some(thread_id), Some(Object(_))) =>
      { ..self, activity: self.activity.started(thread_id), }
    ("turn/completed", Some(thread_id), Some(Object(_))) =>
      { ..self, activity: self.activity.completed(thread_id), }
    ("thread/status/changed", Some(thread_id), _) =>
      {
        ..self,
        activity: self.activity.status_changed(
          thread_id,
          CodexThreadRuntime::decode(fields.get("status")),
        ),
      }
    _ => self
  }
  guard observed.active_thread() is Some(active) &&
    thread_id.unwrap_or(active.id) == active.id else {
    return observed
  }
  let next = match method_ {
    "thread/name/updated" =>
      if @jsonx.json_text(fields, "name") is Some(title) {
        { ..observed, selection: CodexStoredTask({ ..active, title, }), }
      } else {
        observed
      }
    "turn/started" | "turn/completed" =>
      if fields.get("turn") is Some(value) &&
        CodexTurn::decode(value) is Some(turn) {
        { ..observed, selection: CodexStoredTask(active.with_turn(turn)), }
      } else {
        observed
      }
    "item/started" | "item/completed" =>
      if @jsonx.json_text(fields, "turnId") is Some(turn_id) &&
        fields.get("item") is Some(value) &&
        CodexItem::decode(value) is Some(item) {
        {
          ..observed,
          selection: CodexStoredTask(
            active.with_item(
              turn_id,
              item,
              completed=method_ == "item/completed",
            ),
          ),
        }
      } else {
        observed
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
          ..observed,
          selection: CodexStoredTask(active.with_delta(turn_id, item_id, delta)),
        }
      } else {
        observed
      }
    "error" =>
      if fields.get("error") is Some(Object(error)) &&
        @jsonx.json_text(error, "message") is Some(message) {
        { ..observed, notice: message, }
      } else {
        observed
      }
    "warning" =>
      if @jsonx.json_text(fields, "message") is Some(message) {
        { ..observed, notice: message, }
      } else {
        observed
      }
    _ => observed
  }
  next.with_observed_first_prompt()
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
    return { ..self, request_generation: generation, }
  }
  let key = request_id.stringify()
  if self.pending_requests
    .iter()
    .any(request => request.request_id.stringify() == key) {
    return { ..self, request_generation: generation, }
  }
  let pending_requests = self.pending_requests.copy()
  pending_requests.push(request)
  { ..self, pending_requests, request_generation: generation, }
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
  Some({ request_id, thread_id, method_, params, answers: Map([]), })
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
    questions.push({ id, })
  }
  questions
}

///|
fn CodexPendingRequest::response(
  self : CodexPendingRequest,
  decision : Json,
) -> Json? {
  match self.method_ {
    "item/commandExecution/requestApproval"
    | "item/fileChange/requestApproval" => Some({ "decision": decision })
    "item/permissions/requestApproval" => {
      guard decision is String(decision_name) else { return None }
      if decision_name == "decline" || decision_name == "cancel" {
        Some({ "permissions": {}, "scope": "turn" })
      } else if self.params is Object(fields) &&
        fields.get("permissions") is Some(permissions) {
        Some({
          "permissions": permissions,
          "scope": if decision_name == "acceptForSession" {
            "session"
          } else {
            "turn"
          },
        })
      } else {
        None
      }
    }
    "item/tool/requestUserInput" => {
      let answers : Map[String, Json] = Map([])
      for question in self.questions() {
        let text = self.answers.get(question.id).unwrap_or("").trim().to_owned()
        if text.is_empty() {
          return None
        }
        answers[question.id] = { "answers": [Json(text)] }
      }
      Some({ "answers": Json(answers) })
    }
    "mcpServer/elicitation/request" => {
      guard decision is String(decision_name) else { return None }
      if decision_name == "decline" || decision_name == "cancel" {
        Some({ "action": Json(decision_name), "content": Json::null() })
      } else {
        let text = self.answers
          .get("__content")
          .unwrap_or("{}")
          .trim()
          .to_owned()
        let content = @json.parse(text) catch { _ => return None }
        Some({ "action": "accept", "content": content })
      }
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
  // Every app-server item is one response-shaped item: prose, a thought, or
  // one tool call, each with the other two parts empty. Codex commits them
  // separately, so they are never folded into one numbered step.
  let response = (
    reasoning : String?,
    prose : String?,
    calls : Array[@transcript.ToolCall],
  ) => {
    @transcript.Assistant(
      reasoning~,
      prose~,
      calls~,
      replay=false,
      finished=false,
    )
  }
  let kind = match self.kind {
    "userMessage" => @transcript.User(self.text())
    "agentMessage" | "plan" => response(None, Some(self.text()), [])
    "reasoning" => response(Some(self.text()), None, [])
    "contextCompaction" => @transcript.Summary(self.text())
    _ => {
      // A command still running may have streamed part of its output; the
      // app-server reports nothing at all as an empty string.
      let output = self.tool_output()
      let outcome : @transcript.ToolOutcome = if self.tool_has_result() {
        Done(
          content=output,
          is_error=self.tool_failed(),
          brief=self.tool_brief(),
        )
      } else if output.is_empty() {
        Pending(output=None)
      } else {
        Pending(output=Some(output))
      }
      response(None, None, [
        {
          call_id: self.id,
          name: self.tool_name(),
          arguments: self.tool_arguments(),
          outcome,
        },
      ])
    }
  }
  {
    kind,
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
      kind: @transcript.Failure(self.notice),
      ts: None,
      sequence: None,
    })
  }
  if self.waiting_for_first_user_item() &&
    self.submitted_first_prompt is Some(submitted) {
    items.push({
      kind: @transcript.User(submitted.prompt()),
      ts: None,
      sequence: None,
    })
  }
  if self.active_thread() is Some(active) {
    for turn in active.turns {
      for item in turn.items {
        let transcript_item = item.transcript_item()
        // GPT can commit a reasoning item whose only payload is encrypted:
        // until app-server exposes summary text, there is nothing the
        // transcript can display and an empty thought becomes a blank
        // "Thought" card. Keep the semantic item in Codex state so a later
        // summary delta can reveal it, but omit it from this display snapshot.
        let blank_thought = transcript_item.kind
          is @transcript.Assistant(reasoning=Some(summary), ..) &&
          summary.is_blank()
        if !blank_thought {
          items.push(transcript_item)
        }
      }
      // A receipt belongs after the canonical items already observed in the
      // same turn. The app-server User item removes it before the next render,
      // so this projection never shows both representations of one steer.
      for receipt in self.pending_steers {
        if receipt.turn_id == turn.id {
          items.push(receipt.transcript_item())
        }
      }
      if turn.error is Some(message) {
        items.push({
          kind: @transcript.Failure(message),
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
    items_view: None,
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
test "Codex interrupted history is not a running signal" {
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
test "Codex running turn supplies the interrupt target" {
  let observed = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
    },
  })
  assert_eq(observed.active_turn_id(), Some("turn-1"))

  let idle = State::from_thread_snapshot({
    "thread": {
      "id": "thread-1",
      "turns": [{ "id": "turn-1", "status": "completed", "items": [] }],
    },
  })
  assert_eq(idle.active_turn_id(), None)
}

///|
test "Codex request replies preserve structured values" {
  let request : CodexPendingRequest = {
    request_id: Json(7),
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
    request.response(Json("accept")),
    Some({ "answers": { "scope": { "answers": ["Small"] } } }),
  )
  let command : CodexPendingRequest = {
    request_id: Json(8),
    thread_id: "thread-1",
    method_: "item/commandExecution/requestApproval",
    params: { "threadId": "thread-1" },
    answers: {},
  }
  let decision : Json = {
    "acceptWithExecpolicyAmendment": {
      "execpolicy_amendment": ["moon", "info"],
    },
  }
  assert_eq(command.response(decision), Some({ "decision": decision }))
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
test "a summary turn/completed keeps the streamed user message" {
  // The exact envelope sequence observed live against app-server 0.147:
  // the start reply and turn/started carry `itemsView: "notLoaded"`, the
  // user and agent messages arrive only as items, and turn/completed's
  // "summary" view lists the agent message alone.
  let state = State()
    .with_thread_reply(
      { "thread": { "id": "thread-1", "turns": [] } },
      CodexImportedSnapshot,
    )
    .with_notification(
      "turn/started",
      {
        "threadId": "thread-1",
        "turn": {
          "id": "turn-1",
          "items": [],
          "itemsView": "notLoaded",
          "status": "inProgress",
        },
      },
      0,
    )
    .with_notification(
      "item/completed",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "item": {
          "type": "userMessage",
          "id": "user-1",
          "content": [{ "type": "text", "text": "hello" }],
        },
      },
      0,
    )
    .with_notification(
      "item/completed",
      {
        "threadId": "thread-1",
        "turnId": "turn-1",
        "item": { "type": "agentMessage", "id": "agent-1", "text": "hi" },
      },
      0,
    )
  let settled = state.with_notification(
    "turn/completed",
    {
      "threadId": "thread-1",
      "turn": {
        "id": "turn-1",
        "items": [{ "type": "agentMessage", "id": "agent-1", "text": "hi" }],
        "itemsView": "summary",
        "status": "completed",
      },
    },
    0,
  )
  guard settled.active_thread() is Some(thread) else {
    fail("the turn envelope must not deselect the thread")
  }
  assert_eq(thread.turns.length(), 1)
  assert_eq(thread.turns[0].status, "completed")
  assert_eq(thread.turns[0].items.map(item => item.id), ["user-1", "agent-1"])
  // A declared-full view is authoritative and does replace.
  let replaced = settled.with_notification(
    "turn/completed",
    {
      "threadId": "thread-1",
      "turn": {
        "id": "turn-1",
        "items": [{ "type": "agentMessage", "id": "item-2", "text": "hi" }],
        "itemsView": "full",
        "status": "completed",
      },
    },
    0,
  )
  guard replaced.active_thread() is Some(full) else {
    fail("the full envelope must not deselect the thread")
  }
  assert_eq(full.turns[0].items.map(item => item.id), ["item-2"])
}

///|
test "Codex archive notification closes the active thread" {
  let state = State().with_thread_reply(
    { "thread": { "id": "thread-1", "turns": [] } },
    CodexImportedSnapshot,
  )
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
      State().activity.frontier(),
    )
    .with_threads(
      { "data": [{ "id": "thread-archived", "preview": "Archived" }] },
      true,
      State().activity.frontier(),
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
  let state = State().with_thread_reply(
    {
      "thread": {
        "id": "thread-1",
        "cwd": "/project",
        "projectRoot": "/project",
        "preview": "Smoke test",
        "turns": [],
      },
    },
    CodexThreadStart,
  )
  assert_eq(state.threads.length(), 1)
  assert_eq(state.threads[0].id, "thread-1")
  assert_eq(state.threads[0].title, "Smoke test")
  assert_eq(state.threads[0].project_root, Some("/project"))
  assert_eq(state.worktree_launch_workspace(@interop.ChannelId::Local), None)
  let external_worktree = State().with_thread_reply(
    {
      "thread": {
        "id": "thread-external",
        "cwd": "/external/worktree",
        "projectRoot": "/project",
        "turns": [],
      },
    },
    CodexImportedSnapshot,
  )
  assert_eq(
    external_worktree.worktree_launch_workspace(@interop.ChannelId::Local),
    None,
  )
  let refreshed = state.with_threads(
    { "data": [] },
    false,
    state.activity.frontier(),
  )
  assert_eq(refreshed.threads.length(), 1)
  assert_eq(refreshed.threads[0].id, "thread-1")
}

///|
test "carried Codex rows do not revive running after completion" {
  let started = State().with_thread_reply(
    {
      "thread": {
        "id": "thread-1",
        "status": { "type": "active" },
        "turns": [{ "id": "turn-1", "status": "inProgress", "items": [] }],
      },
    },
    CodexThreadStart,
  )
  let completed = started.with_notification(
    "turn/completed",
    {
      "threadId": "thread-1",
      "turn": { "id": "turn-1", "status": "completed", "items": [] },
    },
    0,
  )
  assert_true(
    completed.activity.presentation("thread-1") is @conversation.NoRunMark,
  )
  let (frontier, activity) = completed.activity.reserve_snapshot()
  let refreshed = { ..completed, activity, }.with_threads(
    { "data": [] },
    false,
    frontier,
  )
  assert_eq(refreshed.threads.map(thread => thread.id), ["thread-1"])
  assert_true(
    refreshed.activity.presentation("thread-1") is @conversation.NoRunMark,
  )
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
    State().activity.frontier(),
  )
  let opened = listed.with_thread_reply(
    {
      "thread": {
        "id": "thread-middle",
        "preview": "Middle refreshed",
        "turns": [],
      },
    },
    CodexHistoryRead("thread-middle", listed.activity.frontier()),
  )
  assert_eq(opened.threads.map(thread => thread.id), [
    "thread-new", "thread-middle", "thread-old",
  ])
  assert_eq(opened.threads[1].title, "Middle refreshed")
}

///|
test "Codex Git status starts from app-server and accepts current checkout" {
  let state = State().with_thread_reply(
    {
      "thread": {
        "id": "thread-1",
        "cwd": "/worktrees/a/project",
        "projectRoot": "/workspace/project",
        "gitInfo": { "branch": "captured-branch" },
        "turns": [],
      },
    },
    CodexImportedSnapshot,
  )
  assert_eq(state.new_thread_cwd(), "/workspace/project")
  assert_eq(state.git_status.unwrap().branch, Some("captured-branch"))
  let refreshed = state.with_git_reply("thread-1", 0, "/worktrees/a/project", {
    pull_request: None,
    compare_url: None,
    branch: Some("current-branch"),
  })
  assert_eq(refreshed.git_status.unwrap().branch, Some("current-branch"))
  let empty = state.with_git_reply("thread-1", 0, "/worktrees/a/project", {
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
    State().activity.frontier(),
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
  let range = @common.Range(5, 2, 6, 8)
  let once = state.with_editor_comment(
    "src/main.mbt", range, "rename this", "fn parse_hover() {",
  )
  let twice = once.with_editor_comment(
    "src/main.mbt", range, "rename this", "fn parse_hover() {",
  )
  assert_eq(twice.draft, "")
  assert_eq(twice.mentions.length(), 1)
  guard twice.mention_input(twice.mentions[0]) is Some(Object(input)) &&
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
  let original = twice.with_editor_comment(
    "src/main.mbt",
    @common.Range(3, 1, 3, 11),
    "keep this removal",
    "obsolete()",
    side=@mention_context.OriginalRevision,
  )
  assert_eq(original.mentions.length(), 2)
  assert_true(
    original.mentions[1].ref_
    is @mention_context.Annotation(
      file="src/main.mbt",
      start_line=3,
      end_line=3,
      quote="obsolete()",
      comment="keep this removal",
      side=@mention_context.OriginalRevision
    ),
  )
  assert_eq(original.mentions[1].range, None)
}

///|
pub extend State with Eq::{equal, not_equal}
