// Deliberate exports with no in-repo production consumer (see
// shrink_package.md). Each entry documents its reason.
//
// `goal_set`, `goal_clear`: test seam — the `desktop/backend` engine tests
// drive the command queue, the write-failure path and the discard path with
// these two goal commands (`desktop/backend/engine/engine.mbt`,
// `desktop/backend/engine/ops.mbt`). They are the goal half of the command
// family whose other members (`prompt`, `steer`, `compact`, `cancel`,
// `approval`) have production callers.
//
// `AccountSessionReply`, `AppSystemAppearanceReply`, `AppTitlebarStyleReply`,
// `NotificationKind`, `OpenExternalReply`, `PickAttachmentReply` and
// `SshEvent`: the window host builds each of them — as a record literal or an
// enum variant — inside `desktop/app`, which builds in its own
// `desktop/app/moon.work`. `moon ide analyze` therefore reports no usage and
// flags them narrowable, while the host needs `pub(all)` to construct them.
// Each block below names its construction sites.

///|
/// Set (or replace) the session's standing goal. `auto` arms the engine's
/// autonomous continuation: after a cleanly finished turn it starts the next
/// one itself, until the goal is met, the agent reports it blocked, or the
/// engine's turn budget runs out. Manual is the default the UI offers.
///
/// Arming lives in the serve process, not in the durable record — the
/// `[goal]` marker stores the text alone — so it does not survive an engine
/// restart, and any later goal command supersedes it.
pub fn goal_set(text : String, auto~ : Bool) -> @wire.Command {
  GoalSet(text~, auto~)
}

///|
/// Clear the session's standing goal.
pub fn goal_clear() -> @wire.Command {
  GoalClear
}

///|
/// Exported on purpose: the window host answers `account.session` with a
/// record literal (`{ session: .. }`) at
/// `desktop/app/internal/extension/extension.mbt:489`, in the separate
/// `desktop/app/moon.work` the analyzer cannot see.
#derive(Eq)
pub(all) struct AccountSessionReply {
  session : AccountSession?
}

///|
/// Exported on purpose: the window host answers `app.system_appearance` with a
/// record literal (`{ dark: .. }`) at
/// `desktop/app/internal/extension/app_window.mbt:67`, in the separate
/// `desktop/app/moon.work` the analyzer cannot see. The local operating system
/// preference, independent of the window theme.
#derive(Debug, Eq)
pub(all) struct AppSystemAppearanceReply {
  dark : Bool
}

///|
/// Exported on purpose: the window host answers `app.set_titlebar_style` with
/// record literals (`{ custom_overlay: .. }`) at
/// `desktop/app/internal/extension/app_window.mbt:90`, `:114` and `:116`, in
/// the separate `desktop/app/moon.work` the analyzer cannot see.
pub(all) struct AppTitlebarStyleReply {
  custom_overlay : Bool
}

///|
/// Exported on purpose: the window host names its notifications with these
/// variants (`desktop/app/internal/extension/extension.mbt:14` and the sites
/// that follow) and the js-only relay bridge iterates
/// `NotificationKind::all()` at `desktop/frontend/bridge/local.mbt:126`;
/// neither consumer is visible to the analyzer, and narrowing would stop the
/// host from constructing variants.
///
/// The stable identity of one server-pushed event. Transport registration uses
/// this payload-free enum; `Notification` in `desktop_transport.mbt` carries
/// the associated typed payload once an event is decoded.
#derive(Debug, Eq, Hash)
pub(all) enum NotificationKind {
  PreviewOpen
  CloudMcp
  UserQuestions
  AgentApprovals
  AgentConnected
  AgentStarted
  AgentEvent
  AgentError
  AgentFinished
  AgentPrediction
  SessionEvent
  SessionShareProgress
  SubrunProgress
  WorkflowEntry
  SessionChanged
  WorkspaceChanged
  WorkspaceSettingsChanged
  WorktreeChanged
  SettingsChanged
  SessionArtifactsChanged
  SkillsChanged
  UpdateDownloadProgress
  UpdateDownloaded
  UpdateDownloadFailed
  AuthChanged
  CodexStatusChanged
  CodexNotification
  CodexServerRequest
  LspDiagnostics
  FsChanged
  FsWatchFailed
  TerminalOutput
  TerminalExit
  SemanticSearchProgress
}

///|
/// Exported on purpose: the window host answers `shell.open_external` with a
/// record literal (`{ opened: true }`) at
/// `desktop/app/internal/extension/external_link.mbt:44`, in the separate
/// `desktop/app/moon.work` the analyzer cannot see.
#derive(Debug, Eq)
pub(all) struct OpenExternalReply {
  opened : Bool
}

///|
/// Exported on purpose: the window host answers `host.pick_attachment` with
/// record literals (`{ path: .. }`) at
/// `desktop/app/internal/extension/attachment_picker.mbt:13` and `:19`, in the
/// separate `desktop/app/moon.work` the analyzer cannot see.
#derive(Debug, Eq)
pub(all) struct PickAttachmentReply {
  path : String?
}

///|
/// Exported on purpose: the window host builds SSH events with record literals
/// (`@protocol.SshEvent::{ .. }`) at
/// `desktop/app/internal/extension/extension.mbt:634` and `:669`, in the
/// separate `desktop/app/moon.work` the analyzer cannot see.
pub(all) struct SshEvent {
  host_id : String
  attempt : Int32
  epoch : Int32
  event : Json
}
