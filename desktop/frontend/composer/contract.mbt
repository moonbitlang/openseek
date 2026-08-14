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
  primary_action : PrimaryAction
} derive(Eq)

///|
/// The complete root-to-composer boundary. It contains canonical external
/// facts and view-only presentation, never the root application Model or Msg.
pub(all) struct Input {
  identity : Identity
  draft : Draft
  goal : GoalInput
  root : @common.Uri?
  installed_skills : Array[@transcript.InstalledSkillItem]
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
