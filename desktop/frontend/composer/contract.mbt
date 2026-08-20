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
/// identity so the root can reject or redirect a command after navigation or
/// archive changes.
pub(all) struct Identity {
  owner : @interop.ConversationKey
  archive_generation : Int
} derive(Eq, @debug.Debug)

///|
/// One active archive rotation. The root appends these facts; the composer
/// consumes their ordered tail to move a cached draft to the fresh owner.
pub(all) struct Replacement {
  archived : @interop.ConversationKey
  fresh : @interop.ConversationKey
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
pub(all) enum PrimaryAction {
  Send(available~ : Bool)
  Running(steer_available~ : Bool, can_stop~ : Bool)
} derive(Eq, @debug.Debug)

///|
/// Root-owned presentation surrounding the editable composer. These are
/// deliberately view values, not fields retained by the component Model.
pub(all) struct Presentation {
  context : Array[@html.Html]
  status : Array[@html.Html]
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
pub(all) struct RunHeartbeat {
  stage : RunStage
  started_ms : Double?
  tokens : Int
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
  replacements : Array[Replacement]
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
}

///|
pub extend Draft with Debug::{to_repr}

///|
pub extend Draft with Eq::{equal, not_equal}

///|
pub extend FileIndex with Debug::{to_repr}

///|
pub extend FileIndex with Eq::{equal, not_equal}

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
pub extend Presentation with Eq::{equal, not_equal}

///|
pub extend PrimaryAction with Debug::{to_repr}

///|
pub extend PrimaryAction with Eq::{equal, not_equal}

///|
pub extend Replacement with Debug::{to_repr}

///|
pub extend Replacement with Eq::{equal, not_equal}

///|
pub extend SlashCommand with Debug::{to_repr}

///|
pub extend SlashCommand with Eq::{equal, not_equal}
