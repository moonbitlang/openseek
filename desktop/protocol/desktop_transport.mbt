// Typed desktop notifications. Strings and JSON exist only where a transport
// reads or writes the public wire format.

///|
/// The stable identity of one server-pushed event. Transport registration
/// uses this payload-free enum; `Notification` below carries the associated
/// typed payload once an event is decoded.
pub(all) enum NotificationKind {
  AgentConnected
  AgentStarted
  AgentEvent
  AgentError
  AgentFinished
  SessionEvent
  SubrunProgress
  WorkflowEntry
  SessionChanged
  WorkspaceChanged
  WorkspaceSettingsChanged
  WorktreeChanged
  SettingsChanged
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
} derive(Debug, Eq, Hash)

///|
/// The stable public name written at a transport boundary.
pub fn NotificationKind::wire_name(self : NotificationKind) -> String {
  match self {
    AgentConnected => "agent.connected"
    AgentStarted => "agent.started"
    AgentEvent => "agent.event"
    AgentError => "agent.error"
    AgentFinished => "agent.finished"
    SessionEvent => "session.event"
    SubrunProgress => "subrun.progress"
    WorkflowEntry => "workflow.entry"
    SessionChanged => "session.changed"
    WorkspaceChanged => "workspace.changed"
    WorkspaceSettingsChanged => "workspace.settings_changed"
    WorktreeChanged => "worktree.changed"
    SettingsChanged => "settings.changed"
    SkillsChanged => "skills.changed"
    UpdateDownloadProgress => "update.download_progress"
    UpdateDownloaded => "update.downloaded"
    UpdateDownloadFailed => "update.download_failed"
    AuthChanged => "auth.changed"
    CodexStatusChanged => "codex.status_changed"
    CodexNotification => "codex.notification"
    CodexServerRequest => "codex.server_request"
    LspDiagnostics => "lsp.diagnostics"
    FsChanged => "fs.changed"
    FsWatchFailed => "fs.watch_failed"
    TerminalOutput => "terminal.output"
    TerminalExit => "terminal.exit"
    SemanticSearchProgress => "semantic.search_progress"
  }
}

///|
/// Every event exposed by the desktop transports, in registration order.
pub fn NotificationKind::all() -> Array[NotificationKind] {
  [
    AgentConnected,
    AgentStarted,
    AgentEvent,
    AgentError,
    AgentFinished,
    SessionEvent,
    SubrunProgress,
    WorkflowEntry,
    SessionChanged,
    WorkspaceChanged,
    WorkspaceSettingsChanged,
    WorktreeChanged,
    SettingsChanged,
    SkillsChanged,
    UpdateDownloadProgress,
    UpdateDownloaded,
    UpdateDownloadFailed,
    AuthChanged,
    CodexStatusChanged,
    CodexNotification,
    CodexServerRequest,
    LspDiagnostics,
    FsChanged,
    FsWatchFailed,
    TerminalOutput,
    TerminalExit,
    SemanticSearchProgress,
  ]
}

///|
/// A server-pushed desktop event. Both the event case and its top-level
/// payload are compiler checked throughout the host and frontend. JSON is
/// introduced only by `from_wire`/`params` at the transport boundary.
pub(all) enum Notification {
  AgentConnected(ConnectedPayload)
  AgentStarted(StartedPayload)
  AgentEvent(AgentEventPayload)
  AgentError(AgentErrorPayload)
  AgentFinished(FinishedPayload)
  SessionEvent(SessionCommitPayload)
  SubrunProgress(SubrunProgressPayload)
  WorkflowEntry(WorkflowEntryPayload)
  SessionChanged(SessionChangedPayload)
  WorkspaceChanged(WorkspacesChangedPayload)
  WorkspaceSettingsChanged(WorkspaceSettingsPayload)
  WorktreeChanged(WorktreeChangedPayload)
  SettingsChanged(SettingsStatusPayload)
  SkillsChanged
  UpdateDownloadProgress(UpdateDownloadProgressPayload)
  UpdateDownloaded(UpdateDownloadedPayload)
  UpdateDownloadFailed(UpdateDownloadFailedPayload)
  AuthChanged(AuthStatusPayload)
  // Codex app-server owns its versioned payload schema. These three closed
  // Desktop event identities carry JSON only across that upstream boundary;
  // the frontend Codex package performs the method-specific decoding.
  CodexStatusChanged(Json)
  CodexNotification(Json)
  CodexServerRequest(Json)
  LspDiagnostics(DiagnosticsPayload)
  FsChanged(FsChangedPayload)
  FsWatchFailed(FsWatchFailedPayload)
  TerminalOutput(TerminalOutputPayload)
  TerminalExit(TerminalExitPayload)
  SemanticSearchProgress(SemanticSearchProgressPayload)
} derive(Debug, Eq)

