///|
/// One mention attached to a composer draft. The reference is the durable
/// envelope form; the optional range preserves an exact editor selection.
pub(all) struct Mention {
  ref_ : @mention_context.MentionRef
  range : @common.Range?
} derive(Eq, @debug.Debug)

///|
/// The complete editable value owned by one composer entry.
pub(all) struct Draft {
  task : String
  mentions : Array[Mention]
} derive(Eq, @debug.Debug)

///|
/// The conversation owner plus the archive-fact cursor at which its local
/// composer entry was created. Every conversation-scoped action carries this
/// identity so the root can reject a stale command after archive changes.
pub(all) struct Identity {
  owner : @interop.ConversationKey
  archive_generation : Int
} derive(Eq, @debug.Debug)

///|
/// The root-owned state of the shared workspace-file index. The composer only
/// needs enough information to decide whether local matches are final, a full
/// Host query is required, or the index must be started.
pub(all) enum FileIndex {
  FileIndexEmpty(epoch~ : Int)
  FileIndexLoading(epoch~ : Int)
  FileIndexReady(epoch~ : Int, truncated~ : Bool)
  FileIndexFailed(epoch~ : Int)
} derive(Eq, @debug.Debug)

///|
/// A standing-goal command that has been sent but not yet proven by a durable
/// transcript marker.
pub(all) enum GoalPending {
  GoalSetting(String)
  GoalClearing
} derive(Eq, @debug.Debug)

///|
/// Goal data needed by the composer. `draft` being present means the textarea
/// is editing the standing goal while preserving the prompt underneath it.
pub(all) struct GoalInput {
  draft : String?
  standing : @transcript.GoalStanding?
  pending : GoalPending?
} derive(Eq)

///|
/// One slash-command row supplied by the conversation implementation. The
/// component owns filtering and selection, while OpenSeek and Codex retain
/// their distinct command catalogs and execution semantics.
pub(all) struct SlashCommand {
  label : String
  detail : String
  command : String
} derive(Eq, @debug.Debug)

///|
/// Which primary action the composer should expose for the visible
/// conversation. Availability is root-owned; button behavior remains a typed
/// composer action.
pub(all) enum RunningSubmit {
  Steer
  Queue
  SaveQueue
} derive(Eq, @debug.Debug)

///|
pub(all) enum PrimaryAction {
  Send(available~ : Bool)
  Running(steer_available~ : Bool, can_stop~ : Bool, submit~ : RunningSubmit)
} derive(Eq, @debug.Debug)

///|
/// The exact permission question currently blocking an OpenSeek tool. This is
/// plain state: the composer owns its presentation and emits a typed answer.
pub(all) struct ApprovalNotice {
  tool_name : String
  detail : String
  body : String?
  answered : Bool
} derive(Eq)

///|
pub(all) enum QueuedInputState {
  Queueing
  Queued(editing~ : Bool, interactive~ : Bool)
} derive(Eq)

///|
pub(all) struct QueuedInput {
  id : String
  content : String
  state : QueuedInputState
} derive(Eq)

///|
/// One app-server reverse request shown above the Codex draft. The request is
/// plain state: callers cannot inject DOM or commands, and every answer comes
/// back through an identity-scoped composer Action.
pub(all) struct CodexRequestInput {
  request_key : String
  method_ : String
  params : Json
  answers : Map[String, String]
} derive(Eq)

///|
/// One typed component in the context column above the editable composer.
/// Callers provide only canonical state; this package owns the DOM and maps
/// every interactive affordance back to an identity-scoped `Action`.
pub(all) enum ContextComponent {
  ConnectionBanner(device_name~ : String?)
  SubrunDock(lanes~ : Array[@subrun.Lane])
  ApiSetupNotice(text~ : String)
  ApprovalRequest(ApprovalNotice)
  CodexRequests(requests~ : Array[CodexRequestInput])
  PendingSteerPanel(items~ : Array[String])
  QueuedInputPanel(items~ : Array[QueuedInput])
  CompactionNotice(queued~ : Bool)
  WorktreePlacementNotice
  MissingWorktreeNoticeComponent(MissingWorktreeNotice)
} derive(Eq)

///|
/// The state of one Git control in the composer's status row.
pub(all) struct GitControl {
  presentation : GitPresentation
  open : Bool
} derive(Eq)