///|
/// Decode the event name and payload together at the WebSocket/Proton boundary.
/// Unknown events are deliberately ignored so newer hosts remain compatible
/// with older pages. Matching the wire name here avoids a second name-to-kind
/// table that would only be consumed by this decoder.
pub fn Notification::from_wire(name : String, params : Json) -> Notification? {
  match name {
    "agent.connected" =>
      Some(AgentConnected(@json.from_json(params) catch { _ => return None }))
    "agent.started" =>
      Some(AgentStarted(@json.from_json(params) catch { _ => return None }))
    "agent.event" =>
      Some(AgentEvent(@json.from_json(params) catch { _ => return None }))
    "agent.error" =>
      Some(AgentError(@json.from_json(params) catch { _ => return None }))
    "agent.finished" =>
      Some(AgentFinished(@json.from_json(params) catch { _ => return None }))
    "session.event" =>
      Some(SessionEvent(@json.from_json(params) catch { _ => return None }))
    "subrun.progress" =>
      Some(SubrunProgress(@json.from_json(params) catch { _ => return None }))
    "workflow.entry" =>
      Some(WorkflowEntry(@json.from_json(params) catch { _ => return None }))
    "session.changed" =>
      Some(SessionChanged(@json.from_json(params) catch { _ => return None }))
    "workspace.changed" =>
      Some(WorkspaceChanged(@json.from_json(params) catch { _ => return None }))
    "workspace.settings_changed" =>
      Some(
        WorkspaceSettingsChanged(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    "worktree.changed" =>
      Some(WorktreeChanged(@json.from_json(params) catch { _ => return None }))
    "settings.changed" =>
      Some(SettingsChanged(@json.from_json(params) catch { _ => return None }))
    "skills.changed" => Some(SkillsChanged)
    "update.download_progress" =>
      Some(
        UpdateDownloadProgress(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    "update.downloaded" =>
      Some(UpdateDownloaded(@json.from_json(params) catch { _ => return None }))
    "update.download_failed" =>
      Some(
        UpdateDownloadFailed(@json.from_json(params) catch { _ => return None }),
      )
    "auth.changed" =>
      Some(AuthChanged(@json.from_json(params) catch { _ => return None }))
    "codex.status_changed" => Some(CodexStatusChanged(params))
    "codex.notification" => Some(CodexNotification(params))
    "codex.server_request" => Some(CodexServerRequest(params))
    "lsp.diagnostics" =>
      Some(LspDiagnostics(@json.from_json(params) catch { _ => return None }))
    "fs.changed" =>
      Some(FsChanged(@json.from_json(params) catch { _ => return None }))
    "fs.watch_failed" =>
      Some(FsWatchFailed(@json.from_json(params) catch { _ => return None }))
    "terminal.output" =>
      Some(TerminalOutput(@json.from_json(params) catch { _ => return None }))
    "terminal.exit" =>
      Some(TerminalExit(@json.from_json(params) catch { _ => return None }))
    "semantic.search_progress" =>
      Some(
        SemanticSearchProgress(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    _ => None
  }
}

///|
/// The payload-free identity used by transport registration.
pub fn Notification::kind(self : Notification) -> NotificationKind {
  match self {
    AgentConnected(_) => AgentConnected
    AgentStarted(_) => AgentStarted
    AgentEvent(_) => AgentEvent
    AgentError(_) => AgentError
    AgentFinished(_) => AgentFinished
    SessionEvent(_) => SessionEvent
    SubrunProgress(_) => SubrunProgress
    WorkflowEntry(_) => WorkflowEntry
    SessionChanged(_) => SessionChanged
    WorkspaceChanged(_) => WorkspaceChanged
    WorkspaceSettingsChanged(_) => WorkspaceSettingsChanged
    WorktreeChanged(_) => WorktreeChanged
    SettingsChanged(_) => SettingsChanged
    SkillsChanged => SkillsChanged
    UpdateDownloadProgress(_) => UpdateDownloadProgress
    UpdateDownloaded(_) => UpdateDownloaded
    UpdateDownloadFailed(_) => UpdateDownloadFailed
    AuthChanged(_) => AuthChanged
    CodexStatusChanged(_) => CodexStatusChanged
    CodexNotification(_) => CodexNotification
    CodexServerRequest(_) => CodexServerRequest
    LspDiagnostics(_) => LspDiagnostics
    FsChanged(_) => FsChanged
    FsWatchFailed(_) => FsWatchFailed
    TerminalOutput(_) => TerminalOutput
    TerminalExit(_) => TerminalExit
    SemanticSearchProgress(_) => SemanticSearchProgress
  }
}

///|
/// The stable event name written only by transport adapters.
pub fn Notification::wire_name(self : Notification) -> String {
  self.kind().wire_name()
}

///|
/// Encode the typed payload only when a transport writes the public event.
pub fn Notification::params(self : Notification) -> Json {
  match self {
    AgentConnected(payload) => ToJson::to_json(payload)
    AgentStarted(payload) => ToJson::to_json(payload)
    AgentEvent(payload) => ToJson::to_json(payload)
    AgentError(payload) => ToJson::to_json(payload)
    AgentFinished(payload) => ToJson::to_json(payload)
    SessionEvent(payload) => ToJson::to_json(payload)
    SubrunProgress(payload) => ToJson::to_json(payload)
    WorkflowEntry(payload) => ToJson::to_json(payload)
    SessionChanged(payload) => ToJson::to_json(payload)
    WorkspaceChanged(payload) => ToJson::to_json(payload)
    WorkspaceSettingsChanged(payload) => ToJson::to_json(payload)
    WorktreeChanged(payload) => ToJson::to_json(payload)
    SettingsChanged(payload) => ToJson::to_json(payload)
    SkillsChanged => Json::empty_object()
    UpdateDownloadProgress(payload) => ToJson::to_json(payload)
    UpdateDownloaded(payload) => ToJson::to_json(payload)
    UpdateDownloadFailed(payload) => ToJson::to_json(payload)
    AuthChanged(payload) => ToJson::to_json(payload)
    CodexStatusChanged(payload) => payload
    CodexNotification(payload) => payload
    CodexServerRequest(payload) => payload
    LspDiagnostics(payload) => ToJson::to_json(payload)
    FsChanged(payload) => ToJson::to_json(payload)
    FsWatchFailed(payload) => ToJson::to_json(payload)
    TerminalOutput(payload) => ToJson::to_json(payload)
    TerminalExit(payload) => ToJson::to_json(payload)
    SemanticSearchProgress(payload) => ToJson::to_json(payload)
  }
}

///|
pub extend Notification with Debug::{to_repr}

///|
pub extend Notification with Eq::{equal, not_equal}

///|
pub extend NotificationKind with Debug::{to_repr}

///|
pub extend NotificationKind with Eq::{equal, not_equal}

///|
pub extend NotificationKind with Hash::{hash, hash_combine}