///|
/// The state of Codex's approval-mode control. Confirmation remains in the
/// Codex page because it is a page-level modal, while this compact selector
/// is rendered and operated by the shared composer.
pub(all) struct PermissionControl {
  mode : @protocol.CodexPermissionMode
  open : Bool
  enabled : Bool
} derive(Eq)

///|
/// One typed component in the toolbar's status row. No caller-rendered HTML,
/// command, or emit callback crosses the shared component boundary.
pub(all) enum StatusComponent {
  ModelStatus(ModelSelect)
  ReasoningStatus(ReasoningSelect)
  PermissionStatus(PermissionControl)
  GitStatus(GitControl)
  WorktreeStatus(WorktreeControl)
} derive(Eq)

///|
/// Root-owned presentation surrounding the editable composer. Presentation
/// state is plain data and is never retained by the component Model.
pub(all) struct Presentation {
  context : Array[ContextComponent]
  status : Array[StatusComponent]
  placeholder : String
  // A read-only Codex task still renders its transcript and status, but its
  // textarea must not accept edits that can never be submitted.
  disabled : Bool
  primary_action : PrimaryAction
} derive(Eq)

///|
/// How far the open turn has gotten. The application owns the run phase; the
/// composer owns how it reads on screen.
pub(all) enum RunStage {
  // Accepted, no run id yet.
  Starting
  // Open, no step reported — the engine is in a model call and silent.
  Thinking
  // The engine's latest 1-based step counter.
  AtStep(Int)
  // Open and stepping, from an engine that does not number its steps.
  Working
  // A Stop was sent and the engine has not honored it yet.
  Stopping
} derive(Eq, @debug.Debug)

///|
/// The open turn's heartbeat: facts, never a rendered line. The wording, the
/// clock it is measured against, and the per-second tick that advances it are
/// all the composer's, so a turn's elapsed span costs one component's render
/// rather than the whole application's.
///
/// `started_ms` is `None` whenever that moment is not the page's to know — a
/// run adopted from a reconnect began before anyone here was watching, and
/// dating it from the moment it was noticed always reports too short a wait.
/// `tokens` is likewise `None` until the engine reports usage; `Some(0)` is an
/// explicit zero-token report rather than another spelling of absence.
pub(all) struct RunHeartbeat {
  stage : RunStage
  started_ms : Double?
  tokens : Int?
} derive(Eq, @debug.Debug)

///|
/// The complete root-to-composer boundary. It contains canonical external
/// facts and view-only presentation, never the root application Model or Msg.
pub(all) struct Input {
  identity : Identity
  draft : Draft
  goal : GoalInput
  // The turn in flight, `None` between runs.
  run : RunHeartbeat?
  slash_commands : Array[SlashCommand]
  root : @common.Uri?
  installed_skills : Array[@skills.InstalledItem]
  context_generation : Int
  submission_sequence : Int
  retirements : Array[@interop.ConversationKey]
  file_candidates : Array[@pathx.Relative]
  open_files : Array[@pathx.Relative]
  active_file : @pathx.Relative?
  file_index : FileIndex
  presentation : Presentation
} derive(Eq)

///|
/// Deliberate operations emitted by the composer. Raw keystrokes, completion
/// navigation, debounce ticks, and async replies remain private to the package.
pub(all) enum Action {
  DraftSubmitted(identity~ : Identity, draft~ : Draft)
  DraftPresenceChanged(
    identity~ : Identity,
    present~ : Bool,
    cleared_source~ : Draft?
  )
  RootMentionRemoved(identity~ : Identity, mention~ : Mention)
  SlashCommand(identity~ : Identity, command~ : String)
  MentionOpened(identity~ : Identity, mention~ : Mention)
  GoalEditStarted(identity~ : Identity)
  GoalCancelled(identity~ : Identity)
  GoalCleared(identity~ : Identity)
  GoalSubmitted(identity~ : Identity, draft~ : String, prompt_present~ : Bool)
  StopRequested(identity~ : Identity)
  FileIndexEnsured(identity~ : Identity)
  ModelMenuToggled(identity~ : Identity)
  ReasoningMenuToggled(identity~ : Identity)
  SelectMenuDismissed(identity~ : Identity)
  ModelSelected(identity~ : Identity, value~ : String)
  ReasoningSelected(identity~ : Identity, value~ : String)
  ApprovalAnswered(identity~ : Identity, allow~ : Bool)
  CodexRequestAnswerChanged(
    identity~ : Identity,
    request_key~ : String,
    question_id~ : String,
    answer~ : String
  )
  CodexRequestResponded(
    identity~ : Identity,
    request_key~ : String,
    decision~ : Json
  )
  PermissionMenuToggled(identity~ : Identity)
  PermissionMenuDismissed(identity~ : Identity)
  PermissionSelected(
    identity~ : Identity,
    mode~ : @protocol.CodexPermissionMode
  )
  GitDetailsToggled(identity~ : Identity)
  WorktreeModeToggled(identity~ : Identity)
  ApiSetupRequested(identity~ : Identity)
  QueuedInputEditRequested(identity~ : Identity, id~ : String)
  QueuedInputSteerRequested(identity~ : Identity, id~ : String)
  QueuedInputDeleteRequested(identity~ : Identity, id~ : String)
  WorktreePlacementRetried(identity~ : Identity)
  MissingWorktreeRebuildRequested(identity~ : Identity)
  MissingWorktreeArchiveRequested(identity~ : Identity)
}

///|
/// Every public operation is scoped to the exact composer entry that emitted
/// it. Owners validate this identity before interpreting the operation.
pub fn Action::identity(self : Action) -> Identity {
  match self {
    DraftSubmitted(identity~, ..)
    | DraftPresenceChanged(identity~, ..)
    | RootMentionRemoved(identity~, ..)
    | SlashCommand(identity~, ..)
    | MentionOpened(identity~, ..)
    | GoalEditStarted(identity~)
    | GoalCancelled(identity~)
    | GoalCleared(identity~)
    | GoalSubmitted(identity~, ..)
    | StopRequested(identity~)
    | FileIndexEnsured(identity~)
    | ModelMenuToggled(identity~)
    | ReasoningMenuToggled(identity~)
    | SelectMenuDismissed(identity~)
    | ModelSelected(identity~, ..)
    | ReasoningSelected(identity~, ..)
    | ApprovalAnswered(identity~, ..)
    | CodexRequestAnswerChanged(identity~, ..)
    | CodexRequestResponded(identity~, ..)
    | PermissionMenuToggled(identity~)
    | PermissionMenuDismissed(identity~)
    | PermissionSelected(identity~, ..)
    | GitDetailsToggled(identity~)
    | WorktreeModeToggled(identity~)
    | ApiSetupRequested(identity~)
    | QueuedInputEditRequested(identity~, ..)
    | QueuedInputSteerRequested(identity~, ..)
    | QueuedInputDeleteRequested(identity~, ..)
    | WorktreePlacementRetried(identity~)
    | MissingWorktreeRebuildRequested(identity~)
    | MissingWorktreeArchiveRequested(identity~) => identity
  }
}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ApprovalNotice with Eq::{equal, not_equal}

///|
pub extend QueuedInputState with Eq::{equal, not_equal}

///|
pub extend QueuedInput with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend CodexRequestInput with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend ContextComponent with Eq::{equal, not_equal}

///|
pub extend Draft with Debug::{to_repr}

///|
pub extend Draft with Eq::{equal, not_equal}

///|
pub extend FileIndex with Debug::{to_repr}

///|
pub extend FileIndex with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend GitControl with Eq::{equal, not_equal}

///|
pub extend GoalInput with Eq::{equal, not_equal}

///|
pub extend GoalPending with Debug::{to_repr}

///|
pub extend GoalPending with Eq::{equal, not_equal}

///|
pub extend Identity with Debug::{to_repr}

///|
pub extend Identity with Eq::{equal, not_equal}

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Mention with Debug::{to_repr}

///|
pub extend Mention with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend PermissionControl with Eq::{equal, not_equal}

///|
pub extend Presentation with Eq::{equal, not_equal}

///|
pub extend PrimaryAction with Debug::{to_repr}

///|
pub extend PrimaryAction with Eq::{equal, not_equal}

///|
pub extend RunningSubmit with Debug::{to_repr}

///|
pub extend RunningSubmit with Eq::{equal, not_equal}

///|
pub extend RunHeartbeat with Debug::{to_repr}

///|
pub extend RunHeartbeat with Eq::{equal, not_equal}

///|
pub extend RunStage with Debug::{to_repr}

///|
pub extend RunStage with Eq::{equal, not_equal}

///|
pub extend SlashCommand with Debug::{to_repr}

///|
pub extend SlashCommand with Eq::{equal, not_equal}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend StatusComponent with Eq::{equal, not_equal}
